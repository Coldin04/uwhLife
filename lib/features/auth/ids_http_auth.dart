import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/portal_user_sync.dart';
import 'ids_aes.dart';
import 'ids_slider_captcha.dart';

const _idsHost = 'ids.uwh.edu.cn';

enum IdsLoginStatus {
  authenticated,
  captchaRequired,
  invalidCredentials,
  failed,
}

class IdsLoginResult {
  const IdsLoginResult._({
    required this.status,
    this.message,
    HttpCookieJar? cookieJar,
    Uri? service,
  }) : _cookieJar = cookieJar,
       _service = service;

  const IdsLoginResult.authenticated({
    required HttpCookieJar cookieJar,
    required Uri service,
  }) : this._(
         status: IdsLoginStatus.authenticated,
         cookieJar: cookieJar,
         service: service,
       );

  const IdsLoginResult.captchaRequired()
    : this._(status: IdsLoginStatus.captchaRequired);

  const IdsLoginResult.invalidCredentials(String message)
    : this._(status: IdsLoginStatus.invalidCredentials, message: message);

  const IdsLoginResult.failed(String message)
    : this._(status: IdsLoginStatus.failed, message: message);

  final IdsLoginStatus status;
  final String? message;
  final HttpCookieJar? _cookieJar;
  final Uri? _service;

  /// Copies the authenticated HTTP session into a caller-owned jar. The jar
  /// stays in memory only; callers must not serialize it as credentials.
  bool copyCookiesTo(HttpCookieJar target) {
    final cookieJar = _cookieJar;
    if (cookieJar == null) return false;
    cookieJar.copyTo(target);
    return true;
  }

  Future<void> syncCookiesToWebView() async {
    final cookieJar = _cookieJar;
    final service = _service;
    if (cookieJar == null || service == null) return;

    await cookieJar.syncToWebView(<Uri>[
      Uri.https(_idsHost, '/authserver/'),
      service,
    ]);
  }
}

/// Unified identity authentication implemented without WebView.
///
/// The login form sends an AES-CBC ciphertext in its `password` field and
/// redirects to the requested service after CAS authentication.
class IdsHttpAuthClient {
  IdsHttpAuthClient({
    HttpClient? httpClient,
    IdsPasswordEncoder? passwordEncoder,
    IdsSliderSigner? sliderSigner,
  }) : _httpClient = httpClient ?? HttpClient(),
       _passwordEncoder = passwordEncoder ?? IdsPasswordEncoder(),
       _sliderSigner = sliderSigner ?? IdsSliderSigner();

  final HttpClient _httpClient;
  final IdsPasswordEncoder _passwordEncoder;
  final IdsSliderSigner _sliderSigner;
  final HttpCookieJar _cookieJar = HttpCookieJar();

  Future<IdsLoginResult> login({
    required String username,
    required String password,
    required Uri service,
    Future<IdsSliderAnswer?> Function(IdsSliderChallenge challenge)?
    onSliderCaptcha,
  }) async {
    try {
      final loginUri = Uri.https(
        _idsHost,
        '/authserver/login',
        <String, String>{'service': service.toString()},
      );
      final loginPage = await _requestFollowing(loginUri);
      final form = _IdsLoginForm.parse(loginPage.body, loginPage.uri);
      if (form == null) {
        return const IdsLoginResult.failed('无法识别统一认证登录页');
      }

      final captchaNeeded = await _needsSliderCaptcha(loginPage.uri, username);
      if (captchaNeeded && !await _solveSliderCaptcha(onSliderCaptcha)) {
        return const IdsLoginResult.captchaRequired();
      }

      final fields = Map<String, String>.from(form.hiddenFields)
        ..['username'] = username
        ..['password'] = _passwordEncoder.encode(
          password: password,
          salt: form.passwordSalt,
        );

      final submitted = await _requestFollowing(
        form.submitUri,
        method: 'POST',
        form: fields,
      );
      if (submitted.uri.host.toLowerCase() != _idsHost) {
        await PortalUserSync.fromCookieHeader(
          _cookieJar.cookieHeaderFor(
            Uri.https('ehall.uwh.edu.cn', '/getLoginUser'),
          ),
        );
        return IdsLoginResult.authenticated(
          cookieJar: _cookieJar,
          service: service,
        );
      }

      final error = _readLoginError(submitted.body);
      if (error != null) return IdsLoginResult.invalidCredentials(error);
      return const IdsLoginResult.failed('统一认证没有返回服务页面');
    } on SocketException {
      return const IdsLoginResult.failed('网络连接失败');
    } on HttpException {
      return const IdsLoginResult.failed('统一认证请求失败');
    } on FormatException {
      return const IdsLoginResult.failed('统一认证页面格式异常');
    } catch (_) {
      return const IdsLoginResult.failed('统一认证登录失败');
    } finally {
      _httpClient.close(force: true);
    }
  }

  Future<bool> _needsSliderCaptcha(Uri loginUri, String username) async {
    final checkUri = loginUri.replace(
      path: '/authserver/checkNeedCaptcha.htl',
      queryParameters: <String, String>{'username': username},
    );
    try {
      final response = await _requestFollowing(checkUri);
      final data = jsonDecode(response.body);
      return data is Map && data['isNeed'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Runs the slider flow until the server accepts one drag or the user
  /// gives up.
  Future<bool> _solveSliderCaptcha(
    Future<IdsSliderAnswer?> Function(IdsSliderChallenge challenge)?
    onSliderCaptcha, {
    int maxAttempts = 3,
  }) async {
    if (onSliderCaptcha == null) return false;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final issuedAt = DateTime.now();
      final challenge = await _openSliderCaptcha();
      if (challenge == null) return false;
      final answer = await onSliderCaptcha(challenge);
      if (answer == null) return false;
      // The server rejects answers sent less than ~1.1s after the challenge
      // was issued, so a very quick drag still has to wait a little.
      await _paceVerification(issuedAt);
      if (await _verifySliderCaptcha(challenge, answer)) return true;
    }
    return false;
  }

  Future<void> _paceVerification(DateTime issuedAt) async {
    const minimum = Duration(milliseconds: 1300);
    final elapsed = DateTime.now().difference(issuedAt);
    if (elapsed < minimum) {
      await Future<void>.delayed(minimum - elapsed);
    }
  }

  Future<IdsSliderChallenge?> _openSliderCaptcha() async {
    final uri = Uri.https(
      _idsHost,
      '/authserver/common/openSliderCaptcha.htl',
      <String, String>{'_': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    try {
      final response = await _requestFollowing(uri, xhr: true);
      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      return IdsSliderChallenge.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _verifySliderCaptcha(
    IdsSliderChallenge challenge,
    IdsSliderAnswer answer,
  ) async {
    final sign = _sliderSigner.sign(challenge: challenge, answer: answer);
    final uri = Uri.https(
      _idsHost,
      '/authserver/common/verifySliderCaptcha.htl',
    );
    try {
      final response = await _requestFollowing(
        uri,
        method: 'POST',
        form: <String, String>{'sign': sign},
        xhr: true,
      );
      final data = jsonDecode(response.body);
      return data is Map && data['errorCode'] == 1;
    } catch (_) {
      return false;
    }
  }

  Future<_HttpDocument> _requestFollowing(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
    bool xhr = false,
  }) async {
    var nextUri = uri;
    var nextMethod = method;
    Map<String, String>? nextForm = form;

    for (var hop = 0; hop < 8; hop++) {
      final response = await _request(
        nextUri,
        method: nextMethod,
        form: nextForm,
        xhr: xhr,
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null ||
          response.statusCode < 300 ||
          response.statusCode >= 400) {
        return response;
      }

      nextUri = nextUri.resolve(location);
      nextMethod = 'GET';
      nextForm = null;
    }
    throw const HttpException('Too many redirects');
  }

  Future<_HttpDocument> _request(
    Uri uri, {
    required String method,
    Map<String, String>? form,
    bool xhr = false,
  }) async {
    final request = await _httpClient.openUrl(method, uri);
    request.followRedirects = false;
    if (xhr) {
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set(
        HttpHeaders.refererHeader,
        'https://$_idsHost/authserver/login',
      );
    } else {
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/json',
      );
    }

    final cookieHeader = _cookieJar.cookieHeaderFor(uri);
    if (cookieHeader.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }

    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(_encodeForm(form));
    }

    final response = await request.close();
    _cookieJar.save(uri, response.cookies);
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });
    return _HttpDocument(
      uri: uri,
      statusCode: response.statusCode,
      headers: response.headers,
      body: utf8.decode(bytes, allowMalformed: true),
    );
  }

  String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }

  String? _readLoginError(String html) {
    final document = html_parser.parse(html);
    final text = document.querySelector('#showErrorTip')?.text.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class IdsPasswordEncoder {
  IdsPasswordEncoder({String Function(int)? randomText})
    : _randomText = randomText ?? idsSecureRandomText;

  final String Function(int) _randomText;

  String encode({required String password, required String salt}) {
    return idsAesEncrypt(
      plaintext: '${_randomText(64)}$password',
      key: salt,
      iv: _randomText(16),
    );
  }
}

/// Minimal domain/path-aware jar for the CAS redirect flow.
class HttpCookieJar {
  final List<_StoredCookie> _cookies = <_StoredCookie>[];

  void addCookieHeader(Uri uri, String header) {
    final cookies = <Cookie>[];
    for (final item in header.split(';')) {
      final pair = item.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isEmpty) continue;
      cookies.add(Cookie(name, value)..path = '/');
    }
    save(uri, cookies);
  }

  void save(Uri requestUri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      final stored = _StoredCookie.fromCookie(requestUri, cookie);
      _cookies.removeWhere((existing) => existing.sameScope(stored));
      if (!stored.expired) _cookies.add(stored);
    }
  }

  String cookieHeaderFor(Uri uri) {
    _discardExpired();
    return _cookies
        .where((cookie) => cookie.matches(uri))
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
  }

  /// Copies all currently valid cookies into [target], replacing cookies with
  /// the same name/domain/path scope there.
  void copyTo(HttpCookieJar target) {
    _discardExpired();
    for (final cookie in _cookies) {
      target._cookies.removeWhere((existing) => existing.sameScope(cookie));
      target._cookies.add(cookie);
    }
  }

  /// Copies only cookies that can be sent to [uri]. Returns whether any
  /// session cookie was available for that URI.
  bool copyMatchingTo(Uri uri, HttpCookieJar target) {
    _discardExpired();
    final matching = _cookies.where((cookie) => cookie.matches(uri));
    var copied = false;
    for (final cookie in matching) {
      target._cookies.removeWhere((existing) => existing.sameScope(cookie));
      target._cookies.add(cookie);
      copied = true;
    }
    return copied;
  }

  /// Encrypted persistence is owned by the session module. This encoding
  /// contains only cookie attributes needed to rebuild request headers.
  String encodeForSecureStorage() {
    _discardExpired();
    return jsonEncode(<String, Object?>{
      'version': 1,
      'cookies': _cookies.map((cookie) => cookie.toJson()).toList(),
    });
  }

  static HttpCookieJar? decodeFromSecureStorage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) return null;
      final values = decoded['cookies'];
      if (values is! List) return null;
      final jar = HttpCookieJar();
      for (final value in values) {
        if (value is! Map) continue;
        final cookie = _StoredCookie.fromJson(value);
        if (cookie == null || cookie.expired) continue;
        jar._cookies.removeWhere((existing) => existing.sameScope(cookie));
        jar._cookies.add(cookie);
      }
      return jar;
    } catch (_) {
      return null;
    }
  }

  Future<void> syncToWebView(Iterable<Uri> urls) async {
    _discardExpired();
    for (final uri in urls) {
      final cookies = _cookies
          .where((cookie) => cookie.matches(uri))
          .map((cookie) => cookie.asSetCookieHeader())
          .toList(growable: false);
      await BrowserDataCleaner.setCookiesForUrl(
        url: uri.toString(),
        cookies: cookies,
      );
    }
    await BrowserDataCleaner.persistCookies();
  }

  void _discardExpired() {
    _cookies.removeWhere((cookie) => cookie.expired);
  }
}

class _StoredCookie {
  const _StoredCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    required this.httpOnly,
    required this.expires,
  });

  factory _StoredCookie.fromCookie(Uri requestUri, Cookie cookie) {
    return _StoredCookie(
      name: cookie.name,
      value: cookie.value,
      domain: (cookie.domain ?? requestUri.host).toLowerCase().replaceFirst(
        RegExp(r'^\.'),
        '',
      ),
      path: cookie.path?.isNotEmpty == true ? cookie.path! : '/',
      secure: cookie.secure,
      httpOnly: cookie.httpOnly,
      expires: cookie.expires,
    );
  }

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;
  final DateTime? expires;

  static _StoredCookie? fromJson(Map value) {
    final name = value['name']?.toString() ?? '';
    final valueText = value['value']?.toString() ?? '';
    final domain = value['domain']?.toString().toLowerCase() ?? '';
    final path = value['path']?.toString() ?? '';
    if (name.isEmpty || domain.isEmpty || path.isEmpty) return null;
    final expiresText = value['expires']?.toString();
    final expires = expiresText == null || expiresText.isEmpty
        ? null
        : DateTime.tryParse(expiresText);
    return _StoredCookie(
      name: name,
      value: valueText,
      domain: domain,
      path: path,
      secure: value['secure'] == true,
      httpOnly: value['httpOnly'] == true,
      expires: expires,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'httpOnly': httpOnly,
    'expires': expires?.toIso8601String(),
  };

  bool get expired => expires != null && !expires!.isAfter(DateTime.now());

  bool sameScope(_StoredCookie other) {
    return name == other.name && domain == other.domain && path == other.path;
  }

  bool matches(Uri uri) {
    if (secure && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final domainMatches = host == domain || host.endsWith('.$domain');
    if (!domainMatches) return false;
    return uri.path.startsWith(path);
  }

  String asSetCookieHeader() {
    final parts = <String>['$name=$value', 'Path=$path', 'Domain=$domain'];
    if (secure) parts.add('Secure');
    if (httpOnly) parts.add('HttpOnly');
    return parts.join('; ');
  }
}

class _IdsLoginForm {
  const _IdsLoginForm({
    required this.submitUri,
    required this.passwordSalt,
    required this.hiddenFields,
  });

  static _IdsLoginForm? parse(String html, Uri documentUri) {
    final document = html_parser.parse(html);
    final form = document.querySelector('form#pwdFromId');
    final salt = document.querySelector('#pwdEncryptSalt')?.attributes['value'];
    if (form == null || salt == null || salt.isEmpty) return null;

    final hiddenFields = <String, String>{};
    for (final input in form.querySelectorAll('input[type="hidden"]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      hiddenFields[name] = input.attributes['value'] ?? '';
    }
    if (!hiddenFields.containsKey('execution')) return null;

    final action = form.attributes['action'] ?? '/authserver/login';
    final actionUri = documentUri.resolve(action);
    return _IdsLoginForm(
      submitUri: actionUri.replace(query: documentUri.query),
      passwordSalt: salt,
      hiddenFields: hiddenFields,
    );
  }

  final Uri submitUri;
  final String passwordSalt;
  final Map<String, String> hiddenFields;
}

class _HttpDocument {
  const _HttpDocument({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final HttpHeaders headers;
  final String body;
}
