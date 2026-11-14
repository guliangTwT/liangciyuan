#!/usr/bin/env python3
"""Make ech_http's native build compile with MSVC.

ech_http's CMake embeds the complete Mozilla CA bundle as one C++ raw-string
literal. MSVC caps a single string literal at 16 KiB (C2026), so Windows
builds fail on the generated ca_bundle.h. This helper patches the installed
package's CMake recipe to emit short string literals instead. The PEM data and
its order are unchanged.

Run after `flutter pub get` and before `flutter build windows`.
"""

from __future__ import annotations

import sys
from pathlib import Path

OLD_CA_TEMPLATE = '''#pragma once
#include <string>
inline const std::string &eh_ca_bundle() {
  static const std::string roots = R"ECH_CA_BUNDLE(@EH_CA_PEM@)ECH_CA_BUNDLE";
  return roots;
}
'''

NEW_CA_TEMPLATE = '''#pragma once
#include <string>
#include <vector>
inline const std::string &eh_ca_bundle() {
  static const std::string roots = []() {
    std::string value;
    for (const std::string &chunk : std::vector<std::string>{@EH_CA_CHUNKS@}) {
      value += chunk;
    }
    return value;
  }();
  return roots;
}
'''

OLD_CM = 'file(READ "${CMAKE_CURRENT_SOURCE_DIR}/cacert.pem" EH_CA_PEM)\nconfigure_file(ca_bundle.h.in "${CMAKE_CURRENT_BINARY_DIR}/ca_bundle.h" @ONLY)'
NEW_CM = '''file(READ "${CMAKE_CURRENT_SOURCE_DIR}/cacert.pem" EH_CA_PEM)
# Split the CA bundle into MSVC-sized chunks (C2026 caps one literal at 16 KiB).
string(LENGTH "${EH_CA_PEM}" EH_CA_LEN)
set(EH_CA_CHUNKS "")
set(EH_CA_OFFSET 0)
while(EH_CA_OFFSET LESS EH_CA_LEN)
  string(SUBSTRING "${EH_CA_PEM}" ${EH_CA_OFFSET} 14000 EH_CA_CHUNK)
  string(APPEND EH_CA_CHUNKS "R\\"EHCAPEM(${EH_CA_CHUNK})EHCAPEM\\",")
  math(EXPR EH_CA_OFFSET "${EH_CA_OFFSET} + 14000")
endwhile()
configure_file(ca_bundle.h.in "${CMAKE_CURRENT_BINARY_DIR}/ca_bundle.h" @ONLY)'''


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_ech_http_ca.py <flutter-project-root>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"Project root not found: {root}", file=sys.stderr)
        return 2
    # The package lives under the pinned Pub cache; locate it without guessing
    # at the user's environment variables.
    #
    # 国内镜像（PUB_HOSTED_URL=https://pub.flutter-io.cn）会把包装到
    # hosted/pub.flutter-io.cn 下，所以两个目录都要找——只看 pub.dev
    # 会在镜像环境下静默跳过补丁，随后 build 仍以 C2026 失败。
    cache_root = Path.home() / "AppData" / "Local" / "Pub" / "Cache" / "hosted"
    candidates: list[Path] = []
    for host in ("pub.dev", "pub.flutter-io.cn"):
        host_dir = cache_root / host
        if host_dir.is_dir():
            candidates.extend(sorted(host_dir.glob("ech_http-*")))
    if not candidates:
        print(f"ech_http package not found under {cache_root}", file=sys.stderr)
        return 1
    # 版本目录名排序即可得到最新版本（0.2.10 > 0.2.9）。
    src = candidates[-1] / "src"
    cmake = src / "CMakeLists.txt"
    template = src / "ca_bundle.h.in"
    if not cmake.is_file() or not template.is_file():
        print(f"Incomplete ech_http package: {src}", file=sys.stderr)
        return 1

    cmake_text = cmake.read_text(encoding="utf-8")
    if NEW_CM not in cmake_text:
        if OLD_CM not in cmake_text:
            print("Unexpected ech_http CMakeLists layout; refusing to patch.", file=sys.stderr)
            return 1
        cmake.write_text(cmake_text.replace(OLD_CM, NEW_CM), encoding="utf-8")

    if "EH_CA_CHUNKS" not in template.read_text(encoding="utf-8"):
        template.write_text(NEW_CA_TEMPLATE, encoding="utf-8")

    print(f"Patched MSVC compatibility in {src}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
