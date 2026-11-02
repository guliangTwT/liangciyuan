import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PathProviderPlatform originalPaths;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kazumi_plugins_test_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  File storedRulesFile() =>
      File('${directory.path}/plugins/v2/plugins.json');

  test('a fresh install installs the bundled default rule', () async {
    final controller = PluginsController(pluginJsonWriter: (jsonData) async {
      await storedRulesFile().writeAsString(jsonData);
    });

    await controller.init();

    expect(controller.isFirstRun, isTrue);
    expect(controller.pluginList.map((plugin) => plugin.name),
        contains('giriGiriLove'));
  });

  test('existing rules are kept and are not a first run', () async {
    final file = storedRulesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([
      {'api': '9', 'name': 'custom', 'version': '1.0'},
    ]));
    final controller = PluginsController(pluginJsonWriter: (_) async {});

    await controller.init();

    expect(controller.isFirstRun, isFalse);
    expect(controller.pluginList.map((plugin) => plugin.name), ['custom']);
  });

  test('rules the user deleted stay deleted', () async {
    final file = storedRulesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString('[]');
    final controller = PluginsController(pluginJsonWriter: (_) async {});

    await controller.init();

    expect(controller.isFirstRun, isFalse);
    expect(controller.pluginList, isEmpty);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
