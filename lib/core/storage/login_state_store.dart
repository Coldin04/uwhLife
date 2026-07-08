import 'package:shared_preferences/shared_preferences.dart';

import 'portal_user_store.dart';

/// 统一门户登录态读写。所有页面都通过这个类操作 SharedPreferences，
/// 保证 key 和清理逻辑只有一份。
class LoginStateStore {
  static const String expiryKey = 'login_expiry_millis';
  static const String loggedInKey = 'portal_logged_in';

  static Future<bool> readLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(loggedInKey) ?? false;
  }

  /// 标记为已登录。状态来自最近一次门户探测，不再展示本地 7 天倒计时。
  static Future<bool> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(loggedInKey, true);
    await prefs.remove(expiryKey);
    return true;
  }

  static Future<void> markLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(loggedInKey, false);
    await prefs.remove(expiryKey);
    await PortalUserStore.clear();
  }
}
