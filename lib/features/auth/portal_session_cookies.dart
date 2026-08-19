import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/platform/browser_data_cleaner.dart';
import 'ids_http_auth.dart';

abstract interface class PortalSessionCookiePersistence {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class _SecurePortalSessionCookiePersistence
    implements PortalSessionCookiePersistence {
  static const _key = 'portal_session_cookies_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Securely persisted cookies produced by either IDS login flow.
///
/// The module restores its in-memory jar lazily after a cold start. WebView is
/// retained only as a compatibility fallback when no identity cookie could be
/// imported (for example, an incomplete login or a platform cookie-store
/// failure).
class PortalSessionCookies {
  PortalSessionCookies._();

  static PortalSessionCookiePersistence _persistence =
      _SecurePortalSessionCookiePersistence();
  static HttpCookieJar? _cookies;
  static Future<HttpCookieJar?>? _loading;

  /// Records the fresh IDS/Ehall cookies returned by a successful native login.
  static Future<void> rememberLogin(IdsLoginResult result) async {
    final cookies = HttpCookieJar();
    if (!result.copyCookiesTo(cookies)) return;
    _cookies = cookies;
    _loading = null;
    await _persistence.write(cookies.encodeForSecureStorage());
  }

  /// Imports the session created by the manual WebView login flow.
  ///
  /// Native login calls [rememberLogin] directly. A captcha or a user-entered
  /// WebView login has no [IdsLoginResult], so copy only the identity domains
  /// here and persist them for the next cold launch as well.
  static Future<bool> rememberWebViewSession() async {
    final cookies = HttpCookieJar();
    final urls = <Uri>[
      Uri.https('ids.uwh.edu.cn', '/authserver/'),
      Uri.https('ehall.uwh.edu.cn', '/getLoginUser'),
    ];
    var found = false;
    for (final uri in urls) {
      final header = await BrowserDataCleaner.getCookies(url: uri.toString());
      if (header.trim().isEmpty) continue;
      cookies.addCookieHeader(uri, header);
      found = true;
    }
    if (!found) return false;
    _cookies = cookies;
    _loading = null;
    await _persistence.write(cookies.encodeForSecureStorage());
    return true;
  }

  /// Adds persisted session cookies for [uri] to a service client's jar.
  ///
  /// Returns false when no native-login cookie exists for that host, so callers
  /// can fall back to the platform WebView cookie store.
  static Future<bool> seedFor(Uri uri, HttpCookieJar target) async {
    final cookies = await _load();
    if (cookies == null) return false;
    return cookies.copyMatchingTo(uri, target);
  }

  static Future<HttpCookieJar?> _load() async {
    final current = _cookies;
    if (current != null) return current;
    final pending = _loading;
    if (pending != null) return pending;

    final future = _loadPersisted();
    _loading = future;
    try {
      return await future;
    } finally {
      if (identical(_loading, future)) _loading = null;
    }
  }

  static Future<HttpCookieJar?> _loadPersisted() async {
    final raw = await _persistence.read();
    if (raw == null || raw.isEmpty) return null;
    final cookies = HttpCookieJar.decodeFromSecureStorage(raw);
    if (cookies == null) {
      await _persistence.clear();
      return null;
    }
    _cookies = cookies;
    return cookies;
  }

  /// Removes both the in-memory and encrypted persisted copies.
  static Future<void> clear() async {
    _cookies = null;
    _loading = null;
    await _persistence.clear();
  }

  @visibleForTesting
  static void configureForTesting(PortalSessionCookiePersistence persistence) {
    _persistence = persistence;
    _cookies = null;
    _loading = null;
  }

  @visibleForTesting
  static void resetForTesting() {
    _persistence = _SecurePortalSessionCookiePersistence();
    _cookies = null;
    _loading = null;
  }
}
