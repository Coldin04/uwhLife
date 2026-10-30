import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uwhlife/main.dart';
import 'package:uwhlife/core/platform/side_navigation.dart';
import 'package:uwhlife/core/storage/login_state_store.dart';
import 'package:uwhlife/features/home/home_page.dart';
import 'package:uwhlife/features/root/root_page.dart';

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
    'home content respects asymmetric insets without extra bottom gap',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        isDuoDevice = false;
        systemAdaptivePhone = false;
        systemVerticalEdge = 'none';
      });
      tester.view.devicePixelRatio = 1;

      for (final scenario in [
        (
          size: const Size(390, 844),
          padding: const EdgeInsets.fromLTRB(0, 0, 84, 34),
        ),
        (
          size: const Size(844, 390),
          padding: const EdgeInsets.fromLTRB(84, 0, 0, 21),
        ),
        (
          size: const Size(700, 960),
          padding: const EdgeInsets.fromLTRB(0, 48, 0, 34),
        ),
      ]) {
        tester.view.physicalSize = scenario.size;
        isDuoDevice = scenario.padding.left > 0 || scenario.padding.right > 0;
        systemAdaptivePhone = true;
        systemVerticalEdge = scenario.padding.left > 0
            ? 'left'
            : scenario.padding.right > 0
            ? 'right'
            : 'none';
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: scenario.size,
                padding: scenario.padding,
              ),
              child: const HomePage(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        final greeting = find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              const ['晚安', '上午好', '中午好', '下午好', '晚上好'].contains(widget.data),
        );
        expect(greeting, findsOneWidget);
        final greetingRect = tester.getRect(greeting);
        expect(greetingRect.top, greaterThan(scenario.padding.top + 10));
        expect(greetingRect.left, greaterThanOrEqualTo(scenario.padding.left));

        // The card's InkWell exists while its contents are still loading too.
        final card = find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget.runtimeType.toString() == '_UpcomingCourseQuote',
              ),
              matching: find.byType(RepaintBoundary),
            )
            .first;
        await tester.ensureVisible(card);
        await tester.pump();
        final cardRect = tester.getRect(card);
        expect(
          cardRect.right,
          lessThanOrEqualTo(scenario.size.width - scenario.padding.right),
        );
        final expectedBottom =
            scenario.size.height -
            scenario.padding.bottom -
            (!isDuoDevice && scenario.size.shortestSide >= 600 ? 18 : 0);
        expect(cardRect.bottom, closeTo(expectedBottom, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('inner portrait navigation has room above the home indicator', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    systemAdaptivePhone = true;
    systemVerticalEdge = 'none';
    isDuoDevice = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(669, 951);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      isDuoDevice = false;
      systemAdaptivePhone = false;
      systemVerticalEdge = 'none';
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(669, 951),
            padding: EdgeInsets.only(top: 82, bottom: 34),
            viewPadding: EdgeInsets.only(top: 82, bottom: 34),
          ),
          child: RootPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final card = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_UpcomingCourseQuote',
    );
    final navigation = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_SlidingNavBar',
    );
    final bar = find
        .descendant(of: navigation, matching: find.byType(ClipRRect))
        .first;
    expect(card, findsOneWidget);
    expect(bar, findsOneWidget);
    final cardRect = tester.getRect(card);
    final barRect = tester.getRect(bar);
    expect(barRect.top - cardRect.bottom, closeTo(18, 1));
    expect(951 - barRect.bottom, inInclusiveRange(16, 33));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('course card follows the active navigation position', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      isDuoDevice = false;
      systemAdaptivePhone = false;
      systemVerticalEdge = 'none';
    });

    for (final scenario in [
      (
        size: const Size(393, 852),
        padding: const EdgeInsets.only(top: 24, bottom: 24),
        side: false,
        edge: 'none',
      ),
      (
        size: const Size(466, 678),
        padding: const EdgeInsets.only(right: 84, bottom: 34),
        side: true,
        edge: 'right',
      ),
      (
        size: const Size(844, 500),
        padding: const EdgeInsets.only(left: 84, bottom: 21),
        side: true,
        edge: 'left',
      ),
    ]) {
      tester.view.physicalSize = scenario.size;
      isDuoDevice = scenario.side;
      systemAdaptivePhone = scenario.side;
      systemVerticalEdge = scenario.edge;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: scenario.size,
              padding: scenario.padding,
              viewPadding: scenario.padding,
            ),
            child: const RootPage(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      final card = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_UpcomingCourseQuote',
      );
      expect(card, findsOneWidget);
      await tester.ensureVisible(card);
      await tester.pump();
      final cardRect = tester.getRect(card);

      if (scenario.side) {
        expect(
          cardRect.bottom,
          closeTo(scenario.size.height - scenario.padding.bottom, 1),
        );
      } else {
        final navigation = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_SlidingNavBar',
        );
        final bar = find
            .descendant(of: navigation, matching: find.byType(ClipRRect))
            .first;
        expect(bar, findsOneWidget);
        expect(tester.getRect(bar).top - cardRect.bottom, closeTo(18, 1));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
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
