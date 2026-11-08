import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/version.dart';

void main() {
  group('normalizeVersionTag', () {
    test('strips a leading v or V', () {
      expect(normalizeVersionTag('v1.0.0'), '1.0.0');
      expect(normalizeVersionTag('V1.0.0'), '1.0.0');
      expect(normalizeVersionTag('1.0.0'), '1.0.0');
      expect(normalizeVersionTag('  v2.3 '), '2.3');
    });

    test('drops pre-release suffixes instead of throwing', () {
      // 之前 int.parse('5-beta') 会抛 FormatException，
      // 一次畸形 tag 就能让全量客户端的自动更新静默失效。
      expect(normalizeVersionTag('v1.0.5-beta'), '1.0.5');
      expect(normalizeVersionTag('1.0.5-rc1'), '1.0.5');
      expect(normalizeVersionTag('2.1.0-rc.2'), '2.1.0');
    });

    test('drops build metadata', () {
      expect(normalizeVersionTag('1.0.4+10104'), '1.0.4');
      expect(normalizeVersionTag('v1.0.4+10104'), '1.0.4');
    });

    test('returns empty for a version with no digits', () {
      expect(normalizeVersionTag('latest'), '');
      expect(normalizeVersionTag(''), '');
      expect(normalizeVersionTag('v'), '');
    });
  });

  group('needUpdate', () {
    test('recognises a newer version', () {
      expect(needUpdate('1.0.0', '1.0.1'), isTrue);
      expect(needUpdate('1.0.0', 'v1.0.1'), isTrue);
      expect(needUpdate('1.0.4', 'v1.0.5'), isTrue);
    });

    test('same version is not an update', () {
      expect(needUpdate('1.0.0', 'v1.0.0'), isFalse);
      expect(needUpdate('1.0.4', '1.0.4'), isFalse);
    });

    test('older remote version is not an update', () {
      expect(needUpdate('1.0.0', 'v0.9.9'), isFalse);
      expect(needUpdate('2.0.0', 'v1.9.9'), isFalse);
    });

    test('pads shorter versions with zeros', () {
      expect(needUpdate('1.0.0', 'v1.1'), isTrue);
      expect(needUpdate('1.0', 'v1.0.0'), isFalse);
      expect(needUpdate('1.0.1', 'v1.0'), isFalse);
    });

    test('build metadata on the local side is ignored', () {
      // 某些构建方式会把 +build 带进 appBuildName。
      expect(needUpdate('1.0.4+10104', 'v1.0.5'), isTrue);
      expect(needUpdate('1.0.4+10104', 'v1.0.4'), isFalse);
    });

    test('a malformed remote tag never triggers an update', () {
      // 远端 tag 不可解析时宁可判为「无更新」，也不能崩掉整条检查链路。
      expect(needUpdate('1.0.0', 'nightly'), isFalse);
      expect(needUpdate('1.0.0', ''), isFalse);
      expect(needUpdate('1.0.0', 'v'), isFalse);
    });

    test('pre-release remote tag compares on the numeric part', () {
      expect(needUpdate('1.0.4', 'v1.0.5-beta'), isTrue);
      expect(needUpdate('1.0.5', 'v1.0.5-rc1'), isFalse);
    });

    test('non-numeric local version does not throw', () {
      expect(() => needUpdate('', 'v1.0.0'), returnsNormally);
      expect(() => needUpdate('unknown', 'v1.0.0'), returnsNormally);
      expect(needUpdate('', 'v1.0.0'), isTrue);
    });
  });
}
