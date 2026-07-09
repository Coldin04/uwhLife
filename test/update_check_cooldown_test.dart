import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/features/update/update_check_cooldown.dart';

void main() {
  group('UpdateCheckCooldown', () {
    test('does not skip automatic checks when no cancel time is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final cooldown = UpdateCheckCooldown(
        now: () => DateTime(2026, 7, 9),
      );

      expect(await cooldown.shouldSkipAutomaticCheck(), isFalse);
    });

    test('skips automatic checks for ten days after user cancellation', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      var currentTime = DateTime(2026, 7, 9, 12);
      final cooldown = UpdateCheckCooldown(now: () => currentTime);

      await cooldown.recordUserCancelled();

      currentTime = currentTime.add(const Duration(days: 9, hours: 23));
      expect(await cooldown.shouldSkipAutomaticCheck(), isTrue);

      currentTime = currentTime.add(const Duration(hours: 2));
      expect(await cooldown.shouldSkipAutomaticCheck(), isFalse);
    });
  });
}
