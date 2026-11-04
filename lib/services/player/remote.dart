import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';

class RemotePlay {
  Future<void> castVideo(String video, String referer) async {
    final searcher = DLNAManager();
    final dlna = await searcher.start();
    List<Widget> dlnaDevice = [];
    StreamSubscription? deviceSubscription;
    var dialogOpen = true;

    void stopWatchingDevices() {
      deviceSubscription?.cancel();
      deviceSubscription = null;
    }

    await KazumiDialog.show(
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('远程投屏'),
              content: SingleChildScrollView(
                child: Column(children: dlnaDevice),
              ),
              actions: [
                const SizedBox(width: 20),
                TextButton(
                  onPressed: () => KazumiDialog.dismiss(),
                  child: Text(
                    '退出',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      dlnaDevice = [];
                    });
                    KazumiDialog.showToast(message: '开始搜索');
                    stopWatchingDevices();
                    deviceSubscription = dlna.devices.stream.listen((
                      deviceList,
                    ) {
                      final items = <Widget>[];
                      for (final value in deviceList.values) {
                        KazumiLogger().i(
                          'RemotePlay: ${value.info.friendlyName} ${value.info.deviceType}',
                        );
                        final typeName = _deviceTypeName(value.info.deviceType);
                        items.add(
                          ListTile(
                            leading: _deviceUPnPIcon(typeName),
                            title: Text(value.info.friendlyName),
                            subtitle: Text(typeName),
                            onTap: () async {
                              try {
                                KazumiDialog.showToast(
                                  message: '尝试投屏至 ${value.info.friendlyName}',
                                );
                                final device = DLNADevice(value.info);
                                await device.setUrl(video);
                                await device.play();
                              } catch (e) {
                                KazumiLogger().e(
                                  'RemotePlay: failed to cast to device',
                                  error: e,
                                );
                                KazumiDialog.showToast(
                                  message: 'DLNA 异常: $e \n尝试重新进入 DLNA 投屏或切换设备',
                                );
                              }
                            },
                          ),
                        );
                      }
                      if (!dialogOpen) return;
                      setState(() => dlnaDevice = items);
                    });
                  },
                  child: Text(
                    '搜索',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      onDismiss: () {
        dialogOpen = false;
        stopWatchingDevices();
        searcher.stop();
      },
    );
    dialogOpen = false;
    stopWatchingDevices();
  }

  /// 兼容 `urn:schemas-upnp-org:device:MediaRenderer:1` 与裸 `MediaRenderer`。
  String _deviceTypeName(String deviceType) {
    final parts = deviceType.split(':');
    return parts.length > 3 ? parts[3] : deviceType;
  }

  Icon _deviceUPnPIcon(String deviceType) {
    switch (deviceType) {
      case 'MediaRenderer':
        return const Icon(Icons.cast_connected);
      case 'MediaServer':
        return const Icon(Icons.cast_connected);
      case 'InternetGatewayDevice':
        return const Icon(Icons.router);
      case 'BasicDevice':
        return const Icon(Icons.device_hub);
      case 'DimmableLight':
        return const Icon(Icons.lightbulb);
      case 'WLANAccessPoint':
        return const Icon(Icons.lan);
      case 'WLANConnectionDevice':
        return const Icon(Icons.wifi_tethering);
      case 'Printer':
        return const Icon(Icons.print);
      case 'Scanner':
        return const Icon(Icons.scanner);
      case 'DigitalSecurityCamera':
        return const Icon(Icons.camera_enhance_outlined);
      default:
        return const Icon(Icons.question_mark);
    }
  }
}
