import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/portal_user_sync.dart';

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
  }) : _httpClient = httpClient ?? HttpClient(),
       _passwordEncoder = passwordEncoder ?? IdsPasswordEncoder();

  final HttpClient _httpClient;
  final IdsPasswordEncoder _passwordEncoder;
  final HttpCookieJar _cookieJar = HttpCookieJar();

  Future<IdsLoginResult> login({
    required String username,
    required String password,
    required Uri service,
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

      if (await _needsSliderCaptcha(loginPage.uri, username)) {
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

  Future<_HttpDocument> _requestFollowing(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    var nextUri = uri;
    var nextMethod = method;
    Map<String, String>? nextForm = form;

    for (var hop = 0; hop < 8; hop++) {
      final response = await _request(
        nextUri,
        method: nextMethod,
        form: nextForm,
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
  }) async {
    final request = await _httpClient.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'text/html,application/json');

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
    : _randomText = randomText ?? _secureRandomText;

  static const _alphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  final String Function(int) _randomText;

  String encode({required String password, required String salt}) {
    final key = Uint8List.fromList(utf8.encode(salt));
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw const FormatException('Invalid AES password salt');
    }

    final plaintext = Uint8List.fromList(
      utf8.encode('${_randomText(64)}$password'),
    );
    final iv = Uint8List.fromList(utf8.encode(_randomText(16)));
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
    return base64.encode(cipher.process(plaintext));
  }

  static String _secureRandomText(int length) {
    final random = Random.secure();
    return String.fromCharCodes(
      List<int>.generate(
        length,
        (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
        growable: false,
      ),
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
