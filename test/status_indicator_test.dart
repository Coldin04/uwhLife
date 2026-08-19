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

  testWidgets('shows the logged-out status button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusIndicator(status: LoginStatus.loggedOut)),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
  });
}
