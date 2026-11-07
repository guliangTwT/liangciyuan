// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/player/controller/player_models.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/player/syncplay_client.dart';
import 'package:kazumi/services/player/syncplay_endpoint.dart';
import 'package:kazumi/utils/async_session.dart';
import 'package:mobx/mobx.dart';

part 'player_syncplay_controller.g.dart';

class PlayerSyncPlayController = _PlayerSyncPlayController
    with _$PlayerSyncPlayController;

abstract class _PlayerSyncPlayController with Store {
  _PlayerSyncPlayController({
    required this.bangumiId,
    required this.currentEpisode,
    required this.currentRoad,
    required this.playing,
    required this.currentPosition,
    required this.playerPosition,
    required this.duration,
    required this.pause,
    required this.play,
    required this.seek,
  });

  final int Function() bangumiId;
  final int Function() currentEpisode;
  final int Function() currentRoad;
  final bool Function() playing;
  final Duration Function() currentPosition;
  final Duration Function() playerPosition;
  final Duration Function() duration;
  final Future<void> Function({bool enableSync}) pause;
  final Future<void> Function({bool enableSync}) play;
  final Future<void> Function(Duration duration, {bool enableSync}) seek;

  /// Set before the socket opens and cleared on teardown, so unlike
  /// [syncplayRoom] it also covers the window where the connection is still
  /// being established.
  @observable
  SyncplayClient? syncplayController;

  /// 远端与本地的位置偏差超过该值才跳转；太小会与缓冲抖动互相拉扯。
  static const int _seekThresholdMs = 2000;

  /// 自己触发的状态回传：偏差在此范围内直接忽略，避免本地跳转被回传
  /// 位置（含服务器往返延迟）反复纠正，形成来回跳动。
  static const int _ownEchoIgnoreDriftMs = 3000;

  final AsyncSessionOwner _connectionSessions = AsyncSessionOwner();
  @observable
  String syncplayRoom = '';
  @observable
  int syncplayClientRtt = 0;

  bool get hasSession => syncplayController != null;

  final StreamController<SyncPlayChatMessage> _chatStreamController =
      StreamController<SyncPlayChatMessage>.broadcast();

  Stream<SyncPlayChatMessage> get chatStream => _chatStreamController.stream;

  void emitChatMessage({
    required String username,
    required String message,
    required bool fromRemote,
  }) {
    if (_chatStreamController.isClosed) {
      return;
    }
    _chatStreamController.add(
      SyncPlayChatMessage(
        username: username,
        message: message,
        fromRemote: fromRemote,
      ),
    );
  }

  Future<void> createRoom(
    String room,
    String username,
    Future<void> Function(int episode, {int currentRoad, int offset})
    changeEpisode,
  ) async {
    if (_connectionSessions.isClosed) {
      return;
    }
    final session = _connectionSessions.begin();
    final previousClient = syncplayController;
    syncplayController = null;
    syncplayRoom = '';
    syncplayClientRtt = 0;
    await previousClient?.disconnect();
    if (session.isStale) {
      return;
    }
    final String syncPlayEndPoint = GStorage.getSetting(
      SettingsKeys.syncPlayEndPoint,
    );
    KazumiLogger().i('SyncPlay: connecting to $syncPlayEndPoint');
    final parsed = parseSyncPlayEndPoint(syncPlayEndPoint);
    if (parsed == null) {
      KazumiDialog.showToast(message: 'SyncPlay: 服务器地址不合法 $syncPlayEndPoint');
      KazumiLogger().e('SyncPlay: invalid server address $syncPlayEndPoint');
      return;
    }
    final enableTLS = isOfficialSyncPlayEndPoint(parsed);
    final client = SyncplayClient(host: parsed.host, port: parsed.port);
    syncplayController = client;
    try {
      await client.connect(enableTLS: enableTLS);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      KazumiLogger().i('SyncPlay: connected to ${parsed.host}:${parsed.port}');
      client.onGeneralMessage.listen(
        null,
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final message = error is SyncplayException
              ? error.message
              : error.toString();
          KazumiLogger().e('SyncPlay: error $message', error: error);
          if (error is SyncplayConnectionException) {
            exitRoom();
            KazumiDialog.showToast(
              message: 'SyncPlay: 同步中断 $message',
              duration: const Duration(seconds: 5),
              showActionButton: true,
              actionLabel: '重新连接',
              onActionPressed: () => createRoom(room, username, changeEpisode),
            );
          }
        },
      );
      client.onRoomMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        if (message['type'] == 'init') {
          if (message['username'] == '') {
            KazumiDialog.showToast(
              message: 'SyncPlay: 您是当前房间中的唯一用户',
              duration: const Duration(seconds: 5),
            );
            setPlayingBangumi();
          } else {
            KazumiDialog.showToast(
              message:
                  'SyncPlay: 您不是当前房间中的唯一用户, 当前以用户 ${message['username']} 进度为准',
            );
          }
        }
        if (message['type'] == 'left') {
          KazumiDialog.showToast(
            message: 'SyncPlay: ${message['username']} 离开了房间',
            duration: const Duration(seconds: 5),
          );
        }
        if (message['type'] == 'joined') {
          KazumiDialog.showToast(
            message: 'SyncPlay: ${message['username']} 加入了房间',
            duration: const Duration(seconds: 5),
          );
        }
      });
      client.onFileChangedMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        KazumiLogger().i(
          'SyncPlay: file changed by ${message['setBy']}: ${message['name']}',
        );
        RegExp regExp = RegExp(r'(\d+)\[(\d+)\]');
        Match? match = regExp.firstMatch(message['name']);
        if (match != null) {
          int bangumiID = int.tryParse(match.group(1) ?? '0') ?? 0;
          int episode = int.tryParse(match.group(2) ?? '0') ?? 0;
          // 只跟随同一个番剧的切集；否则会把本地跳到无关番剧的集数，
          // 甚至因集数越界在停播后进入错误页。
          if (bangumiID != 0 &&
              bangumiID == bangumiId() &&
              episode != 0 &&
              episode != currentEpisode()) {
            KazumiDialog.showToast(
              message:
                  'SyncPlay: ${message['setBy'] ?? 'unknown'} 切换到第 $episode 话',
              duration: const Duration(seconds: 3),
            );
            changeEpisode(episode, currentRoad: currentRoad());
          }
        }
      });
      client.onChatMessage.listen(
        (message) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final String sender = (message['username'] ?? '').toString();
          final String text = (message['message'] ?? '').toString();
          final bool fromRemote = message['username'] != username;

          emitChatMessage(
            username: sender,
            message: text,
            fromRemote: fromRemote,
          );
        },
        onError: (error) {
          if (!_isCurrentConnection(session, client)) {
            return;
          }
          final message = error is SyncplayException
              ? error.message
              : error.toString();
          KazumiLogger().e('SyncPlay: error $message', error: error);
        },
      );
      client.onPositionChangedMessage.listen((message) {
        if (!_isCurrentConnection(session, client)) {
          return;
        }
        syncplayClientRtt = (message['clientRtt'].toDouble() * 1000).toInt();
        final double calculatedPosition =
            message['calculatedPositon'].toDouble();
        final int driftMs =
            (playerPosition().inMilliseconds - (calculatedPosition * 1000).toInt())
                .abs();
        // 服务端会把状态回传给发起者。发起者本地已经跳到位，若再按回传的
        // 位置（服务器算出的值通常还带着往返延迟）跳一次，用户会看到
        // 「拖一下进度条又被打回去」的抖动。只有偏离较大时才纠正。
        final bool ownEcho = message['setBy'] == username;
        KazumiLogger().i(
          'SyncPlay: position changed by ${message['setBy']}: calculatedPosition $calculatedPosition position: ${message['position']} doSeek: ${message['doSeek']} paused: ${message['paused']} drift: ${driftMs}ms ownEcho: $ownEcho',
        );
        // 自己发起的暂停/播放回调不重复提示，但状态仍需保持一致。
        if (message['paused'] != !playing()) {
          if (message['paused']) {
            if (message['position'] != 0) {
              if (!ownEcho) {
                KazumiDialog.showToast(
                  message: 'SyncPlay: ${message['setBy'] ?? 'unknown'} 暂停了播放',
                  duration: const Duration(seconds: 3),
                );
              }
              pause(enableSync: false);
            }
          } else {
            if (message['position'] != 0) {
              if (!ownEcho) {
                KazumiDialog.showToast(
                  message: 'SyncPlay: ${message['setBy'] ?? 'unknown'} 开始了播放',
                  duration: const Duration(seconds: 3),
                );
              }
              play(enableSync: false);
            }
          }
        }
        // 自己的操作已经在本机生效，回传位置还带着往返延迟，
        // 再跳一次会出现「拖完进度条又被打回去」的抖动。
        if (ownEcho && driftMs <= _ownEchoIgnoreDriftMs) {
          return;
        }
        if ((driftMs > _seekThresholdMs || message['doSeek']) &&
            duration().inMilliseconds > 0) {
          seek(
            Duration(milliseconds: (calculatedPosition * 1000).toInt()),
            enableSync: false,
          );
        }
      });
      await client.joinRoom(room, username);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      syncplayRoom = room;
    } catch (e) {
      KazumiLogger().e('SyncPlay: error', error: e);
      if (!_isCurrentConnection(session, client)) {
        await client.disconnect();
        return;
      }
      syncplayController = null;
      syncplayRoom = '';
      syncplayClientRtt = 0;
      await client.disconnect();
      final message = e is SyncplayException ? e.message : e.toString();
      KazumiDialog.showToast(
        message: 'SyncPlay: 连接失败 $message',
        duration: const Duration(seconds: 5),
      );
    }
  }

  bool _isCurrentConnection(AsyncSession session, SyncplayClient client) {
    return session.isActive && identical(syncplayController, client);
  }

  void setCurrentPosition({bool? forceSyncPlaying, double? forceSyncPosition}) {
    if (syncplayController == null) {
      return;
    }
    forceSyncPlaying ??= playing();
    syncplayController!.setPaused(!forceSyncPlaying);
    syncplayController!.setPosition(
      (forceSyncPosition ??
          (((currentPosition().inMilliseconds - playerPosition().inMilliseconds)
                      .abs() >
                  2000)
              ? currentPosition().inMilliseconds.toDouble() / 1000
              : playerPosition().inMilliseconds.toDouble() / 1000)),
    );
  }

  Future<void> setPlayingBangumi({
    bool? forceSyncPlaying,
    double? forceSyncPosition,
  }) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(() async {
      await client.setSyncPlayPlaying(
        "${bangumiId()}[${currentEpisode()}]",
        10800,
        220514438,
      );
      if (!identical(syncplayController, client)) {
        return;
      }
      setCurrentPosition(
        forceSyncPlaying: forceSyncPlaying,
        forceSyncPosition: forceSyncPosition,
      );
      await client.sendSyncPlaySyncRequest(doSeek: null);
    });
  }

  Future<void> requestSync({bool? doSeek}) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(
      () => client.sendSyncPlaySyncRequest(doSeek: doSeek),
    );
  }

  Future<void> sendChatMessage(String message) async {
    final client = syncplayController;
    if (client == null) {
      return;
    }
    await _runBestEffortSync(() => client.sendChatMessage(message));
  }

  Future<void> _runBestEffortSync(Future<void> Function() operation) async {
    try {
      await operation();
    } on SyncplayConnectionException {
      // Socket handlers report active connection failures.
    }
  }

  @action
  Future<void> exitRoom() async {
    _connectionSessions.cancel();
    final controller = syncplayController;
    syncplayController = null;
    syncplayRoom = '';
    syncplayClientRtt = 0;
    if (controller == null) {
      return;
    }
    await controller.disconnect();
  }

  Future<void> dispose() async {
    _connectionSessions.close();
    await exitRoom();
    await _chatStreamController.close();
  }
}
