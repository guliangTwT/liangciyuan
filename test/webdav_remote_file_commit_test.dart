import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/sync/webdav_remote_file_commit.dart';

void main() {
  late Directory tempDirectory;
  late String sourcePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('webdav_commit_');
    sourcePath = '${tempDirectory.path}${Platform.pathSeparator}source.txt';
    await File(sourcePath).writeAsString('new-content');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  const temporaryPath = '/root/file.tmp.cache';
  const destinationPath = '/root/file.tmp';

  test(
    'accepts a MOVE that completes but is reported with status 200',
    () async {
      final remote = _FakeRemote({destinationPath: 'old-content'});

      await _commit(
        remote,
        sourcePath,
        rename: (from, to) async {
          final value = remote.files.remove(from);
          if (value == null) throw StateError('missing $from');
          remote.files[to] = value;
          // webdav_client rejects 200 for MOVE; the server did move the file.
          throw StateError('unexpected status 200');
        },
      );

      expect(remote.files[destinationPath], 'new-content');
    },
  );

  test('falls back to a direct PUT when overwrite MOVE is rejected', () async {
    final remote = _FakeRemote({destinationPath: 'old-content'});

    await _commit(
      remote,
      sourcePath,
      rename: (from, to) async {
        if (remote.files.containsKey(to)) {
          throw StateError('409 conflict');
        }
        final value = remote.files.remove(from);
        if (value == null) throw StateError('missing $from');
        remote.files[to] = value;
      },
    );

    expect(remote.files[destinationPath], 'new-content');
    // 旧文件不应在替换前被删除。
    expect(remote.removed, isNot(contains(destinationPath)));
  });

  test('falls back to a direct upload when MOVE is unsupported', () async {
    final remote = _FakeRemote({destinationPath: 'old-content'});

    await _commit(
      remote,
      sourcePath,
      rename: (from, to) async => throw StateError('405 method not allowed'),
    );

    expect(remote.files[destinationPath], 'new-content');
  });

  test('keeps the uploaded temporary file when every strategy fails', () async {
    final remote = _FakeRemote({destinationPath: 'old-content'});

    await expectLater(
      _commit(
        remote,
        sourcePath,
        rename: (from, to) async => throw StateError('405'),
        failUploadToDestination: true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(remote.files[temporaryPath], 'new-content');
    // 所有策略都失败时，旧的目标文件仍然保留。
    expect(remote.files[destinationPath], 'old-content');
    expect(remote.removed, isNot(contains(destinationPath)));
  });
}

Future<void> _commit(
  _FakeRemote remote,
  String sourcePath, {
  required Future<void> Function(String from, String to) rename,
  bool failUploadToDestination = false,
}) {
  const temporaryPath = '/root/file.tmp.cache';
  const destinationPath = '/root/file.tmp';
  return const WebDavRemoteFileCommitter().replaceFile(
    sourceFilePath: sourcePath,
    temporaryPath: temporaryPath,
    destinationPath: destinationPath,
    remove: (path) async {
      if (remote.files.remove(path) == null) {
        throw StateError('404 $path');
      }
      remote.removed.add(path);
    },
    uploadFromFile: (source, destination) async {
      if (failUploadToDestination && destination == destinationPath) {
        throw StateError('upload failed');
      }
      remote.files[destination] = await File(source).readAsString();
    },
    rename: rename,
    exists: (path) async => remote.files.containsKey(path),
  );
}

class _FakeRemote {
  _FakeRemote(Map<String, String> initial) : files = Map.of(initial);

  final Map<String, String> files;
  final List<String> removed = [];
}
