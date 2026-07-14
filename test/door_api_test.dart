import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/auth/ids_http_auth.dart';
import 'package:uwhlife/features/door/door_api.dart';

void main() {
  group('DoorAspNetForm', () {
    test('parses the ASP.NET state and image-button coordinates', () {
      const html = '''
        <form id="aspnetForm" method="post" action="./Default.aspx">
          <input type="hidden" name="__VIEWSTATE" value="view-state" />
          <input type="hidden" name="__VIEWSTATEGENERATOR" value="generator" />
          <input type="image" name="ctl00\$btnOpen" id="ctl00_btnOpen" />
        </form>
      ''';

      final form = DoorAspNetForm.parse(
        html,
        Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx'),
      );

      expect(form, isNotNull);
      expect(
        form!.submitUri.toString(),
        'http://opendoor.uwh.edu.cn:46010/Default.aspx',
      );
      expect(form.openFields['__VIEWSTATE'], 'view-state');
      expect(form.openFields['__VIEWSTATEGENERATOR'], 'generator');
      expect(form.openFields['ctl00\$btnOpen.x'], '1');
      expect(form.openFields['ctl00\$btnOpen.y'], '1');
    });

    test('rejects a page without view state or the open image button', () {
      final uri = Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx');

      expect(
        DoorAspNetForm.parse('<form id="aspnetForm"></form>', uri),
        isNull,
      );
    });

    test('reads the server result label', () {
      expect(
        DoorAspNetForm.readResultMessage(
          '<span id="ctl00_lblInfo">开门请求已处理</span>',
        ),
        '开门请求已处理',
      );
    });
  });

  test('imports browser cookies without leaking them to another host', () {
    final jar = HttpCookieJar();
    final ids = Uri.https('ids.uwh.edu.cn', '/authserver/login');
    final door = Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx');

    jar.addCookieHeader(ids, 'CASTGC=dummy-ticket; route=dummy-route');

    expect(jar.cookieHeaderFor(ids), contains('CASTGC=dummy-ticket'));
    expect(jar.cookieHeaderFor(door), isEmpty);
  });
}
