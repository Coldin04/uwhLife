import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/portal_user_store.dart';

void main() {
  test('saves profile fields from a JSON-encoded portal response', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final saved = await PortalUserStore.saveFromLoginUserResponse(
      '"{\\"data\\":{\\"userName\\":\\"测试同学\\",\\"userAccount\\":\\"20260001\\",\\"categoryName\\":\\"学生\\",\\"orgs\\":[{\\"name\\":\\"软件工程 1 班\\"}]}}"',
    );

    expect(saved, isTrue);
    expect(await PortalUserStore.read(), (
      userName: '测试同学',
      userAccount: '20260001',
      categoryName: '学生',
      className: '软件工程 1 班',
    ));
  });
}
