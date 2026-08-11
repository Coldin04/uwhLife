import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/screen_brightness_boost.dart';
import '../../core/storage/paycode_brightness_settings.dart';
import '../../core/utils/route_utils.dart';
import '../webview/portal_webview_page.dart';
import 'paycode_api.dart';
import 'pay_result_sheet.dart';

class PayCodeScreen extends StatefulWidget {
  const PayCodeScreen({super.key});

  @override
  State<PayCodeScreen> createState() => _PayCodeScreenState();
}

class _PayCodeScreenState extends State<PayCodeScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _error;
  String? _qrData;

  /// 倒计时每秒都在跳，但页面上只有一行字跟着它变。走 ValueNotifier 而不是
  /// setState，二维码那块就不用陪着每秒重建 —— QrImageView 每次 build 都会
  /// 重跑一遍 QR 编码并重绘 180×180。
  final ValueNotifier<int> _countdown = ValueNotifier<int>(30);
  Timer? _refreshTimer;
  Timer? _statusTimer;
  bool _polling = false;
  final ScreenBrightnessBoost _brightness = ScreenBrightnessBoost();
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 主题（含系统深色模式切换）变了要重新判断增不增亮。
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    if (isDarkMode == _isDarkMode && _brightness.isApplied) return;
    _isDarkMode = isDarkMode;
    unawaited(_syncBrightness());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    _countdown.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_brightness.restore());
    unawaited(PayCodeApi.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      unawaited(_syncBrightness());
      return;
    }
    // inactive/hidden/paused/detached：切出 App、锁屏、来电都要立刻还原亮度。
    unawaited(_brightness.restore());
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _statusTimer?.cancel();
    }
  }

  /// 按设置决定拉亮还是还原；设置可能在「我的」里改过，每次都重读。
  Future<void> _syncBrightness() async {
    final settings = await PayCodeBrightnessSettings.read();
    if (!mounted) return;
    if (settings.shouldBoost(isDarkMode: _isDarkMode)) {
      await _brightness.apply();
    } else {
      await _brightness.restore();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = _qrData == null;
      _error = null;
    });

    try {
      final data = await PayCodeApi.fetchQRCode();
      if (!mounted) return;
      setState(() {
        _qrData = data;
        _isLoading = false;
        _countdown.value = 30;
        _error = null;
      });
      _startTimers();
    } catch (e, st) {
      debugPrint('[PayCodeScreen] load error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (!mounted || _isLoading) return;
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await PayCodeApi.refreshQRCode().timeout(
        const Duration(seconds: 10),
      );
      if (!mounted) return;
      setState(() {
        _qrData = data;
        _isLoading = false;
        _countdown.value = 30;
      });
      _startTimers();
    } catch (e) {
      debugPrint('[PayCodeScreen] refresh error: $e');
      if (!mounted) return;
      // If we still have old QR data, just resume timers
      if (_qrData != null) {
        setState(() {
          _isLoading = false;
          _countdown.value = 30;
        });
        _startTimers();
      } else {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();

    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_countdown.value > 0) {
        _countdown.value--;
      } else if (!_isLoading) {
        _refresh();
      }
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _queryStatus();
    });
  }

  Future<void> _queryStatus() async {
    if (_qrData == null || _polling || !mounted) return;
    _polling = true;
    try {
      final result = await PayCodeApi.queryResult(_qrData!);
      if (!mounted) return;
      if (result.isSuccess) {
        _refreshTimer?.cancel();
        _statusTimer?.cancel();
        _showPayResult(result);
      } else if (result.isFailure) {
        _refreshTimer?.cancel();
        _statusTimer?.cancel();
        _showPayFailure();
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  void _showPayResult(PayCodeResult result) {
    unawaited(
      showPayResultSheet(
        context: context,
        success: true,
        money: result.money,
        payTypeName: result.payTypeName,
        primaryLabel: '继续刷卡',
      ).whenComplete(() {
        if (mounted) _refresh();
      }),
    );
  }

  void _showPayFailure() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('支付失败，请重试'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _load();
  }

  Future<void> _openWebViewFallback() async {
    // 离开付款码去别的页面，先把亮度还原，回来再按设置恢复。
    await _brightness.restore();
    if (!mounted) return;
    await Navigator.of(context).push(
      createSlideFadeRoute(
        const PortalWebViewPage(
          title: '付款码',
          icon: Icons.qr_code_2_outlined,
          initialUrl:
              'https://auth.xiaofubao.com/authoriz/getCodeV2?bindSkip=1'
              '&ymAppId=1810181825222034&authType=3&authAppid=4622023061501'
              '&callbackUrl=https%3A%2F%2Fwebapp.xiaofubao.com%2Fcard%2F'
              'card_pay_code.shtml%3Fplatform%3DWJ%26schoolCode%3D2023061501'
              '%26authAppid%3D4622023061501',
          topSafeArea: false,
          bottomSafeArea: false,
          accentColor: Color(0xFFFF7A00),
        ),
      ),
    );
    if (!mounted) return;
    await _syncBrightness();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBackground = Theme.of(context).scaffoldBackgroundColor;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(color: pageBackground),
        child: Scaffold(
          // 不用 extendBodyBehindAppBar：让 body 自然从 AppBar 下沿开始，
          // 免得再手算 kToolbarHeight 偏移（算不准就会留出一条空白）。
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            forceMaterialTransparency: true,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isDark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            ),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.open_in_browser_rounded,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                tooltip: '网页版',
                onPressed: () => unawaited(_openWebViewFallback()),
              ),
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Blue card：紧贴 AppBar 下沿，中间不留空隙。
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1677FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          // Card header
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.credit_card,
                                    size: 16,
                                    color: Color(0xFF1677FF),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  PayCodeApi.userName != null
                                      ? '一码通 · ${PayCodeApi.userName}'
                                      : '一码通',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '向商家付款',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // QR code
                          Center(
                            child: GestureDetector(
                              onTap: _isLoading ? null : _refresh,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SizedBox(
                                  width: 180,
                                  height: 180,
                                  child: _buildQrContent(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Countdown + refresh
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_qrData != null)
                                ValueListenableBuilder<int>(
                                  valueListenable: _countdown,
                                  builder: (context, seconds, _) => Text(
                                    '${seconds}s 后自动刷新',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (_qrData != null && !_isLoading)
                                GestureDetector(
                                  onTap: _refresh,
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Icon(
                                      Icons.refresh_rounded,
                                      color: Colors.white54,
                                      size: 16,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Hint
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '请在支持扫码的机具上使用，点击二维码可刷新',
                        style: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQrContent() {
    if (_isLoading && _qrData == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1677FF)),
      );
    }
    if (_error != null && _qrData == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              '加载失败，点击重试',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_qrData != null) {
      // 单独一层：页面其它部分（倒计时、刷新态）重绘时不连带重画二维码。
      return RepaintBoundary(
        child: QrImageView(
          data: _qrData!,
          version: QrVersions.auto,
          size: 180,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      );
    }
    return const SizedBox();
  }
}
