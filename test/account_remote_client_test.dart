import 'package:flutter_test/flutter_test.dart';
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
}