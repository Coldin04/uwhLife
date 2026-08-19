import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/core/theme/app_theme.dart';

void main() {
  testWidgets('app dialogs blur the background behind alert content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAppDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认操作'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              child: const Text('打开弹窗'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹窗'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
