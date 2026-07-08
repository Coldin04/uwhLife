import 'dart:io';

import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 清除 App 内 WebView 使用的全局浏览器数据。
/// 不触碰 flutter_secure_storage / Keychain 中保存的账号密码。
class BrowserDataCleaner {
  static const MethodChannel _channel = MethodChannel('uwhlife/browser_data');

  static Future<void> clear() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod<void>('clearAppBrowserData');
        return;
      }
    } catch (_) {
      // 兜底走 webview_flutter 的 cookie 清理，至少保证登录态失效。
    }
    await WebViewCookieManager().clearCookies();
  }

  static Future<void> persistCookies() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('flushCookies');
    } catch (_) {
      // Android WebView 会自行择机落盘；这里仅做显式 flush 的增强。
    }
  }

  static Future<void> clearCookiesForUrl({
    required String url,
    required List<String> names,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('clearCookiesForUrl', {
        'url': url,
        'names': names,
      });
    } catch (_) {}
  }

  static Future<void> setCookiesForUrl({
    required String url,
    required List<String> cookies,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (cookies.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('setCookiesForUrl', {
        'url': url,
        'cookies': cookies,
      });
    } catch (_) {}
  }
}
