import 'package:shared_preferences/shared_preferences.dart';

/// 首页快捷入口的显示偏好。
class HomePageSettings {
  const HomePageSettings({required this.iconOnlyMode});

  static const defaults = HomePageSettings(iconOnlyMode: false);

  static const String iconOnlyModeKey = 'home_icon_only_mode';

  final bool iconOnlyMode;

  HomePageSettings copyWith({bool? iconOnlyMode}) {
    return HomePageSettings(iconOnlyMode: iconOnlyMode ?? this.iconOnlyMode);
  }

  static Future<HomePageSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    return HomePageSettings(
      iconOnlyMode: prefs.getBool(iconOnlyModeKey) ?? defaults.iconOnlyMode,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(iconOnlyModeKey, iconOnlyMode);
  }
}
