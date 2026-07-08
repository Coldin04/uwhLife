import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/boundary_debug_settings.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import '../../core/theme/app_theme.dart';
import '../scanner/qr_scanner_page.dart';
import 'bridges/hybrid_ble_bridge.dart';
import 'webview_overlays.dart';

class PortalWebViewPage extends StatefulWidget {
  const PortalWebViewPage({
    super.key,
    required this.title,
    required this.icon,
    required this.initialUrl,
    this.credentialAutofillHost = 'ids.uwh.edu.cn',
    this.topSafeArea = true,
    this.bottomSafeArea = true,
    this.accentColor,
  });

  final String title;
  final IconData icon;
  final String initialUrl;
  final Color? accentColor;

  /// 当 WebView 加载页面的 host 命中该值时，启用账号密码捕获 / 自动填充
  /// 以及登录态自动追踪。默认 `ids.uwh.edu.cn`（统一身份认证 CAS 登录页），
  /// 因此任意页面（付款码/洗浴/智慧课堂）跳到 ids 都会触发。
  final String? credentialAutofillHost;

  /// true 时 WebView 会留出顶部状态栏的安全区，不会铺到刘海/灵动岛/通知栏下面。
  /// 默认 true。少数沉浸式 H5（自带顶栏）可以传 false 关掉。
  final bool topSafeArea;

  /// true 时 WebView 会留出底部系统导航条的安全区（Android 手势条 / iOS Home 区）。
  /// 默认 true。
  final bool bottomSafeArea;

  @override
  State<PortalWebViewPage> createState() => _PortalWebViewPageState();
}

enum _PickSource { camera, gallery }

class _PortalWebViewPageState extends State<PortalWebViewPage> {
  static const Duration _launchOverlayDelay = Duration(milliseconds: 140);
  static const Duration _launchOverlayMinShow = Duration(milliseconds: 260);
  static const MethodChannel _wkInjectorChannel = MethodChannel(
    'uwhlife/wkwebview_injector',
  );
  static const MethodChannel _androidInjectorChannel = MethodChannel(
    'uwhlife/android_webview_injector',
  );
  late final WebViewController _controller;
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = true;
  bool _showLaunchLoading = false;
  String? _errorText;
  String? _lastUrl;
  bool _promptingSave = false;
  Timer? _launchOverlayDelayTimer;
  DateTime? _launchOverlayShownAt;
  HybridBleBridge? _bleBridge;

  @override
  void dispose() {
    _launchOverlayDelayTimer?.cancel();
    final bleBridge = _bleBridge;
    if (bleBridge != null) {
      unawaited(bleBridge.dispose());
    }
    super.dispose();
  }

  /// 处理 Android WebView 的 `<input type="file">` 触发：
  /// 弹一个底部菜单让用户选「拍照 / 从相册选择」，返回选中文件的
  /// `file://...` URI 列表。用户取消返回空数组（WebView 会把它当成
  /// "用户没选"）。
  ///
  /// - 多选 (`mode == openMultiple`)：相册支持，拍照不支持
  /// - `isCaptureEnabled`：网页声明了 `capture` 属性，直接走相机
  /// - `acceptTypes`：含 `video/` → 拍/选视频；否则按图片处理
  Future<List<String>> _pickFilesForWebView(FileSelectorParams params) async {
    final acceptsVideo = params.acceptTypes.any(
      (t) => t.toLowerCase().startsWith('video/'),
    );
    final acceptsImage =
        params.acceptTypes.isEmpty ||
        params.acceptTypes.any((t) {
          final s = t.toLowerCase();
          return s.startsWith('image/') || s == '*/*';
        });

    Future<List<String>> fromCamera() async {
      try {
        final XFile? f = acceptsVideo && !acceptsImage
            ? await _imagePicker.pickVideo(source: ImageSource.camera)
            : await _imagePicker.pickImage(source: ImageSource.camera);
        return f == null ? <String>[] : <String>['file://${f.path}'];
      } catch (e) {
        debugPrint('[WebViewFilePicker] camera failed: $e');
        return <String>[];
      }
    }

    Future<List<String>> fromGallery() async {
      try {
        // 用 pickMedia / pickMultipleMedia 走系统 Photo Picker：
        // - Android 13+ ：沙盒级别，无需相册权限
        // - Android 12 / iOS：自动回落到 ACTION_GET_CONTENT / PHPicker
        // 视频也由系统选择器统一处理，不再分支调 pickVideo。
        if (params.mode == FileSelectorMode.openMultiple) {
          final files = await _imagePicker.pickMultipleMedia();
          return files.map((f) => 'file://${f.path}').toList();
        }
        final XFile? f = await _imagePicker.pickMedia();
        return f == null ? <String>[] : <String>['file://${f.path}'];
      } catch (e) {
        debugPrint('[WebViewFilePicker] gallery failed: $e');
        return <String>[];
      }
    }

    // capture 属性 → 直接相机，不弹菜单。
    if (params.isCaptureEnabled) return fromCamera();

    if (!mounted) return <String>[];
    final source = await showModalBottomSheet<_PickSource>(
      context: context,
      // 不再写死白底；交给主题，深色下自动切换。
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('拍照'),
                onTap: () => Navigator.of(ctx).pop(_PickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(
                  params.mode == FileSelectorMode.openMultiple
                      ? '从相册选择（多选）'
                      : '从相册选择',
                ),
                onTap: () => Navigator.of(ctx).pop(_PickSource.gallery),
              ),
              ListTile(
                leading: Icon(
                  Icons.close_rounded,
                  color: Theme.of(ctx).hintColor,
                ),
                title: const Text('取消'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );

    switch (source) {
      case _PickSource.camera:
        return fromCamera();
      case _PickSource.gallery:
        return fromGallery();
      case null:
        return <String>[];
    }
  }

  @override
  void initState() {
    super.initState();
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setOnConsoleMessage((msg) {
        debugPrint('[WebViewConsole][${msg.level.name}] ${msg.message}');
      });

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnJavaScriptTextInputDialog((request) async {
        final message = request.message.trim();
        final defaultText = request.defaultText?.trim() ?? '';
        final lowerMessage = message.toLowerCase();
        final lowerDefault = defaultText.toLowerCase();
        final isGapPrompt =
            lowerMessage.startsWith('gap:') ||
            lowerMessage.startsWith('gap_init:') ||
            lowerDefault.startsWith('gap:') ||
            lowerDefault.startsWith('gap_init:');

        if (isGapPrompt) {
          debugPrint(
            '[WebViewPrompt] swallowed Cordova prompt: '
            'message="$message" default="$defaultText"',
          );
          // 返回非空值，避免 Cordova 侧把空串继续当成非法消息刷屏。
          return '0';
        }

        debugPrint(
          '[WebViewPrompt] auto-handled prompt: '
          'message="$message" default="$defaultText"',
        );
        return defaultText;
      });

      // 让网页上的 <input type="file"> / 物业报修等场景可以拍照 / 选图。
      // 默认行为只会提示"未实现"，需要 Dart 侧返回选中文件的 file:// URI。
      platformController.setOnShowFileSelector(_pickFilesForWebView);
    }

    if (widget.credentialAutofillHost != null) {
      _controller.addJavaScriptChannel(
        'FlutterCreds',
        onMessageReceived: (msg) {
          _handleCredentialsCaptured(msg.message);
        },
      );
    }

    // 接管 campushoy / 今日校园 SDK 的 cordova.exec 调用，转发到 Dart 端。
    _controller.addJavaScriptChannel(
      'HuBridge',
      onMessageReceived: (msg) {
        _handleHybridMessage(msg.message);
      },
    );

    _controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          return _handleNavigationRequest(request);
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _isLoading = true;
            _errorText = null;
            _lastUrl = url;
          });
          _scheduleLaunchOverlay();
        },
        onPageFinished: (url) async {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _lastUrl = url;
          });
          await _hideLaunchOverlay();
          await _injectHybridBridge();
          await _debugHybridBridgeState('pageFinished');
          await _maybeInjectBoundaryDebug(url);
          await _trackLoginTransition(url);
          await _maybeAutofill(url);
        },
        onWebResourceError: (error) {
          if (!mounted) return;
          _launchOverlayDelayTimer?.cancel();
          setState(() {
            _isLoading = false;
            _showLaunchLoading = false;
            _errorText = '${error.errorCode}: ${error.description}';
          });
        },
      ),
    );

    _initializeWebView();
    _scheduleLaunchOverlay();
  }

  NavigationDecision _handleNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    final scheme = uri.scheme.toLowerCase();
    const safeSchemes = <String>{
      'http',
      'https',
      'about',
      'data',
      'file',
      'javascript',
      'blob',
    };
    if (safeSchemes.contains(scheme)) {
      return NavigationDecision.navigate;
    }

    if (scheme == 'gap' && uri.host.toLowerCase() == 'ready') {
      return NavigationDecision.prevent;
    }

    debugPrint('[WebViewNav] blocked custom scheme: ${request.url}');

    // 部分校园页在 Android WebView 中会误走 iPhone 分支，
    // 直接尝试跳转自定义 scheme，导致 error_unknown_url_scheme。
    // 这里先统一拦下，避免错误页打断调试；后续再按日志把具体 scheme
    // 路由到扫码 / 蓝牙等原生能力。
    return NavigationDecision.prevent;
  }

  Future<void> _initializeWebView() async {
    await _injectHybridBridgeAtDocumentStart();
    await _injectBoundaryDebugAtDocumentStart();
    await _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  void _scheduleLaunchOverlay() {
    _launchOverlayDelayTimer?.cancel();
    _launchOverlayShownAt = null;
    if (_showLaunchLoading) {
      setState(() {
        _showLaunchLoading = false;
      });
    }
    _launchOverlayDelayTimer = Timer(_launchOverlayDelay, () {
      if (!mounted || !_isLoading || _errorText != null) return;
      setState(() {
        _showLaunchLoading = true;
        _launchOverlayShownAt = DateTime.now();
      });
    });
  }

  Future<void> _hideLaunchOverlay() async {
    _launchOverlayDelayTimer?.cancel();
    if (!_showLaunchLoading) return;
    final shownAt = _launchOverlayShownAt;
    if (shownAt != null) {
      final elapsed = DateTime.now().difference(shownAt);
      final remaining = _launchOverlayMinShow - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }
    if (!mounted) return;
    setState(() {
      _showLaunchLoading = false;
      _launchOverlayShownAt = null;
    });
  }

  Future<void> _injectHybridBridge() async {
    try {
      await _controller.runJavaScript(_cordovaStubScript);
      debugPrint('[HuBridge.inject] runtime injection applied');
    } catch (e) {
      debugPrint('[HuBridge.inject] runtime injection failed: $e');
    }
  }

  Future<void> _injectHybridBridgeAtDocumentStart() async {
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      try {
        await _wkInjectorChannel.invokeMethod('injectDocumentStartScript', {
          'webViewIdentifier': platform.webViewIdentifier,
          'script': _cordovaStubScript,
        });
        debugPrint(
          '[HuBridge.inject] iOS document-start injection installed '
          'for webView=${platform.webViewIdentifier}',
        );
      } on PlatformException catch (e) {
        // iOS 静默失败会让蓝牙 / 扫码完全没反应，必须暴露出来：
        // code=no_webview 通常是 identifier 还没在 instance manager 里登记
        // （注入时机太早），details 里会给出 implicit_registry_miss /
        // self_registry_miss 之类，便于在真机日志里直接看到。
        debugPrint(
          '[HuBridge.inject] iOS document-start injection FAILED '
          'code=${e.code} message=${e.message} details=${e.details}',
        );
        if (mounted) {
          setState(() {
            _errorText =
                'iOS 注入失败：${e.code} ${e.message ?? ''} ${e.details ?? ''}';
          });
        }
        rethrow;
      } catch (e) {
        debugPrint('[HuBridge.inject] iOS document-start injection failed: $e');
        rethrow;
      }
      return;
    }
    if (platform is AndroidWebViewController) {
      try {
        await _androidInjectorChannel
            .invokeMethod('injectDocumentStartScript', {
              'webViewIdentifier': platform.webViewIdentifier,
              'script': _cordovaStubScript,
            });
        debugPrint(
          '[HuBridge.inject] Android document-start injection installed '
          'for webView=${platform.webViewIdentifier}',
        );
      } catch (e) {
        debugPrint(
          '[HuBridge.inject] Android document-start injection failed: $e',
        );
      }
    }
  }

  Future<void> _injectBoundaryDebugAtDocumentStart() async {
    final settings = await BoundaryDebugSettings.read();
    if (!settings.enabled) return;
    final script = _buildBoundaryDebugScript(settings);
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) {
      try {
        await _wkInjectorChannel.invokeMethod('injectDocumentStartScript', {
          'webViewIdentifier': platform.webViewIdentifier,
          'script': script,
        });
        debugPrint('[BoundaryDebug] iOS document-start injection installed');
      } catch (e) {
        debugPrint('[BoundaryDebug] iOS document-start injection failed: $e');
      }
      return;
    }
    if (platform is AndroidWebViewController) {
      try {
        await _androidInjectorChannel.invokeMethod(
          'injectDocumentStartScript',
          {'webViewIdentifier': platform.webViewIdentifier, 'script': script},
        );
        debugPrint(
          '[BoundaryDebug] Android document-start injection installed',
        );
      } catch (e) {
        debugPrint(
          '[BoundaryDebug] Android document-start injection failed: $e',
        );
      }
    }
  }

  Future<void> _maybeInjectBoundaryDebug(String url) async {
    final settings = await BoundaryDebugSettings.read();
    if (!settings.enabled || !_isBoundaryDebugUrl(url)) return;
    try {
      await _controller.runJavaScript(_buildBoundaryDebugScript(settings));
      debugPrint('[BoundaryDebug] runtime injection applied');
    } catch (e) {
      debugPrint('[BoundaryDebug] runtime injection failed: $e');
    }
  }

  bool _isBoundaryDebugUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return uri.host.toLowerCase() == 'ehall.uwh.edu.cn' &&
        uri.path.startsWith('/student/cas/wap/menu/student/sign/stu/sign');
  }

  Future<void> _debugHybridBridgeState(String source) async {
    try {
      final state = await _controller.runJavaScriptReturningResult(r'''
JSON.stringify({
  stubbed: !!window.__huHybridStubbed,
  hasRefresh: typeof window.__huHybridRefresh === 'function',
  hasHuBridgeChannel: typeof HuBridge !== 'undefined',
  hasCampus: typeof window.campus !== 'undefined',
  hasCordova: typeof window.cordova !== 'undefined',
  cordovaExecIsFunction: !!(window.cordova && typeof window.cordova.exec === 'function'),
  cordovaExecIsHooked: !!(window.cordova && window.cordova.exec === window.__huBridgeExec),
  hasCallNative: typeof window.callNative !== 'undefined',
  hasNativeCallbacks: typeof window.native !== 'undefined'
})
''');
      debugPrint('[HuBridge.inject] probe($source) => $state');
    } catch (e) {
      debugPrint('[HuBridge.inject] probe($source) failed: $e');
    }
  }

  bool _isAutofillUrl(String url) {
    final host = widget.credentialAutofillHost;
    if (host == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.toLowerCase() == host.toLowerCase();
  }

  /// 根据当前 WebView 导航到的 URL 自动维护登录态：
  /// - 落在 `ids.uwh.edu.cn/authserver/login*` → 说明被踢回登录页，标记已登出
  /// - 落在 `ehall.uwh.edu.cn` → 说明 SSO 通过，标记已登录 7 天
  ///
  /// 任何 WebView 页面（门锁 / 付款码 / 洗浴 / 智慧课堂）都会经过这里，
  /// 所以即使不是从右上角入口进的统一门户，也能正确同步状态。
  Future<void> _trackLoginTransition(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == 'ids.uwh.edu.cn' && path.contains('/authserver/login')) {
      await LoginStateStore.markLoggedOut();
      return;
    }
    if (host == 'ehall.uwh.edu.cn') {
      await LoginStateStore.markLoggedIn();
      await BrowserDataCleaner.persistCookies();
    }
  }

  Future<void> _maybeAutofill(String url) async {
    if (!_isAutofillUrl(url)) return;

    // 1) 始终注入捕获脚本，监听用户点击登录按钮 / 提交表单时的明文。
    await _controller.runJavaScript(_captureScript);

    // 2) 始终勾选「7天内保持登录」复选框（无论是否已保存密码）。
    await _controller.runJavaScript(_rememberMeScript);

    // 3) 如果本地有保存的账号密码，则回填。
    final saved = await PortalCredentials.read();
    if (saved == null) return;
    await _controller.runJavaScript(_buildFillScript(saved.$1, saved.$2));
  }

  Future<void> _handleCredentialsCaptured(String raw) async {
    if (_promptingSave) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final username = (data['u'] as String?)?.trim() ?? '';
    final password = (data['p'] as String?) ?? '';
    if (username.isEmpty || password.isEmpty) return;

    final existing = await PortalCredentials.read();
    if (existing != null &&
        existing.$1 == username &&
        existing.$2 == password) {
      return; // 与本地一致，无需打扰
    }

    if (!mounted) return;
    _promptingSave = true;
    final isUpdate = existing != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isUpdate ? '更新已保存的密码？' : '记住此账号？'),
          content: Text(
            isUpdate
                ? '检测到与本地保存不同的账号或密码，是否更新？\n账号：$username'
                : '下次进入统一门户时将自动填入。\n账号：$username',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('不用了'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(isUpdate ? '更新' : '记住'),
            ),
          ],
        );
      },
    );
    _promptingSave = false;

    if (confirmed == true) {
      await PortalCredentials.save(username, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isUpdate ? '已更新保存的密码' : '已保存账号密码')),
      );
    }
  }

  /// 弹出 Flutter 扫码页，返回扫到的字符串；用户取消返回 null。
  Future<String?> _showScanner() async {
    if (!mounted) return null;
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerPage(),
      ),
    );
  }

  /// 接收 JS 通过 `HuBridge.postMessage(...)` 转发的 cordova.exec 调用，
  /// 第一阶段：纯日志 + 默认空成功回复，方便扒 SDK 在调哪些 action。
  /// 后续按需在 switch 里加具体实现（扫码 / 蓝牙等）。
  Future<void> _handleHybridMessage(String raw) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = data['id'];
    final service = (data['service'] ?? '').toString();
    final action = (data['action'] ?? '').toString();
    final args = data['args'];

    debugPrint('[HuBridge] $service.$action args=${jsonEncode(args)}');

    Object? result = <String, dynamic>{};
    bool ok = true;

    // campushoy 的 cordova.exec 调用约定：service 是真实方法名（如 "scan"、
    // "openBluetoothAdapter"），action 是 SDK 自加的回调 ID（"JCpdaily<ts>"）。
    // 所以方法识别要看 service。
    final method = service.toLowerCase();
    final actionName = action.toLowerCase();
    if (method == 'scan' ||
        method == 'scanqrcode' ||
        method == 'scancode' ||
        method.contains('scan') ||
        actionName.contains('scan')) {
      final scanned = await _showScanner();
      final isDingTalkScan =
          actionName.contains('dd.biz.util.scan') ||
          actionName.contains('dingtalk') ||
          actionName.contains('dd.');
      final isWechatScan =
          actionName.contains('wx.scanqrcode') ||
          actionName.contains('weixinjsbridge') ||
          actionName.contains('scanqrcode');
      if (scanned == null) {
        ok = false;
        if (isWechatScan) {
          result = {'errMsg': 'scanQRCode:fail cancel'};
        } else {
          result = {
            'errorCode': -1,
            'errorMessage': 'cancelled',
            'errMsg': '$action:fail cancel',
          };
        }
      } else {
        if (isWechatScan) {
          result = {'resultStr': scanned, 'errMsg': 'scanQRCode:ok'};
        } else {
          result = {
            'text': scanned,
            'result': scanned,
            'code': scanned,
            'value': scanned,
            'content': scanned,
            'resultStr': scanned,
            'scanResult': scanned,
            'qrcode': scanned,
            'barCode': scanned,
            'type': 'QR_CODE',
            'scanType': 'qrCode',
            'codeType': 'qrCode',
            'errorCode': 0,
            'errMsg': '$action:ok',
          };

          if (isDingTalkScan) {
            result = {
              ...?result as Map<String, dynamic>?,
              'text': scanned,
              'type': 'QR_CODE',
              'qrCode': scanned,
            };
          }
        }
      }
    } else if (_hybridBleMethods.contains(method)) {
      final bleResult = await _handleBleHybridMessage(
        method: method,
        action: action,
        args: args,
      );
      result = bleResult.payload;
      ok = bleResult.ok;
      // 输出到 vconsole 方便真机调试（Flutter debugPrint 在 vconsole 里看不到）
      try {
        final bleJson = jsonEncode(result);
        await _controller.runJavaScript(
          'console.log("[HuBLE.dart]", "$method", $bleJson);',
        );
      } catch (_) {}
    }

    final replyJson = jsonEncode(result);
    final okStr = ok ? 'true' : 'false';
    final js =
        'window.__huBridgeResolve && window.__huBridgeResolve($id, $okStr, $replyJson);';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  static const Set<String> _hybridBleMethods = <String>{
    'openbluetoothadapter',
    'closebluetoothadapter',
    'getbluetoothadapterstate',
    'onbluetoothadapterstatechange',
    'offbluetoothadapterstatechange',
    'startbluetoothdevicesdiscovery',
    'stopbluetoothdevicesdiscovery',
    'getbluetoothdevices',
    'getconnectedbluetoothdevices',
    'connectbledevice',
    'disconnectbledevice',
    'getbledeviceservices',
    'getbledevicecharacteristics',
    'notifyblecharacteristicvaluechange',
    'onbluetoothdevicefound',
    'offbluetoothdevicefound',
    'onbleconnectionstatechanged',
    'offbleconnectionstatechanged',
    'onblecharacteristicvaluechange',
    'offblecharacteristicvaluechange',
    'writeblecharacteristicvalue',
    'readblecharacteristicvalue',
  };

  Future<({bool ok, Object payload})> _handleBleHybridMessage({
    required String method,
    required String action,
    required Object? args,
  }) async {
    final bridge = _ensureBleBridgeForUrl(_lastUrl ?? widget.initialUrl);
    if (bridge == null) {
      return (ok: false, payload: bleFailPayload(51098, '当前页面未启用蓝牙桥接'));
    }
    final opts = _extractHybridOptions(args);
    return await bridge.handleMethod(
      method: method,
      opts: opts,
      emitEvent: _emitHybridEvent,
    );
  }

  HybridBleBridge? _ensureBleBridgeForUrl(String? url) {
    if (_bleBridge != null) return _bleBridge;
    if (!_shouldEnableBleForUrl(url)) return null;
    _bleBridge = HybridBleBridge();
    return _bleBridge;
  }

  bool _shouldEnableBleForUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return host.contains('ymtpt.uwh.edu.cn') ||
        host == '223.241.72.135' ||
        path.contains('uwc_webapp') ||
        path.contains('uwc_web_app');
  }

  Map<String, dynamic> _extractHybridOptions(Object? args) {
    if (args is List && args.isNotEmpty) {
      final first = args.first;
      if (first is Map) {
        return Map<String, dynamic>.from(
          first.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    if (args is Map) {
      return Map<String, dynamic>.from(
        args.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return <String, dynamic>{};
  }

  Future<void> _emitHybridEvent(
    String key,
    Map<String, dynamic> payload,
  ) async {
    final eventJson = jsonEncode(payload);
    final js =
        'window.__huBridgeEmitEvent && window.__huBridgeEmitEvent(${jsonEncode(key)}, $eventJson);';
    try {
      await _controller.runJavaScript(js);
    } catch (_) {}
  }

  /// 校园里很多 H5（今日校园 / 完美校园 / xiaofubao 等）会内嵌
  /// `campushoy-2.0.0.js` 之类的 SDK，这些 SDK 假设自己在 Cordova 容器里跑，
  /// 会持续调用 `cordova.exec(...)` → `__gap` bridge → `prompt()` 找原生。
  /// 我们的 WebView 没有这些桥，SDK 会死循环重试 + 把 console 打爆。
  /// 这里用 `HuBridge` JavaScript channel 接管 cordova.exec，转发到 Dart。
  /// 第一阶段所有调用都默认空 success，避免 SDK 报错。
  static const String _cordovaStubScript = r'''
(function(){
  if (window.__huHybridRefresh) {
    try { console.log('[HuBridge.inject] refresh'); } catch (_) {}
    try { window.__huHybridRefresh(); } catch (_) {}
    return;
  }
  try { console.log('[HuBridge.inject] bootstrap', location.href); } catch (_) {}
  window.__huHybridStubbed = true;
  var noop = function(){};

  // ---- HuBridge 路由：所有 cordova.exec 调用都走这里 ----
  window.__huBridgeReturn = window.__huBridgeReturn || {};
  window.__huBridgeEventCallbacks = window.__huBridgeEventCallbacks || {};
  window.__huCordovaEventCallbacks = window.__huCordovaEventCallbacks || {};
  window.__huBridgeNextId = window.__huBridgeNextId || 0;
  window.__huBridgeAddEventCallback = function(key, callback){
    if (!key || typeof callback !== 'function') return;
    var list = window.__huBridgeEventCallbacks[key] || [];
    list.push(callback);
    window.__huBridgeEventCallbacks[key] = list;
  };
  window.__huBridgeRemoveEventCallback = function(key){
    if (!key) return;
    delete window.__huBridgeEventCallbacks[key];
  };
  window.__huBridgeEmitEvent = function(key, payload){
    var list = window.__huBridgeEventCallbacks[key] || [];
    for (var i = 0; i < list.length; i++) {
      try { list[i] && list[i](payload); } catch(_) {}
    }
    var cordovaList = window.__huCordovaEventCallbacks[key] || [];
    if (!cordovaList.length) return;
    var c = normalizeCordova(window.cordova);
    var status = (c && c.callbackStatus && c.callbackStatus.OK) || 1;
    if (!c || typeof c.callbackFromNative !== 'function') return;
    for (var j = 0; j < cordovaList.length; j++) {
      try {
        c.callbackFromNative(cordovaList[j], true, status, [payload], true);
      } catch(_) {}
    }
  };
  window.__huBridgeAddCordovaEventCallback = function(keys, callbackId){
    if (!keys || !callbackId) return;
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      if (!key) continue;
      var list = window.__huCordovaEventCallbacks[key] || [];
      if (list.indexOf(callbackId) === -1) {
        list.push(callbackId);
      }
      window.__huCordovaEventCallbacks[key] = list;
    }
  };
  window.__huBridgeRemoveCordovaEventCallback = function(keys, callbackId){
    if (!keys) return;
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      var list = window.__huCordovaEventCallbacks[key] || [];
      if (!list.length) continue;
      if (!callbackId) {
        delete window.__huCordovaEventCallbacks[key];
        continue;
      }
      var next = [];
      for (var j = 0; j < list.length; j++) {
        if (list[j] !== callbackId) next.push(list[j]);
      }
      if (next.length) window.__huCordovaEventCallbacks[key] = next;
      else delete window.__huCordovaEventCallbacks[key];
    }
  };
  window.__huBridgeResolve = function(id, ok, payload){
    var cb = window.__huBridgeReturn[id];
    if (!cb) return;
    delete window.__huBridgeReturn[id];
    try { console.log('[HuBridge←]', '#' + id, ok ? 'ok' : 'fail', payload); } catch(_) {}
    try {
      if (cb.mode === 'cordova') {
        if (cb.isEventSubscription) {
          if (ok) {
            window.__huBridgeAddCordovaEventCallback(cb.eventKeys, cb.callbackId);
          }
          return;
        }
        if (cb.isEventUnsubscribe) {
          window.__huBridgeRemoveCordovaEventCallback(cb.eventKeys, cb.callbackId);
          return;
        }
        var c = normalizeCordova(window.cordova);
        var status = ok
          ? ((c && c.callbackStatus && c.callbackStatus.OK) || 1)
          : ((c && c.callbackStatus && c.callbackStatus.ERROR) || 9);
        if (c && typeof c.callbackFromNative === 'function') {
          c.callbackFromNative(cb.callbackId, ok, status, [payload], false);
        }
        return;
      }
      if (ok) {
        if (typeof cb.success === 'function') {
          cb.success(payload);
        }
      } else {
        if (typeof cb.fail === 'function') {
          cb.fail(payload);
        }
      }
    } catch(e) {
      try {
        console.log(
          '[HuBridge.callback.error]',
          '#' + id,
          ok ? 'success' : 'fail',
          e && e.message ? e.message : e,
          e && e.stack ? e.stack : ''
        );
      } catch(_) {}
    }
  };

    // 暴露给 probe 用：判断 cordova.exec 是否仍然指向我们的 bridgeExec
    window.__huBridgeExec = bridgeExec;

  function bridgeExec(success, fail, service, action, args){
    // ArrayBuffer / TypedArray 序列化：cpdaily 走 cordova-ios 时，cordova 会把
    // ArrayBuffer 编码成 {CDVType:"ArrayBuffer", data: <base64>}；但我们用
    // mustOverride 直接走 HuBridge.postMessage，JSON.stringify(ArrayBuffer) 会
    // 输出 "{}"，导致 Dart 端拿到空字节、写 BLE 失败、设备无响应。
    // 这里在序列化前把所有 ArrayBuffer / TypedArray 转成 hex 字符串，
    // Dart 的 _normalizeWriteValue 已能处理 hex string。
    function huNormalizeBleArg(v){
      if (v == null) return v;
      // ArrayBuffer
      if (typeof ArrayBuffer === 'function' && v instanceof ArrayBuffer) {
        var u8 = new Uint8Array(v);
        var hex = '';
        for (var i = 0; i < u8.length; i++) {
          var b = u8[i].toString(16);
          hex += b.length < 2 ? '0' + b : b;
        }
        return hex;
      }
      // TypedArray (Uint8Array / Int8Array / etc.)
      if (typeof ArrayBuffer === 'function' && ArrayBuffer.isView && ArrayBuffer.isView(v)) {
        var u8b = (v.constructor === Uint8Array) ? v : new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
        var hex2 = '';
        for (var j = 0; j < u8b.length; j++) {
          var bb = u8b[j].toString(16);
          hex2 += bb.length < 2 ? '0' + bb : bb;
        }
        return hex2;
      }
      // 普通对象 / 数组 → 递归（避免破坏 success/fail 函数引用，所以函数不递归）
      if (typeof v === 'function') return v;
      if (Array.isArray(v)) {
        return v.map(huNormalizeBleArg);
      }
      if (typeof v === 'object') {
        var out = {};
        for (var k in v) {
          if (Object.prototype.hasOwnProperty.call(v, k)) {
            out[k] = huNormalizeBleArg(v[k]);
          }
        }
        return out;
      }
      return v;
    }
    args = huNormalizeBleArg(args);

    var id = ++window.__huBridgeNextId;
    var isCordovaNativeExec =
      typeof success !== 'function' &&
      typeof fail === 'string' &&
      typeof service === 'string' &&
      typeof action === 'string';
    var serviceName = service || '';
    var actionName = action || '';
    var bridgeArgs = args || [];

    if (isCordovaNativeExec) {
      serviceName = service || '';
      actionName = action || '';
      if (typeof args === 'string') {
        try { bridgeArgs = JSON.parse(args); } catch(_) { bridgeArgs = []; }
      }
      var eventKeys = null;
      if (/^on[A-Z]/.test(serviceName) || /^off[A-Z]/.test(serviceName)) {
        eventKeys = ['JCpdaily.' + serviceName, 'campus.' + serviceName];
      }
      window.__huBridgeReturn[id] = {
        mode: 'cordova',
        callbackId: action || '',
        service: fail || '',
        action: service || '',
        isEventSubscription: /^on[A-Z]/.test(serviceName),
        isEventUnsubscribe: /^off[A-Z]/.test(serviceName),
        eventKeys: eventKeys
      };
    } else {
      window.__huBridgeReturn[id] = { mode: 'direct', success: success, fail: fail };
    }
    // 同时打到 vConsole + Dart 端，方便对照
    try {
      console.log('[HuBridge→]', '#' + id, serviceName + '.' + actionName, bridgeArgs);
    } catch(_) {}
    try {
      HuBridge.postMessage(JSON.stringify({
        id: id, service: serviceName, action: actionName, args: bridgeArgs
      }));
    } catch(e) {
      delete window.__huBridgeReturn[id];
      try {
        if (!isCordovaNativeExec && typeof fail === 'function') {
          fail(e && e.toString ? e.toString() : 'bridge_unavailable');
        }
      } catch(_) {}
    }
  }

  var huCampusMethodNames = [
    'takeCamera','checkPermissions','gotoSystemSetting',
    'openBluetoothAdapter','closeBluetoothAdapter','getBluetoothAdapterState',
    'onBluetoothAdapterStateChange','offBluetoothAdapterStateChange',
    'onBLEConnectionStateChanged','offBLEConnectionStateChanged',
    'startBluetoothDevicesDiscovery','stopBluetoothDevicesDiscovery',
    'getBluetoothDevices','getConnectedBluetoothDevices',
    'connectBLEDevice','disconnectBLEDevice',
    'writeBLECharacteristicValue','readBLECharacteristicValue',
    'notifyBLECharacteristicValueChange','getBLEDeviceServices',
    'getBLEDeviceCharacteristics','onBluetoothDeviceFound',
    'offBluetoothDeviceFound','onBLECharacteristicValueChange',
    'offBLECharacteristicValueChange','scan'
  ];

  function normalizeHybridArgs(input, callback) {
    var opts = {};
    if (typeof input === 'function') {
      callback = input;
    } else if (input && typeof input === 'object') {
      opts = input;
    }
    return {
      opts: opts,
      callback: callback
    };
  }

  function dispatchHybridMethod(namespace, method, input, callback){
    var normalized = normalizeHybridArgs(input, callback);
    var opts = normalized.opts || {};
    var cb = normalized.callback;
    var eventKey = namespace + '.' + method;
    var isEventSubscription = /^on[A-Z]/.test(method);
    var success =
      (opts && (opts.success || opts.onSuccess)) ||
      (typeof cb === 'function' ? cb : noop);
    var fail =
      (opts && (opts.fail || opts.onFail)) ||
      noop;
    var complete =
      (opts && opts.complete) ||
      noop;

    if (isEventSubscription && typeof cb === 'function') {
      window.__huBridgeAddEventCallback(eventKey, cb);
    }
    if (/^off[A-Z]/.test(method)) {
      var onKey = namespace + '.on' + method.substring(3);
      window.__huBridgeRemoveEventCallback(onKey);
    }

    try {
      console.log(
        '[HuCampus]',
        namespace + '.' + method,
        opts,
        'hasSuccess=' + (typeof success === 'function'),
        'hasFail=' + (typeof fail === 'function'),
        'hasComplete=' + (typeof complete === 'function'),
        'cbType=' + (typeof cb),
        'isEventSub=' + isEventSubscription
      );
    } catch(_) {}
    bridgeExec(function(payload){
      // 关键：订阅类（onXxx）的 bridgeExec ack 是 Dart "我收到订阅了" 的成功响应，
      // payload 是 {errcode:0, errmsg:'SUCCESS'} 这种 stub，**不要**当成首次事件回调
      // 来调用户 cb —— 否则页面会拿到 res.connected=undefined 等空字段，误判为断开/异常。
      // 真正的事件由 Dart 的 emitEvent → __huBridgeEmitEvent 单独推到 cb。
      if (isEventSubscription) {
        return;
      }
      try {
        console.log(
          '[HuCampus.success.invoke]',
          namespace + '.' + method,
          payload,
          'hasSuccess=' + (typeof success === 'function'),
          'hasComplete=' + (typeof complete === 'function')
        );
      } catch(_) {}
      try {
        success && success(payload);
      } catch(e) {
        try {
          console.log(
            '[HuCampus.callback.error]',
            namespace + '.' + method,
            'success',
            e && e.message ? e.message : e,
            e && e.stack ? e.stack : ''
          );
        } catch(_) {}
      }
      try {
        complete && complete(payload);
      } catch(e) {
        try {
          console.log(
            '[HuCampus.callback.error]',
            namespace + '.' + method,
            'complete',
            e && e.message ? e.message : e,
            e && e.stack ? e.stack : ''
          );
        } catch(_) {}
      }
    }, function(error){
      // 订阅注册本身失败时（极少），还是要把 fail 抛出去；不会带 connected/value 字段
      // 所以页面收到的就是真正的错误，不会和事件回调混淆。
      try {
        console.log(
          '[HuCampus.fail.invoke]',
          namespace + '.' + method,
          error,
          'hasFail=' + (typeof fail === 'function'),
          'hasComplete=' + (typeof complete === 'function'),
          'isEventSub=' + isEventSubscription
        );
      } catch(_) {}
      try {
        fail && fail(error);
      } catch(e) {
        try {
          console.log(
            '[HuCampus.callback.error]',
            namespace + '.' + method,
            'fail',
            e && e.message ? e.message : e,
            e && e.stack ? e.stack : ''
          );
        } catch(_) {}
      }
      try {
        complete && complete(error);
      } catch(e) {
        try {
          console.log(
            '[HuCampus.callback.error]',
            namespace + '.' + method,
            'complete',
            e && e.message ? e.message : e,
            e && e.stack ? e.stack : ''
          );
        } catch(_) {}
      }
    }, method, namespace + '.' + method, [opts || {}]);
  }

  function installWindowObjectHook(name, patchFn){
    var currentValue = window[name];
    try {
      Object.defineProperty(window, name, {
        configurable: true,
        enumerable: true,
        get: function(){
          return currentValue;
        },
        set: function(v){
          currentValue = v;
          try { patchFn(currentValue); } catch(_) {}
        }
      });
    } catch(_) {}
    if (currentValue) {
      try { patchFn(currentValue); } catch(_) {}
    }
  }

  function fireDocumentEvent(name, data) {
    try {
      var evt;
      if (typeof CustomEvent === 'function') {
        evt = new CustomEvent(name, { detail: data });
      } else {
        evt = document.createEvent('CustomEvent');
        evt.initCustomEvent(name, false, false, data);
      }
      document.dispatchEvent(evt);
    } catch (_) {}
  }

  function normalizeCordova(c) {
    if (!c) return null;
    c.callbacks = c.callbacks || {};
    c.callbackId = c.callbackId || 0;
    c.platformId = c.platformId || 'browser';
    c.version = c.version || '1.0.0';
    c.exec = bridgeExec;
    c.fireDocumentEvent = c.fireDocumentEvent || fireDocumentEvent;
    c.fireWindowEvent = c.fireWindowEvent || noop;
    c.addWindowEventHandler = c.addWindowEventHandler || function(){ return { fire: noop }; };
    c.addDocumentEventHandler = c.addDocumentEventHandler || function(){ return { fire: fireDocumentEvent }; };
    c.require = c.require || function(){ return {}; };
    c.define = c.define || noop;
    c.channel = c.channel || {
      onDOMContentLoaded: { fired: true, fire: function(){ fireDocumentEvent('DOMContentLoaded'); } },
      onNativeReady: { fired: true, fire: noop },
      onCordovaReady: { fired: true, fire: noop },
      onPluginsReady: { fired: true, fire: noop },
      deviceready: { fired: true, fire: function(){ fireDocumentEvent('deviceready'); } }
    };
    window.Cordova = window.Cordova || c;
    window.PhoneGap = window.PhoneGap || c;
    return c;
  }

  // ---- cordova.exec hook：覆盖标准赋值 + defineProperty 双保险，重试到成功 ----
  // iOS WKWebView 上 onPageStarted 触发晚于 SDK 的 cordova.js，导致原版 exec 已就位
  // 且可能被 SDK 锁成不可写。这里反复尝试，无论 cordova 何时出现 / 是否被锁都能 hook。
  function tryHookCordova(){
    var cordovaObj = normalizeCordova(window.cordova);
    if (!cordovaObj || typeof cordovaObj.exec !== 'function') return false;
    if (cordovaObj.exec === bridgeExec) return true; // 已 hook
    try {
      Object.defineProperty(cordovaObj, 'exec', {
        configurable: true, writable: true, value: bridgeExec
      });
    } catch(_) {}
    if (cordovaObj.exec !== bridgeExec) {
      try { cordovaObj.exec = bridgeExec; } catch(_) {}
    }
    return cordovaObj.exec === bridgeExec;
  }

  // 立刻试一次 + 50ms 间隔重试 5 秒（覆盖 SDK 异步加载的情况）
  var attempts = 0;
  var hookTimer = setInterval(function(){
    attempts++;
    if (tryHookCordova() || attempts > 100) clearInterval(hookTimer);
  }, 50);

  function patchCordovaNativeObject(target){
    if (!target) return;
    target.exec = bridgeExec;
    target.nativeToJsModes = target.nativeToJsModes || { EVAL_BRIDGE: 0, POLLING: 1 };
    target.jsToNativeModes = target.jsToNativeModes || { PROMPT: 0, JS_OBJECT: 1 };
    target.retrieveJsMessages =
      target.retrieveJsMessages || function(){ return ''; };
    target.setNativeToJsBridgeMode =
      target.setNativeToJsBridgeMode || noop;
    target.setJsToNativeBridgeMode =
      target.setJsToNativeBridgeMode || noop;
    target.versions =
      target.versions || function(){
        return {
          platform: /iphone|ipad|ipod/i.test(navigator.userAgent) ? 'ios' : 'android',
          cordova: '12.0.0',
          appVersion: '1.0.0'
        };
      };
  }
  if (!window._cordovaNative) {
    window._cordovaNative = {};
  }
  patchCordovaNativeObject(window._cordovaNative);

  // ---- window.campus / JCpdaily 兜底：不用 Proxy，兼容旧 Android WebView 内核 ----
  // BLE 派发只在洗浴页 host 启用 —— 智慧团学等纯扫码页面不能受影响。
  function huIsBleEnabledHost(){
    try {
      var h = (location.hostname || '').toLowerCase();
      var p = (location.pathname || '').toLowerCase();
      return h.indexOf('ymtpt.uwh.edu.cn') >= 0
          || h === '223.241.72.135'
          || p.indexOf('uwc_webapp') >= 0
          || p.indexOf('uwc_web_app') >= 0;
    } catch(_) { return false; }
  }
  // 与 Dart 侧 _hybridBleMethods（toLowerCase 比对）一一对应的方法名集合。
  var huBleMethodSet = {
    'openBluetoothAdapter':1,'closeBluetoothAdapter':1,'getBluetoothAdapterState':1,
    'onBluetoothAdapterStateChange':1,'offBluetoothAdapterStateChange':1,
    'startBluetoothDevicesDiscovery':1,'stopBluetoothDevicesDiscovery':1,
    'getBluetoothDevices':1,'getConnectedBluetoothDevices':1,
    'connectBLEDevice':1,'disconnectBLEDevice':1,
    'writeBLECharacteristicValue':1,'readBLECharacteristicValue':1,
    'notifyBLECharacteristicValueChange':1,
    'getBLEDeviceServices':1,'getBLEDeviceCharacteristics':1,
    'onBluetoothDeviceFound':1,'offBluetoothDeviceFound':1,
    'onBLECharacteristicValueChange':1,'offBLECharacteristicValueChange':1,
    'onBLEConnectionStateChanged':1,'offBLEConnectionStateChanged':1
  };
  function huMustOverrideMethod(method){
    if (method === 'scan' || method === 'scanQrcode' || method === 'scanCode') return true;
    // mamp-plugin-campus 的 BLE 方法在模块定义时闭包捕获了 cordova/exec，
    // 我们 patch window.cordova.exec 影响不到它；唯一稳妥的做法是直接覆盖
    // campus.<method>（参考 scan 的 mustOverride 模式）。仅在洗浴页生效。
    if (huBleMethodSet[method] && huIsBleEnabledHost()) return true;
    return false;
  }
  function campusCall(action, opts){
    var success = (opts && (opts.success || opts.onSuccess)) || noop;
    var fail = (opts && (opts.fail || opts.onFail)) || noop;
    bridgeExec(success, fail, action, 'campus.' + action, [opts || {}]);
  }
  function patchCampusObject(target){
    if (!target) return;
    for (var i = 0; i < huCampusMethodNames.length; i++) {
      (function(method){
        var mustOverride = huMustOverrideMethod(method);
        if (mustOverride || typeof target[method] !== 'function') {
          target[method] = function(input, callback){
            dispatchHybridMethod('campus', method, input, callback);
          };
        }
      })(huCampusMethodNames[i]);
    }
    target.scanQrcode = function(input, callback){
      dispatchHybridMethod('campus', 'scan', input, callback);
    };
    target.scanCode = function(input, callback){
      dispatchHybridMethod('campus', 'scan', input, callback);
    };
  }
  if (window.campus) {
    patchCampusObject(window.campus);
    for (var i = 0; i < huCampusMethodNames.length; i++) {
      (function(method){
        if (typeof window.campus[method] !== 'function') {
          window.campus[method] = function(input, callback){
            dispatchHybridMethod('campus', method, input, callback);
          };
        }
      })(huCampusMethodNames[i]);
    }
    if (typeof window.campus.scanQrcode !== 'function') {
      window.campus.scanQrcode = function(input, callback){
        dispatchHybridMethod('campus', 'scan', input, callback);
      };
    }
    if (typeof window.campus.scanCode !== 'function') {
      window.campus.scanCode = function(input, callback){
        dispatchHybridMethod('campus', 'scan', input, callback);
      };
    }
  }

  // 今日校园 / 完美校园 直接挂在 window.JCpdaily 的 SDK 入口
  function patchJCpdailyObject(target){
    if (!target) return;
    target.__methods = huCampusMethodNames.slice();
    target.methods = huCampusMethodNames.slice();
    if (typeof target.getSupportedApi !== 'function') {
      target.getSupportedApi = function(){
        return huCampusMethodNames.slice();
      };
    }
    if (typeof target.isSupportMethod !== 'function') {
      target.isSupportMethod = function(name){
        return huCampusMethodNames.indexOf(name) >= 0;
      };
    }
    if (typeof target.invoke !== 'function') {
      target.invoke = function(method, input, callback){
        if (huCampusMethodNames.indexOf(method) >= 0) {
          dispatchHybridMethod('JCpdaily', method, input, callback);
          return;
        }
        try {
          callback && callback({
            errMsg: method + ':fail not supported',
            errorMessage: 'not supported',
            errorCode: -2
          });
        } catch(_) {}
      };
    }
    for (var j = 0; j < huCampusMethodNames.length; j++) {
      (function(method){
        var mustOverride = huMustOverrideMethod(method);
        if (mustOverride || typeof target[method] !== 'function') {
          target[method] = function(input, callback){
            dispatchHybridMethod('JCpdaily', method, input, callback);
          };
        }
      })(huCampusMethodNames[j]);
    }
  }
  if (window.JCpdaily) {
    patchJCpdailyObject(window.JCpdaily);
  }

  // ---- 微信 JSSDK shim：洗浴页实际会走 scanQRCode，强制路由到 Flutter 扫码 ----
  var wxReadyQueue = [];
  function flushWxReady(){
    while (wxReadyQueue.length) {
      try { wxReadyQueue.shift()(); } catch(_) {}
    }
  }
  function ensureWxShim(){
    var wx = window.wx;
    if (!wx) return;
    wx.config = function(opts){
      try { opts && opts.debug; } catch(_) {}
      setTimeout(flushWxReady, 0);
    };
    wx.ready = function(cb){
      if (typeof cb === 'function') {
        wxReadyQueue.push(cb);
        setTimeout(flushWxReady, 0);
      }
    };
    wx.error = function(_cb){};
    wx.checkJsApi = function(opts){
      try {
        (opts && (opts.success || opts.complete) || noop)({
          checkResult: {
            scanQRCode: true,
            getNetworkType: true,
          },
          errMsg: 'checkJsApi:ok'
        });
      } catch(_) {}
    };
    wx.scanQRCode = function(opts){
      try { console.log('[HuWX] wx.scanQRCode', opts || {}); } catch(_) {}
      var success = (opts && (opts.success || opts.complete)) || noop;
      var fail = (opts && opts.fail) || noop;
      bridgeExec(success, fail, 'scan', 'wx.scanQRCode', [opts || {}]);
    };
    wx.invoke = function(name, params, callback){
      try { console.log('[HuWX] wx.invoke', name || '', params || {}); } catch(_) {}
      try {
        callback && callback({
          err_msg: (name || 'invoke') + ':ok',
          errMsg: (name || 'invoke') + ':ok'
        });
      } catch(_) {}
    };
    wx.getNetworkType = function(opts){
      try {
        (opts && (opts.success || opts.complete) || noop)({
          networkType: 'wifi',
          errMsg: 'getNetworkType:ok'
        });
      } catch(_) {}
    };
    wx.miniProgram = wx.miniProgram || {
      getEnv: function(cb){
        try { cb && cb({ miniprogram: false }); } catch(_) {}
      },
      postMessage: noop,
      navigateTo: noop,
      redirectTo: noop,
      switchTab: noop,
      reLaunch: noop,
      navigateBack: noop,
      close: noop,
    };
    wx.closeWindow = function(){};
  }

  ensureWxShim();
  installWindowObjectHook('_cordovaNative', patchCordovaNativeObject);
  installWindowObjectHook('campus', patchCampusObject);
  installWindowObjectHook('JCpdaily', patchJCpdailyObject);
  installWindowObjectHook('wx', function(v){ ensureWxShim(); return v; });
  installWindowObjectHook('cordova', function(v){ tryHookCordova(); return v; });
  var hybridTimer = setInterval(function(){
    try { window.__huHybridRefresh && window.__huHybridRefresh(); } catch(_) {}
  }, 200);
  setTimeout(function(){ clearInterval(hybridTimer); }, 30000);

  function ensureCampusShim(){
    if (!window.campus) return;
    if (typeof window.campus.scan !== 'function') {
      window.campus.scan = function(opts){ campusCall('scan', opts); };
    }
    if (typeof window.campus.scanQrcode !== 'function') {
      window.campus.scanQrcode = function(opts){ campusCall('scanQrcode', opts); };
    }
    if (typeof window.campus.scanCode !== 'function') {
      window.campus.scanCode = function(opts){ campusCall('scanCode', opts); };
    }
    if (window.JCpdaily && typeof window.JCpdaily.scan !== 'function') {
      window.JCpdaily.scan = function(opts){ campusCall('scan', opts); };
    }
  }

  window.__huHybridRefresh = function(){
    tryHookCordova();
    ensureCampusShim();
    ensureWxShim();
    // 诊断埋点：每次 refresh 时重新 instrument，新出现的对象也能被包到
    if (typeof instrumentCallNative === 'function' && window.callNative) {
      try { instrumentCallNative(window.callNative); } catch(_) {}
    }
    if (typeof instrumentCampusBle === 'function' && window.campus) {
      try { instrumentCampusBle(window.campus); } catch(_) {}
    }
  };
  window.__huHybridRefresh();

  // ---- 全局 JS 异常捕获：让被 Vue / Promise 吞掉的同步异常能在 vconsole 里看到 ----
  if (!window.__huErrorTrapInstalled) {
    window.__huErrorTrapInstalled = true;
    var prevOnError = window.onerror;
    window.onerror = function(msg, src, line, col, err){
      try {
        console.log('[HuJSError] onerror', msg, src + ':' + line + ':' + col,
          err && err.stack ? err.stack : '');
      } catch(_) {}
      if (typeof prevOnError === 'function') {
        try { return prevOnError(msg, src, line, col, err); } catch(_) {}
      }
    };
    try {
      window.addEventListener('unhandledrejection', function(ev){
        try {
          var reason = ev && ev.reason;
          console.log('[HuJSError] unhandledrejection',
            reason && reason.message ? reason.message : reason,
            reason && reason.stack ? reason.stack : '');
        } catch(_) {}
      });
    } catch(_) {}
  }

  // ---- hzsun callNative 日志壳：原方法照旧调（会跳 com.hzsun.h5call:// scheme），
  // 只在调用前打一行 [HuCallNative]，方便定位 "先关闭蓝牙模块" 走的是不是 callNative。----
  function instrumentCallNative(target){
    if (!target || target.__huInstrumented) return target;
    Object.keys(target).forEach(function(key){
      var orig = target[key];
      if (typeof orig !== 'function') return;
      target[key] = function(){
        try { console.log('[HuCallNative]', key, Array.prototype.slice.call(arguments)); } catch(_) {}
        return orig.apply(this, arguments);
      };
    });
    target.__huInstrumented = true;
    return target;
  }
  if (window.callNative) instrumentCallNative(window.callNative);
  // 不能再调 installWindowObjectHook('callNative', ...) —— 它用 defineProperty
  // 直接覆盖前一个 hook，会把 patchCampusObject / wx / cordova 那几个 hook 干掉。
  // 改在 __huHybridRefresh 里每次 refresh 时重新尝试 instrument 即可。

  // ---- campus.* BLE 日志壳：原方法照旧调（cpdaily 走 cordova.exec），
  // 只在调用前打一行 [HuCampus.BLE]，方便确认这一族是不是真正被使用。----
  var campusBleNames = [
    'openBluetoothAdapter','closeBluetoothAdapter','getBluetoothAdapterState',
    'onBluetoothAdapterStateChange','offBluetoothAdapterStateChange',
    'startBluetoothDevicesDiscovery','stopBluetoothDevicesDiscovery',
    'getBluetoothDevices','getConnectedBluetoothDevices',
    'connectBLEDevice','disconnectBLEDevice',
    'writeBLECharacteristicValue','readBLECharacteristicValue',
    'notifyBLECharacteristicValueChange',
    'getBLEDeviceServices','getBLEDeviceCharacteristics',
    'onBluetoothDeviceFound','offBluetoothDeviceFound',
    'onBLECharacteristicValueChange','offBLECharacteristicValueChange',
    'onBLEConnectionStateChanged','offBLEConnectionStateChanged'
  ];
  function instrumentCampusBle(target){
    if (!target || target.__huBleInstrumented) return target;
    campusBleNames.forEach(function(name){
      var orig = target[name];
      if (typeof orig !== 'function') return;
      target[name] = function(){
        try { console.log('[HuCampus.BLE]', name, Array.prototype.slice.call(arguments)); } catch(_) {}
        return orig.apply(this, arguments);
      };
    });
    target.__huBleInstrumented = true;
    return target;
  }
  if (window.campus) instrumentCampusBle(window.campus);
  // 同理：不要再用 installWindowObjectHook 覆盖原 patchCampusObject hook。

  setTimeout(function(){
    try {
      var c = normalizeCordova(window.cordova);
      if (c && c.channel) {
        c.channel.onDOMContentLoaded.fire();
        c.channel.deviceready.fire();
        c.fireDocumentEvent('deviceready');
      }
    } catch (_) {}
  }, 0);
})();
''';

  String _buildBoundaryDebugScript(BoundaryDebugSettings settings) {
    final lng = settings.longitudeBd09;
    final lat = settings.latitudeBd09;
    final address = jsonEncode(settings.address);
    final city = jsonEncode(settings.city);
    return '''
(function(){
  var target = /^https?:\\/\\/ehall\\.uwh\\.edu\\.cn\\/student\\/cas\\/wap\\/menu\\/student\\/sign\\/stu\\/sign/;
  if (!target.test(location.href)) return;

  var mock = {
    longitude: $lng,
    latitude: $lat,
    lng: $lng,
    lat: $lat,
    lon: $lng,
    locationDescribe: $address,
    address: $address,
    city: $city,
    code: 0,
    status: 0,
    errMsg: 'getLocation:ok'
  };
  var browserPosition = {
    coords: {
      longitude: mock.longitude,
      latitude: mock.latitude,
      accuracy: 5,
      altitude: null,
      altitudeAccuracy: null,
      heading: null,
      speed: null
    },
    timestamp: Date.now()
  };

  function success(opts) {
    try {
      console.log('[BoundaryDebug] BD-09', mock.longitude, mock.latitude, mock.address);
    } catch (_) {}
    try {
      if (opts && typeof opts.success === 'function') opts.success(mock);
      if (opts && typeof opts.complete === 'function') opts.complete(mock);
      if (typeof opts === 'function') opts(mock);
    } catch (e) {
      try { console.log('[BoundaryDebug] callback error', e && e.message ? e.message : e); } catch (_) {}
    }
  }

  function geoSuccess(successCallback, errorCallback) {
    try {
      console.log('[BoundaryDebug] navigator.geolocation', mock.longitude, mock.latitude);
    } catch (_) {}
    if (typeof successCallback === 'function') {
      setTimeout(function(){ successCallback(browserPosition); }, 0);
    }
    return 1;
  }

  function patchWis() {
    if (typeof window.jutil === 'undefined') {
      setTimeout(patchWis, 50);
      return;
    }
    try {
      window.jutil.isWis = function() { return true; };
      window.jutil.isWeiXin = function() { return false; };
      window.jutil.isDing = function() { return false; };
      window.jutil.isYiban = function() { return false; };
      window.jutil.isChaoxing = function() { return false; };
      console.log('[BoundaryDebug] jutil patched: isWis=true');
    } catch (_) {}
  }

  window.SFWis = {
    config: function(params, cb) {
    if (typeof params === 'function') params(true);
    if (typeof cb === 'function') cb(true);
    },
    getLocation: success,
    location: success,
    geolocation: success
  };

  function patchCampus(target) {
    if (!target) return;
    target.geolocation = success;
    target.getLocation = success;
    target.location = success;
  }

  function patchNavigatorGeolocation() {
    var geo = {
      getCurrentPosition: function(successCallback, errorCallback, options) {
        return geoSuccess(successCallback, errorCallback);
      },
      watchPosition: function(successCallback, errorCallback, options) {
        return geoSuccess(successCallback, errorCallback);
      },
      clearWatch: function(id) {}
    };
    try {
      Object.defineProperty(navigator, 'geolocation', {
        configurable: true,
        enumerable: true,
        get: function() { return geo; }
      });
    } catch (_) {
      try {
        navigator.geolocation.getCurrentPosition = geo.getCurrentPosition;
        navigator.geolocation.watchPosition = geo.watchPosition;
        navigator.geolocation.clearWatch = geo.clearWatch;
      } catch (_) {}
    }
  }

  var campusValue = window.campus || {};
  patchCampus(campusValue);
  try {
    Object.defineProperty(window, 'campus', {
      configurable: true,
      enumerable: true,
      get: function() { return campusValue; },
      set: function(v) {
        campusValue = v || {};
        patchCampus(campusValue);
      }
    });
  } catch (_) {
    window.campus = campusValue;
  }
  patchCampus(window.campus);
  patchNavigatorGeolocation();
  patchWis();

  var attempts = 0;
  var timer = setInterval(function() {
    attempts++;
    patchCampus(window.campus);
    patchNavigatorGeolocation();
    if (window.SFWis) {
      window.SFWis.getLocation = success;
      window.SFWis.location = success;
      window.SFWis.geolocation = success;
    }
    if (attempts > 100) clearInterval(timer);
  }, 50);

  function logFinalInputs() {
    try {
      var zb = document.querySelector('#zb');
      var address = document.querySelector('#address');
      var ly = document.querySelector('#ly');
      console.log(
        '[BoundaryDebug] final inputs',
        'zb=' + (zb ? zb.value : ''),
        'address=' + (address ? (address.value || address.textContent || '') : ''),
        'ly=' + (ly ? ly.value : '')
      );
    } catch (_) {}
  }
  setTimeout(logFinalInputs, 800);
  setTimeout(logFinalInputs, 1800);
})();
''';
  }

  static const String _rememberMeScript = r'''
(function(){
  // 兼容多种命名：rememberMe / keepLogin / 7天免登 等。
  var sels = [
    '#rememberMe',
    'input[name="rememberMe"]',
    '#keepLogin',
    'input[name="keepLogin"]',
    'input[type="checkbox"][name*="remember" i]',
    'input[type="checkbox"][id*="remember" i]',
    'input[type="checkbox"][name*="keep" i]',
    'input[type="checkbox"][id*="keep" i]'
  ];
  var box = null;
  for (var i = 0; i < sels.length; i++) {
    box = document.querySelector(sels[i]);
    if (box) break;
  }
  // 兜底：根据旁边的中文 label 文本去匹配
  if (!box) {
    var labels = document.querySelectorAll('label');
    for (var j = 0; j < labels.length; j++) {
      var t = (labels[j].textContent || '').trim();
      if (/7\s*天|七天|保持登录|自动登录|记住/.test(t)) {
        var forId = labels[j].getAttribute('for');
        if (forId) box = document.getElementById(forId);
        if (!box) box = labels[j].querySelector('input[type="checkbox"]');
        if (box) break;
      }
    }
  }
  if (box && !box.checked) {
    box.checked = true;
    box.dispatchEvent(new Event('change', {bubbles:true}));
    box.dispatchEvent(new Event('click', {bubbles:true}));
  }
})();
''';

  static const String _captureScript = r'''
(function(){
  if (window.__happyUwhCredsHooked) return;
  window.__happyUwhCredsHooked = true;
  function $(sel){ return document.querySelector(sel); }
  function fields(){
    var u = $('#username') || document.querySelector('input[name="username"]');
    var p = $('#password') || document.querySelector('input[type="password"]');
    return {u:u, p:p};
  }
  function send(){
    var f = fields();
    if (!f.u || !f.p) return;
    var uv = (f.u.value || '').trim();
    var pv = f.p.value || '';
    if (!uv || !pv) return;
    try {
      FlutterCreds.postMessage(JSON.stringify({u: uv, p: pv}));
    } catch(e) {}
  }
  // 拦截登录按钮点击（capture 阶段，早于站点自身的加密/提交逻辑）
  var btn = $('#login_submit') ||
            document.querySelector('button[type="submit"]') ||
            document.querySelector('input[type="submit"]') ||
            document.querySelector('.auth_login_btn') ||
            document.querySelector('.login-btn');
  if (btn) btn.addEventListener('click', send, true);
  // 表单 submit / 回车键也兜底
  var f = fields();
  var form = (f.u && f.u.form) || document.querySelector('form');
  if (form) form.addEventListener('submit', send, true);
  if (f.p) {
    f.p.addEventListener('keydown', function(e){
      if (e.key === 'Enter') send();
    }, true);
  }
})();
''';

  String _buildFillScript(String username, String password) {
    final u = jsonEncode(username);
    final p = jsonEncode(password);
    return '''
(function(){
  function fire(el){
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  }
  var u = document.querySelector('#username') || document.querySelector('input[name="username"]');
  var p = document.querySelector('#password') || document.querySelector('input[type="password"]');
  if (u && !u.value) { u.value = $u; fire(u); }
  if (p && !p.value) { p.value = $p; fire(p); }
})();
''';
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(_lastUrl);
  }

  void _handleClose() {
    Navigator.of(context).pop(_lastUrl);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topInset = mq.padding.top;
    // 悬浮按钮所占的纵向空间：顶部偏移 8 + 胶囊高 32 + 与内容的间距 8
    const double floatingBarHeight = 8 + 32 + 8;
    final double webviewTopPadding = widget.topSafeArea
        ? topInset + floatingBarHeight
        : 0;
    final double webviewBottomPadding = widget.bottomSafeArea
        ? mq.padding.bottom
        : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  top: webviewTopPadding,
                  bottom: webviewBottomPadding,
                ),
                child: WebViewWidget(controller: _controller),
              ),
            ),
            if (_errorText != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 32,
                        color: Color(0xFF111111),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '页面加载失败',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: const Color(0xFF111111),
                              fontWeight: wBold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorText!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF777777),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorText = null;
                          });
                          _scheduleLaunchOverlay();
                          _controller.loadRequest(Uri.parse(widget.initialUrl));
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF111111),
                        ),
                        child: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading)
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFF111111),
                  backgroundColor: Color(0xFFE8E8E5),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showLaunchLoading,
                child: AnimatedOpacity(
                  opacity: _showLaunchLoading ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: MiniProgramLaunchView(
                    icon: widget.icon,
                    title: widget.title,
                    accentColor: widget.accentColor,
                  ),
                ),
              ),
            ),
            // 左上：返回（先回退 WebView 历史，无可退则关闭页面）
            Positioned(
              top: topInset + 8,
              left: 12,
              child: FloatingNavButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: _handleBack,
                semanticLabel: '返回',
              ),
            ),
            // 右上：微信小程序风格胶囊（刷新 | 关闭）
            Positioned(
              top: topInset + 8,
              right: 12,
              child: MiniProgramCapsule(
                onRefresh: () {
                  setState(() {
                    _isLoading = true;
                    _errorText = null;
                  });
                  _scheduleLaunchOverlay();
                  _controller.reload();
                },
                onClose: _handleClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
