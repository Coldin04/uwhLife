import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

import '../../core/platform/browser_data_cleaner.dart';
import '../auth/ids_http_auth.dart';
import '../auth/ids_login_form.dart';
import '../auth/portal_auto_login.dart';

enum DoorOpenStatus { opened, needsLogin, failed }

class DoorOpenResult {
  const DoorOpenResult._(this.status, this.message, {this.retrySafe = false});

  const DoorOpenResult.opened(String message)
    : this._(DoorOpenStatus.opened, message);

  const DoorOpenResult.needsLogin({bool retrySafe = true})
    : this._(DoorOpenStatus.needsLogin, '需要先登录统一门户', retrySafe: retrySafe);

  const DoorOpenResult.failed(String message)
    : this._(DoorOpenStatus.failed, message);

  final DoorOpenStatus status;
  final String message;
  final bool retrySafe;
}

class DoorApi {
  const DoorApi._();

  static Future<DoorOpenResult> openDoor() async {
    final session = PortalAutoLogin.instance;
    return DoorSessionCoordinator(
      waitForRecovery: session.waitForRecovery,
      generation: () => session.generation,
      open: (generation) => DoorApiClient().openDoor(generation: generation),
      loginRequired: session.reportLoginRequired,
      onRetryLoginRequired: (generation) async {
        await session.reportLoginRequired(generation, recover: false);
      },
    ).run();
  }
}

/// Runs a door request immediately unless another operation is already
/// restoring the shared IDS session. A submitted open action is never replayed.
class DoorSessionCoordinator {
  DoorSessionCoordinator({
    required this.waitForRecovery,
    required this.generation,
    required this.open,
    required this.loginRequired,
    this.onRetryLoginRequired,
  });

  final Future<void> Function() waitForRecovery;
  final int Function() generation;
  final Future<DoorOpenResult> Function(int) open;
  final Future<PortalAutoLoginOutcome> Function(int) loginRequired;
  final Future<void> Function(int)? onRetryLoginRequired;

  Future<DoorOpenResult> run() async {
    await waitForRecovery();
    final observedGeneration = generation();
    final first = await open(observedGeneration);
    if (first.status != DoorOpenStatus.needsLogin) return first;

    final outcome = await loginRequired(observedGeneration);
    if (first.retrySafe && outcome == PortalAutoLoginOutcome.restored) {
      final retryGeneration = generation();
      final retried = await open(retryGeneration);
      if (retried.status == DoorOpenStatus.needsLogin) {
        await onRetryLoginRequired?.call(retryGeneration);
      }
      return retried;
    }
    return first;
  }
}

class DoorApiClient {
  DoorApiClient({
    HttpClient? httpClient,
    Future<String> Function(Uri)? readCookies,
    Future<void> Function(Uri, List<Cookie>, int)? writeCookies,
    bool Function(int)? isCurrent,
  }) : _httpClient =
           httpClient ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8)),
       _readCookies = readCookies ?? _readBrowserCookies,
       _writeCookies = writeCookies ?? _writeBrowserCookies,
       _isCurrent =
           isCurrent ??
           ((generation) => PortalAutoLogin.instance.generation == generation);

  static final Uri doorUri = Uri.parse(
    'http://opendoor.uwh.edu.cn:46010/Default.aspx',
  );
  static final Uri idsUri = Uri.https('ids.uwh.edu.cn', '/authserver/');

  final HttpClient _httpClient;
  final Future<String> Function(Uri) _readCookies;
  final Future<void> Function(Uri, List<Cookie>, int) _writeCookies;
  final bool Function(int) _isCurrent;
  final HttpCookieJar _cookies = HttpCookieJar();

  static Future<String> _readBrowserCookies(Uri uri) =>
      BrowserDataCleaner.getCookies(url: uri.toString());

  static Future<void> _writeBrowserCookies(
    Uri uri,
    List<Cookie> cookies,
    int generation,
  ) async {
    await PortalAutoLogin.instance.applyCookiesIfCurrent(
      observedGeneration: generation,
      write: () => BrowserDataCleaner.setCookiesForUrl(
        url: uri.toString(),
        cookies: cookies.map((cookie) => cookie.toString()).toList(),
      ),
    );
  }

  Future<DoorOpenResult> openDoor({required int generation}) async {
    try {
      final landing = await _requestFollowing(doorUri, generation: generation);
      if (_isLoginPage(landing)) {
        return const DoorOpenResult.needsLogin();
      }
      if (!_isDoorPage(landing.uri)) {
        return const DoorOpenResult.failed('门锁服务返回了未知页面');
      }

      final form = DoorAspNetForm.parse(landing.body, landing.uri);
      if (form == null) {
        return const DoorOpenResult.failed('无法识别门锁页面');
      }

      final opened = await _requestFollowing(
        form.submitUri,
        method: 'POST',
        form: form.openFields,
        referer: landing.uri,
        generation: generation,
      );
      if (_isLoginPage(opened)) {
        return const DoorOpenResult.needsLogin(retrySafe: false);
      }
      if (!_isDoorPage(opened.uri)) {
        return const DoorOpenResult.failed('开门请求没有返回门锁页面');
      }

      final message = DoorAspNetForm.readResultMessage(opened.body);
      return DoorOpenResult.opened(message.isEmpty ? '已发送开门指令' : message);
    } on SocketException {
      return const DoorOpenResult.failed('无法连接门锁服务');
    } on TimeoutException {
      return const DoorOpenResult.failed('门锁请求超时，请重试');
    } on HttpException catch (error) {
      return DoorOpenResult.failed(error.message);
    } on FormatException {
      return const DoorOpenResult.failed('门锁页面格式异常');
    } catch (_) {
      return const DoorOpenResult.failed('开门失败，请稍后重试');
    } finally {
      _httpClient.close(force: true);
    }
  }

  Future<_DoorDocument> _requestFollowing(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
    Uri? referer,
    required int generation,
  }) async {
    var nextUri = uri;
    var nextMethod = method;
    var nextForm = form;
    var nextReferer = referer;

    for (var hop = 0; hop < 10; hop++) {
      final response = await _request(
        nextUri,
        method: nextMethod,
        form: nextForm,
        referer: nextReferer,
        generation: generation,
      );
      final location = response.location;
      if (location == null ||
          response.statusCode < 300 ||
          response.statusCode >= 400) {
        return response;
      }

      final previousUri = nextUri;
      nextUri = nextUri.resolve(location);
      nextReferer = previousUri;
      if (response.statusCode != HttpStatus.temporaryRedirect &&
          response.statusCode != HttpStatus.permanentRedirect) {
        nextMethod = 'GET';
        nextForm = null;
      }
    }
    throw const HttpException('门锁登录跳转次数过多');
  }

  Future<_DoorDocument> _request(
    Uri uri, {
    required String method,
    Map<String, String>? form,
    Uri? referer,
    required int generation,
  }) async {
    // Browser cookies are scoped to this exact request URL. Never store the
    // header in the temporary jar: headers do not contain scope attributes.
    final browserCookies = await _readCookies(uri);
    if (!_isCurrent(generation)) {
      throw const HttpException('登录状态已更改，请重试');
    }
    final request = await _httpClient.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
    );
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer.toString());
    }
    final responseCookies = _cookies.cookieHeaderFor(uri);
    final responseNames = responseCookies
        .split(';')
        .map((item) => item.trim().split('=').first)
        .where((name) => name.isNotEmpty)
        .toSet();
    final cookieHeader = <String>[
      if (responseCookies.isNotEmpty) responseCookies,
      ...browserCookies
          .split(';')
          .map((item) => item.trim())
          .where(
            (item) =>
                item.isNotEmpty &&
                !responseNames.contains(item.split('=').first),
          ),
    ].join('; ');
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

    if (!_isCurrent(generation)) {
      throw const HttpException('登录状态已更改，请重试');
    }
    final response = await request.close().timeout(const Duration(seconds: 12));
    _cookies.save(uri, response.cookies);
    if (response.cookies.isNotEmpty) {
      try {
        await _writeCookies(uri, response.cookies, generation);
      } catch (_) {
        // A completed door POST must not be reported as failed or replayed
        // just because the optional browser synchronization failed.
      }
    }
    final bytes = await response
        .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 400) {
      throw HttpException('门锁服务请求失败（${response.statusCode}）');
    }
    return _DoorDocument(
      uri: uri,
      statusCode: response.statusCode,
      location: response.headers.value(HttpHeaders.locationHeader),
      body: utf8.decode(bytes, allowMalformed: true),
    );
  }

  bool _isLoginPage(_DoorDocument document) =>
      isIdsLoginForm(url: document.uri.toString(), body: document.body);

  bool _isDoorPage(Uri uri) {
    return uri.host.toLowerCase() == doorUri.host &&
        uri.port == doorUri.port &&
        uri.path.toLowerCase().endsWith('/default.aspx');
  }

  String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }
}

class DoorAspNetForm {
  const DoorAspNetForm({
    required this.submitUri,
    required this.openButtonName,
    required this.hiddenFields,
  });

  final Uri submitUri;
  final String openButtonName;
  final Map<String, String> hiddenFields;

  Map<String, String> get openFields => <String, String>{
    ...hiddenFields,
    '$openButtonName.x': '1',
    '$openButtonName.y': '1',
  };

  static DoorAspNetForm? parse(String html, Uri documentUri) {
    final document = html_parser.parse(html);
    final form = document.querySelector('form#aspnetForm');
    if (form == null) return null;
    final openButton = form.querySelector('input[type="image"][name]');
    final buttonName = openButton?.attributes['name']?.trim() ?? '';
    if (buttonName.isEmpty) return null;

    final hiddenFields = <String, String>{};
    for (final input in form.querySelectorAll('input[type="hidden"][name]')) {
      final name = input.attributes['name']?.trim() ?? '';
      if (name.isEmpty) continue;
      hiddenFields[name] = input.attributes['value'] ?? '';
    }
    if (!hiddenFields.containsKey('__VIEWSTATE')) return null;

    final action = form.attributes['action']?.trim();
    return DoorAspNetForm(
      submitUri: action == null || action.isEmpty
          ? documentUri
          : documentUri.resolve(action),
      openButtonName: buttonName,
      hiddenFields: hiddenFields,
    );
  }

  static String readResultMessage(String html) {
    final document = html_parser.parse(html);
    return document.querySelector('#ctl00_lblInfo')?.text.trim() ?? '';
  }
}

class _DoorDocument {
  const _DoorDocument({
    required this.uri,
    required this.statusCode,
    required this.location,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String? location;
  final String body;
}
