import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';
import 'package:uwhlife/features/auth/portal_session_cookies.dart';

void main() {
  late _MemoryPersistence persistence;

  setUp(() {
    persistence = _MemoryPersistence();
    PortalSessionCookies.configureForTesting(persistence);
  });

  tearDown(PortalSessionCookies.resetForTesting);

  test(
    'seeds a service client from the cookies produced by IDS login',
    () async {
      final idsUri = Uri.https('ids.uwh.edu.cn', '/authserver/login');
      final loginCookies = HttpCookieJar()
        ..save(idsUri, <Cookie>[Cookie('CASTGC', 'fresh')..path = '/']);
      final loginResult = IdsLoginResult.authenticated(
        cookieJar: loginCookies,
        service: Uri.parse('https://ehall.uwh.edu.cn/login'),
      );
      final serviceCookies = HttpCookieJar();

      await PortalSessionCookies.rememberLogin(loginResult);

      expect(
        await PortalSessionCookies.seedFor(idsUri, serviceCookies),
        isTrue,
      );
      expect(serviceCookies.cookieHeaderFor(idsUri), contains('CASTGC=fresh'));
    },
  );

  test(
    'does not claim a service cookie that the login flow never received',
    () async {
      final idsUri = Uri.https('ids.uwh.edu.cn', '/authserver/login');
      final doorUri = Uri.parse(
        'http://opendoor.uwh.edu.cn:46010/Default.aspx',
      );
      final loginCookies = HttpCookieJar()
        ..save(idsUri, <Cookie>[Cookie('CASTGC', 'fresh')..path = '/']);
      final loginResult = IdsLoginResult.authenticated(
        cookieJar: loginCookies,
        service: Uri.parse('https://ehall.uwh.edu.cn/login'),
      );

      await PortalSessionCookies.rememberLogin(loginResult);

      expect(
        await PortalSessionCookies.seedFor(doorUri, HttpCookieJar()),
        isFalse,
      );
    },
  );

  test(
    'restores native-login cookies after the in-memory cache is lost',
    () async {
      final idsUri = Uri.https('ids.uwh.edu.cn', '/authserver/login');
      final loginCookies = HttpCookieJar()
        ..save(idsUri, <Cookie>[Cookie('CASTGC', 'fresh')..path = '/']);
      final loginResult = IdsLoginResult.authenticated(
        cookieJar: loginCookies,
        service: Uri.parse('https://ehall.uwh.edu.cn/login'),
      );
      await PortalSessionCookies.rememberLogin(loginResult);

      // Simulate a cold launch: new in-memory state, same secure store.
      PortalSessionCookies.configureForTesting(persistence);
      final serviceCookies = HttpCookieJar();

      expect(
        await PortalSessionCookies.seedFor(idsUri, serviceCookies),
        isTrue,
      );
      expect(serviceCookies.cookieHeaderFor(idsUri), contains('CASTGC=fresh'));
    },
  );
}

class _MemoryPersistence implements PortalSessionCookiePersistence {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async => value = next;
}
