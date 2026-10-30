import 'dart:convert';
import 'dart:io';

import '../platform/browser_data_cleaner.dart';
import 'portal_user_store.dart';

class PortalUserSync {
  static final Uri _loginUserUri = Uri.https(
    'ehall.uwh.edu.cn',
    '/getLoginUser',
  );

  static Future<bool> fromCookieHeader(String cookieHeader) async {
    try {
      final body = await fetchUserResponse(cookieHeader);
      return body != null &&
          await PortalUserStore.saveFromLoginUserResponse(body);
    } catch (_) {
      return false;
    }
  }

  /// Fetch without changing local state; callers can discard stale results.
  static Future<String?> fetchUserResponse(String cookieHeader) async {
    if (cookieHeader.trim().isEmpty) return null;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final request = await client.getUrl(_loginUserUri);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      return await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<bool> fromWebViewCookies() async {
    try {
      final body = await fetchWebViewUserResponse();
      return body != null &&
          await PortalUserStore.saveFromLoginUserResponse(body);
    } catch (_) {
      return false;
    }
  }

  static Future<String?> fetchWebViewUserResponse() async {
    try {
      final cookieHeader = await BrowserDataCleaner.getCookies(
        url: _loginUserUri.toString(),
      );
      return await fetchUserResponse(cookieHeader);
    } catch (_) {
      return null;
    }
  }
}
