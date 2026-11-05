import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/storage/settings_keys.dart';

void main() {
  group('room danmaku settings', () {
    test('room danmaku is on by default and only-room is off', () {
      expect(SettingsKeys.danmakuRoomEnabled.defaultValue, isTrue);
      expect(SettingsKeys.danmakuRoomOnly.defaultValue, isFalse);
    });

    test('both keys are registered for persistence and reset', () {
      expect(SettingsKeys.all, contains(SettingsKeys.danmakuRoomEnabled));
      expect(SettingsKeys.all, contains(SettingsKeys.danmakuRoomOnly));

      final danmakuKeys = SettingsKeys.byGroup(SettingGroup.danmaku);
      expect(danmakuKeys, contains(SettingsKeys.danmakuRoomEnabled));
      expect(danmakuKeys, contains(SettingsKeys.danmakuRoomOnly));
    });
  });
}