import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:uwhlife/features/auth/portal_session_probe.dart';

const _ids =
    'https://ids.uwh.edu.cn/authserver/login?service=https://ehall.uwh.edu.cn/login';
const _portal = 'https://ehall.uwh.edu.cn/dark/index.html';
const _user = 'https://ehall.uwh.edu.cn/getLoginUser';

void main() {
  late _Browser browser;
  late PortalSessionProbe probe;

  setUp(() {
    browser = _Browser();
    WebViewPlatform.instance = browser;
    probe = PortalSessionProbe();
  });
  tearDown(() => probe.dispose());

  testWidgets(
    'follows the successful CAS chain before reading portal user data',
    (tester) async {
      final result = probe.check();
      await tester.pump();
      final page = browser.page;
      expect(page.requests, ['https://ehall.uwh.edu.cn/login']);
      page.start(_ids);
      page.start('https://ehall.uwh.edu.cn/login?ticket=example');
      page.start('https://ehall.uwh.edu.cn/login');
      page.start(_portal);
      page.finish(_portal);
      await tester.pump();
      expect(page.requests.last, _user);
      page.body = '{"data":{"userName":"Student"}}';
      page.start(_user);
      page.finish(_user);
      await tester.pump();
      expect((await result).status, PortalProbeStatus.response);
      expect((await result).body, page.body);
    },
  );

  testWidgets('requires the real redirected page to show the credential form', (
    tester,
  ) async {
    final result = probe.check();
    await tester.pump();
    browser.page.formVisible = true;
    browser.page.start(_ids);
    browser.page.finish(_ids);
    var finished = false;
    result.then((_) => finished = true);
    await tester.pump(const Duration(seconds: 2));
    expect(finished, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect((await result).status, PortalProbeStatus.loginRequired);
  });

  testWidgets('a hidden password form times out as unavailable', (
    tester,
  ) async {
    final result = probe.check();
    await tester.pump();
    browser.page.start(_ids);
    browser.page.finish(_ids);
    await tester.pump(const Duration(seconds: 15));
    expect((await result).status, PortalProbeStatus.unavailable);
  });

  testWidgets('a main-frame network failure is not login expiry', (
    tester,
  ) async {
    final result = probe.check();
    await tester.pump();
    browser.page.start(_ids);
    browser.page.delegate.error?.call(
      const WebResourceError(
        errorCode: -1009,
        description: 'Offline',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect((await result).status, PortalProbeStatus.unavailable);
  });

  testWidgets('closing the probe cancels a pending login decision', (
    tester,
  ) async {
    final result = probe.check();
    await tester.pump();
    browser.page.formVisible = true;
    browser.page.start(_ids);
    browser.page.finish(_ids);
    probe.dispose();
    await tester.pump(const Duration(seconds: 4));
    expect((await result).status, PortalProbeStatus.unavailable);
  });
}

class _Browser extends WebViewPlatform {
  late _Page page;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return page = _Page(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params);
}

class _Page extends PlatformWebViewController {
  _Page(super.params) : super.implementation();
  late _Delegate delegate;
  final requests = <String>[];
  bool formVisible = false;
  String body = '';

  void start(String url) => delegate.started?.call(url);
  void finish(String url) => delegate.finished?.call(url);

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async => delegate = handler as _Delegate;
  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      requests.add(params.uri.toString());
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      script.contains('idsCredentialFields') ? formVisible : body;
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  PageEventCallback? started;
  PageEventCallback? finished;
  WebResourceErrorCallback? error;

  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async =>
      started = callback;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async =>
      finished = callback;
  @override
  Future<void> setOnUrlChange(UrlChangeCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      error = callback;
}
