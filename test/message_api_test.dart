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

  test('reports unread messages when any category has an unread count', () {
    expect(
      MessageApi.hasUnreadIn([
        MessageCategory(appId: 'a', appName: 'A', tagId: 1),
        MessageCategory(appId: 'b', appName: 'B', tagId: 2, unReadMsgCount: 1),
      ]),
      isTrue,
    );
    expect(
      MessageApi.hasUnreadIn([
        MessageCategory(appId: 'a', appName: 'A', tagId: 1),
      ]),
      isFalse,
    );
  });
}
