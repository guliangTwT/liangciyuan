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

import json
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


def resolve_package_dir(root: Path) -> Path | None:
    """按项目实际解析到的版本定位 ech_http。

    不能靠「缓存目录名字排序取最新」：换过镜像后 pub.dev 与
    pub.flutter-io.cn 两个缓存目录里可能有不同版本，排序会把旧版本
    当成目标去打补丁，而构建用的是另一个，白白失败一次。
    `.dart_tool/package_config.json` 是 pub 实际解析结果，最可靠。
    """
    config_path = root / ".dart_tool" / "package_config.json"
    if config_path.is_file():
        try:
            config = json.loads(config_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            config = {}
        for pkg in config.get("packages", []) or []:
            if pkg.get("name") != "ech_http":
                continue
            uri = str(pkg.get("rootUri") or "")
            if uri.startswith("file:///"):
                # Windows: file:///C:/... → C:/...
                path = Path(uri[len("file:///"):].replace("/", "\\"))
                if path.is_dir():
                    return path
            elif uri.startswith("file://"):
                path = Path(uri[len("file://"):])
                if path.is_dir():
                    return path

    # 退路：在缓存里找，取版本号最大的那个。
    cache_root = Path.home() / "AppData" / "Local" / "Pub" / "Cache" / "hosted"
    candidates: list[Path] = []
    for host in ("pub.dev", "pub.flutter-io.cn"):
        host_dir = cache_root / host
        if host_dir.is_dir():
            candidates.extend(host_dir.glob("ech_http-*"))
    if not candidates:
        return None

    def version_key(path: Path) -> tuple:
        tail = path.name.split("-", 1)[-1]
        parts = []
        for chunk in tail.split("."):
            digits = "".join(ch for ch in chunk if ch.isdigit())
            parts.append(int(digits) if digits else 0)
        return tuple(parts)

    return max(candidates, key=version_key)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_ech_http_ca.py <flutter-project-root>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    if not root.is_dir():
        print(f"Project root not found: {root}", file=sys.stderr)
        return 2

    package = resolve_package_dir(root)
    if package is None:
        print("ech_http package not found; run `flutter pub get` first.", file=sys.stderr)
        return 1
    src = package / "src"
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
