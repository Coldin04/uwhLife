import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';

void main() {
  test('native IDS login submits the seven-day login checkbox', () async {
    final http = _Client();
    final result = await IdsHttpAuthClient(httpClient: http).login(
      username: 'student',
      password: 'password',
      service: Uri.parse('https://ehall.uwh.edu.cn/login'),
    );

    expect(result.status, IdsLoginStatus.authenticated);
    final submitted = http.requests.singleWhere((r) => r.method == 'POST');
    expect(Uri.splitQueryString(submitted.body)['rememberMe'], 'true');
  });

  test('native IDS login respects opting out of seven-day login', () async {
    final http = _Client();
    final result = await IdsHttpAuthClient(httpClient: http).login(
      username: 'student',
      password: 'password',
      service: Uri.parse('https://ehall.uwh.edu.cn/login'),
      rememberMe: false,
    );

    expect(result.status, IdsLoginStatus.authenticated);
    final submitted = http.requests.singleWhere((r) => r.method == 'POST');
    expect(Uri.splitQueryString(submitted.body), isNot(contains('rememberMe')));
  });
}

class _Client implements HttpClient {
  final requests = <_Request>[];

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final response = requests.isEmpty
        ? _Response(
            body: '''
          <form id="pwdFromId" action="/authserver/login">
            <input type="hidden" id="pwdEncryptSalt" value="1234567890abcdef">
            <input type="hidden" name="execution" value="flow">
            <input type="checkbox" name="rememberMe" value="true">
          </form>
        ''',
          )
        : url.path.contains('checkNeedCaptcha')
        ? _Response(body: '{"isNeed": false}')
        : method == 'POST'
        ? _Response(statusCode: 302, location: 'https://ehall.uwh.edu.cn/login')
        : _Response(body: 'ok');
    final request = _Request(method, url, response);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.response);
  @override
  final String method;
  @override
  final Uri uri;
  final _Response response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  String body = '';
  @override
  void write(Object? object) => body += object.toString();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response({this.statusCode = 200, String? location, this.body = ''})
    : headers = _Headers() {
    if (location != null) headers.set(HttpHeaders.locationHeader, location);
  }
  @override
  final int statusCode;
  @override
  final _Headers headers;
  @override
  final List<Cookie> cookies = [];
  final String body;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, String>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value.toString();
  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
