import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/webview/webview_overlays.dart';

Widget _capsule({required Brightness theme, bool onDarkBackground = false}) {
  return MaterialApp(
    theme: ThemeData(brightness: theme),
    home: Scaffold(
      body: Center(
        child: MiniProgramCapsule(
          onRefresh: () {},
          onOpenInBrowser: () {},
          onClose: () {},
          onDarkBackground: onDarkBackground,
        ),
      ),
    ),
  );
}

Widget _topBar({required Brightness theme}) {
  return MaterialApp(
    theme: ThemeData(brightness: theme),
    home: Scaffold(
      body: WebViewTopBar(
        topInset: 24,
        onBack: () {},
        onRefresh: () {},
        onOpenInBrowser: () {},
        onClose: () {},
      ),
    ),
  );
}

/// 控件自己那层 Material 的底色（深度优先的第一个）。
Color _backgroundOf(WidgetTester tester, Finder scope) {
  return tester
      .widget<Material>(
        find.descendant(of: scope, matching: find.byType(Material)).first,
      )
      .color!;
}

Future<Color> _openMenuIconColor(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded));
  await tester.pumpAndSettle();
  return tester.widget<Icon>(find.byIcon(Icons.refresh_rounded)).color!;
}

void main() {
  group('MiniProgramCapsule', () {
    testWidgets('opens a menu with refresh and open-in-browser', (
      tester,
    ) async {
      var refreshed = 0;
      var openedInBrowser = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniProgramCapsule(
                onRefresh: () => refreshed += 1,
                onOpenInBrowser: () => openedInBrowser += 1,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      // 胶囊上只有「更多」和「关闭」，刷新收进菜单里。
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('在浏览器中打开'), findsOneWidget);

      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(refreshed, 1);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在浏览器中打开'));
      await tester.pumpAndSettle();
      expect(openedInBrowser, 1);
    });

    testWidgets('stays light on a light page even in dark mode', (
      tester,
    ) async {
      await tester.pumpWidget(_capsule(theme: Brightness.dark));

      expect(
        _backgroundOf(
          tester,
          find.byType(MiniProgramCapsule),
        ).computeLuminance(),
        greaterThan(0.5),
      );
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.close_rounded))
            .color!
            .computeLuminance(),
        lessThan(0.1),
      );
      // 菜单跟着胶囊走，不跟 App 主题走。
      expect(
        (await _openMenuIconColor(tester)).computeLuminance(),
        lessThan(0.1),
      );
    });

    testWidgets('turns dark on a dark page even in light mode', (tester) async {
      await tester.pumpWidget(
        _capsule(theme: Brightness.light, onDarkBackground: true),
      );

      expect(
        _backgroundOf(
          tester,
          find.byType(MiniProgramCapsule),
        ).computeLuminance(),
        lessThan(0.1),
      );
      expect(
        tester
            .widget<Icon>(find.byIcon(Icons.close_rounded))
            .color!
            .computeLuminance(),
        greaterThan(0.5),
      );
      expect(
        (await _openMenuIconColor(tester)).computeLuminance(),
        greaterThan(0.9),
      );
    });
  });

  group('WebViewTopBar', () {
    testWidgets('has no title and keeps the same menu actions', (tester) async {
      var refreshed = 0;
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WebViewTopBar(
              topInset: 24,
              onBack: () {},
              onRefresh: () => refreshed += 1,
              onOpenInBrowser: () {},
              onClose: () => closed += 1,
            ),
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(refreshed, 1);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('is light under the light theme', (tester) async {
      await tester.pumpWidget(_topBar(theme: Brightness.light));

      expect(
        _backgroundOf(tester, find.byType(WebViewTopBar)).computeLuminance(),
        greaterThan(0.9),
      );
      expect(
        (await _openMenuIconColor(tester)).computeLuminance(),
        lessThan(0.1),
      );
    });

    testWidgets('is dark under the dark theme', (tester) async {
      await tester.pumpWidget(_topBar(theme: Brightness.dark));

      expect(
        _backgroundOf(tester, find.byType(WebViewTopBar)).computeLuminance(),
        lessThan(0.1),
      );
      expect(
        (await _openMenuIconColor(tester)).computeLuminance(),
        greaterThan(0.9),
      );
    });
  });
}
