import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';
import 'package:uwhlife/features/door/door_api.dart';

void main() {
  group('DoorAspNetForm', () {
    test('parses the ASP.NET state and image-button coordinates', () {
      const html = '''
        <form id="aspnetForm" method="post" action="./Default.aspx">
          <input type="hidden" name="__VIEWSTATE" value="view-state" />
          <input type="hidden" name="__VIEWSTATEGENERATOR" value="generator" />
          <input type="image" name="ctl00\$btnOpen" id="ctl00_btnOpen" />
        </form>
      ''';

      final form = DoorAspNetForm.parse(
        html,
        Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx'),
      );

      expect(form, isNotNull);
      expect(
        form!.submitUri.toString(),
        'http://opendoor.uwh.edu.cn:46010/Default.aspx',
      );
      expect(form.openFields['__VIEWSTATE'], 'view-state');
      expect(form.openFields['__VIEWSTATEGENERATOR'], 'generator');
      expect(form.openFields['ctl00\$btnOpen.x'], '1');
      expect(form.openFields['ctl00\$btnOpen.y'], '1');
    });

    test('rejects a page without view state or the open image button', () {
      final uri = Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx');

      expect(
        DoorAspNetForm.parse('<form id="aspnetForm"></form>', uri),
        isNull,
      );
    });

    test('reads the server result label', () {
      expect(
        DoorAspNetForm.readResultMessage(
          '<span id="ctl00_lblInfo">开门请求已处理</span>',
        ),
        '开门请求已处理',
      );
    });
  });

  test('imports browser cookies without leaking them to another host', () {
    final jar = HttpCookieJar();
    final ids = Uri.https('ids.uwh.edu.cn', '/authserver/login');
    final door = Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx');

    jar.addCookieHeader(ids, 'CASTGC=dummy-ticket; route=dummy-route');

    expect(jar.cookieHeaderFor(ids), contains('CASTGC=dummy-ticket'));
    expect(jar.cookieHeaderFor(door), isEmpty);
  });

  test(
    'cold launch follows CAS with WebKit cookies and submits once',
    () async {
      final reads = <Uri>[];
      final writes = <(Uri, List<Cookie>, int)>[];
      final idsUri = Uri.parse(
        'https://ids.uwh.edu.cn/authserver/login?service=door',
      );
      final doorUri = DoorApiClient.doorUri;
      final http = _FakeHttpClient([
        _FakeResponse(statusCode: 302, location: idsUri.toString()),
        _FakeResponse(
          statusCode: 302,
          location: '${doorUri.toString()}?ticket=one',
          cookies: [Cookie('ids_refreshed', 'response')..path = '/'],
        ),
        _FakeResponse(
          body: '''
          <form id="aspnetForm" action="./Default.aspx">
            <input type="hidden" name="__VIEWSTATE" value="state" />
            <input type="image" name="openDoor" />
          </form>
        ''',
        ),
        _FakeResponse(body: '<span id="ctl00_lblInfo">已开门</span>'),
      ]);
      final client = DoorApiClient(
        httpClient: http,
      isCurrent: (_) => true,
        readCookies: (uri) async {
          reads.add(uri);
          return uri.host == idsUri.host
              ? 'CASTGC=webkit-ticket'
              : 'door_session=webkit-door';
        },
        writeCookies: (uri, cookies, generation) async {
          writes.add((uri, cookies, generation));
        },
      );

      final result = await client.openDoor(generation: 12);

      expect(result.status, DoorOpenStatus.opened);
      expect(http.requests.map((request) => request.method), [
        'GET',
        'GET',
        'GET',
        'POST',
      ]);
      expect(http.requests.first.uri, doorUri);
      expect(reads, [
        doorUri,
        idsUri,
        doorUri.replace(query: 'ticket=one'),
        doorUri,
      ]);
      expect(
        http.requests[1].headers.value(HttpHeaders.cookieHeader),
        'CASTGC=webkit-ticket',
      );
      expect(
        http.requests[1].headers.value(HttpHeaders.cookieHeader),
        isNot(contains('webkit-door')),
      );
      expect(http.requests.last.body, contains('__VIEWSTATE=state'));
      expect(http.requests.last.body, contains('openDoor.x=1'));
      expect(writes, hasLength(1));
      expect(writes.single.$1, idsUri);
      expect(writes.single.$2.map((cookie) => cookie.name), ['ids_refreshed']);
      expect(writes.single.$3, 12);
      expect(http.closed, isTrue);
    },
  );
  test('does not submit an open action after the session changes', () async {
    final http = _FakeHttpClient([
      _FakeResponse(
        body: '''
          <form id="aspnetForm" action="./Default.aspx">
            <input type="hidden" name="__VIEWSTATE" value="state" />
            <input type="image" name="openDoor" />
          </form>
        ''',
      ),
    ]);
    var reads = 0;
    var current = true;
    final client = DoorApiClient(
      httpClient: http,
      isCurrent: (_) => current,
      readCookies: (_) async {
        reads++;
        if (reads == 2) current = false;
        return 'door_session=webkit-door';
      },
      writeCookies: (_, _, _) async {},
    );

    final result = await client.openDoor(generation: 12);

    expect(result.status, DoorOpenStatus.failed);
    expect(http.requests.map((request) => request.method), ['GET']);
    expect(http.closed, isTrue);
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.responses);

  final List<_FakeResponse> responses;
  final requests = <_FakeRequest>[];
  bool closed = false;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _FakeRequest(method, url, responses[requests.length]);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.method, this.uri, this.response);

  @override
  final String method;
  @override
  final Uri uri;
  final _FakeResponse response;
  @override
  final _FakeHeaders headers = _FakeHeaders();
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

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse({
    this.statusCode = 200,
    String? location,
    this.body = '',
    this.cookies = const [],
  }) : headers = _FakeHeaders() {
    if (location != null) headers.set(HttpHeaders.locationHeader, location);
  }

  @override
  final int statusCode;
  @override
  final _FakeHeaders headers;
  @override
  final List<Cookie> cookies;
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

class _FakeHeaders implements HttpHeaders {
  final Map<String, String> _values = {};

  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
