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
  });

  group('needUpdate with v-prefixed tags', () {
    test('recognises a newer v-tag', () {
      expect(needUpdate('1.0.0', 'v1.0.1'), isTrue);
      expect(needUpdate('1.0.0', 'V2.0.0'), isTrue);
    });

    test('same version is not an update', () {
      expect(needUpdate('1.0.0', 'v1.0.0'), isFalse);
    });

    test('older remote version is not an update', () {
      expect(needUpdate('1.0.0', 'v0.9.9'), isFalse);
    });

    test('shorter remote version pads with zeros', () {
      expect(needUpdate('1.0.0', 'v1.1'), isTrue);
      expect(needUpdate('1.0', 'v1.0.0'), isFalse);
    });
  });
}
