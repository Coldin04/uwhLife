import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uwhlife/features/home/widgets/status_indicator.dart';

void main() {
  testWidgets('hides the indicator when status is logged in', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusIndicator(status: LoginStatus.loggedIn)),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('shows the red indicator when status is logged out', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusIndicator(status: LoginStatus.loggedOut)),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    final redDot = tester.widget<Container>(
      find.descendant(
        of: find.byType(InkWell),
        matching: find.byWidgetPredicate((widget) {
          return widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).color ==
                  const Color(0xFFD44848);
        }),
      ),
    );
    expect((redDot.decoration! as BoxDecoration).shape, BoxShape.circle);
  });
}
