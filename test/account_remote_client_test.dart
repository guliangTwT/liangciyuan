import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/account/account_api.dart';
import 'package:kazumi/services/sync/account_remote_client.dart';

void main() {
  test('maps remote paths to stable blob kinds', () {
    const paths = [
      '/kazumiSync/history/snapshot.json',
      '/kazumiSync/history/changes/abcd.jsonl',
      '/kazumiSync/danmakuShield/device.json',
      '/kazumiSync/collectibles.tmp.cache',
      '/kazumiSync/histories.tmp',
    ];
    for (final path in paths) {
      final kind = AccountRemoteClient.kindFor(path);
      expect(kind, matches(RegExp(r'^[a-zA-Z0-9_\-]{1,200}$')));
      expect(AccountRemoteClient.pathForKind(kind), path);
    }
    expect(AccountRemoteClient.kindFor('/kazumiSync/collectibles.tmp'),
        'collectibles');
    expect(AccountRemoteClient.pathForKind('collectibles'),
        '/kazumiSync/collectibles.tmp');
  });

  group('upload', () {
    late Directory directory;
    late _FakeAccountApi api;
    late AccountRemoteClient client;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('account_remote_');
      api = _FakeAccountApi();
      client = AccountRemoteClient(token: 'token', api: api);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('skips empty files instead of sending an empty payload', () async {
      final file = File('${directory.path}/collectibles.tmp');
      await file.writeAsBytes(const []);

      await client.writeFromFile(file.path, '/kazumiSync/collectibles.tmp');

      expect(api.puts, isEmpty);
    });

    test('uploads non-empty files as base64 with the mapped kind', () async {
      final file = File('${directory.path}/collectibles.tmp');
      await file.writeAsBytes([1, 2, 3]);

      await client.writeFromFile(file.path, '/kazumiSync/collectibles.tmp');

      expect(api.puts, hasLength(1));
      expect(api.puts.single.kind, 'collectibles');
      expect(base64Decode(api.puts.single.payload), [1, 2, 3]);
      expect(api.puts.single.updatedAt, greaterThan(0));
    });
  });
}

class _FakeAccountApi implements AccountApi {
  final puts = <_Put>[];

  @override
  Future<void> putBlob(
    String token,
    String kind,
    String payload, {
    required int updatedAt,
  }) async {
    puts.add(_Put(kind, payload, updatedAt));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Put {
  const _Put(this.kind, this.payload, this.updatedAt);

  final String kind;
  final String payload;
  final int updatedAt;
}