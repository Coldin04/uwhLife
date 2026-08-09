import 'package:shared_preferences/shared_preferences.dart';

/// 付款码页的屏幕增亮设置。
///
/// 默认浅色模式增亮、深色模式不增亮——深色模式多半是在暗环境里用，
/// 突然拉满屏幕会晃眼；需要的人可以在「我的」里单独打开。
class PayCodeBrightnessSettings {
  const PayCodeBrightnessSettings({
    required this.autoBoost,
    required this.boostInDarkMode,
  });

  static const defaults = PayCodeBrightnessSettings(
    autoBoost: true,
    boostInDarkMode: false,
  );

  static const String autoBoostKey = 'paycode_auto_brightness';
  static const String boostInDarkModeKey = 'paycode_auto_brightness_dark';

  final bool autoBoost;
  final bool boostInDarkMode;

  /// 当前主题下要不要增亮。
  bool shouldBoost({required bool isDarkMode}) {
    if (!autoBoost) return false;
    return isDarkMode ? boostInDarkMode : true;
  }

  PayCodeBrightnessSettings copyWith({bool? autoBoost, bool? boostInDarkMode}) {
    return PayCodeBrightnessSettings(
      autoBoost: autoBoost ?? this.autoBoost,
      boostInDarkMode: boostInDarkMode ?? this.boostInDarkMode,
    );
  }

  static Future<PayCodeBrightnessSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    return PayCodeBrightnessSettings(
      autoBoost: prefs.getBool(autoBoostKey) ?? defaults.autoBoost,
      boostInDarkMode:
          prefs.getBool(boostInDarkModeKey) ?? defaults.boostInDarkMode,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoBoostKey, autoBoost);
    await prefs.setBool(boostInDarkModeKey, boostInDarkMode);
  }
}
