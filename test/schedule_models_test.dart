import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_api.dart';

void main() {
  group('ScheduleCourse', () {
    test('maps the week bitmap from the first teaching week', () {
      const course = ScheduleCourse(
        name: '课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '101',
      );

      expect(course.isHeldInWeek(1), isTrue);
      expect(course.isHeldInWeek(2), isFalse);
      expect(course.isHeldInWeek(3), isTrue);
      expect(course.isHeldInWeek(4), isFalse);
      expect(course.teachingWeeks, [1, 3]);
      expect(course.weekDescription, '1, 3周');
    });

    test('describes consecutive and non-consecutive teaching weeks', () {
      expect(ScheduleWeekBitmap.describe('111010110'), '1-3, 5, 7-8周');
    });

    test(
      'maps course metadata and meeting details without identity fields',
      () {
        final course = ScheduleCourse.fromJson(<String, dynamic>{
          'KCM': '课程',
          'KCH': 'course-code',
          'KXH': '02',
          'JXBID': 'teaching-class',
          'SKJS': '教师',
          'SKBJ': '上课班级',
          'XS': 48,
          'XF': 3.5,
          'KSLXDM_DISPLAY': '考试',
          'KCXZDM_DISPLAY': '选修',
          'KCLBDM_DISPLAY': '专业选修模块',
          'KKDWDM_DISPLAY': '开课单位',
          'SKXQ': 3,
          'SKXQ_DISPLAY': '星期三',
          'KSJC': 5,
          'JSJC': 7,
          'KSSJ': '14:00',
          'JSSJ': '16:40',
          'SKZC': '001111',
          'ZCMC': '3-6周',
          'JASMC': '教学楼教室',
          'JXLDM_DISPLAY': '教学楼',
          'XXXQDM_DISPLAY': '校区',
          'YPSJDD': '完整时间地点汇总',
          'XM': '不应进入模型',
          'XH': '不应进入模型',
        });

        expect(course.name, '课程');
        expect(course.sectionCode, '02');
        expect(course.teachingClassId, 'teaching-class');
        expect(course.teachingClass, '上课班级');
        expect(course.totalHours, 48);
        expect(course.credits, 3.5);
        expect(course.assessmentType, '考试');
        expect(course.courseNature, '选修');
        expect(course.courseCategory, '专业选修模块');
        expect(course.displayWeekday, '星期三');
        expect(course.startTime, '14:00');
        expect(course.endTime, '16:40');
        expect(course.classroom, '教学楼教室');
        expect(course.plannedSchedule, '完整时间地点汇总');
        expect(course.weekDescription, '3-6周');
      },
    );
  });

  group('ScheduleData', () {
    test('filters and orders the selected weekday', () {
      const first = ScheduleCourse(
        name: '后两节',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 1,
        startPeriod: 3,
        endPeriod: 4,
        weekBitmap: '1',
      );
      const second = ScheduleCourse(
        name: '前两节',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      );
      const otherDay = ScheduleCourse(
        name: '其他天',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      );
      const data = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期'),
        lessonTimes: [],
        courses: [first, second, otherDay],
      );

      expect(
        data
            .coursesForWeekday(week: 1, weekday: 1)
            .map((course) => course.name),
        ['前两节', '后两节'],
      );
      expect(data.coursesForWeekday(week: 1, weekday: 2), [otherDay]);
    });

    test('uses the calendar total instead of an oversized course bitmap', () {
      const data = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期', totalWeeks: 18),
        lessonTimes: [],
        courses: <ScheduleCourse>[
          ScheduleCourse(
            name: '异常位图课程',
            courseCode: '',
            teacher: '',
            classroom: '',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 2,
            weekBitmap: '111111111111111111111111111111',
          ),
        ],
      );

      expect(data.maxWeek, 18);
    });

    test('trims empty trailing calendar weeks after the last course', () {
      const data = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期', totalWeeks: 20),
        lessonTimes: [],
        courses: <ScheduleCourse>[
          ScheduleCourse(
            name: '只上到十八周',
            courseCode: '',
            teacher: '',
            classroom: '',
            weekday: 1,
            startPeriod: 1,
            endPeriod: 2,
            weekBitmap: '11111111111111111100',
          ),
        ],
        currentWeek: 20,
      );

      expect(data.maxWeek, 18);
      expect(data.currentWeek.clamp(1, data.maxWeek), 18);
    });

    test('keeps the calendar total when there are no physical courses', () {
      const data = ScheduleData(
        term: ScheduleTerm(code: 'term', name: '学期', totalWeeks: 20),
        lessonTimes: [],
        courses: <ScheduleCourse>[],
      );

      expect(data.maxWeek, 20);
    });
  });

  group('ScheduleTerm', () {
    test('calculates the teaching week from the semester start', () {
      final term = ScheduleTerm(
        code: 'term',
        name: '学期',
        startDate: DateTime(2026, 2, 23),
        totalWeeks: 18,
      );

      expect(term.weekFor(DateTime(2026, 2, 23), maxWeek: 18), 1);
      expect(term.weekFor(DateTime(2026, 3, 2), maxWeek: 18), 2);
      expect(term.weekFor(DateTime(2027, 1, 1), maxWeek: 18), 18);
    });

    test('clamps invalid server weeks to the teaching calendar', () {
      const term = ScheduleTerm(code: 'term', name: '学期', totalWeeks: 18);

      expect(term.clampWeek(999), 18);
      expect(term.clampWeek(0), 1);
    });
  });

  test('maps a network course response', () {
    final course = ScheduleOnlineCourse.fromJson(<String, dynamic>{
      'KCM': '网络课程',
      'KCH': 'course-code',
      'SKJS': '网络教师',
      'SKZC': '1-18周',
      'KXH': '01',
      'XS': 8,
      'XF': 2.5,
      'JXBID': 'online-class-id',
      'XNXQDM': '2025-2026-2',
    });

    expect(course.name, '网络课程');
    expect(course.courseCode, 'course-code');
    expect(course.teacher, '网络教师');
    expect(course.weekDescription, '1-18周');
    expect(course.sectionCode, '01');
    expect(course.totalHours, 8);
    expect(course.credits, 2.5);
    expect(course.teachingClassId, 'online-class-id');
    expect(course.termCode, '2025-2026-2');
  });

  test('extracts the dynamic role id from the landing page', () {
    expect(
      ScheduleApi.roleIdFromLandingPage(
        '<script>pageMeta = {"params":{"ROLEID":"dynamic-role"}};</script>',
      ),
      'dynamic-role',
    );
  });

  test('uses the landing page role fallback when pageMeta is empty', () {
    expect(
      ScheduleApi.roleIdFromLandingPage(
        '<script>'
        'pageMeta = {"params":{"ROLEID":""}};'
        "roleId = pageMeta.params.ROLEID==''?'default-role':pageMeta.params.ROLEID;"
        '</script>',
      ),
      'default-role',
    );
  });

  test('extracts a quoted or unquoted landing app id', () {
    expect(
      ScheduleApi.appIdFromLandingPage(
        '<script>window._JW_INIT_CONFIG = {"appId":"app-id"};</script>',
      ),
      'app-id',
    );
    expect(
      ScheduleApi.appIdFromLandingPage(
        '<script>window.WIS_CONFIG = { APPID: app_id_2 };</script>',
      ),
      'app_id_2',
    );
  });

  test('maps the selectable academic terms', () {
    final terms = ScheduleApi.termsFromResponse(<String, dynamic>{
      'datas': <String, dynamic>{
        'xnxqcx': <String, dynamic>{
          'rows': <Map<String, dynamic>>[
            <String, dynamic>{'DM': '2025-2026-2', 'MC': '2025-2026学年2学期'},
            <String, dynamic>{'DM': '2025-2026-1', 'MC': '2025-2026学年1学期'},
          ],
        },
      },
    });

    expect(terms.map((term) => term.code), <String>[
      '2025-2026-2',
      '2025-2026-1',
    ]);
    expect(terms.first.name, '2025-2026学年2学期');
  });

  test('skips empty role declarations before a resolved role', () {
    expect(
      ScheduleApi.roleIdFromLandingPage(
        '<script>'
        'var pageMeta = {"ROLEID":""};'
        'var appConfig = {"ROLEID":"resolved-role"};'
        '</script>',
      ),
      'resolved-role',
    );
  });

  test('uses the active role from the app config', () {
    expect(
      ScheduleApi.roleIdFromAppConfig(<String, dynamic>{
        'HEADER': <String, dynamic>{
          'dropMenu': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'other-role', 'active': false},
            <String, dynamic>{'id': 'active-role', 'active': true},
          ],
        },
      }),
      'active-role',
    );
  });

  test('accepts a serialized active app-config role', () {
    expect(
      ScheduleApi.roleIdFromAppConfig(<String, dynamic>{
        'HEADER': <String, dynamic>{
          'dropMenu': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'first-role', 'active': false},
            <String, dynamic>{'id': 'active-role', 'active': 'true'},
          ],
        },
      }),
      'active-role',
    );
  });
}
