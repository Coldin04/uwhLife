import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/platform/browser_data_cleaner.dart';
import 'models/schedule_models.dart';

class ScheduleApi {
  static const _host = 'ehall.uwh.edu.cn';
  static final Uri _landingUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/*default/index.do',
    const <String, String>{'EMAP_LANG': 'zh'},
  );
  static final Uri _idsBootstrapUri = Uri.https(
    'ids.uwh.edu.cn',
    '/authserver/login',
    <String, String>{'service': _landingUri.toString()},
  );
  static final Uri _setRoleUri = Uri.https(
    _host,
    '/jwapp/sys/jwpubapp/pub/setJwCommonAppRole.do',
  );
  static final Uri _termUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do',
  );
  static final Uri _termsUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/jshkcb/xnxqcx.do',
  );
  static final Uri _lessonTimeUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/jshkcb/jc.do',
  );
  static final Uri _currentWeekUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/jshkcb/dqzc.do',
  );
  static final Uri _termCalendarUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/xskcb/cxxljc.do',
  );
  static final Uri _scheduleUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/xskcb/cxxszhxqkb.do',
  );
  static final Uri _onlineCoursesUri = Uri.https(
    _host,
    '/jwapp/sys/wdkb/modules/xskcb/xswpkc.do',
  );

  static Future<ScheduleData> fetchCurrentSchedule() {
    return fetchSchedule();
  }

  static Future<ScheduleData> fetchSchedule({String? termCode}) async {
    final client = _ScheduleHttpClient(
      nativeCookieHosts: const <String>{'ids.uwh.edu.cn'},
    );
    try {
      // The portal session alone can produce an empty pageMeta role. Start at
      // the IDS service endpoint so it issues a fresh ticket for the course
      // schedule application, matching the browser's SSO redirect chain.
      final landing = await client.getText(_idsBootstrapUri);
      final landingHtml = landing.body;
      var roleId = roleIdFromLandingPage(landingHtml);
      if (roleId == null) {
        final appId = appIdFromLandingPage(landingHtml);
        debugPrint(
          '[ScheduleApi] landing config: appId='
          '${appId == null ? 'absent' : 'present'}',
        );
        if (appId == null) {
          return _throwMissingRole(landing, landingHtml);
        }

        final configUri = Uri.https(
          _host,
          '/jwapp/sys/funauthapp/api/getAppConfig/wdkb-$appId.do',
        );
        roleId = roleIdFromAppConfig(await client.getAppConfig(configUri));
        debugPrint(
          '[ScheduleApi] app config: activeRole='
          '${roleId == null ? 'absent' : 'present'}',
        );
      }
      if (roleId == null) {
        return _throwMissingRole(landing, landingHtml);
      }

      await client.postJson(_setRoleUri, <String, String>{'ROLEID': roleId});
      final currentTerm = _parseTerm(await client.postJson(_termUri));
      final availableTerms = termsFromResponse(
        await client.postJson(_termsUri, const <String, String>{
          '*order': '-DM',
        }),
      );
      final baseTerm = _selectTerm(
        requestedCode: termCode,
        currentTerm: currentTerm,
        availableTerms: availableTerms,
      );
      final calendar = _parseTermCalendar(
        await client.postJson(_termCalendarUri, _termCalendarForm(baseTerm)),
      );
      final term = baseTerm.copyWith(
        startDate: calendar.startDate,
        totalWeeks: calendar.totalWeeks,
      );
      final currentWeek = baseTerm.code == currentTerm.code
          ? term.clampWeek(
              _parseCurrentWeek(
                await client.postJson(
                  _currentWeekUri,
                  _currentWeekForm(baseTerm, DateTime.now()),
                ),
              ),
            )
          : 1;
      final lessonTimes = _parseLessonTimes(
        await client.postJson(_lessonTimeUri),
      );
      final courses = _parseCourses(
        await client.postJson(_scheduleUri, <String, String>{
          'XNXQDM': term.code,
        }),
      );
      final onlineCourses = _parseOnlineCourses(
        await client.postJson(_onlineCoursesUri, <String, String>{
          'XNXQDM': term.code,
        }),
      );

      return ScheduleData(
        term: term,
        lessonTimes: lessonTimes,
        courses: courses,
        currentWeek: currentWeek,
        onlineCourses: onlineCourses,
        availableTerms: availableTerms,
        isCurrentTerm: baseTerm.code == currentTerm.code,
      );
    } on SocketException {
      throw const ScheduleApiException('网络连接失败');
    } on HttpException catch (error) {
      throw ScheduleApiException(error.message);
    } on FormatException {
      throw const ScheduleApiException('教务系统返回的数据格式异常');
    } finally {
      client.close();
    }
  }

  static String? roleIdFromLandingPage(String page) {
    final normalized = page
        .replaceAll('&quot;', '"')
        .replaceAll('&#34;', '"')
        .replaceAll('&#x22;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    final document = html_parser.parse(page);
    for (final script in document.querySelectorAll('script')) {
      final roleId = _roleIdFromText(script.text);
      if (roleId != null) return roleId;
    }

    return _roleIdFromText(normalized);
  }

  static String? appIdFromLandingPage(String page) {
    final match = RegExp(
      r'''["']?(?:appId|app_id|appid)["']?\s*[:=]\s*(?:["']([^"']+)["']|([A-Za-z0-9_-]+))''',
      caseSensitive: false,
    ).firstMatch(page);
    final appId = (match?.group(1) ?? match?.group(2))?.trim();
    return appId?.isNotEmpty == true ? appId : null;
  }

  static String? roleIdFromAppConfig(Map<String, dynamic> config) {
    final header = config['HEADER'];
    if (header is! Map) return null;
    final dropMenu = header['dropMenu'];
    if (dropMenu is! List) return null;

    String? firstRoleId;
    for (final item in dropMenu.whereType<Map>()) {
      final roleId = item['id']?.toString().trim();
      if (roleId == null || roleId.isEmpty) continue;
      firstRoleId ??= roleId;
      if (_isActiveRole(item['active'])) return roleId;
    }
    return firstRoleId;
  }

  static List<ScheduleTerm> termsFromResponse(Map<String, dynamic> response) {
    return _rows(response, 'xnxqcx')
        .map(
          (row) => ScheduleTerm(
            code: _text(row['DM']),
            name: _text(row['MC'], fallback: _text(row['DM'])),
          ),
        )
        .where((term) => term.code.isNotEmpty)
        .toList();
  }

  static bool _isActiveRole(Object? value) {
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true';
  }

  static Never _throwMissingRole(
    _ScheduleResponse landing,
    String landingHtml,
  ) {
    debugPrint(
      '[ScheduleApi] landing page: host=${landing.uri.host}, '
      'path=${landing.uri.path}, pageMeta=${landingHtml.contains('pageMeta')}, '
      'roleId=${landingHtml.contains('ROLEID')}, '
      'roleShape=${_roleIdShape(landingHtml)}, '
      'login=${_looksLikeLoginPage(landingHtml)}',
    );
    if (_looksLikeLoginPage(landingHtml)) {
      throw const ScheduleAuthenticationException('教务系统登录态已失效，请重新登录统一门户');
    }
    throw const ScheduleApiException('课表初始化页未返回教务角色，请重新登录统一门户后重试');
  }

  static String? _roleIdFromText(String text) {
    final directMatches = RegExp(
      r'''["']?ROLEID["']?\s*:\s*["']([^"']+)["']''',
    ).allMatches(text);
    final directRoleId = _firstNonEmptyRoleId(directMatches);
    if (directRoleId != null) return directRoleId;

    final fallbackMatches = RegExp(
      r'''ROLEID\s*==\s*["']{2}\s*\?\s*["']([^"']+)["']''',
    ).allMatches(text);
    return _firstNonEmptyRoleId(fallbackMatches);
  }

  static String? _firstNonEmptyRoleId(Iterable<RegExpMatch> matches) {
    for (final match in matches) {
      final value = match.group(1)?.trim();
      if (value?.isNotEmpty == true) return value;
    }
    return null;
  }

  static String _roleIdShape(String text) {
    final directMatches = RegExp(
      r'''["']?ROLEID["']?\s*:\s*["']([^"']*)["']''',
    ).allMatches(text);
    final fallbackMatches = RegExp(
      r'''ROLEID\s*==\s*["']{2}\s*\?\s*["']([^"']*)["']''',
    ).allMatches(text);
    String shapeOf(Iterable<RegExpMatch> matches) {
      var found = false;
      for (final match in matches) {
        found = true;
        if (match.group(1)?.trim().isNotEmpty == true) return 'present';
      }
      return found ? 'empty' : 'absent';
    }

    return 'direct:${shapeOf(directMatches)},'
        'fallback:${shapeOf(fallbackMatches)}';
  }

  static bool _looksLikeLoginPage(String page) {
    final lower = page.toLowerCase();
    return lower.contains('/authserver/login') ||
        lower.contains('pwdfromid') ||
        lower.contains('统一身份认证');
  }

  static ScheduleTerm _parseTerm(Map<String, dynamic> response) {
    final rows = _rows(response, 'dqxnxq');
    if (rows.isEmpty) throw const FormatException('No current term');
    final row = rows.first;
    final code = _text(row['DM']);
    if (code.isEmpty) throw const FormatException('Missing term code');
    return ScheduleTerm(
      code: code,
      name: _text(row['MC'], fallback: code),
      startDate: _date(row['QSSYRQ']),
      endDate: _date(row['ZZSYRQ']),
    );
  }

  static ScheduleTerm _selectTerm({
    required String? requestedCode,
    required ScheduleTerm currentTerm,
    required List<ScheduleTerm> availableTerms,
  }) {
    if (availableTerms.every((term) => term.code != currentTerm.code)) {
      availableTerms.insert(0, currentTerm);
    }
    if (requestedCode == null || requestedCode.isEmpty) return currentTerm;
    for (final term in availableTerms) {
      if (term.code == requestedCode) return term;
    }
    throw const ScheduleApiException('所选学期不可用，请重新选择');
  }

  static Map<String, String> _termCalendarForm(ScheduleTerm term) {
    final parts = term.code.split('-');
    if (parts.length < 3 || parts[0].isEmpty || parts[1].isEmpty) {
      throw const FormatException('Invalid term code');
    }
    return <String, String>{'XN': '${parts[0]}-${parts[1]}', 'XQ': parts.last};
  }

  static Map<String, String> _currentWeekForm(
    ScheduleTerm term,
    DateTime date,
  ) {
    return <String, String>{
      ..._termCalendarForm(term),
      'RQ': '${date.year}-${date.month}-${date.day}',
    };
  }

  static int _parseCurrentWeek(Map<String, dynamic> response) {
    final rows = _rows(response, 'dqzc');
    if (rows.isEmpty) throw const FormatException('No current week');
    final currentWeek = _number(rows.first['ZC']);
    if (currentWeek <= 0) throw const FormatException('Missing current week');
    return currentWeek;
  }

  static _TermCalendar _parseTermCalendar(Map<String, dynamic> response) {
    final rows = _rows(response, 'cxxljc');
    if (rows.isEmpty) throw const FormatException('No term calendar');
    final row = rows.first;
    final totalWeeks = _number(row['ZZC']);
    if (totalWeeks <= 0) throw const FormatException('Missing total weeks');
    return _TermCalendar(
      startDate: _date(row['XQKSRQ']),
      totalWeeks: totalWeeks,
    );
  }

  static List<ScheduleLessonTime> _parseLessonTimes(
    Map<String, dynamic> response,
  ) {
    final lessonTimes = _rows(response, 'jc')
        .map(
          (row) => ScheduleLessonTime(
            period: _number(row['DM']),
            startTime: _time(row['KSSJ']),
            endTime: _time(row['JSSJ']),
          ),
        )
        .where((lessonTime) => lessonTime.period > 0)
        .toList();
    lessonTimes.sort((a, b) => a.period.compareTo(b.period));
    return lessonTimes;
  }

  static List<ScheduleCourse> _parseCourses(Map<String, dynamic> response) {
    return _rows(response, 'cxxszhxqkb')
        .map(ScheduleCourse.fromJson)
        .where(
          (course) =>
              course.weekday >= 1 &&
              course.weekday <= 7 &&
              course.startPeriod > 0 &&
              course.endPeriod >= course.startPeriod &&
              course.weekBitmap.isNotEmpty,
        )
        .toList();
  }

  static List<ScheduleOnlineCourse> _parseOnlineCourses(
    Map<String, dynamic> response,
  ) {
    return _rows(response, 'xswpkc')
        .map(ScheduleOnlineCourse.fromJson)
        .where((course) => course.name.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _rows(
    Map<String, dynamic> response,
    String key,
  ) {
    final datas = response['datas'];
    if (datas is! Map) throw const FormatException('Missing datas');
    final table = datas[key];
    if (table is! Map) throw FormatException('Missing $key');
    final rows = table['rows'];
    if (rows is! List) throw FormatException('Missing $key rows');
    return rows.whereType<Map>().map(_stringKeyedMap).toList();
  }

  static Map<String, dynamic> _stringKeyedMap(Map map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _number(Object? value) {
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _time(Object? value) {
    final raw = _text(value);
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(raw);
    return match?.group(1) ?? raw;
  }

  static DateTime? _date(Object? value) {
    final raw = _text(value);
    final match = RegExp(r'\d{4}-\d{1,2}-\d{1,2}').firstMatch(raw);
    return match == null ? null : DateTime.tryParse(match.group(0)!);
  }
}

class _ScheduleHttpClient {
  static const _desktopUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:152.0) '
      'Gecko/20100101 Firefox/152.0';
  static const _documentAccept =
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
  static const _ajaxAccept = 'application/json, text/javascript, */*; q=0.01';
  static const _acceptLanguage =
      'zh-CN,zh;q=0.9,zh-TW;q=0.8,zh-HK;q=0.7,en-US;q=0.6,en;q=0.5';

  _ScheduleHttpClient({required Set<String> nativeCookieHosts})
    : _nativeCookieHosts = nativeCookieHosts
          .map((host) => host.toLowerCase())
          .toSet();

  final HttpClient _client = HttpClient();
  final _CookieJar _cookies = _CookieJar();
  final Set<String> _nativeCookieHosts;

  Future<_ScheduleResponse> getText(Uri uri) async {
    return _requestFollowing(uri, method: 'GET');
  }

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    final response = await _requestFollowing(uri, method: 'GET');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid JSON response');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, dynamic>> getAppConfig(Uri uri) async {
    final response = await _requestFollowing(
      uri,
      method: 'GET',
      requestType: _ScheduleRequestType.appConfig,
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid JSON response');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, dynamic>> postJson(
    Uri uri, [
    Map<String, String> form = const <String, String>{},
  ]) async {
    final response = await _requestFollowing(uri, method: 'POST', form: form);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid JSON response');
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<_ScheduleResponse> _requestFollowing(
    Uri uri, {
    required String method,
    Map<String, String>? form,
    _ScheduleRequestType requestType = _ScheduleRequestType.document,
  }) async {
    var nextUri = uri;
    var nextMethod = method;
    Map<String, String>? nextForm = form;
    var nextRequestType = requestType;

    for (var redirectCount = 0; redirectCount < 8; redirectCount += 1) {
      final response = await _request(
        nextUri,
        method: nextMethod,
        form: nextForm,
        requestType: nextRequestType,
      );
      debugPrint(
        '[ScheduleApi] $nextMethod ${nextUri.host}${nextUri.path} '
        '-> ${response.statusCode}',
      );
      if (response.statusCode < 300 || response.statusCode >= 400) {
        await BrowserDataCleaner.persistCookies();
        return response;
      }

      final location = response.location;
      if (location == null || location.isEmpty) {
        throw const HttpException('教务系统登录跳转异常');
      }
      nextUri = nextUri.resolve(location);
      nextMethod = 'GET';
      nextForm = null;
      nextRequestType = _ScheduleRequestType.document;
    }

    throw const HttpException('教务系统登录跳转次数过多');
  }

  Future<_ScheduleResponse> _request(
    Uri uri, {
    required String method,
    Map<String, String>? form,
    required _ScheduleRequestType requestType,
  }) async {
    await _addNativeCookies(uri);
    final request = await _client.openUrl(method, uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.userAgentHeader, _desktopUserAgent);
    request.headers.set(HttpHeaders.acceptLanguageHeader, _acceptLanguage);
    if (method == 'GET' && requestType == _ScheduleRequestType.appConfig) {
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.refererHeader, ScheduleApi._landingUri);
    } else if (method == 'GET') {
      request.headers.set(HttpHeaders.acceptHeader, _documentAccept);
      request.headers.set(
        HttpHeaders.refererHeader,
        'https://ehall.uwh.edu.cn/',
      );
    } else {
      request.headers.set(HttpHeaders.acceptHeader, _ajaxAccept);
      request.headers.set('Origin', 'https://ehall.uwh.edu.cn');
      request.headers.set(HttpHeaders.refererHeader, ScheduleApi._landingUri);
      request.headers.set('X-Requested-With', 'XMLHttpRequest');
    }
    final cookies = _cookies.headerFor(uri);
    if (cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookies);
    }

    if (form != null) {
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.write(
        form.entries
            .map(
              (entry) =>
                  '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
            )
            .join('&'),
      );
    }

    final response = await request.close();
    _cookies.save(uri, response.cookies);
    await _saveResponseCookiesToBrowser(uri, response.cookies);
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      all.addAll(chunk);
      return all;
    });
    final body = utf8.decode(bytes, allowMalformed: true);
    if (response.statusCode >= 400) {
      throw HttpException('教务系统请求失败（${response.statusCode}）');
    }
    return _ScheduleResponse(
      uri: uri,
      statusCode: response.statusCode,
      location: response.headers.value(HttpHeaders.locationHeader),
      body: body,
    );
  }

  Future<void> _addNativeCookies(Uri uri) async {
    if (!_nativeCookieHosts.contains(uri.host.toLowerCase())) {
      debugPrint('[ScheduleApi] native cookies skipped on ${uri.host}');
      return;
    }
    final cookies = await BrowserDataCleaner.getCookies(url: uri.toString());
    _cookies.addNativeCookies(uri, cookies);
    debugPrint(
      '[ScheduleApi] native cookies on ${uri.host}: '
      '${_CookieJar.cookieNames(cookies).join(',')}',
    );
  }

  Future<void> _saveResponseCookiesToBrowser(
    Uri uri,
    List<Cookie> cookies,
  ) async {
    if (cookies.isEmpty) return;
    await BrowserDataCleaner.setCookiesForUrl(
      url: uri.toString(),
      cookies: cookies
          .map(_CookieJar.asSetCookieHeader)
          .toList(growable: false),
    );
    debugPrint(
      '[ScheduleApi] response cookies on ${uri.host}: '
      '${cookies.map((cookie) => cookie.name).join(',')}',
    );
  }

  void close() {
    _client.close(force: true);
  }
}

enum _ScheduleRequestType { document, appConfig }

class _ScheduleResponse {
  const _ScheduleResponse({
    required this.uri,
    required this.statusCode,
    required this.location,
    required this.body,
  });

  final Uri uri;
  final int statusCode;
  final String? location;
  final String body;
}

class _TermCalendar {
  const _TermCalendar({required this.startDate, required this.totalWeeks});

  final DateTime? startDate;
  final int totalWeeks;
}

class _CookieJar {
  final Map<String, Map<String, String>> _valuesByDomain =
      <String, Map<String, String>>{};

  void addNativeCookies(Uri uri, String header) {
    final values = _valuesByDomain.putIfAbsent(
      uri.host.toLowerCase(),
      () => <String, String>{},
    );
    for (final item in header.split(';')) {
      final pair = item.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      values.putIfAbsent(pair.substring(0, separator).trim(), () => pair);
    }
  }

  static List<String> cookieNames(String header) {
    return header
        .split(';')
        .map((item) => item.trim().split('=').first.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  }

  static String asSetCookieHeader(Cookie cookie) {
    final parts = <String>['${cookie.name}=${cookie.value}'];
    if (cookie.path?.isNotEmpty == true) parts.add('Path=${cookie.path}');
    if (cookie.domain?.isNotEmpty == true) {
      parts.add('Domain=${cookie.domain}');
    }
    if (cookie.secure) parts.add('Secure');
    if (cookie.httpOnly) parts.add('HttpOnly');
    return parts.join('; ');
  }

  void save(Uri requestUri, List<Cookie> cookies) {
    for (final cookie in cookies) {
      final domain = (cookie.domain ?? requestUri.host)
          .toLowerCase()
          .replaceFirst(RegExp(r'^\.'), '');
      final values = _valuesByDomain.putIfAbsent(
        domain,
        () => <String, String>{},
      );
      if (cookie.expires != null && !cookie.expires!.isAfter(DateTime.now())) {
        values.remove(cookie.name);
      } else {
        values[cookie.name] = '${cookie.name}=${cookie.value}';
      }
    }
  }

  String headerFor(Uri uri) {
    final host = uri.host.toLowerCase();
    return _valuesByDomain.entries
        .where((entry) => host == entry.key || host.endsWith('.${entry.key}'))
        .expand((entry) => entry.value.values)
        .join('; ');
  }
}

class ScheduleApiException implements Exception {
  const ScheduleApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScheduleAuthenticationException extends ScheduleApiException {
  const ScheduleAuthenticationException(super.message);
}
