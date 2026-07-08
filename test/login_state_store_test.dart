import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/core/storage/login_state_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LoginStateStore', () {
    test(
      'stores explicit logged in state without requiring an expiry',
      () async {
        SharedPreferences.setMockInitialValues({});

        await LoginStateStore.markLoggedIn();

        expect(await LoginStateStore.readLoggedIn(), isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey(LoginStateStore.expiryKey), isFalse);
      },
    );

    test('ignores legacy expiry when explicit state is absent', () async {
      SharedPreferences.setMockInitialValues({
        LoginStateStore.expiryKey: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });

      expect(await LoginStateStore.readLoggedIn(), isFalse);
    });

    test('markLoggedOut clears explicit and legacy login state', () async {
      SharedPreferences.setMockInitialValues({
        LoginStateStore.loggedInKey: true,
        LoginStateStore.expiryKey: DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });

      await LoginStateStore.markLoggedOut();

      expect(await LoginStateStore.readLoggedIn(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(LoginStateStore.expiryKey), isFalse);
    });
  });
}
