import 'package:shared_preferences/shared_preferences.dart';

class BoundaryDebugSettings {
  const BoundaryDebugSettings({
    required this.enabled,
    required this.menuVisible,
    required this.longitudeBd09,
    required this.latitudeBd09,
    required this.address,
    required this.city,
  });

  static const targetPattern =
      r'^https?://ehall\.uwh\.edu\.cn/student/cas/wap/menu/student/sign/stu/sign';

  static const _enabledKey = 'boundary_debug_enabled';
  static const _menuVisibleKey = 'boundary_debug_menu_visible';
  static const _longitudeKey = 'boundary_debug_lng_bd09';
  static const _latitudeKey = 'boundary_debug_lat_bd09';
  static const _addressKey = 'boundary_debug_address';
  static const _cityKey = 'boundary_debug_city';

  static const defaults = BoundaryDebugSettings(
    enabled: false,
    menuVisible: false,
    longitudeBd09: 118.27330,
    latitudeBd09: 31.36830,
    address: '安徽省芜湖市鸠江区靠近芜湖学院图书馆',
    city: '芜湖市',
  );

  final bool enabled;
  final bool menuVisible;
  final double longitudeBd09;
  final double latitudeBd09;
  final String address;
  final String city;

  BoundaryDebugSettings copyWith({
    bool? enabled,
    bool? menuVisible,
    double? longitudeBd09,
    double? latitudeBd09,
    String? address,
    String? city,
  }) {
    return BoundaryDebugSettings(
      enabled: enabled ?? this.enabled,
      menuVisible: menuVisible ?? this.menuVisible,
      longitudeBd09: longitudeBd09 ?? this.longitudeBd09,
      latitudeBd09: latitudeBd09 ?? this.latitudeBd09,
      address: address ?? this.address,
      city: city ?? this.city,
    );
  }

  static Future<BoundaryDebugSettings> read() async {
    final prefs = await SharedPreferences.getInstance();
    return BoundaryDebugSettings(
      enabled: prefs.getBool(_enabledKey) ?? defaults.enabled,
      menuVisible: prefs.getBool(_menuVisibleKey) ?? defaults.menuVisible,
      longitudeBd09: prefs.getDouble(_longitudeKey) ?? defaults.longitudeBd09,
      latitudeBd09: prefs.getDouble(_latitudeKey) ?? defaults.latitudeBd09,
      address: prefs.getString(_addressKey) ?? defaults.address,
      city: prefs.getString(_cityKey) ?? defaults.city,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    await prefs.setBool(_menuVisibleKey, menuVisible);
    await prefs.setDouble(_longitudeKey, longitudeBd09);
    await prefs.setDouble(_latitudeKey, latitudeBd09);
    await prefs.setString(_addressKey, address);
    await prefs.setString(_cityKey, city);
  }

  static Future<void> resetToDefaults({bool menuVisible = false}) async {
    await defaults.copyWith(menuVisible: menuVisible).save();
  }
}
