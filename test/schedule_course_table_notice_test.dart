import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_api.dart';

const _unpublishedScheduleResponse = '''
{"datas":{"cxxszhxqkb":{"extParams":{"code":3,"msg":"查询学年学期的课表未发布"},
"pageSize":1000,"pageNumber":0,"totalSize":0,"rows":[]}},"code":"0"}
''';

const _unscheduledCoursesResponse = '''
{"datas":{"xswpkc":{"totalSize":2,"rows":[
{"XS":64,"SKZC":"1-16周","SKJS":"韩秀君","XF":4,"XNXQDM":"2026-2027-1",
"JXBID":"2026202711100010401","KXH":"01","KCM":"Python程序设计","KCH":"11000104"},
{"XS":48,"SKZC":"1-16周","SKJS":null,"XF":3,"XNXQDM":"2026-2027-1",
"JXBID":"2026202711100130102","KXH":"02","KCM":"Web应用开发","KCH":"11001301"}],
"extParams":{"logId":"ccd9e45a","code":1,"totalPage":0,"msg":"查询成功"}}},"code":"0"}
''';

Map<String, dynamic> _decode(String raw) {
  return (jsonDecode(raw) as Map).map(
    (key, value) => MapEntry(key.toString(), value),
  );
}

const _course = ScheduleCourse(
  name: '课程',
  courseCode: '',
  teacher: '',
  classroom: '',
  weekday: 1,
  startPeriod: 1,
  endPeriod: 2,
  weekBitmap: '1',
);

void main() {
  group('ScheduleApi.tableOf', () {
    test('reads extParams status from an unpublished course table', () {
      final table = ScheduleApi.tableOf(
        _decode(_unpublishedScheduleResponse),
        'cxxszhxqkb',
      );

      expect(table, isNotNull);
      expect(table!.rows, isEmpty);
      expect(table.code, 3);
      expect(table.message, '查询学年学期的课表未发布');
    });

    test('returns null for missing or malformed tables', () {
      expect(ScheduleApi.tableOf(null, 'cxxszhxqkb'), isNull);
      expect(
        ScheduleApi.tableOf(<String, dynamic>{'code': '0'}, 'cxxszhxqkb'),
        isNull,
      );
      expect(
        ScheduleApi.tableOf(<String, dynamic>{
          'datas': <String, dynamic>{'cxxszhxqkb': 'unexpected'},
        }, 'cxxszhxqkb'),
        isNull,
      );
    });

    test('still maps online courses independently of the course table', () {
      final table = ScheduleApi.tableOf(
        _decode(_unscheduledCoursesResponse),
        'xswpkc',
      );
      final courses = table!.rows
          .map(ScheduleUnscheduledCourse.fromJson)
          .toList(growable: false);

      expect(courses.map((course) => course.name), ['Python程序设计', 'Web应用开发']);
      expect(courses.first.teacher, '韩秀君');
      expect(courses.first.weekDescription, '1-16周');
      expect(courses.last.teacher, isEmpty);
    });
  });

  group('ScheduleApi.courseTableNotice', () {
    test('surfaces the server message when the table is unpublished', () {
      final table = ScheduleApi.tableOf(
        _decode(_unpublishedScheduleResponse),
        'cxxszhxqkb',
      );

      expect(
        ScheduleApi.courseTableNotice(
          table: table,
          parsedCourses: const <ScheduleCourse>[],
        ),
        '查询学年学期的课表未发布',
      );
    });

    test('returns null once any course parsed', () {
      expect(
        ScheduleApi.courseTableNotice(
          table: const ScheduleTable(
            rows: <Map<String, dynamic>>[],
            code: 1,
            message: '查询成功',
          ),
          parsedCourses: const <ScheduleCourse>[_course],
        ),
        isNull,
      );
    });

    test('falls back to a generic notice for an empty published table', () {
      expect(
        ScheduleApi.courseTableNotice(
          table: const ScheduleTable(
            rows: <Map<String, dynamic>>[],
            code: 1,
            message: '查询成功',
          ),
          parsedCourses: const <ScheduleCourse>[],
        ),
        ScheduleApi.emptyCourseTableNotice,
      );
    });

    test('reports a fetch failure when the request produced no table', () {
      expect(
        ScheduleApi.courseTableNotice(
          table: null,
          parsedCourses: const <ScheduleCourse>[],
        ),
        contains('获取失败'),
      );
    });

    test('reports a parse failure when rows exist but none are usable', () {
      expect(
        ScheduleApi.courseTableNotice(
          table: const ScheduleTable(
            rows: <Map<String, dynamic>>[
              <String, dynamic>{'KCM': '缺少排课信息'},
            ],
            code: 1,
            message: '查询成功',
          ),
          parsedCourses: const <ScheduleCourse>[],
        ),
        contains('解析失败'),
      );
    });
  });

  group('ScheduleData.courseTableNotice', () {
    test('hasCourseTable follows the notice', () {
      const available = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期'),
        lessonTimes: <ScheduleLessonTime>[],
        courses: <ScheduleCourse>[_course],
      );
      const unavailable = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期'),
        lessonTimes: <ScheduleLessonTime>[],
        courses: <ScheduleCourse>[],
        courseTableNotice: '查询学年学期的课表未发布',
      );

      expect(available.hasCourseTable, isTrue);
      expect(unavailable.hasCourseTable, isFalse);
    });

    test('survives a cache round trip and copyWith', () {
      const source = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期'),
        lessonTimes: <ScheduleLessonTime>[],
        courses: <ScheduleCourse>[],
        unscheduledCourses: <ScheduleUnscheduledCourse>[
          ScheduleUnscheduledCourse(
            name: 'Python程序设计',
            courseCode: '11000104',
            teacher: '韩秀君',
            weekDescription: '1-16周',
          ),
        ],
        courseTableNotice: '查询学年学期的课表未发布',
      );

      final restored = ScheduleData.fromCacheJson(source.toCacheJson());

      expect(restored.courseTableNotice, '查询学年学期的课表未发布');
      expect(restored.hasCourseTable, isFalse);
      expect(restored.unscheduledCourses.single.name, 'Python程序设计');
      expect(restored.copyWith(currentWeek: 3).courseTableNotice, isNotNull);
    });

    test('older caches without the field stay renderable', () {
      final legacy = ScheduleData.fromCacheJson(<String, dynamic>{
        'term': <String, dynamic>{'code': 'term', 'name': '学期'},
        'lessonTimes': <dynamic>[],
        'courses': <dynamic>[],
        'unscheduledCourses': <dynamic>[],
        'availableTerms': <dynamic>[],
        'currentWeek': 1,
        'isCurrentTerm': true,
      });

      expect(legacy.courseTableNotice, isNull);
      expect(legacy.hasCourseTable, isTrue);
    });
  });
}
