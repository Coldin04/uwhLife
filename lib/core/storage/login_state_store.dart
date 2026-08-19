import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'portal_user_store.dart';

/// 统一门户登录态读写。所有页面都通过这个类操作 SharedPreferences，
/// 保证 key 和清理逻辑只有一份。
class LoginStateStore {
  /// Process-local login state shared by the home status indicator and the
  /// profile tab. The persisted value remains the source of truth; this
  /// notifier only avoids making each page wait for its own refresh.
  static final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  static const String expiryKey = 'login_expiry_millis';
  static const String loggedInKey = 'portal_logged_in';

  /// 用户主动退出登录的标记。会话被动失效（被踢回统一认证）不会写这个值，
  /// 只有点击“退出登录 / 清除登录状态”才会。重新登录成功后自动清除。
  static const String manualLogoutKey = 'portal_manual_logout';

  static Future<bool> readLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(loggedInKey) ?? false;
    if (notifier.value != value) notifier.value = value;
    return value;
  }

  /// 用户是否主动退出过登录（且此后没有再登录成功）。
  static Future<bool> readManualLogout() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(manualLogoutKey) ?? false;
  }

  /// 标记为已登录。状态来自最近一次门户探测，不再展示本地 7 天倒计时。
  static Future<bool> markLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(loggedInKey, true);
    await prefs.remove(expiryKey);
    await prefs.remove(manualLogoutKey);
    notifier.value = true;
    return true;
  }

  /// 会话失效导致的登出（探测被重定向到统一认证等），之后允许自动重新登录。
  static Future<void> markLoggedOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(loggedInKey, false);
    await prefs.remove(expiryKey);
    await PortalUserStore.clear();
    notifier.value = false;
  }

  /// 用户主动退出登录 / 清除登录状态，在下次成功登录前不再自动重登。
  static Future<void> markManualLogout() async {
    await markLoggedOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(manualLogoutKey, true);
  }
}
