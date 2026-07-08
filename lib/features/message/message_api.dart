import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/platform/browser_data_cleaner.dart';

class MessageApi {
  static const String _baseUrl = 'https://ehall.uwh.edu.cn';
  static const String _initPage =
      '$_baseUrl/message_pocket_web/inboxpc/pc.html';
  static const String _calConfigUrl =
      '$_baseUrl/message_pocket_web/user/app?searchContent=';
  static const String _msgListUrl = '$_baseUrl/message_pocket_web/user/msg';
  static const String _msgDetailUrl =
      '$_baseUrl/message_pocket_web/user/msg/msgDetail';
  static const List<String> _staleCookieNames = [
    'mcsessionid',
    'JSESSIONID',
    'route',
    'minos-stata',
  ];
  static const Duration _warmUpTimeout = Duration(seconds: 10);
  static const Duration _cookieWaitTimeout = Duration(seconds: 4);
  static const Duration _requestTimeout = Duration(seconds: 12);

  static const _channel = MethodChannel('uwhlife/browser_data');
  static bool _warmedUp = false;
  static Future<void>? _warmUpFuture;
  static List<MessageCategory>? _cachedCategories;
  static Future<List<MessageCategory>>? _categoryFetchFuture;

  /// Call once at app startup to preload categories in background.
  static void preload() {
    _ensureAndFetchCategories();
  }

  static Future<void> _ensureAndFetchCategories() async {
    try {
      await fetchCategories();
    } catch (e) {
      debugPrint('[MessageApi] preload failed: $e');
    }
  }

  /// Returns cached categories immediately, or null if not yet loaded.
  static List<MessageCategory>? get cachedCategories => _cachedCategories;

  static Future<String> _getNativeCookies() async {
    // Use the full path so Android CookieManager returns path-scoped cookies
    // like mcsessionid (which is likely set with path=/message_pocket_web/).
    final raw = await _channel.invokeMethod<String>('getCookies', {
      'url': _calConfigUrl,
    });
    return raw ?? '';
  }

  static Future<String> _getNativeCookiesForUrl(String url) async {
    final raw = await _channel.invokeMethod<String>('getCookies', {
      'url': url,
    });
    return raw ?? '';
  }

  /// Bootstrap the message session from the shared WebView cookie store.
  ///
  /// Real app WebViews already persist portal cookies into the native store.
  /// Reuse those cookies for a lightweight HTTP call to the message config
  /// endpoint, then write returned Set-Cookie headers back into the same native
  /// WebView store that later API requests read from.
  static Future<void> _warmUp() async {
    if (_warmedUp) return;
    final existing = _warmUpFuture;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _doWarmUp();
    _warmUpFuture = future;
    try {
      await future;
    } finally {
      if (identical(_warmUpFuture, future)) {
        _warmUpFuture = null;
      }
    }
  }

  static Future<void> _doWarmUp() async {
    final portalCookies = await _getNativeCookiesForUrl(_initPage);
    if (portalCookies.trim().isEmpty) {
      throw Exception('未获取到门户 Cookie，请先登录统一门户');
    }

    final setCookieHeaders = await _requestMessageSessionCookies(
      _initPage,
    ).timeout(_warmUpTimeout);
    final cookiesToStore = cookieHeadersForBrowserStore(setCookieHeaders);
    debugPrint('[MessageApi] bootstrap set-cookie count: ${cookiesToStore.length}');
    await BrowserDataCleaner.setCookiesForUrl(
      url: _calConfigUrl,
      cookies: cookiesToStore,
    );
    await BrowserDataCleaner.persistCookies();
    await _waitForMessageCookies();
    _warmedUp = true;
  }

  static Future<List<String>> _requestMessageSessionCookies(
    String startUrl,
  ) async {
    final client = HttpClient();
    final setCookieHeaders = <String>[];
    var url = startUrl;
    try {
      for (var redirectCount = 0; redirectCount < 8; redirectCount += 1) {
        final requestUri = Uri.parse(url);
        final nativeCookies = await _getNativeCookiesForUrl(url);
        final request = await client.getUrl(requestUri).timeout(_requestTimeout);
        request.followRedirects = false;
        final cookies = cookiesForRedirectRequest(
          nativeCookies: nativeCookies,
          responseCookieHeaders: setCookieHeaders,
        );
        if (cookies.isNotEmpty) {
          request.headers.set('Cookie', cookies);
        }
        request.headers.set('Referer', _initPage);
        _setCommonHeaders(request);

        final resp = await request.close().timeout(_requestTimeout);
        final responseSetCookies =
            resp.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
        setCookieHeaders.addAll(responseSetCookies);
        await resp.drain<void>().timeout(_requestTimeout);
        debugPrint('[MessageApi] bootstrap $url -> ${resp.statusCode}');

        if (_isRedirectStatus(resp.statusCode)) {
          final location = resp.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw _MessageSessionExpiredException('消息登录态跳转异常');
          }
          url = requestUri.resolve(location).toString();
          continue;
        }

        if (resp.statusCode == 401 || resp.statusCode == 403) {
          throw _MessageSessionExpiredException('消息登录态已失效，请先登录统一门户');
        }
        if (resp.statusCode >= 400) {
          throw _MessageApiException(
            code: 'http_${resp.statusCode}',
            message: '消息 Cookie 初始化失败',
          );
        }

        if (url != _calConfigUrl) {
          url = _calConfigUrl;
          continue;
        }

        return setCookieHeaders;
      }
      throw _MessageSessionExpiredException('消息登录态跳转次数过多');
    } finally {
      client.close(force: false);
    }
  }

  static Future<void> _waitForMessageCookies() async {
    final deadline = DateTime.now().add(_cookieWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final cookies = await _getNativeCookies();
      if (_hasMessageSessionCookie(cookies)) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw Exception('消息 Cookie 未就绪');
  }

  static bool _hasMessageSessionCookie(String cookies) {
    final lower = cookies.toLowerCase();
    return lower.contains('mcsessionid=') || lower.contains('jsessionid=');
  }

  @visibleForTesting
  static List<String> cookieHeadersForBrowserStore(List<String> headers) {
    return headers.map((header) => header.trim()).where((header) {
      if (header.isEmpty) return false;
      final name = header.split('=').first.trim().toLowerCase();
      return name.isNotEmpty;
    }).toList();
  }

  @visibleForTesting
  static String cookiesForRedirectRequest({
    required String nativeCookies,
    required List<String> responseCookieHeaders,
  }) {
    final cookies = <String, String>{};
    for (final cookie in nativeCookies.split(';')) {
      final trimmed = cookie.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) continue;
      final name = trimmed.split('=').first.trim();
      if (name.isEmpty) continue;
      cookies[name] = trimmed;
    }
    for (final header in responseCookieHeaders) {
      final cookie = _cookiePairFromSetCookie(header);
      if (cookie == null) continue;
      cookies[cookie.$1] = cookie.$2;
    }
    return cookies.values.join('; ');
  }

  static (String, String)? _cookiePairFromSetCookie(String header) {
    final pair = header.split(';').first.trim();
    if (pair.isEmpty || !pair.contains('=')) return null;
    final name = pair.split('=').first.trim();
    if (name.isEmpty) return null;
    return (name, pair);
  }

  @visibleForTesting
  static bool isWarmUpCookieRefreshUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return uri.host.toLowerCase() == 'ehall.uwh.edu.cn' &&
        uri.path == '/message_pocket_web/user/app' &&
        uri.queryParameters.containsKey('searchContent');
  }

  static String _cookiesForRequest(String cookies) {
    return cookies
        .split(';')
        .map((cookie) => cookie.trim())
        .where((cookie) => cookie.isNotEmpty)
        .where((cookie) {
          final name = cookie.split('=').first.trim().toLowerCase();
          return name != 'mod_auth_cas';
        })
        .join('; ');
  }

  static void reset() {
    _warmedUp = false;
    _warmUpFuture = null;
    _categoryFetchFuture = null;
  }

  static Future<String> _ensureMessageCookies({
    required bool forceWarmUp,
  }) async {
    final existingCookies = await _getNativeCookies();
    if (!forceWarmUp) {
      debugPrint('[MessageApi] first try cookies: "$existingCookies"');
      return _cookiesForRequest(existingCookies);
    }

    if (_hasMessageSessionCookie(existingCookies)) {
      debugPrint('[MessageApi] reuse cookies: "$existingCookies"');
      return _cookiesForRequest(existingCookies);
    }

    _warmedUp = false;
    await _warmUp();
    final cookies = await _getNativeCookies();
    debugPrint('[MessageApi] cookies: "$cookies"');

    if (!_hasMessageSessionCookie(cookies)) {
      reset();
      throw Exception('未获取到消息 Cookie，请先登录统一门户');
    }
    return _cookiesForRequest(cookies);
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    var cookies = await _ensureMessageCookies(forceWarmUp: false);
    try {
      return await _requestJson(url, cookies);
    } catch (e) {
      if (!_shouldRefreshSessionAndRetry(e)) rethrow;
      debugPrint('[MessageApi] request failed, refresh message session: $e');
      if (e is _MessageSessionExpiredException) {
        await _clearStaleMessageCookies();
      }
      reset();
      cookies = await _ensureMessageCookies(forceWarmUp: true);
      return _requestJson(url, cookies);
    }
  }

  static bool _shouldRefreshSessionAndRetry(Object error) {
    return error is _MessageSessionExpiredException ||
        error is _MessageApiException ||
        error is TimeoutException ||
        error is IOException ||
        error is FormatException;
  }

  static Future<void> _clearStaleMessageCookies() async {
    debugPrint('[MessageApi] clear stale message cookies');
    await BrowserDataCleaner.clearCookiesForUrl(
      url: _calConfigUrl,
      names: _staleCookieNames,
    );
  }

  static Future<Map<String, dynamic>> _requestJson(
    String url,
    String cookies,
  ) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(_requestTimeout);
      request.followRedirects = false;
      request.headers.set('Cookie', cookies);
      request.headers.set('Referer', _initPage);
      _setCommonHeaders(request);
      final resp = await request.close().timeout(_requestTimeout);
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      debugPrint('[MessageApi] $url -> ${resp.statusCode}');

      if (resp.statusCode == 401 ||
          resp.statusCode == 403 ||
          resp.statusCode == 301 ||
          resp.statusCode == 302 ||
          resp.statusCode == 303 ||
          resp.statusCode == 307 ||
          resp.statusCode == 308) {
        throw _MessageSessionExpiredException('未登录或会话过期 (${resp.statusCode})');
      }
      if (resp.statusCode == 408 || resp.statusCode >= 500) {
        throw _MessageApiException(
          code: 'http_${resp.statusCode}',
          message: '消息接口请求失败',
        );
      }

      late final Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } on FormatException catch (e) {
        if (body.contains('/authserver/login') ||
            body.toLowerCase().contains('<html')) {
          throw _MessageSessionExpiredException('未登录或会话过期');
        }
        throw FormatException('消息接口返回非 JSON 内容：${e.message}');
      }
      if (json['code'] != '0000') {
        throw _MessageApiException(
          code: json['code']?.toString() ?? '',
          message: json['msg']?.toString() ?? json['message']?.toString(),
        );
      }
      return json;
    } finally {
      client.close(force: false);
    }
  }

  static void _setCommonHeaders(HttpClientRequest request) {
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
    );
    request.headers.set('Accept', 'application/json, text/plain, */*');
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static Future<List<MessageCategory>> fetchCategories({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCategories != null) return _cachedCategories!;
    if (!forceRefresh) {
      final existing = _categoryFetchFuture;
      if (existing != null) return existing;
    }

    final future = _fetchCategoriesFromNetwork();
    if (!forceRefresh) _categoryFetchFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_categoryFetchFuture, future)) {
        _categoryFetchFuture = null;
      }
    }
  }

  static Future<List<MessageCategory>> _fetchCategoriesFromNetwork() async {
    final json = await _getJson(_calConfigUrl);
    final list = json['data'] as List;
    _cachedCategories = list
        .map((e) => MessageCategory.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cachedCategories!;
  }

  /// Silently refresh categories in background, updating cache.
  static Future<void> refreshCategoriesSilently() async {
    try {
      await fetchCategories(forceRefresh: true);
    } catch (_) {}
  }

  static Future<MessageListResult> fetchMessages({
    required String appId,
    int current = 1,
    int size = 20,
  }) async {
    final url =
        '$_msgListUrl?appId=$appId&current=$current&size=$size&sendType=-1&searchContent=';
    final json = await _getJson(url);
    return MessageListResult.fromJson(json['data'] as Map<String, dynamic>);
  }

  static Future<MessageDetail> fetchDetail({
    required String id,
    required String msgId,
  }) async {
    final url = '$_msgDetailUrl?id=$id&msgId=$msgId';
    final json = await _getJson(url);
    return MessageDetail.fromJson(json['data'] as Map<String, dynamic>);
  }
}

class _MessageApiException implements Exception {
  _MessageApiException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() {
    final detail = message;
    if (detail == null || detail.isEmpty) return '消息接口异常：$code';
    return '消息接口异常：$code $detail';
  }
}

class _MessageSessionExpiredException implements Exception {
  _MessageSessionExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MessageCategory {
  final String appId;
  final String appName;
  final int tagId;
  final int total;
  final int unReadMsgCount;
  final String? latestMsgContent;
  final String? latestMsgSendDate;

  MessageCategory({
    required this.appId,
    required this.appName,
    required this.tagId,
    this.total = 0,
    this.unReadMsgCount = 0,
    this.latestMsgContent,
    this.latestMsgSendDate,
  });

  factory MessageCategory.fromJson(Map<String, dynamic> json) {
    return MessageCategory(
      appId: json['appId']?.toString() ?? '',
      appName: json['appName']?.toString() ?? '',
      tagId: (json['tagId'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      unReadMsgCount: (json['unReadMsgCount'] as num?)?.toInt() ?? 0,
      latestMsgContent: json['latestMsgContent'] as String?,
      latestMsgSendDate: json['latestMsgSendDate'] as String?,
    );
  }

  bool get hasMessages => total > 0;
}

class MessageListResult {
  final int current;
  final int pages;
  final int total;
  final List<MessageItem> records;

  MessageListResult({
    required this.current,
    required this.pages,
    required this.total,
    required this.records,
  });

  factory MessageListResult.fromJson(Map<String, dynamic> json) {
    final list = json['records'] as List? ?? [];
    return MessageListResult(
      current: (json['current'] as num?)?.toInt() ?? 1,
      pages: (json['pages'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? 0,
      records: list
          .map((e) => MessageItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MessageItem {
  final String id;
  final String msgId;
  final String msgTitle;
  final String msgContent;
  final String msgSendDate;
  final bool isRead;
  final String? mobileUrl;
  final String? pcUrl;

  MessageItem({
    required this.id,
    required this.msgId,
    required this.msgTitle,
    required this.msgContent,
    required this.msgSendDate,
    required this.isRead,
    this.mobileUrl,
    this.pcUrl,
  });

  factory MessageItem.fromJson(Map<String, dynamic> json) {
    return MessageItem(
      id: json['id']?.toString() ?? '',
      msgId: json['msgId']?.toString() ?? '',
      msgTitle: json['msgTitle']?.toString() ?? '',
      msgContent: json['msgContent']?.toString() ?? '',
      msgSendDate: json['msgSendDate']?.toString() ?? '',
      isRead: (json['isReaded'] as num?)?.toInt() == 1,
      mobileUrl: json['mobileUrl'] as String?,
      pcUrl: json['pcUrl'] as String?,
    );
  }
}

class MessageDetail {
  final String msgTitle;
  final String msgContent;
  final String msgSendDate;
  final String? mobileRedirectUrl;
  final String? pcRedirectUrl;
  final String appName;

  MessageDetail({
    required this.msgTitle,
    required this.msgContent,
    required this.msgSendDate,
    this.mobileRedirectUrl,
    this.pcRedirectUrl,
    required this.appName,
  });

  factory MessageDetail.fromJson(Map<String, dynamic> json) {
    return MessageDetail(
      msgTitle: json['msgTitle']?.toString() ?? '',
      msgContent: json['msgContent']?.toString() ?? '',
      msgSendDate: json['msgSendDate']?.toString() ?? '',
      mobileRedirectUrl: json['mobileRedirectUrl'] as String?,
      pcRedirectUrl: json['pcRedirectUrl'] as String?,
      appName: json['appName']?.toString() ?? '',
    );
  }

  String? get redirectUrl => mobileRedirectUrl ?? pcRedirectUrl;
}
