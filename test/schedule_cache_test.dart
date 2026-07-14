import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uwhlife/core/storage/portal_user_store.dart';
import 'package:uwhlife/features/schedule/models/schedule_models.dart';
import 'package:uwhlife/features/schedule/schedule_cache.dart';

void main() {
  final now = DateTime(2026, 3, 9, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PortalUserStore.save(userAccount: 'student-1');
  });

  test('round-trips physical and online courses through JSON cache', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);

    final cached = await ScheduleCache.read(now: now);

    expect(cached, isNotNull);
    expect(cached!.schedule.currentWeek, 3);
    expect(cached.schedule.courses.single.name, '操作系统');
    expect(cached.schedule.courses.single.classroom, '5栋教学楼B302');
    expect(cached.schedule.onlineCourses.single.name, '海洋与人类文明');
    expect(
      cached.schedule.onlineCourses.single.teachingClassId,
      'online-class-id',
    );
    expect(cached.schedule.onlineCourses.single.termCode, '2025-2026-2');
    expect(cached.schedule.availableTerms.length, 2);
  });

  test('uses fresh cache without requesting the server', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    var fetchCount = 0;
    final repository = ScheduleRepository(
      now: () => now.add(const Duration(days: 6)),
      cacheValidity: const Duration(days: 7),
      fetcher: ({String? termCode}) async {
        fetchCount += 1;
        return _schedule(courseName: '联网课程');
      },
    );

    final schedule = await repository.load();

    expect(fetchCount, 0);
    expect(schedule.courses.single.name, '操作系统');
  });

  test('advances a cached current week after crossing Monday', () async {
    final savedAt = DateTime(2026, 3, 8, 22);
    await ScheduleCache.write(
      _schedule(includeStartDate: false, currentWeek: 2),
      savedAt: savedAt,
    );

    final cached = await ScheduleCache.read(now: DateTime(2026, 3, 9, 8));

    expect(cached, isNotNull);
    expect(cached!.schedule.currentWeek, 3);
  });

  test(
    'keeps a cached current week when the date stays in the same week',
    () async {
      final savedAt = DateTime(2026, 3, 3, 8);
      await ScheduleCache.write(
        _schedule(includeStartDate: false, currentWeek: 2),
        savedAt: savedAt,
      );

      final cached = await ScheduleCache.read(now: DateTime(2026, 3, 8, 22));

      expect(cached, isNotNull);
      expect(cached!.schedule.currentWeek, 2);
    },
  );

  test('refreshes an expired cache and persists the new response', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    var fetchCount = 0;
    final refreshTime = now.add(const Duration(days: 8));
    final repository = ScheduleRepository(
      now: () => refreshTime,
      cacheValidity: const Duration(days: 7),
      fetcher: ({String? termCode}) async {
        fetchCount += 1;
        return _schedule(courseName: '联网课程');
      },
    );

    final schedule = await repository.load();
    final cached = await ScheduleCache.read(now: refreshTime);

    expect(fetchCount, 1);
    expect(schedule.courses.single.name, '联网课程');
    expect(cached!.schedule.courses.single.name, '联网课程');
  });

  test('force refresh bypasses a still-valid cache', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    var fetchCount = 0;
    final repository = ScheduleRepository(
      now: () => now.add(const Duration(days: 1)),
      cacheValidity: const Duration(days: 7),
      fetcher: ({String? termCode}) async {
        fetchCount += 1;
        return _schedule(courseName: '手动刷新课程');
      },
    );

    final schedule = await repository.load(forceRefresh: true);

    expect(fetchCount, 1);
    expect(schedule.courses.single.name, '手动刷新课程');
  });

  test('falls back to expired cache when refresh fails', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    final repository = ScheduleRepository(
      now: () => now.add(const Duration(days: 8)),
      cacheValidity: const Duration(days: 7),
      fetcher: ({String? termCode}) async => throw Exception('offline'),
    );

    final schedule = await repository.load();

    expect(schedule.courses.single.name, '操作系统');
    expect(schedule.onlineCourses.single.name, '海洋与人类文明');
  });

  test('does not expose cached schedule to another account', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    await PortalUserStore.save(userAccount: 'student-2');

    expect(await ScheduleCache.read(now: now), isNull);
  });

  test('keeps a historical term at its saved week', () async {
    await ScheduleCache.write(_schedule(termCode: '2025-2026-1'), savedAt: now);

    final cached = await ScheduleCache.read(now: now);

    expect(cached, isNotNull);
    expect(cached!.schedule.isCurrentTerm, isFalse);
    expect(cached.schedule.currentWeek, 1);
  });

  test('requests a selected term without using another term cache', () async {
    await ScheduleCache.write(_schedule(), savedAt: now);
    String? requestedTerm;
    final repository = ScheduleRepository(
      now: () => now,
      fetcher: ({String? termCode}) async {
        requestedTerm = termCode;
        return _schedule(termCode: termCode ?? '2025-2026-2');
      },
    );

    final schedule = await repository.load(termCode: '2025-2026-1');

    expect(requestedTerm, '2025-2026-1');
    expect(schedule.term.code, '2025-2026-1');
  });
}

ScheduleData _schedule({
  String courseName = '操作系统',
  String termCode = '2025-2026-2',
  bool includeStartDate = true,
  int currentWeek = 1,
}) {
  return ScheduleData(
    term: ScheduleTerm(
      code: termCode,
      name: termCode,
      startDate: includeStartDate ? DateTime(2026, 2, 23) : null,
      endDate: DateTime(2026, 6, 28),
      totalWeeks: 18,
    ),
    lessonTimes: const <ScheduleLessonTime>[
      ScheduleLessonTime(period: 1, startTime: '08:20', endTime: '09:05'),
    ],
    courses: <ScheduleCourse>[
      ScheduleCourse(
        name: courseName,
        courseCode: '11000050',
        teacher: '王老师',
        classroom: '5栋教学楼B302',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weekBitmap: '111111111111111100',
        sectionCode: '02',
        teachingClassId: 'physical-class-id',
      ),
    ],
    currentWeek: currentWeek,
    isCurrentTerm: termCode == '2025-2026-2',
    onlineCourses: <ScheduleOnlineCourse>[
      ScheduleOnlineCourse(
        name: '海洋与人类文明',
        courseCode: '01000076',
        teacher: '网络教师',
        weekDescription: '1-18周',
        sectionCode: '01',
        totalHours: 8,
        teachingClassId: 'online-class-id',
        termCode: termCode,
      ),
    ],
    availableTerms: const <ScheduleTerm>[
      ScheduleTerm(code: '2025-2026-2', name: '2025-2026学年2学期'),
      ScheduleTerm(code: '2025-2026-1', name: '2025-2026学年1学期'),
    ],
  );
}
