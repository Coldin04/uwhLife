import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_login_guard.dart';

const _service = 'https://ehall.uwh.edu.cn/getLoginUser';
const _ids = 'https://ids.uwh.edu.cn/authserver/login?service=ehall';

void main() {
  testWidgets(
    'requires a service redirect and three seconds on a visible form',
    (tester) async {
      var expired = 0;
      final guard = IdsLoginGuard(
        hasVisibleLoginForm: () async => true,
        onLoginRequired: () async {
          expired++;
        },
      );
      addTearDown(guard.dispose);
      guard.pageStarted(_service);
      guard.pageStarted(_ids);
      guard.pageFinished(_ids);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(expired, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(expired, 1);
    },
  );

  testWidgets('does not expire a session for a directly opened IDS page', (
    tester,
  ) async {
    var expired = false;
    final guard = IdsLoginGuard(
      hasVisibleLoginForm: () async => true,
      onLoginRequired: () async {
        expired = true;
      },
    );
    addTearDown(guard.dispose);
    guard.pageStarted(_ids);
    guard.pageFinished(_ids);
    await tester.pump(const Duration(seconds: 4));
    expect(expired, isFalse);
  });

  for (final scenario in [
    'returns to service',
    'network error',
    'hidden form',
    'DOM error',
    'disposed',
  ]) {
    testWidgets('preserves the session when $scenario', (tester) async {
      var expired = false;
      final guard = IdsLoginGuard(
        hasVisibleLoginForm: () async {
          if (scenario == 'DOM error') throw StateError('page unavailable');
          return scenario != 'hidden form';
        },
        onLoginRequired: () async {
          expired = true;
        },
      );
      addTearDown(guard.dispose);
      guard.pageStarted(_service);
      guard.pageStarted(_ids);
      guard.pageFinished(_ids);
      await tester.pump(const Duration(seconds: 1));
      if (scenario == 'returns to service') guard.pageStarted(_service);
      if (scenario == 'network error') guard.requestFailed();
      if (scenario == 'disposed') guard.dispose();
      await tester.pump(const Duration(seconds: 3));
      expect(expired, isFalse);
    });
  }

  testWidgets('ignores a DOM result from a page that has already navigated', (
    tester,
  ) async {
    final form = Completer<bool>();
    var expired = false;
    final guard = IdsLoginGuard(
      hasVisibleLoginForm: () => form.future,
      onLoginRequired: () async {
        expired = true;
      },
    );
    addTearDown(guard.dispose);
    guard.pageStarted(_service);
    guard.pageStarted(_ids);
    guard.pageFinished(_ids);
    await tester.pump(const Duration(seconds: 3));
    guard.urlChanged(_service);
    form.complete(true);
    await tester.pump();
    expect(expired, isFalse);
  });
}
