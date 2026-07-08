import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 门户账号密码的安全存储。
/// iOS 使用 Keychain，Android 使用 EncryptedSharedPreferences。
class PortalCredentials {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _userKey = 'portal_username';
  static const _passKey = 'portal_password';

  static Future<(String, String)?> read() async {
    final u = await _storage.read(key: _userKey);
    final p = await _storage.read(key: _passKey);
    if (u == null || p == null || u.isEmpty || p.isEmpty) return null;
    return (u, p);
  }

  static Future<void> save(String username, String password) async {
    await _storage.write(key: _userKey, value: username);
    await _storage.write(key: _passKey, value: password);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _passKey);
  }
}
