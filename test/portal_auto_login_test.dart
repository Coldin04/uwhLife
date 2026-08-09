import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/login_state_store.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';
import 'package:uwhlife/features/auth/portal_auto_login.dart';

class _Recorder {
  int attempts = 0;
  bool markedLoggedIn = false;
  bool syncedCookies = false;
  String? lastUsername;
}

PortalAutoLogin _autoLogin(
  _Recorder recorder, {
  required IdsLoginResult result,
  (String, String)? credentials = ('student-1', 'secret'),
  bool loggedIn = false,
  bool manualLogout = false,
}) {
  return PortalAutoLogin(
    readLoggedIn: () async => loggedIn,
    readManualLogout: () async => manualLogout,
    readCredentials: () async => credentials,
    login: ({
      required String username,
      required String password,
      required Uri service,
    }) async {
      recorder.attempts += 1;
      recorder.lastUsername = username;
      return result;
    },
    markLoggedIn: () async => recorder.markedLoggedIn = true,
    syncCookies: (_) async => recorder.syncedCookies = true,
  );
}

final _authenticated = IdsLoginResult.authenticated(
  cookieJar: HttpCookieJar(),
  service: PortalAutoLogin.serviceUri,
);

void main() {
  group('PortalAutoLogin', () {
    test('restores the session with the saved credentials', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(recorder, result: _authenticated);

      expect(
        await autoLogin.restoreSession(),
        PortalAutoLoginOutcome.restored,
      );
      expect(recorder.attempts, 1);
      expect(recorder.lastUsername, 'student-1');
      expect(recorder.syncedCookies, isTrue);
      expect(recorder.markedLoggedIn, isTrue);
    });

    test('does nothing while the portal session is healthy', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: _authenticated,
        loggedIn: true,
      );

      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(recorder.attempts, 0);
    });

    test('does nothing after the user logged out on purpose', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: _authenticated,
        manualLogout: true,
      );

      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(recorder.attempts, 0);
    });

    test('does nothing without saved credentials', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: _authenticated,
        credentials: null,
      );

      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(recorder.attempts, 0);
    });

    test('retries only once per offline episode', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: const IdsLoginResult.invalidCredentials('密码错误'),
      );

      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.failed);
      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(recorder.attempts, 1);
      expect(recorder.markedLoggedIn, isFalse);
    });

    test('does not retry when a captcha is required', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: const IdsLoginResult.captchaRequired(),
      );

      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.failed);
      expect(await autoLogin.restoreSession(), PortalAutoLoginOutcome.skipped);
      expect(recorder.attempts, 1);
    });

    test('reset gives back one retry after credentials change', () async {
      final recorder = _Recorder();
      final autoLogin = _autoLogin(
        recorder,
        result: const IdsLoginResult.failed('网络连接失败'),
      );

      await autoLogin.restoreSession();
      autoLogin.reset();
      await autoLogin.restoreSession();

      expect(recorder.attempts, 2);
    });
  });

  group('LoginStateStore manual logout flag', () {
    test('session expiry keeps automatic re-login allowed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LoginStateStore.markLoggedIn();

      await LoginStateStore.markLoggedOut();

      expect(await LoginStateStore.readLoggedIn(), isFalse);
      expect(await LoginStateStore.readManualLogout(), isFalse);
    });

    test('explicit logout blocks automatic re-login', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LoginStateStore.markLoggedIn();

      await LoginStateStore.markManualLogout();

      expect(await LoginStateStore.readLoggedIn(), isFalse);
      expect(await LoginStateStore.readManualLogout(), isTrue);
    });

    test('logging in again clears the manual logout flag', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        LoginStateStore.manualLogoutKey: true,
      });

      await LoginStateStore.markLoggedIn();

      expect(await LoginStateStore.readManualLogout(), isFalse);
    });
  });
}
