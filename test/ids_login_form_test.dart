import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_login_form.dart';

void main() {
  test(
    'recognizes an IDS login page only when both credential fields exist',
    () {
      expect(
        isIdsLoginForm(
          url: 'https://ids.uwh.edu.cn/authserver/login?service=ehall',
          body: '<input id="username"><input type="password">',
        ),
        isTrue,
      );
      expect(
        isIdsLoginForm(
          url: 'https://ids.uwh.edu.cn/authserver/login?service=ehall',
          body: '<input id="username">',
        ),
        isFalse,
      );
      expect(
        isIdsLoginForm(
          url: 'https://ehall.uwh.edu.cn/authserver/login',
          body: '<input id="username"><input id="password">',
        ),
        isFalse,
      );
    },
  );
}
