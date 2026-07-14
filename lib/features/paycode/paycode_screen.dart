import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  int _countdown = 30;
  Timer? _refreshTimer;
  Timer? _statusTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(PayCodeApi.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    } else if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _statusTimer?.cancel();
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
        _countdown = 30;
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
        _countdown = 30;
      });
      _startTimers();
    } catch (e) {
      debugPrint('[PayCodeScreen] refresh error: $e');
      if (!mounted) return;
      // If we still have old QR data, just resume timers
      if (_qrData != null) {
        setState(() {
          _isLoading = false;
          _countdown = 30;
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
      if (_countdown > 0) {
        setState(() => _countdown--);
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

  void _openWebViewFallback() {
    Navigator.of(context).push(
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
            onPressed: _openWebViewFallback,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Blue card
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
                                fontWeight: FontWeight.w500,
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
                            Text(
                              '${_countdown}s 后自动刷新',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
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
      return QrImageView(
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
      );
    }
    return const SizedBox();
  }
}
