import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayCodeApi {
  static const String _authUrl =
      'https://auth.xiaofubao.com/authoriz/getCodeV2?bindSkip=1'
      '&ymAppId=1810181825222034&authType=3&authAppid=4622023061501'
      '&callbackUrl=https%3A%2F%2Fwebapp.xiaofubao.com%2Fcard%2F'
      'card_pay_code.shtml%3Fplatform%3DWJ%26schoolCode%3D2023061501'
      '%26authAppid%3D4622023061501';

  static WebViewController? _webView;
  static bool _ready = false;
  static String? _userName;
  static PayCodeResult? _lastResult;

  static String? get userName => _userName;

  static PayCodeResult? _consumeLastResult() {
    final result = _lastResult;
    _lastResult = null;
    return result;
  }

  static Future<WebViewController> _ensureWebView() async {
    if (_webView != null && _ready) return _webView!;

    final completer = Completer<void>();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Block navigation away from pay code page (e.g. pay_result.shtml)
            if (request.url.contains('pay_result')) {
              _lastResult = PayCodeResult.fromResultUrl(request.url);
              debugPrint('[PayCodeApi] captured pay result: ${request.url}');
              return NavigationDecision.prevent;
            }
            if (!request.url.contains('card_pay_code') &&
                !request.url.contains('auth.xiaofubao.com') &&
                request.url.startsWith('http')) {
              debugPrint('[PayCodeApi] blocked navigation to: ${request.url}');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            debugPrint('[PayCodeApi] pageFinished: $url');
            if (url.contains('webapp.xiaofubao.com') &&
                url.contains('card_pay_code')) {
              if (!completer.isCompleted) completer.complete();
            }
          },
          onWebResourceError: (error) {
            debugPrint('[PayCodeApi] error: ${error.description}');
            if (!completer.isCompleted) {
              completer.completeError(
                Exception('加载付款码页面失败: ${error.description}'),
              );
            }
          },
        ),
      );

    _webView = controller;
    _ready = false;
    await controller.loadRequest(Uri.parse(_authUrl));

    await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        debugPrint('[PayCodeApi] warmup timeout');
      },
    );

    // Wait for the page's JS to finish calling defaultLogin + getQRCode.
    // Poll for vueObj.qrCodeStr instead of a fixed delay.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    // Extract user name
    try {
      final userRaw = await controller.runJavaScriptReturningResult(
        'JSON.stringify(getObjectCache("loginUser"))',
      );
      var userStr = userRaw.toString();
      if (userStr.startsWith('"') && userStr.endsWith('"')) {
        userStr = userStr.substring(1, userStr.length - 1);
        userStr = userStr.replaceAll(r'\"', '"');
      }
      if (userStr != 'null' && userStr.isNotEmpty) {
        final user = jsonDecode(userStr) as Map<String, dynamic>;
        _userName = user['userName']?.toString();
        debugPrint('[PayCodeApi] userName=$_userName');
      }
    } catch (e) {
      debugPrint('[PayCodeApi] extract user failed: $e');
    }

    _ready = true;
    return controller;
  }

  static Future<String> fetchQRCode() async {
    final controller = await _ensureWebView();

    // Poll for vueObj.qrCodeStr (the page fetches it on load)
    for (var i = 0; i < 20; i++) {
      try {
        final existing = await controller.runJavaScriptReturningResult(
          'typeof vueObj !== "undefined" && vueObj.qrCodeStr ? vueObj.qrCodeStr : ""',
        );
        var str = existing.toString();
        if (str.startsWith('"') && str.endsWith('"')) {
          str = str.substring(1, str.length - 1);
        }
        if (str.isNotEmpty) {
          debugPrint('[PayCodeApi] got QR on poll #$i');
          return str;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Fallback: fetch via JS ourselves
    return _fetchQRCodeViaJs(controller);
  }

  /// Force refresh: trigger the page's own refresh, then poll for new data
  static Future<String> refreshQRCode() async {
    final controller = await _ensureWebView();
    // Clear old data and trigger page's own refresh function
    try {
      await controller.runJavaScript('''
        if (typeof vueObj !== "undefined") {
          vueObj.qrCodeStr = null;
          vueObj.lastQueryTime = 0;
          vueObj.queryQRCode(true);
        }
      ''');
    } catch (_) {}

    // Poll for new data
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      try {
        final result = await controller
            .runJavaScriptReturningResult(
              'typeof vueObj !== "undefined" && vueObj.qrCodeStr ? vueObj.qrCodeStr : ""',
            )
            .timeout(const Duration(seconds: 3));
        var str = result.toString();
        if (str.startsWith('"') && str.endsWith('"')) {
          str = str.substring(1, str.length - 1);
        }
        if (str.isNotEmpty) {
          debugPrint('[PayCodeApi] refreshed QR on poll #$i');
          return str;
        }
      } catch (_) {}
    }
    throw Exception('刷新二维码超时');
  }

  // Kept as fallback but no longer primary path
  static Future<String> _fetchQRCodeViaJs(WebViewController controller) async {
    final js = '''
(async function() {
  try {
    var user = getObjectCache("loginUser");
    if (!user) return JSON.stringify({"error": "no_user"});
    var params = new URLSearchParams();
    params.append("type", "0");
    params.append("deviceId", user.id);
    params.append("platform", "WJ");
    var resp = await fetch("/card/getQRCode", {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: params.toString()
    });
    var json = await resp.json();
    return JSON.stringify(json);
  } catch(e) {
    return JSON.stringify({"error": e.toString()});
  }
})()
''';
    final result = await controller
        .runJavaScriptReturningResult(js)
        .timeout(const Duration(seconds: 8));
    var raw = result.toString();
    if (raw.startsWith('"') && raw.endsWith('"')) {
      raw = raw.substring(1, raw.length - 1);
      raw = raw.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    debugPrint(
      '[PayCodeApi] fetch QR result: ${raw.substring(0, raw.length.clamp(0, 100))}',
    );

    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw Exception(json['error']);
    }
    if (json['statusCode'] != 0) {
      throw Exception(json['message'] ?? '获取二维码失败');
    }
    final data = json['data'] as String;

    // Also update the page's Vue instance so the timer stays in sync
    try {
      await controller.runJavaScript(
        'if (typeof vueObj !== "undefined") { vueObj.qrCodeStr = ${jsonEncode(data)}; }',
      );
    } catch (_) {}

    return data;
  }

  /// Query payment result. Returns {flag: 0|1|2, money: "x.xx"}
  static Future<PayCodeResult> queryResult(String qrCode) async {
    final captured = _consumeLastResult();
    if (captured != null) return captured;
    if (_webView == null || !_ready) return PayCodeResult.pending();
    final controller = _webView!;

    final js =
        '''
(async function() {
  try {
    var user = getObjectCache("loginUser");
    if (!user) return JSON.stringify({"statusCode": -1});
    var params = new URLSearchParams();
    params.append("qrCode", ${jsonEncode(qrCode)});
    params.append("deviceId", user.id);
    params.append("platform", "WJ");
    var resp = await fetch("/card/getQRCodeResult", {
      method: "POST",
      credentials: "include",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
        "X-Requested-With": "XMLHttpRequest"
      },
      body: params.toString()
    });
    var json = await resp.json();
    return JSON.stringify(json);
  } catch(e) {
    return JSON.stringify({"statusCode": -1});
  }
})()
''';
    try {
      final result = await controller
          .runJavaScriptReturningResult(js)
          .timeout(const Duration(seconds: 8));
      var raw = result.toString();
      if (raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
        raw = raw.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['statusCode'] != 0) return PayCodeResult.pending();
      final data = json['data'] as Map<String, dynamic>?;
      final payResult = PayCodeResult.fromJson(data);
      // Stop JS-side timers to prevent page from navigating away
      if (payResult.isFinished) {
        try {
          await controller.runJavaScript('''
            if (typeof vueObj !== "undefined") {
              vueObj.clearTimeout();
              if (typeof timerResult !== "undefined" && timerResult) {
                clearTimeout(timerResult);
                timerResult = null;
              }
            }
          ''');
        } catch (_) {}
      }
      return payResult;
    } catch (_) {
      return PayCodeResult.pending();
    }
  }

  static void reset() {
    _webView = null;
    _ready = false;
    _userName = null;
    _lastResult = null;
  }
}

class PayCodeResult {
  const PayCodeResult({
    required this.flag,
    this.money = '',
    this.payTypeName = '',
  });

  final int flag;
  final String money;
  final String payTypeName;

  bool get isPending => flag == 0;
  bool get isSuccess => flag == 1;
  bool get isFailure => flag == 2;
  bool get isFinished => isSuccess || isFailure;

  factory PayCodeResult.pending() => const PayCodeResult(flag: 0);

  factory PayCodeResult.fromJson(Map<String, dynamic>? data) {
    final rawFlag = data?['recflag'];
    var flag = 0;
    if (rawFlag is int) flag = rawFlag;
    if (rawFlag is String) flag = int.tryParse(rawFlag) ?? 0;

    final rawMoney = data?['monDealCur']?.toString().trim() ?? '';
    final money = _normalizeMoney(rawMoney);
    final payTypeName = data?['payTypeName']?.toString().trim() ?? '';
    return PayCodeResult(
      flag: flag,
      money: money,
      payTypeName: payTypeName.isEmpty ? '一码通' : payTypeName,
    );
  }

  factory PayCodeResult.fromResultUrl(String url) {
    final uri = Uri.tryParse(url);
    final money = _normalizeMoney(uri?.queryParameters['money'] ?? '');
    final payTypeName = uri?.queryParameters['pay_type']?.trim() ?? '';
    return PayCodeResult(
      flag: 1,
      money: money,
      payTypeName: payTypeName.isEmpty ? '一码通' : payTypeName,
    );
  }

  static String _normalizeMoney(String raw) {
    final value = double.tryParse(raw);
    if (value == null) return raw;
    return value.toStringAsFixed(2);
  }
}
