import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';

void main() {
  group('bundled default rule', () {
    test('parses as a usable giriGiriLove source', () {
      final raw = File('assets/rules/giriGiriLove.json').readAsStringSync();
      final json = jsonDecode(raw);
      expect(json, isA<Map>());

      final plugin = Plugin.fromJson(Map<String, dynamic>.from(json as Map));
      expect(plugin.name, 'giriGiriLove');
      expect(plugin.baseUrl, 'https://ani.girigirilove.com');
      expect(plugin.requiresNewerClient, isFalse);
      expect(plugin.usesApiSearch, isTrue);
      expect(plugin.searchApiConfig.request.url, isNotEmpty);
      expect(plugin.chapterApiConfig.request.url, isNotEmpty);
    });

    test('stays compatible with the client rule schema', () {
      final json = jsonDecode(
        File('assets/rules/giriGiriLove.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['api'], '9');
      expect(json['type'], 'anime');
      expect(json['useNativePlayer'], isTrue);
    });
  });
}
