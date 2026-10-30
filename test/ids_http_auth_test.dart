import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:uwhlife/core/platform/browser_data_cleaner.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';

void main() {
  test('encodes the password with the IDS AES-CBC shape', () {
    final encoder = IdsPasswordEncoder(
      randomText: (length) => length == 64 ? 'A' * 64 : 'B' * length,
    );
    final encoded = encoder.encode(
      password: 'secret',
      salt: '1234567890abcdef',
    );

    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
      ..init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(
            KeyParameter(Uint8List.fromList(utf8.encode('1234567890abcdef'))),
            Uint8List.fromList(utf8.encode('B' * 16)),
          ),
          null,
        ),
      );
    final plaintext = utf8.decode(cipher.process(base64.decode(encoded)));

    expect(plaintext, '${'A' * 64}secret');
  });

  test('keeps cookies constrained to their domain and path', () {
    final jar = HttpCookieJar();
    final rootCookie = Cookie('ids', 'one')..path = '/';
    final pathCookie = Cookie('portal', 'two')..path = '/message/';
    jar.save(Uri.parse('https://ids.uwh.edu.cn/authserver/login'), <Cookie>[
      rootCookie,
      pathCookie,
    ]);

    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/message/list')),
      contains('ids=one'),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/message/list')),
      contains('portal=two'),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/other')),
      isNot(contains('portal=two')),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ehall.uwh.edu.cn/message/list')),
      isEmpty,
    );
  });

  test('host-only cookies and path boundaries do not leak', () {
    final jar = HttpCookieJar()
      ..save(Uri.parse('https://ids.uwh.edu.cn/authserver/login'), [
        Cookie('host', 'one')..path = '/auth',
        Cookie('domain', 'two')
          ..domain = 'uwh.edu.cn'
          ..path = '/',
      ]);
    expect(
      jar.cookieHeaderFor(Uri.parse('https://ids.uwh.edu.cn/authz')),
      isNot(contains('host=')),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://sub.ids.uwh.edu.cn/auth')),
      isNot(contains('host=')),
    );
    expect(
      jar.cookieHeaderFor(Uri.parse('https://sub.ids.uwh.edu.cn/auth')),
      contains('domain=two'),
    );
  });

  test('browser bridge filters invalid campus parent-domain cookies', () {
    final cookies = BrowserDataCleaner.filterCookiesForUrl(
      Uri.parse('https://ids.uwh.edu.cn/authserver/login'),
      ['platformMultilingual=zh; Domain=edu.cn; Path=/', 'CASTGC=ticket; Path=/authserver'],
    );
    expect(cookies, ['CASTGC=ticket; Path=/authserver']);
  });

  test('ignores cookies scoped above the campus domain before WebView sync', () async {
    final ids = Uri.parse('https://ids.uwh.edu.cn/authserver/login');
    final jar = HttpCookieJar()
      ..save(ids, [
        Cookie('platformMultilingual', 'zh_CN')
          ..domain = 'edu.cn'
          ..path = '/',
        Cookie('CASTGC', 'ticket')..path = '/authserver',
      ]);
    final writes = <String>[];
    await jar.syncToWebView(
      [ids],
      setCookies: (_, cookies) async => writes.addAll(cookies),
      persistCookies: () async {},
    );
    expect(writes.any((cookie) => cookie.startsWith('platformMultilingual=')), isFalse);
    expect(writes.any((cookie) => cookie.startsWith('CASTGC=')), isTrue);
  });

  test(
    'syncs every cookie for the host with attributes and waits for the bridge',
    () async {
      final jar = HttpCookieJar()
        ..save(Uri.parse('https://ids.uwh.edu.cn/authserver/login'), [
          Cookie('ids', 'one')
            ..path = '/authserver/private'
            ..secure = true
            ..httpOnly = true
            ..sameSite = SameSite.lax
            ..expires = DateTime.utc(2035, 1, 2),
        ]);
      final done = Completer<void>();
      List<String>? received;
      var finished = false;
      final sync = jar.syncToWebView(
        [Uri.parse('https://ids.uwh.edu.cn/authserver/')],
        setCookies: (uri, cookies) {
          received = cookies;
          return done.future;
        },
        persistCookies: () async {},
      )..then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(received, hasLength(1));
      expect(received!.single, contains('Path=/authserver/private'));
      expect(
        received!.single,
        contains('Expires=Tue, 02 Jan 2035 00:00:00 GMT'),
      );
      expect(received!.single, contains('Secure'));
      expect(received!.single, contains('HttpOnly'));
      expect(received!.single, contains('SameSite=Lax'));
      expect(received!.single, isNot(contains('Domain=')));
      done.complete();
      await sync;
      expect(finished, isTrue);
    },
  );

  test(
    'a server deletion reaches the browser and failures propagate',
    () async {
      final uri = Uri.parse('https://ids.uwh.edu.cn/authserver/login');
      final jar = HttpCookieJar()
        ..save(uri, [Cookie('ids', 'old')..path = '/'])
        ..save(uri, [
          Cookie('ids', '')
            ..path = '/'
            ..maxAge = 0,
        ]);
      expect(jar.cookieHeaderFor(uri), isEmpty);
      await expectLater(
        jar.syncToWebView(
          [uri],
          setCookies: (_, cookies) async {
            expect(cookies.single, contains('Expires='));
            throw StateError('bridge unavailable');
          },
          persistCookies: () async {},
        ),
        throwsStateError,
      );
    },
  );
}
