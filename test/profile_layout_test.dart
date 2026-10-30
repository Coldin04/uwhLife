import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/features/profile/profile_page.dart';

void main() {
  testWidgets('profile applies the top safe area only once', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});

    Future<double> avatarTop(double topInset) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 1000),
              padding: EdgeInsets.fromLTRB(0, topInset, 80, 34),
            ),
            child: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未登录'), findsOneWidget);
      return tester.getTopLeft(find.byType(CircleAvatar)).dy;
    }

    final noTopInset = await avatarTop(0);
    final withTopInset = await avatarTop(60);
    expect(withTopInset - noTopInset, 60);
  });
}
