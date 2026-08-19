import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/home_page_settings.dart';

void main() {
  test('home icon-only mode defaults off and persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    expect((await HomePageSettings.read()).iconOnlyMode, isFalse);

    await const HomePageSettings(iconOnlyMode: true).save();

    expect((await HomePageSettings.read()).iconOnlyMode, isTrue);
  });
}
