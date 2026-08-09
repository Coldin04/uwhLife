import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/paycode_brightness_settings.dart';

void main() {
  group('PayCodeBrightnessSettings', () {
    test('defaults to boosting in light mode only', () {
      const settings = PayCodeBrightnessSettings.defaults;

      expect(settings.autoBoost, isTrue);
      expect(settings.boostInDarkMode, isFalse);
      expect(settings.shouldBoost(isDarkMode: false), isTrue);
      expect(settings.shouldBoost(isDarkMode: true), isFalse);
    });

    test('dark mode boost opts in', () {
      const settings = PayCodeBrightnessSettings(
        autoBoost: true,
        boostInDarkMode: true,
      );

      expect(settings.shouldBoost(isDarkMode: true), isTrue);
      expect(settings.shouldBoost(isDarkMode: false), isTrue);
    });

    test('the master switch wins over the dark mode switch', () {
      const settings = PayCodeBrightnessSettings(
        autoBoost: false,
        boostInDarkMode: true,
      );

      expect(settings.shouldBoost(isDarkMode: false), isFalse);
      expect(settings.shouldBoost(isDarkMode: true), isFalse);
    });

    test('round-trips through preferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await const PayCodeBrightnessSettings(
        autoBoost: false,
        boostInDarkMode: true,
      ).save();
      final restored = await PayCodeBrightnessSettings.read();

      expect(restored.autoBoost, isFalse);
      expect(restored.boostInDarkMode, isTrue);
    });

    test('falls back to defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final settings = await PayCodeBrightnessSettings.read();

      expect(settings.autoBoost, PayCodeBrightnessSettings.defaults.autoBoost);
      expect(
        settings.boostInDarkMode,
        PayCodeBrightnessSettings.defaults.boostInDarkMode,
      );
    });
  });
}
