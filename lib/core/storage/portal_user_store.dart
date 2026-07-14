import 'dart:convert';

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

  /// Parses `ehall.uwh.edu.cn/getLoginUser` and refreshes the local profile.
  ///
  /// WebView JavaScript values may be JSON-encoded strings, so unwrap one
  /// string layer before parsing the portal response.
  static Future<bool> saveFromLoginUserResponse(String raw) async {
    var body = raw;
    if (body.startsWith('"')) {
      try {
        final unwrapped = jsonDecode(body);
        if (unwrapped is String) body = unwrapped;
      } catch (_) {}
    }

    try {
      final parsed = jsonDecode(body);
      if (parsed is! Map || parsed['data'] is! Map) return false;
      final data = (parsed['data'] as Map).cast<String, dynamic>();
      final userName = data['userName']?.toString();
      if (userName == null || userName.isEmpty) return false;

      String? className;
      final orgs = data['orgs'];
      if (orgs is List && orgs.isNotEmpty) {
        final first = orgs.first;
        if (first is Map) {
          final name = first['name']?.toString();
          if (name != null && name.isNotEmpty) className = name;
        }
      }
      if (className == null) {
        final deptRaw = data['deptName']?.toString();
        if (deptRaw != null && deptRaw.isNotEmpty) {
          final segments = deptRaw
              .split('/')
              .where((segment) => segment.isNotEmpty)
              .toList();
          if (segments.isNotEmpty) className = segments.last;
        }
      }

      await save(
        userName: userName,
        userAccount: data['userAccount']?.toString(),
        categoryName: data['categoryName']?.toString(),
        className: className,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
