import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';

/// 用**真实发布出来的资产**验证更新器的选择结果。
///
/// 数据来自 `dart run tool/verify_update_channel.dart --download` 抓到的
/// GitHub Release 资产列表（存在 build 目录，不进仓库）。文件不存在时跳过，
/// 这样 CI/别的机器上跑测试也不会红。
void main() {
  final fixture = File('D:/build/gh-rel-assets.json');
  final hasFixture = fixture.existsSync();

  group('真实发布资产', () {
    late List<dynamic> assets;

    setUpAll(() {
      if (!hasFixture) return;
      assets = jsonDecode(fixture.readAsStringSync()) as List<dynamic>;
    });

    test('资产数量与发布一致', () {
      if (!hasFixture) return;
      expect(assets.length, greaterThanOrEqualTo(4));
    });

    test('Windows 选中 setup.exe 且带 64 位校验值', () {
      if (!hasFixture) return;
      final asset = getUpdateAssetForType(assets, InstallationType.windowsSetup);
      expect(asset, isNotNull);
      expect(asset!['name'] as String, endsWith('setup.exe'));
      expect(getUpdateFileHashFromAsset(asset).length, 64);
    });

    test('Android 选中 .apk 且带 64 位校验值', () {
      if (!hasFixture) return;
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(asset, isNotNull);
      final name = asset!['name'] as String;
      expect(name, contains('android'));
      expect(name, endsWith('.apk'));
      expect(getUpdateFileHashFromAsset(asset).length, 64);
    });

    test('选中的 APK 只属于一个架构', () {
      if (!hasFixture) return;
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      final name = asset!['name'] as String;
      final markers = <String>[
        if (name.contains('arm64')) 'arm64',
        if (name.contains('armv7') || name.contains('armeabi')) 'armv7',
        if (name.contains('x86_64')) 'x86_64',
      ];
      expect(markers.length, 1, reason: '选中包名 $name 应恰好含一个架构标记');
    });

    test('没有 windows zip，所以便携版应为空', () {
      if (!hasFixture) return;
      expect(
        getUpdateAssetForType(assets, InstallationType.windowsPortable),
        isNull,
      );
    });
  });
}
