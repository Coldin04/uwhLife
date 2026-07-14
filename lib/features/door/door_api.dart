import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

import '../../core/platform/browser_data_cleaner.dart';
import '../auth/ids_http_auth.dart';

enum DoorOpenStatus { opened, needsLogin, failed }

class DoorOpenResult {
  const DoorOpenResult._(this.status, this.message);

  const DoorOpenResult.opened(String message)
    : this._(DoorOpenStatus.opened, message);

  const DoorOpenResult.needsLogin()
    : this._(DoorOpenStatus.needsLogin, '需要先登录统一门户');

  const DoorOpenResult.failed(String message)
    : this._(DoorOpenStatus.failed, message);

  final DoorOpenStatus status;
  final String message;
}

class DoorApi {
  const DoorApi._();

  static Future<DoorOpenResult> openDoor() => DoorApiClient().openDoor();
}

class DoorApiClient {
  DoorApiClient({HttpClient? httpClient})
    : _httpClient =
          httpClient ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  static final Uri doorUri = Uri.parse(
    'http://opendoor.uwh.edu.cn:46010/Default.aspx',
  );
  static final Uri idsUri = Uri.https('ids.uwh.edu.cn', '/authserver/');

  final HttpClient _httpClient;
  final HttpCookieJar _cookies = HttpCookieJar();

  Future<DoorOpenResult> openDoor() async {
    try {
      await _loadBrowserCookies(idsUri);
      await _loadBrowserCookies(doorUri);

      final landing = await _requestFollowing(doorUri);
      if (_isLoginPage(landing.uri)) {
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
      );
      if (_isLoginPage(opened.uri)) {
        return const DoorOpenResult.needsLogin();
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
      await _cookies.syncToWebView(<Uri>[idsUri, doorUri]);
      _httpClient.close(force: true);
    }
  }

  Future<void> _loadBrowserCookies(Uri uri) async {
    final header = await BrowserDataCleaner.getCookies(url: uri.toString());
    _cookies.addCookieHeader(uri, header);
  }

  Future<_DoorDocument> _requestFollowing(
    Uri uri, {
    String method = 'GET',
    Map<String, String>? form,
    Uri? referer,
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
  }) async {
    final request = await _httpClient.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
    );
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer.toString());
    }
    final cookieHeader = _cookies.cookieHeaderFor(uri);
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

    final response = await request.close().timeout(const Duration(seconds: 12));
    _cookies.save(uri, response.cookies);
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

  bool _isLoginPage(Uri uri) => uri.host.toLowerCase() == idsUri.host;

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
