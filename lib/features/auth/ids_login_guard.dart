import 'dart:async';

import 'ids_login_form.dart';

/// A service navigation must settle on an visible IDS login form before it
/// can invalidate the shared session. Network errors and intermediate SSO
/// pages never supply that evidence.
class IdsLoginGuard {
  IdsLoginGuard({
    required this.hasVisibleLoginForm,
    required this.onLoginRequired,
    this.settleDelay = const Duration(seconds: 3),
  });

  final Future<bool> Function() hasVisibleLoginForm;
  final Future<void> Function() onLoginRequired;
  final Duration settleDelay;
  Timer? _timer;
  String? _url;
  bool _visitedService = false;
  bool _disposed = false;
  bool _failed = false;
  int _generation = 0;

  void pageStarted(String url) {
    _cancel();
    _url = url;
    _failed = false;
    final uri = Uri.tryParse(url);
    if ((uri?.scheme == 'https' || uri?.scheme == 'http') &&
        uri?.host.toLowerCase() != 'ids.uwh.edu.cn') {
      _visitedService = true;
    }
  }

  void urlChanged(String url) {
    if (url != _url) pageStarted(url);
  }

  void pageFinished(String url) {
    if (_disposed || _failed || _url != url) return;
    _cancel();
    if (!_visitedService || !isIdsLoginUrl(url)) return;
    final generation = _generation;
    _timer = Timer(settleDelay, () => unawaited(_confirm(generation)));
  }

  Future<void> _confirm(int generation) async {
    try {
      final editable = await hasVisibleLoginForm();
      if (_disposed || generation != _generation || !editable) return;
      await onLoginRequired();
    } catch (_) {
      // Reading a page which is navigating or unavailable proves nothing.
    }
  }

  void requestFailed() {
    _failed = true;
    _cancel();
  }

  void _cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }
}
