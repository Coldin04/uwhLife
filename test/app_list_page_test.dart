import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uwhlife/features/apps/app_list_page.dart';
import 'package:uwhlife/features/apps/models/app_entry.dart';

void main() {
  testWidgets('app categories are presented with a page view', (tester) async {
    await _pumpAppList(tester);

    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.text('教务'));
    await tester.pumpAndSettle();

    expect(find.text('座位预约'), findsOneWidget);
    expect(find.text('消费账单'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('消费账单'), findsOneWidget);
    expect(find.text('座位预约'), findsNothing);
  });
}

Future<void> _pumpAppList(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AppListPage(onOpenApp: (AppEntry app) {})),
    ),
  );
  for (var i = 0; i < 20 && find.byType(PageView).evaluate().isEmpty; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
