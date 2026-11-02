import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_android/flutter_inappwebview_android.dart'
    as android_webview;
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

/// A real embedded browser for the bundled anime site.
///
/// The site is intentionally kept outside the XPath rule engine: the portal is
/// for browsing and playback inside the site itself, while the existing rule
/// search remains available for metadata-oriented workflows.
class WebPortalPage extends StatefulWidget {
  const WebPortalPage({super.key});

  @override
  State<WebPortalPage> createState() => _WebPortalPageState();
}

class _WebPortalPageState extends State<WebPortalPage> {
  WebviewController? _windowsController;
  StreamSubscription<String>? _titleSubscription;
  StreamSubscription<String>? _urlSubscription;
  StreamSubscription<HistoryChanged>? _historySubscription;

  PlatformInAppWebViewController? _mobileController;
  bool _loading = true;
  bool _mobileCreated = false;
  PlatformInAppWebViewWidget? _mobileWebView;
  String? _error;
  String _title = '网页';
  String _currentUrl = '';

  String get _homeUrl {
    final configured = GStorage.getSetting(SettingsKeys.webPortalUrl).trim();
    return _normalizeUrl(
      configured.isEmpty ? kDefaultWebPortalUrl : configured,
    );
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = _homeUrl;
    if (Platform.isWindows) {
      _initializeWindows();
    } else {
      _loading = true;
    }
  }

  Future<void> _initializeWindows() async {
    try {
      await WebviewController.initializeEnvironment();
      final controller = WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);
      _titleSubscription = controller.title.listen((value) {
        if (mounted && value.isNotEmpty) setState(() => _title = value);
      });
      _urlSubscription = controller.url.listen((value) {
        if (mounted && value.isNotEmpty) setState(() => _currentUrl = value);
      });
      _historySubscription = controller.historyChanged.listen((_) {
        if (mounted) setState(() {});
      });
      await controller.loadUrl(_homeUrl);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _windowsController = controller;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法启动内嵌浏览器：$error';
      });
    }
  }

  Future<void> _load(String url) async {
    final target = _normalizeUrl(url);
    setState(() {
      _error = null;
      _currentUrl = target;
    });
    try {
      if (Platform.isWindows) {
        await _windowsController?.loadUrl(target);
      } else {
        await _mobileController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(target)),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '网页加载失败：$error');
    }
  }

  Future<void> _reload() async {
    try {
      if (Platform.isWindows) {
        await _windowsController?.reload();
      } else {
        await _mobileController?.reload();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '刷新失败：$error');
    }
  }

  Future<void> _goBack() async {
    if (Platform.isWindows) {
      await _windowsController?.goBack();
    } else {
      await _mobileController?.goBack();
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      KazumiDialog.showToast(message: '无法打开外部浏览器');
    }
  }

  Future<void> _openHome() => _load(_homeUrl);

  Future<void> _showSitePicker() async {
    final sites = parseWebPortalSites(
      GStorage.getSetting(SettingsKeys.webPortalSites),
    );
    if (sites.isEmpty) {
      KazumiDialog.showToast(message: '还没有添加备用站点，可在「界面设置」中添加');
      return;
    }
    final selected = await KazumiDialog.show<String>(
      builder: (context) => SimpleDialog(
        title: const Text('切换网页'),
        children: [
          for (final site in sites)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(site),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.public_rounded),
                title: Text(site),
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      await _load(selected);
    }
  }

  Widget _buildMobileWebView() {
    if (Platform.isAndroid) {
      android_webview.AndroidInAppWebViewPlatform.registerWith();
    }
    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      supportMultipleWindows: false,
      useHybridComposition: true,
      transparentBackground: false,
    );
    _mobileWebView ??= PlatformInAppWebViewWidget(
      PlatformInAppWebViewWidgetCreationParams(
        initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
        initialSettings: settings,
        onWebViewCreated: (controller) {
          _mobileController = controller;
          if (mounted) setState(() => _mobileCreated = true);
          controller.addJavaScriptHandler(
            handlerName: 'KazumiNavigation',
            callback: (args) {
              if (args.isNotEmpty && args.first is String) {
                setState(() => _currentUrl = args.first as String);
              }
            },
          );
        },
        onLoadStart: (controller, url) {
          if (mounted) {
            setState(() {
              _loading = true;
              if (url != null) _currentUrl = url.toString();
            });
          }
        },
        onLoadStop: (controller, url) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = null;
            if (url != null) _currentUrl = url.toString();
          });
        },
        onTitleChanged: (controller, title) {
          if (mounted && title != null && title.isNotEmpty) {
            setState(() => _title = title);
          }
        },
        onReceivedError: (controller, request, error) {
          if (!mounted || request.isForMainFrame != true) return;
          setState(() {
            _loading = false;
            _error = '网页加载失败：${error.description}';
          });
        },
      ),
    );
    return _mobileWebView!.build(context);
  }

  @override
  void dispose() {
    _titleSubscription?.cancel();
    _urlSubscription?.cancel();
    _historySubscription?.cancel();
    unawaited(_windowsController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 64,
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '返回',
            onPressed: _goBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '主页',
            onPressed: _openHome,
            icon: const Icon(Icons.home_rounded),
          ),
          IconButton(
            tooltip: '切换网页',
            onPressed: _showSitePicker,
            icon: const Icon(Icons.travel_explore_rounded),
          ),
          IconButton(
            tooltip: '在浏览器中打开',
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(ClipboardData(text: _currentUrl));
                        KazumiDialog.showToast(message: '已复制网址');
                      },
                      child: Text(
                        _currentUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.public_off_rounded, size: 40),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: _reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _loading && _windowsController == null && Platform.isWindows
                ? const Center(child: CircularProgressIndicator())
                : Platform.isWindows
                ? (_windowsController == null
                      ? const SizedBox.shrink()
                      : Webview(_windowsController!))
                : Column(
                    children: [
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: _mobileCreated
                            ? _buildMobileWebView()
                            : const Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Strip whitespace and add a safe scheme when the user omits it.
String _normalizeUrl(String raw) {
  var value = raw.trim();
  if (!value.contains('://')) {
    value = 'https://$value';
  }
  return value;
}

/// The home URL is user-editable; keep the default in one place.
const String kDefaultWebPortalUrl = 'https://ani.girigirilove.com';

/// Exported for the settings page so it never drifts from the portal default.
const String webPortalDefaultUrl = kDefaultWebPortalUrl;

/// Stored as one URL per line so settings can be edited without JSON syntax.
List<String> parseWebPortalSites(String raw) {
  return [
    for (final line in raw.split(RegExp(r'[\r\n,，]+')))
      if (line.trim().isNotEmpty) _normalizeUrl(line),
  ];
}
