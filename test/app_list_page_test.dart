import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uwhlife/features/apps/app_list_page.dart';
import 'package:uwhlife/features/apps/models/app_entry.dart';

void main() {
  // rootBundle 会把 loadString 的 Future 连同它所在的 fake-async 时区一起缓存下来，
  // 下一个用例 await 到的就是上一个用例（已经结束）时区里的 Future，永远不会完成，
  // 页面会一直卡在 loading。每个用例前清一次缓存。
  setUp(rootBundle.clear);

  testWidgets('app categories are presented with a page view', (tester) async {
    await _pumpAppList(tester);

    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.text('教务'));
    await tester.pumpAndSettle();

    expect(find.text('座位预约'), findsOneWidget);
    expect(find.text('消费账单'), findsNothing);

    // 页面已占满屏宽，拖动距离要明确超过半页才会翻页。
    await tester.drag(find.byType(PageView), const Offset(700, 0));
    await tester.pumpAndSettle();

    expect(find.text('消费账单'), findsOneWidget);
    expect(find.text('座位预约'), findsNothing);
  });

  // 分类结果改成加载时一次性分好组、搜索结果改成输入变化时才算，
  // 这两条锁住「切分类 / 搜索 / 清空搜索」拿到的还是原来那批应用。
  // 注意：输入框一拿到焦点光标就一直在闪，pumpAndSettle 永远等不到静止，
  // 所以这里都用有界的 pump。
  testWidgets('searching filters across every category', (tester) async {
    await _pumpAppList(tester);
    expect(find.byType(TextField), findsNothing);

    await _openSearch(tester);
    expect(find.byType(TextField), findsOneWidget);

    await _search(tester, '座位');

    expect(find.byType(PageView), findsNothing);
    expect(find.text('座位预约'), findsOneWidget);
    expect(find.text('消费账单'), findsNothing);

    await _search(tester, '不存在的应用');
    expect(find.text('没有匹配的应用'), findsOneWidget);
  });

  testWidgets('clearing the search restores category paging', (tester) async {
    await _pumpAppList(tester);

    await _openSearch(tester);
    await _search(tester, '座位');
    expect(find.byType(PageView), findsNothing);
    expect(find.text('座位预约'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();

    // 返回关闭搜索后，分类分页回来，并且还是原来那批应用（「全部」页第一屏）。
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('消费账单'), findsOneWidget);
  });

  testWidgets('clearing the search keeps the selected category', (
    tester,
  ) async {
    await _pumpAppList(tester);

    await tester.tap(find.text('教务'));
    await tester.pumpAndSettle();
    expect(find.text('座位预约'), findsOneWidget);

    await _openSearch(tester);
    await _search(tester, '座位');
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();

    // 关闭搜索要回到原来那个分类，而不是悄悄跳回「全部」——
    // 跳回去的话内容是「全部」、下划线还在「教务」，两边对不上。
    expect(find.text('座位预约'), findsOneWidget);
    expect(find.text('消费账单'), findsNothing);
  });

  testWidgets('reselecting the tab returns to all apps on the second tap', (
    tester,
  ) async {
    final key = GlobalKey<AppListPageState>();
    await _pumpAppList(tester, key: key);

    await tester.tap(find.text('教务'));
    await tester.pumpAndSettle();
    expect(find.text('座位预约'), findsOneWidget);

    key.currentState!.handleTabReselect();
    await tester.pump();
    expect(find.text('座位预约'), findsOneWidget);

    key.currentState!.handleTabReselect();
    await tester.pumpAndSettle();
    expect(find.text('消费账单'), findsOneWidget);
    expect(find.text('座位预约'), findsNothing);
  });

  testWidgets('search waits for idle input and closes on system back', (
    tester,
  ) async {
    await _pumpAppList(tester);
    await _openSearch(tester);

    expect(find.text('消费账单'), findsNothing);
    expect(find.text('座位预约'), findsNothing);

    await tester.enterText(find.byType(TextField), '座位');
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('座位预约'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('座位预约'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TextField), findsNothing);
  });
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(find.byTooltip('搜索应用'));
  await tester.pump();
}

Future<void> _pumpAppList(WidgetTester tester, {Key? key}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppListPage(key: key, onOpenApp: (AppEntry app) {}),
      ),
    ),
  );
  for (var i = 0; i < 20 && find.byType(PageView).evaluate().isEmpty; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
