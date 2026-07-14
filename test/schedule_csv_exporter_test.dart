import 'package:flutter_test/flutter_test.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_csv_exporter.dart';

void main() {
  test('exports the WakeUp CSV columns and compact teaching weeks', () {
    final csv = ScheduleCsvExporter.encode(
      _schedule(<ScheduleCourse>[
        const ScheduleCourse(
          name: '高等数学',
          courseCode: '',
          teacher: '小明',
          classroom: '逸夫楼201',
          weekday: 1,
          startPeriod: 1,
          endPeriod: 2,
          weekBitmap: '111110101111',
        ),
      ]),
    );

    expect(
      csv,
      '课程名称,星期,开始节数,结束节数,老师,地点,周数\r\n'
      '高等数学,1,1,2,小明,逸夫楼201,1-5、7、9-12',
    );
  });

  test('quotes commas, quotes and line breaks in CSV fields', () {
    final csv = ScheduleCsvExporter.encode(
      _schedule(<ScheduleCourse>[
        const ScheduleCourse(
          name: '阅读,写作',
          courseCode: '',
          teacher: '王"老师',
          classroom: 'A楼\n201',
          weekday: 2,
          startPeriod: 3,
          endPeriod: 4,
          weekBitmap: '1',
        ),
      ]),
    );

    expect(csv, contains('"阅读,写作"'));
    expect(csv, contains('"王""老师"'));
    expect(csv, contains('"A楼\n201"'));
  });

  test('skips rows without a valid weekday, period or teaching week', () {
    final schedule = _schedule(<ScheduleCourse>[
      const ScheduleCourse(
        name: '无排课课程',
        courseCode: '',
        teacher: '',
        classroom: '',
        weekday: 0,
        startPeriod: 0,
        endPeriod: 0,
        weekBitmap: '',
      ),
    ]);

    expect(ScheduleCsvExporter.exportableCourseCount(schedule), 0);
    expect(ScheduleCsvExporter.encode(schedule).split('\r\n'), hasLength(1));
  });
}

ScheduleData _schedule(List<ScheduleCourse> courses) {
  return ScheduleData(
    term: const ScheduleTerm(code: '2025-2026-2', name: '测试学期'),
    lessonTimes: const <ScheduleLessonTime>[],
    courses: courses,
  );
}
