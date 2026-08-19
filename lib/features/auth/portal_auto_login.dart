import 'package:flutter/foundation.dart';

import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import 'ids_http_auth.dart';
import 'portal_session_cookies.dart';

typedef IdsLoginCall =
    Future<IdsLoginResult> Function({
      required String username,
      required String password,
      required Uri service,
    });

enum PortalAutoLoginOutcome {
  /// 不满足自动重登条件（已登录 / 用户主动退出 / 没有保存账号 / 本轮已重试过）。
  skipped,

  /// 已用保存的账号密码重新拿到门户会话。
  restored,

  /// 尝试过但失败（密码错误、需要滑块验证、网络异常等）。
  failed,
}

/// 会话失效时用已保存的账号密码静默重登一次。
///
/// 触发条件：右上角状态异常（未登录）+ 本机保存了账号密码 +
/// 用户没有主动点过“退出登录 / 清除登录状态”。
/// 每个“掉线周期”只重试一次，避免密码失效时反复提交把账号锁掉；
/// 下一次登录成功后重新允许重试。
class PortalAutoLogin {
  PortalAutoLogin({
    IdsLoginCall? login,
    Future<(String, String)?> Function()? readCredentials,
    Future<bool> Function()? readLoggedIn,
    Future<bool> Function()? readManualLogout,
    Future<void> Function()? markLoggedIn,
    Future<void> Function(IdsLoginResult result)? syncCookies,
  }) : _login = login ?? _defaultLogin,
       _readCredentials = readCredentials ?? PortalCredentials.read,
       _readLoggedIn = readLoggedIn ?? LoginStateStore.readLoggedIn,
       _readManualLogout = readManualLogout ?? LoginStateStore.readManualLogout,
       _markLoggedIn = markLoggedIn ?? LoginStateStore.markLoggedIn,
       _syncCookies = syncCookies ?? _defaultSyncCookies;

  static final Uri serviceUri = Uri.parse('https://ehall.uwh.edu.cn/login');
  static final PortalAutoLogin instance = PortalAutoLogin();

  final IdsLoginCall _login;
  final Future<(String, String)?> Function() _readCredentials;
  final Future<bool> Function() _readLoggedIn;
  final Future<bool> Function() _readManualLogout;
  final Future<void> Function() _markLoggedIn;
  final Future<void> Function(IdsLoginResult result) _syncCookies;

  bool _attempted = false;
  bool _running = false;

  @visibleForTesting
  bool get attempted => _attempted;

  /// Uses the saved password to establish a fresh IDS + portal session.
  ///
  /// [force] is for the case where an Ehall cookie still works but the IDS
  /// SSO cookie has expired. In that state the portal can look healthy while
  /// a service redirect leaves the user at the IDS login page, so the normal
  /// `loggedIn` shortcut must not suppress the single recovery attempt.
  Future<PortalAutoLoginOutcome> restoreSession({bool force = false}) async {
    if (_running) return PortalAutoLoginOutcome.skipped;
    _running = true;
    try {
      if (!force && await _readLoggedIn()) {
        // 会话恢复正常，下次掉线时重新获得一次重试机会。
        _attempted = false;
        return PortalAutoLoginOutcome.skipped;
      }
      if (_attempted) return PortalAutoLoginOutcome.skipped;
      if (await _readManualLogout()) return PortalAutoLoginOutcome.skipped;
      final credentials = await _readCredentials();
      if (credentials == null) return PortalAutoLoginOutcome.skipped;

      _attempted = true;
      final result = await _login(
        username: credentials.$1,
        password: credentials.$2,
        service: serviceUri,
      );
      if (result.status != IdsLoginStatus.authenticated) {
        debugPrint('[PortalAutoLogin] failed: ${result.status.name}');
        return PortalAutoLoginOutcome.failed;
      }

      await _syncCookies(result);
      await _markLoggedIn();
      _attempted = false;
      debugPrint('[PortalAutoLogin] session restored');
      return PortalAutoLoginOutcome.restored;
    } finally {
      _running = false;
    }
  }

  /// 账号密码变更等场景下重新放开一次重试机会。
  void reset() => _attempted = false;

  static Future<IdsLoginResult> _defaultLogin({
    required String username,
    required String password,
    required Uri service,
  }) {
    return IdsHttpAuthClient().login(
      username: username,
      password: password,
      service: service,
    );
  }

  static Future<void> _defaultSyncCookies(IdsLoginResult result) async {
    await PortalSessionCookies.rememberLogin(result);
    await result.syncCookiesToWebView();
  }
}
