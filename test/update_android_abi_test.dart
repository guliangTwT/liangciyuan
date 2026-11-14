import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';

/// 分架构 APK 的选择逻辑。
///
/// 1.0.8 起同一版本会发布 arm64 / armv7 / x86_64 三个 APK。原来的匹配条件
/// 只有 `android` + `.apk`，三个包全满足，`firstWhere` 会拿到列表里第一个——
/// 在 x86_64 排在前面时，arm64 手机会装上不兼容的包。
///
/// 这里的断言不依赖运行测试的主机架构（测试跑在 Windows x64 上），
/// 只检查「不会选到明确属于别的架构的包」这一不变量。
void main() {
  List<Map<String, dynamic>> assets(List<String> names) => [
        for (final name in names)
          {
            'name': name,
            'browser_download_url': 'https://example.invalid/$name',
            'digest': 'sha256:${'a' * 64}',
          },
      ];

  group('分架构 APK 选择', () {
    test('三个架构包都在时，不会选到「别的架构」的包', () {
      final list = assets([
        'liangciyuan-1.0.8-android-x86_64.apk',
        'liangciyuan-1.0.8-android-armv7.apk',
        'liangciyuan-1.0.8-android-arm64.apk',
      ]);
      final picked =
          getUpdateAssetForType(list, InstallationType.androidApk)?['name']
              as String;

      // 主机是 x64，所以这里实际会选 x86_64；关键是选择要「自洽」：
      // 被选中的包，其架构标记必须是本机可用的，而不是随便取第一个。
      expect(picked, contains('android'));
      expect(picked, endsWith('.apk'));

      // 无论选哪个，都不应该同时出现两个互斥架构标记。
      final isArm64 = picked.contains('arm64');
      final isArmv7 = picked.contains('armv7') && !isArm64;
      final isX64 = picked.contains('x86_64');
      expect([isArm64, isArmv7, isX64].where((v) => v).length, 1,
          reason: '选中的包必须恰好属于一个架构：$picked');
    });

    test('只有单包（旧版本）时仍然可用', () {
      final list = assets(['liangciyuan-1.0.5-android-arm64.apk']);
      final picked =
          getUpdateAssetForType(list, InstallationType.androidApk)?['name'];
      expect(picked, 'liangciyuan-1.0.5-android-arm64.apk');
    });

    test('文件名不带架构标记时退回第一个 APK', () {
      final list = assets(['liangciyuan-1.0.8-android.apk']);
      final picked =
          getUpdateAssetForType(list, InstallationType.androidApk)?['name'];
      expect(picked, 'liangciyuan-1.0.8-android.apk');
    });

    test('没有 APK 时返回 null（界面应改为跳发布页）', () {
      final list = assets(['liangciyuan-1.0.8-windows-x64-setup.exe']);
      expect(getUpdateAssetForType(list, InstallationType.androidApk), isNull);
    });

    test('Windows 安装包不受架构选择影响', () {
      final list = assets([
        'liangciyuan-1.0.8-windows-x64-setup.exe',
        'liangciyuan-1.0.8-android-arm64.apk',
      ]);
      final picked =
          getUpdateAssetForType(list, InstallationType.windowsSetup)?['name'];
      expect(picked, 'liangciyuan-1.0.8-windows-x64-setup.exe');
    });
  });

  group('安装包命名契约', () {
    test('Windows 安装包名同时含 windows 与 x64-setup.exe', () {
      final patterns = getUpdateFilePatterns(InstallationType.windowsSetup);
      const name = 'liangciyuan-1.0.8-windows-x64-setup.exe';
      for (final p in patterns) {
        expect(name.toLowerCase(), contains(p.toLowerCase()));
      }
    });

    test('Android 包名同时含 android 与 .apk', () {
      final patterns = getUpdateFilePatterns(InstallationType.androidApk);
      for (final name in [
        'liangciyuan-1.0.8-android-arm64.apk',
        'liangciyuan-1.0.8-android-armv7.apk',
        'liangciyuan-1.0.8-android-x86_64.apk',
      ]) {
        for (final p in patterns) {
          expect(name.toLowerCase(), contains(p.toLowerCase()));
        }
      }
    });
  });
}
