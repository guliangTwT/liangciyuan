import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';

void main() {
  group('github fallback url', () {
    test('wraps GitHub API release endpoint', () {
      final url = githubFallbackUrl(
        'https://api.github.com/repos/GuLiang-I/liangciyuan/releases/latest',
      );
      expect(
        url.toString(),
        'https://gh-proxy.org/https://api.github.com/repos/GuLiang-I/liangciyuan/releases/latest',
      );
    });

    test('wraps GitHub release asset downloads', () {
      final url = githubFallbackUrl(
        'https://github.com/GuLiang-I/liangciyuan/releases/download/3.0.0/liangciyuan-3.0.0-windows-x64-setup.exe',
      );
      expect(url, isNotNull);
      expect(url.toString(), startsWith('https://gh-proxy.org/https://github.com/'));
    });

    test('leaves non-GitHub URLs untouched', () {
      expect(githubFallbackUrl('https://maven.aliyun.com/x.jar'), isNull);
      expect(
        githubFallbackUrl('https://gh-proxy.org/https://github.com/a/b'),
        isNull,
      );
    });
  });
}
