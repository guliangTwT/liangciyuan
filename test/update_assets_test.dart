import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/services/update/update_downloader.dart';

void main() {
  group('update release assets', () {
    const assets = <dynamic>[
      {
        'name': 'liangciyuan-3.11.0-android-arm64.apk',
        'browser_download_url':
            'https://codeberg.org/GuLiang/liangciyuan/releases/download/3.11.0/a.apk',
        'digest':
            'sha256:0b8cec731144e5a35b523a0dc8b513957a9c2afb4af08da97347de0e398803a0',
      },
      {
        'name': 'liangciyuan-3.11.0-windows-x64.zip',
        'browser_download_url':
            'https://codeberg.org/GuLiang/liangciyuan/releases/download/3.11.0/a.zip',
        'digest':
            'sha256:d8351fba1cd359d6cc8758b4dd6ad8fb4442c2698a9d2259ebda918238b80685',
      },
      {
        'name': 'liangciyuan-3.11.0-windows-x64-setup.exe',
        'browser_download_url':
            'https://codeberg.org/GuLiang/liangciyuan/releases/download/3.11.0/a.exe',
        'digest':
            'sha256:d8351fba1cd359d6cc8758b4dd6ad8fb4442c2698a9d2259ebda918238b80685',
      },
      {
        'name': 'checksums.txt',
        'browser_download_url':
            'https://codeberg.org/GuLiang/liangciyuan/releases/download/3.11.0/checksums.txt',
      },
    ];

    test('matches the Android APK asset', () {
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(asset?['name'], 'liangciyuan-3.11.0-android-arm64.apk');
    });

    test('matches the Windows setup installer asset', () {
      final asset = getUpdateAssetForType(assets, InstallationType.windowsSetup);
      expect(asset?['name'], 'liangciyuan-3.11.0-windows-x64-setup.exe');
      // 安装包为 Windows 默认推荐类型。
      expect(
        getUpdateFilePatterns(InstallationType.windowsSetup).isNotEmpty,
        isTrue,
      );
    });

    test('matches the Windows portable ZIP asset', () {
      final asset = getUpdateAssetForType(
        assets,
        InstallationType.windowsPortable,
      );
      expect(asset?['name'], 'liangciyuan-3.11.0-windows-x64.zip');
    });

    test('has no MSIX asset, so the dialog must not default to it', () {
      expect(
        getUpdateAssetForType(assets, InstallationType.windowsMsix),
        isNull,
      );
    });

    test('direct source uses the Codeberg browser download URL', () {
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(
        getUpdateDownloadUrlFromAsset(asset, UpdateDownloadSource.direct),
        startsWith('https://codeberg.org/GuLiang/liangciyuan/releases/'),
      );
    });

    test('mirror source is empty because this release has no mirror URL', () {
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(
        getUpdateDownloadUrlFromAsset(asset, UpdateDownloadSource.mirror),
        isEmpty,
      );
    });

    test('candidates put the direct URL first and add acceleration mirrors', () {
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      final candidates = getUpdateDownloadUrlCandidatesFromAsset(
        asset,
        UpdateDownloadSource.direct,
      );
      expect(candidates.first, startsWith('https://codeberg.org/'));
      // Codeberg 地址会附带一个 GitHub 后备地址。
      expect(candidates.length, greaterThan(1));
    });

    test('asset SHA-256 is parsed for integrity checking', () {
      final asset = getUpdateAssetForType(assets, InstallationType.androidApk);
      expect(
        getUpdateFileHashFromAsset(asset!),
        '0b8cec731144e5a35b523a0dc8b513957a9c2afb4af08da97347de0e398803a0',
      );
    });
  });
}