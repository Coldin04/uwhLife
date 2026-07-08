import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/message/message_api.dart';

void main() {
  group('MessageApi warmup', () {
    test('waits for cookies only after the app config refresh finishes', () {
      expect(
        MessageApi.isWarmUpCookieRefreshUrl(
          'https://ehall.uwh.edu.cn/message_pocket_web/inboxpc/pc.html#/messageDetail',
        ),
        isFalse,
      );

      expect(
        MessageApi.isWarmUpCookieRefreshUrl(
          'https://ehall.uwh.edu.cn/message_pocket_web/user/app?searchContent=',
        ),
        isTrue,
      );
    });

    test('keeps set-cookie headers needed for native browser storage', () {
      expect(
        MessageApi.cookieHeadersForBrowserStore([
          'mcsessionid=abc; Path=/message_pocket_web/; HttpOnly',
          '',
          'route=server1; Path=/',
        ]),
        [
          'mcsessionid=abc; Path=/message_pocket_web/; HttpOnly',
          'route=server1; Path=/',
        ],
      );
    });

    test('merges native and response cookies for redirect requests', () {
      expect(
        MessageApi.cookiesForRedirectRequest(
          nativeCookies: 'MOD_AUTH_CAS=portal',
          responseCookieHeaders: [
            'mcsessionid=message; Path=/message_pocket_web/; HttpOnly',
            'route=node1; Path=/',
          ],
        ),
        'MOD_AUTH_CAS=portal; mcsessionid=message; route=node1',
      );
    });
  });
}
