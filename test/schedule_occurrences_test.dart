import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_occurrences.dart';

void main() {
  test('maps teaching weeks with lesson-time fallbacks', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '数据库概论',
        courseCode: '',
        teacher: '',
        classroom: '5栋B306',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '101',
      ),
    ]);

    final occurrences = ScheduleOccurrenceMapper.map(schedule);

    expect(occurrences, hasLength(2));
    expect(occurrences.first.start, DateTime(2026, 2, 24, 8, 20));
    expect(occurrences.first.end, DateTime(2026, 2, 24, 10));
    expect(occurrences.last.start, DateTime(2026, 3, 10, 8, 20));
  });

  test('finds a tomorrow course inside the rolling 24-hour window', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '明早课程',
        courseCode: '',
        teacher: '',
        classroom: 'A101',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      ),
    ]);

    final next = ScheduleOccurrenceMapper.nextWithin(
      schedule,
      now: DateTime(2026, 2, 23, 12),
    );

    expect(next?.course.name, '明早课程');
    expect(next?.start, DateTime(2026, 2, 24, 8, 20));
  });

  test('excludes the next course when it is beyond 24 hours', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '较远课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 3,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      ),
    ]);
    final now = DateTime(2026, 2, 23, 8);

    expect(ScheduleOccurrenceMapper.nextWithin(schedule, now: now), isNull);
    expect(
      ScheduleOccurrenceMapper.nextAfter(schedule, now: now)?.course.name,
      '较远课程',
    );
  });

  test('includes a course starting exactly at the 24-hour boundary', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '边界课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      ),
    ]);

    final next = ScheduleOccurrenceMapper.nextWithin(
      schedule,
      now: DateTime(2026, 2, 23, 8, 20),
    );

    expect(next?.course.name, '边界课程');
  });

  test('detects a course that is currently in progress', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '本节课程',
        courseCode: '',
        teacher: '',
        classroom: '5栋B306',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      ),
    ]);

    expect(
      ScheduleOccurrenceMapper.currentAt(
        schedule,
        now: DateTime(2026, 2, 23, 9),
      )?.course.name,
      '本节课程',
    );
    expect(
      ScheduleOccurrenceMapper.currentAt(
        schedule,
        now: DateTime(2026, 2, 23, 10),
      ),
      isNull,
    );
  });

  test('searches through tomorrow but excludes the following midnight', () {
    final tomorrowSchedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '明天课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 2,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
      ),
    ]);
    final midnightSchedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '后天零点课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 3,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '1',
        startTime: '00:00',
        endTime: '01:00',
      ),
    ]);
    final now = DateTime(2026, 2, 23, 20);
    final endExclusive = DateTime(2026, 2, 25);

    expect(
      ScheduleOccurrenceMapper.nextBefore(
        tomorrowSchedule,
        now: now,
        endExclusive: endExclusive,
      )?.course.name,
      '明天课程',
    );
    expect(
      ScheduleOccurrenceMapper.nextBefore(
        midnightSchedule,
        now: now,
        endExclusive: endExclusive,
      ),
      isNull,
    );
  });
}

ScheduleData _schedule(List<ScheduleCourse> courses) {
  return ScheduleData(
    term: ScheduleTerm(
      code: '2025-2026-2',
      name: '测试学期',
      startDate: DateTime(2026, 2, 23),
      totalWeeks: 20,
    ),
    lessonTimes: const <ScheduleLessonTime>[
      ScheduleLessonTime(period: 1, startTime: '08:20', endTime: '09:05'),
      ScheduleLessonTime(period: 2, startTime: '09:15', endTime: '10:00'),
    ],
    courses: courses,
  );
}
