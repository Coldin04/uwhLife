import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import 'ids_http_auth.dart';

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
    Future<void> Function()? markLoggedOut,
    Future<void> Function()? markManualLogout,
    Future<void> Function(IdsLoginResult result)? syncCookies,
  }) : _login = login ?? _defaultLogin,
       _readCredentials = readCredentials ?? PortalCredentials.read,
       _readLoggedIn = readLoggedIn ?? LoginStateStore.readLoggedIn,
       _readManualLogout = readManualLogout ?? LoginStateStore.readManualLogout,
       _markLoggedIn = markLoggedIn ?? LoginStateStore.markLoggedIn,
       _markLoggedOut = markLoggedOut ?? LoginStateStore.markLoggedOut,
       _markManualLogout = markManualLogout ?? LoginStateStore.markManualLogout,
       _syncCookies = syncCookies ?? _defaultSyncCookies;

  static final Uri serviceUri = Uri.parse('https://ehall.uwh.edu.cn/login');
  static final PortalAutoLogin instance = PortalAutoLogin();

  final IdsLoginCall _login;
  final Future<(String, String)?> Function() _readCredentials;
  final Future<bool> Function() _readLoggedIn;
  final Future<bool> Function() _readManualLogout;
  final Future<void> Function() _markLoggedIn;
  final Future<void> Function() _markLoggedOut;
  final Future<void> Function() _markManualLogout;
  final Future<void> Function(IdsLoginResult result) _syncCookies;

  bool _attempted = false;
  Future<PortalAutoLoginOutcome>? _restoreFuture;
  Future<PortalAutoLoginOutcome>? _expiryFuture;
  Future<void> _mutations = Future<void>.value();
  int _generation = 0;
  int? _lastAuthenticatedGeneration;

  /// Snapshot before a request: a late result must not invalidate a newer
  /// successful login or a user-initiated logout.
  int get generation => _generation;

  /// Wait only for an already-running recovery, without starting one.
  Future<void> waitForRecovery() async {
    final pending = _expiryFuture ?? _restoreFuture;
    if (pending != null) await pending;
  }

  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _mutations.then((_) => operation());
    _mutations = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  /// A confirmed IDS login form is evidence of expiry only for the session
  /// which initiated that request. Concurrent reports share one recovery.
  Future<PortalAutoLoginOutcome> reportLoginRequired(
    int observedGeneration, {
    bool recover = true,
  }) {
    final pending = _expiryFuture;
    if (pending != null && observedGeneration == _generation) return pending;
    if (observedGeneration != _generation) {
      return Future<PortalAutoLoginOutcome>.value(
        _lastAuthenticatedGeneration == _generation
            ? PortalAutoLoginOutcome.restored
            : PortalAutoLoginOutcome.skipped,
      );
    }
    final future = _reportLoginRequired(observedGeneration, recover: recover);
    _expiryFuture = future;
    return future.whenComplete(() {
      if (identical(_expiryFuture, future)) _expiryFuture = null;
    });
  }

  Future<PortalAutoLoginOutcome> _reportLoginRequired(
    int observed, {
    required bool recover,
  }) async {
    final expired = await _mutate(() async {
      if (observed != _generation || await _readManualLogout()) return false;
      if (observed != _generation) return false;
      await _markLoggedOut();
      _lastAuthenticatedGeneration = null;
      return observed == _generation;
    });
    if (!expired || !recover) return PortalAutoLoginOutcome.skipped;
    return restoreSession(force: true);
  }

  /// Call when the user starts an explicit login, invalidating older requests.
  int beginInteractiveLogin() => ++_generation;

  /// Commits a manual login only after its Cookie update has completed.
  Future<bool> completeInteractiveLogin({
    required int observedGeneration,
    required Future<void> Function() syncCookies,
  }) => _mutate(() async {
    if (observedGeneration != _generation) return false;
    await syncCookies();
    if (observedGeneration != _generation) return false;
    await _markLoggedIn();
    if (observedGeneration != _generation) return false;
    _generation++;
    _lastAuthenticatedGeneration = _generation;
    _attempted = false;
    return true;
  });

  /// Apply a response Cookie only if the request still belongs to the
  /// current session. Shares the same ordering as login and logout.
  Future<bool> applyCookiesIfCurrent({
    required int observedGeneration,
    required Future<void> Function() write,
  }) => _mutate(() async {
    if (observedGeneration != _generation) return false;
    await write();
    return observedGeneration == _generation;
  });

  /// Invalidate pending work immediately, then clear after any active Cookie
  /// write has finished. This prevents an old recovery from undoing logout.
  Future<void> logout({required Future<void> Function() clear}) {
    _generation++;
    _lastAuthenticatedGeneration = null;
    return _mutate(() async {
      await _markManualLogout();
      await clear();
    });
  }

  @visibleForTesting
  bool get attempted => _attempted;

  /// Uses the saved password to establish a fresh IDS + portal session.
  ///
  /// [force] is for the case where an Ehall cookie still works but the IDS
  /// SSO cookie has expired. In that state the portal can look healthy while
  /// a service redirect leaves the user at the IDS login page, so the normal
  /// `loggedIn` shortcut must not suppress the single recovery attempt.
  Future<PortalAutoLoginOutcome> restoreSession({bool force = false}) async {
    final running = _restoreFuture;
    if (running != null) return running;

    final future = _restoreSession(force: force, generation: _generation);
    _restoreFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_restoreFuture, future)) _restoreFuture = null;
    }
  }

  Future<PortalAutoLoginOutcome> _restoreSession({
    required bool force,
    required int generation,
  }) async {
    if (!force && await _readLoggedIn()) {
      // 会话恢复正常，下次掉线时重新获得一次重试机会。
      _attempted = false;
      return PortalAutoLoginOutcome.skipped;
    }
    if (_attempted) return PortalAutoLoginOutcome.skipped;
    if (await _readManualLogout()) return PortalAutoLoginOutcome.skipped;
    final credentials = await _readCredentials();
    if (credentials == null) return PortalAutoLoginOutcome.skipped;
    if (generation != _generation) return PortalAutoLoginOutcome.skipped;

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

    try {
      final committed = await _mutate(() async {
        if (generation != _generation || await _readManualLogout()) {
          return false;
        }
        if (generation != _generation) return false;
        await _syncCookies(result);
        if (generation != _generation) return false;
        await _markLoggedIn();
        if (generation != _generation) return false;
        _generation++;
        _lastAuthenticatedGeneration = _generation;
        _attempted = false;
        return true;
      });
      if (!committed) return PortalAutoLoginOutcome.skipped;
    } catch (error) {
      debugPrint('[PortalAutoLogin] cookie sync failed: $error');
      return PortalAutoLoginOutcome.failed;
    }
    debugPrint('[PortalAutoLogin] session restored');
    return PortalAutoLoginOutcome.restored;
  }

  /// 账号密码变更等场景下重新放开一次重试机会。
  void reset() => _attempted = false;

  static Future<IdsLoginResult> _defaultLogin({
    required String username,
    required String password,
    required Uri service,
  }) async {
    final rememberMe = await LoginStateStore.readRememberMe();
    return IdsHttpAuthClient().login(
      username: username,
      password: password,
      service: service,
      rememberMe: rememberMe,
    );
  }

  static Future<void> _defaultSyncCookies(IdsLoginResult result) async {
    await result.syncCookiesToWebView();
  }
}
