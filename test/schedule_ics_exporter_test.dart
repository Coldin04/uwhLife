import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_ics_exporter.dart';

void main() {
  test('maps teaching weeks and weekdays to calendar dates', () {
    final schedule = _schedule(
      courses: const <ScheduleCourse>[
        ScheduleCourse(
          name: '移动应用开发',
          courseCode: 'CS101',
          teacher: '王老师',
          classroom: '5栋B104',
          weekday: 3,
          startPeriod: 3,
          endPeriod: 4,
          weekBitmap: '101',
        ),
      ],
    );

    final events = ScheduleIcsExporter.events(schedule);

    expect(events, hasLength(2));
    expect(events.first.start, DateTime(2026, 2, 25, 10, 15));
    expect(events.first.end, DateTime(2026, 2, 25, 11, 55));
    expect(events.last.start, DateTime(2026, 3, 11, 10, 15));
    expect(events.first.location, '5栋B104');
    expect(events.first.notes, contains('教师：王老师'));
  });

  test('emits RFC-style calendar fields and escapes text', () {
    final schedule = _schedule(
      courses: const <ScheduleCourse>[
        ScheduleCourse(
          name: '阅读,写作;实践',
          courseCode: '',
          teacher: '王老师',
          classroom: 'A楼,201',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekBitmap: '1',
        ),
      ],
    );

    final ics = ScheduleIcsExporter.encode(
      schedule,
      generatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, contains('DTSTAMP:20260102T030405Z'));
    expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260223T082000'));
    expect(ics, contains(r'SUMMARY:阅读\,写作\;实践'));
    expect(ics, contains(r'LOCATION:A楼\,201'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
  });

  test('skips courses when date or lesson time cannot be resolved', () {
    final missingDate = ScheduleData(
      term: const ScheduleTerm(code: '2025-2026-2', name: '测试学期'),
      lessonTimes: const <ScheduleLessonTime>[],
      courses: const <ScheduleCourse>[],
    );
    final missingTime = _schedule(
      lessonTimes: const <ScheduleLessonTime>[],
      courses: const <ScheduleCourse>[
        ScheduleCourse(
          name: '无时间课程',
          courseCode: '',
          teacher: '',
          classroom: '',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekBitmap: '1',
        ),
      ],
    );

    expect(ScheduleIcsExporter.events(missingDate), isEmpty);
    expect(ScheduleIcsExporter.events(missingTime), isEmpty);
  });
}

ScheduleData _schedule({
  required List<ScheduleCourse> courses,
  List<ScheduleLessonTime> lessonTimes = const <ScheduleLessonTime>[
    ScheduleLessonTime(period: 1, startTime: '08:20', endTime: '09:05'),
    ScheduleLessonTime(period: 2, startTime: '09:15', endTime: '10:00'),
    ScheduleLessonTime(period: 3, startTime: '10:15', endTime: '11:00'),
    ScheduleLessonTime(period: 4, startTime: '11:10', endTime: '11:55'),
  ],
}) {
  return ScheduleData(
    term: ScheduleTerm(
      code: '2025-2026-2',
      name: '2025-2026学年2学期',
      startDate: DateTime(2026, 2, 23),
      totalWeeks: 20,
    ),
    lessonTimes: lessonTimes,
    courses: courses,
  );
}
