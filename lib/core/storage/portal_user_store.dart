import 'package:shared_preferences/shared_preferences.dart';

/// 缓存从 `ehall.uwh.edu.cn/getLoginUser` 拿到的用户信息（姓名 / 学号 /
/// 身份类别 / 班级）。用于个人中心展示。非敏感信息，存普通 SharedPreferences。
class PortalUserStore {
  static const _nameKey = 'portal_user_name';
  static const _acctKey = 'portal_user_account';
  static const _categoryKey = 'portal_user_category';
  static const _classKey = 'portal_user_class';

  static Future<void> save({
    String? userName,
    String? userAccount,
    String? categoryName,
    String? className,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> put(String k, String? v) async {
      if (v == null || v.isEmpty) {
        await prefs.remove(k);
      } else {
        await prefs.setString(k, v);
      }
    }

    await put(_nameKey, userName);
    await put(_acctKey, userAccount);
    await put(_categoryKey, categoryName);
    await put(_classKey, className);
  }

  static Future<
    ({
      String? userName,
      String? userAccount,
      String? categoryName,
      String? className,
    })
  >
  read() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      userName: prefs.getString(_nameKey),
      userAccount: prefs.getString(_acctKey),
      categoryName: prefs.getString(_categoryKey),
      className: prefs.getString(_classKey),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_nameKey);
    await prefs.remove(_acctKey);
    await prefs.remove(_categoryKey);
    await prefs.remove(_classKey);
  }
}
