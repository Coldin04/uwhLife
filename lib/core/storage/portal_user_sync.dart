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
    if (cookieHeader.trim().isEmpty) return false;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final request = await client.getUrl(_loginUserUri);
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return false;
      final body = await response.transform(utf8.decoder).join();
      return PortalUserStore.saveFromLoginUserResponse(body);
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<bool> fromWebViewCookies() async {
    final cookieHeader = await BrowserDataCleaner.getCookies(
      url: _loginUserUri.toString(),
    );
    return fromCookieHeader(cookieHeader);
  }
}
