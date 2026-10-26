import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uwhlife/main.dart';
import 'package:uwhlife/core/storage/login_state_store.dart';
import 'package:uwhlife/features/home/home_page.dart';

void main() {
  const deepLinkMethodChannel = MethodChannel('uwhlife/deep_links');

  setUp(() {
    WebViewPlatform.instance = _FakeWebViewPlatform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deepLinkMethodChannel, (call) async {
          if (call.method == 'getInitialLink') return null;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deepLinkMethodChannel, null);
  });

  testWidgets('home page renders', (WidgetTester tester) async {
    await tester.pumpWidget(const UwhLifeApp());
    await tester.pump();

    expect(find.text('门锁'), findsOneWidget);
    expect(find.byIcon(Icons.shower_outlined), findsOneWidget);
  });

  testWidgets(
    'cold launch does not warn from a cached false or an unparseable probe',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        LoginStateStore.loggedInKey: false,
      });
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pump();
      expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an unparseable cold-launch probe preserves a saved login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({LoginStateStore.loggedInKey: true});
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(await LoginStateStore.readLoggedIn(), isTrue);
    expect(find.byIcon(Icons.priority_high_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an explicit logout still shows the login entry', (tester) async {
    SharedPreferences.setMockInitialValues({
      LoginStateStore.loggedInKey: false,
      LoginStateStore.manualLogoutKey: true,
    });
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pump();
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakeWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakeWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return _FakeWebViewCookieManager(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakeNavigationDelegate(params);
  }
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigationDelegate = handler as _FakeNavigationDelegate?;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    var url = params.uri.toString();
    if (url.contains('auth.xiaofubao.com')) {
      url = 'https://webapp.xiaofubao.com/card/card_pay_code.shtml';
    }
    _navigationDelegate?.onPageFinished?.call(url);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    if (javaScript.contains('getObjectCache("loginUser")')) return 'null';
    if (javaScript.contains('vueObj.qrCodeStr')) return '"fake-qr"';
    return '';
  }

  @override
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

  _FakeNavigationDelegate? _navigationDelegate;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _FakeWebViewCookieManager extends PlatformWebViewCookieManager {
  _FakeWebViewCookieManager(super.params) : super.implementation();
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;
  NavigationRequestCallback? onNavigationRequest;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    this.onNavigationRequest = onNavigationRequest;
  }
}
