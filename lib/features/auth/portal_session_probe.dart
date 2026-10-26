import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import 'ids_login_form.dart';
import 'ids_login_guard.dart';

enum PortalProbeStatus { response, loginRequired, unavailable }

class PortalProbeResult {
  const PortalProbeResult(this.status, {this.body = ''});

  final PortalProbeStatus status;
  final String body;
}

/// Checks Ehall using the actual browser cookie store, including SSO page
/// scripts. Only a settled, visible IDS form can prove authentication loss.
class PortalSessionProbe {
  Future<PortalProbeResult>? _pending;
  void Function()? _cancel;

  Future<PortalProbeResult> check() {
    return _pending ??= _check()
        .catchError(
          (Object _) => const PortalProbeResult(PortalProbeStatus.unavailable),
        )
        .whenComplete(() => _pending = null);
  }

  Future<PortalProbeResult> _check() async {
    final completed = Completer<PortalProbeResult>();
    final controller = WebViewController();
    var requestedUser = false;
    void finish(PortalProbeResult result) {
      if (!completed.isCompleted) completed.complete(result);
    }

    _cancel = () =>
        finish(const PortalProbeResult(PortalProbeStatus.unavailable));
    final guard = IdsLoginGuard(
      hasVisibleLoginForm: () async {
        final result = await controller.runJavaScriptReturningResult(
          idsVisibleLoginFormScript,
        );
        return result == true || result.toString() == 'true';
      },
      onLoginRequired: () async {
        finish(const PortalProbeResult(PortalProbeStatus.loginRequired));
      },
    );
    final timeout = Timer(const Duration(seconds: 15), () {
      finish(const PortalProbeResult(PortalProbeStatus.unavailable));
    });
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: guard.pageStarted,
          onUrlChange: (change) {
            if (change.url != null) {
              guard.urlChanged(change.url!);
            }
          },
          onPageFinished: (url) async {
            if (completed.isCompleted) return;
            guard.pageFinished(url);
            final uri = Uri.tryParse(url);
            if (uri?.host.toLowerCase() != 'ehall.uwh.edu.cn') return;
            // CAS commonly returns via /login?ticket=... -> /login -> index.
            // Let that chain establish the browser session before reading user
            // information. A failed read still cannot invalidate the session.
            if (uri?.path != '/getLoginUser') {
              if (!requestedUser) {
                requestedUser = true;
                try {
                  await controller.loadRequest(
                    Uri.parse('https://ehall.uwh.edu.cn/getLoginUser'),
                  );
                } catch (_) {
                  finish(
                    const PortalProbeResult(PortalProbeStatus.unavailable),
                  );
                }
              }
              return;
            }
            try {
              final raw = await controller.runJavaScriptReturningResult(
                'document.body ? document.body.innerText : ""',
              );
              var body = raw.toString();
              if (body.startsWith('"')) {
                final decoded = jsonDecode(body);
                if (decoded is String) body = decoded;
              }
              finish(PortalProbeResult(PortalProbeStatus.response, body: body));
            } catch (_) {
              finish(const PortalProbeResult(PortalProbeStatus.unavailable));
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            guard.requestFailed();
            finish(const PortalProbeResult(PortalProbeStatus.unavailable));
          },
        ),
      );
      const url = 'https://ehall.uwh.edu.cn/login';
      guard.pageStarted(url);
      await controller.loadRequest(Uri.parse(url));
      return await completed.future;
    } catch (_) {
      return const PortalProbeResult(PortalProbeStatus.unavailable);
    } finally {
      guard.dispose();
      timeout.cancel();
      _cancel = null;
      // The background page must not keep running scripts after the check.
      unawaited(_close(controller));
    }
  }

  Future<void> _close(WebViewController controller) async {
    try {
      await controller.setNavigationDelegate(NavigationDelegate());
      await controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
  }

  void dispose() => _cancel?.call();
}
