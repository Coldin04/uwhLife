import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uwhlife/core/storage/boundary_debug_settings.dart';
import 'package:uwhlife/features/profile/profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfoPlatform.instance = _FakePackageInfoPlatform();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets(
    'version taps show and hide testing page without resetting location values',
    (tester) async {
      await BoundaryDebugSettings.defaults
          .copyWith(
            enabled: true,
            menuVisible: false,
            longitudeBd09: 120.12345,
            latitudeBd09: 30.54321,
            address: '自定义地址',
            city: '自定义城市',
          )
          .save();

      await _pumpProfile(tester);
      await tester.tap(find.text('关于'));
      await tester.pumpAndSettle();

      await _tapVersionTimes(tester, 10);
      var settings = await BoundaryDebugSettings.read();
      expect(settings.menuVisible, isTrue);
      expect(settings.enabled, isFalse);
      expect(settings.longitudeBd09, 120.12345);
      expect(settings.latitudeBd09, 30.54321);
      expect(settings.address, '自定义地址');
      expect(settings.city, '自定义城市');

      await _tapVersionTimes(tester, 10);
      settings = await BoundaryDebugSettings.read();
      expect(settings.menuVisible, isFalse);
      expect(settings.enabled, isFalse);
      expect(settings.longitudeBd09, 120.12345);
      expect(settings.latitudeBd09, 30.54321);
      expect(settings.address, '自定义地址');
      expect(settings.city, '自定义城市');
    },
  );

  testWidgets('testing page row is hidden until version taps enable it', (
    tester,
  ) async {
    await BoundaryDebugSettings.defaults
        .copyWith(enabled: true, menuVisible: false)
        .save();

    await _pumpProfile(tester);
    expect(find.text('测试与调试'), findsNothing);

    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    await _tapVersionTimes(tester, 10);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('测试与调试'), findsOneWidget);
  });

  testWidgets(
    'long pressing about resets defaults only while boundary debug is enabled',
    (tester) async {
      await BoundaryDebugSettings.defaults
          .copyWith(
            enabled: true,
            menuVisible: false,
            longitudeBd09: 120.12345,
            latitudeBd09: 30.54321,
            address: '自定义地址',
            city: '自定义城市',
          )
          .save();

      await _pumpProfile(tester);
      await tester.longPress(find.text('关于'));
      await tester.pumpAndSettle();

      var settings = await BoundaryDebugSettings.read();
      expect(settings.menuVisible, isFalse);
      expect(settings.enabled, isTrue);
      expect(settings.longitudeBd09, 120.12345);
      expect(settings.latitudeBd09, 30.54321);
      expect(settings.address, '自定义地址');
      expect(settings.city, '自定义城市');

      await settings.copyWith(enabled: false, menuVisible: true).save();
      await _pumpProfile(tester);
      await tester.longPress(find.text('关于'));
      await tester.pumpAndSettle();

      settings = await BoundaryDebugSettings.read();
      expect(settings.menuVisible, isTrue);
      expect(settings.enabled, isFalse);
      expect(settings.longitudeBd09, 120.12345);
      expect(settings.latitudeBd09, 30.54321);
      expect(settings.address, '自定义地址');
      expect(settings.city, '自定义城市');

      await settings.copyWith(enabled: true, menuVisible: true).save();
      await _pumpProfile(tester);
      await tester.longPress(find.text('关于'));
      await tester.pumpAndSettle();

      settings = await BoundaryDebugSettings.read();
      expect(settings.menuVisible, isTrue);
      expect(settings.enabled, BoundaryDebugSettings.defaults.enabled);
      expect(
        settings.longitudeBd09,
        BoundaryDebugSettings.defaults.longitudeBd09,
      );
      expect(
        settings.latitudeBd09,
        BoundaryDebugSettings.defaults.latitudeBd09,
      );
      expect(settings.address, BoundaryDebugSettings.defaults.address);
      expect(settings.city, BoundaryDebugSettings.defaults.city);
    },
  );

  testWidgets('profile page leaves the root gradient visible', (tester) async {
    await _pumpProfile(tester);

    expect(
      find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.gradient is LinearGradient;
      }),
      findsNothing,
    );
  });
}

Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ProfilePage())),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVersionTimes(WidgetTester tester, int count) async {
  final versionFinder = find.textContaining('版本');
  expect(versionFinder, findsOneWidget);
  for (var i = 0; i < count; i += 1) {
    await tester.tap(versionFinder);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _FakePackageInfoPlatform extends PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    return PackageInfoData(
      appName: '芜忧皖江',
      packageName: 'com.cold04.uwhlife',
      version: '1.1.4',
      buildNumber: '9',
      buildSignature: '',
    );
  }
}
