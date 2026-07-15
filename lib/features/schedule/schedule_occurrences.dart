import 'models/schedule_models.dart';

class ScheduleCourseOccurrence {
  const ScheduleCourseOccurrence({
    required this.course,
    required this.week,
    required this.start,
    required this.end,
  });

  final ScheduleCourse course;
  final int week;
  final DateTime start;
  final DateTime end;
}

class ScheduleOccurrenceMapper {
  const ScheduleOccurrenceMapper._();

  static List<ScheduleCourseOccurrence> map(ScheduleData schedule) {
    final termStart = schedule.term.startDate;
    if (termStart == null) return const <ScheduleCourseOccurrence>[];

    final result = <ScheduleCourseOccurrence>[];
    for (final course in schedule.courses) {
      if (!_hasValidPlacement(course)) continue;
      final startClock = _parseClock(
        course.startTime,
        fallback: schedule.lessonTimeForPeriod(course.startPeriod)?.startTime,
      );
      final endClock = _parseClock(
        course.endTime,
        fallback: schedule.lessonTimeForPeriod(course.endPeriod)?.endTime,
      );
      if (startClock == null || endClock == null) continue;

      for (final week in course.teachingWeeks) {
        final date = DateTime(
          termStart.year,
          termStart.month,
          termStart.day,
        ).add(Duration(days: (week - 1) * 7 + course.weekday - 1));
        final start = DateTime(
          date.year,
          date.month,
          date.day,
          startClock.$1,
          startClock.$2,
        );
        final end = DateTime(
          date.year,
          date.month,
          date.day,
          endClock.$1,
          endClock.$2,
        );
        if (!end.isAfter(start)) continue;
        result.add(
          ScheduleCourseOccurrence(
            course: course,
            week: week,
            start: start,
            end: end,
          ),
        );
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static ScheduleCourseOccurrence? nextAfter(
    ScheduleData schedule, {
    required DateTime now,
  }) {
    for (final occurrence in map(schedule)) {
      if (occurrence.start.isAfter(now)) return occurrence;
    }
    return null;
  }

  static ScheduleCourseOccurrence? currentAt(
    ScheduleData schedule, {
    required DateTime now,
  }) {
    for (final occurrence in map(schedule)) {
      if (!occurrence.start.isAfter(now) && occurrence.end.isAfter(now)) {
        return occurrence;
      }
    }
    return null;
  }

  static ScheduleCourseOccurrence? nextBefore(
    ScheduleData schedule, {
    required DateTime now,
    required DateTime endExclusive,
  }) {
    final next = nextAfter(schedule, now: now);
    return next != null && next.start.isBefore(endExclusive) ? next : null;
  }

  static ScheduleCourseOccurrence? nextWithin(
    ScheduleData schedule, {
    required DateTime now,
    Duration window = const Duration(hours: 24),
  }) {
    final next = nextAfter(schedule, now: now);
    if (next == null || next.start.isAfter(now.add(window))) return null;
    return next;
  }

  static bool _hasValidPlacement(ScheduleCourse course) {
    return course.weekday >= 1 &&
        course.weekday <= 7 &&
        course.startPeriod > 0 &&
        course.endPeriod >= course.startPeriod &&
        course.teachingWeeks.isNotEmpty;
  }

  static (int, int)? _parseClock(String value, {String? fallback}) {
    final match = RegExp(
      r'(^|\D)([01]?\d|2[0-3]):([0-5]\d)',
    ).firstMatch(value.isNotEmpty ? value : fallback ?? '');
    if (match == null) return null;
    return (int.parse(match.group(2)!), int.parse(match.group(3)!));
  }
}
