import 'dart:io';

import 'package:flutter/foundation.dart';
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
    final filtered = filterCookiesForUrl(Uri.parse(url), cookies);
    if (filtered.isEmpty) return;
    await _channel.invokeMethod<void>('setCookiesForUrl', {
      'url': url,
      'cookies': filtered,
    });
  }

  /// A campus service may only scope cookies to the campus domain or one of
  /// its subdomains. The IDS sometimes sends Domain=edu.cn, which browsers
  /// reject as a public suffix and which must not block valid session cookies.
  static bool isCookieDomainAllowed(Uri uri, String? cookieDomain) {
    if (cookieDomain == null || cookieDomain.isEmpty) return true;
    final host = uri.host.toLowerCase();
    final domain = cookieDomain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    if (host != domain && !host.endsWith('.$domain')) return false;
    const campus = 'uwh.edu.cn';
    final campusHost = host == campus || host.endsWith('.$campus');
    return !campusHost || domain == campus || domain.endsWith('.$campus');
  }

  @visibleForTesting
  static List<String> filterCookiesForUrl(Uri uri, List<String> cookies) {
    return cookies.where((raw) {
      final cookie = Cookie.fromSetCookieValue(raw);
      return isCookieDomainAllowed(uri, cookie.domain);
    }).toList(growable: false);
  }

  static Future<String> getCookies({required String url}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return '';
    return await _channel.invokeMethod<String>('getCookies', {'url': url}) ??
        '';
  }
}
