class ScheduleData {
  const ScheduleData({
    required this.term,
    required this.lessonTimes,
    required this.courses,
    this.currentWeek = 1,
    this.onlineCourses = const <ScheduleOnlineCourse>[],
    this.availableTerms = const <ScheduleTerm>[],
    this.isCurrentTerm = true,
  });

  final ScheduleTerm term;
  final List<ScheduleLessonTime> lessonTimes;
  final List<ScheduleCourse> courses;
  final int currentWeek;
  final List<ScheduleOnlineCourse> onlineCourses;
  final List<ScheduleTerm> availableTerms;
  final bool isCurrentTerm;

  factory ScheduleData.fromCacheJson(Map<String, dynamic> json) {
    return ScheduleData(
      term: ScheduleTerm.fromCacheJson(_map(json['term'])),
      lessonTimes: _maps(
        json['lessonTimes'],
      ).map(ScheduleLessonTime.fromCacheJson).toList(),
      courses: _maps(
        json['courses'],
      ).map(ScheduleCourse.fromCacheJson).toList(),
      currentWeek: _int(json['currentWeek'], fallback: 1),
      onlineCourses: _maps(
        json['onlineCourses'],
      ).map(ScheduleOnlineCourse.fromCacheJson).toList(),
      availableTerms: _maps(
        json['availableTerms'],
      ).map(ScheduleTerm.fromCacheJson).toList(),
      isCurrentTerm: json['isCurrentTerm'] != false,
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'term': term.toCacheJson(),
      'lessonTimes': lessonTimes
          .map((lessonTime) => lessonTime.toCacheJson())
          .toList(),
      'courses': courses.map((course) => course.toCacheJson()).toList(),
      'currentWeek': currentWeek,
      'onlineCourses': onlineCourses
          .map((course) => course.toCacheJson())
          .toList(),
      'availableTerms': availableTerms
          .map((term) => term.toCacheJson())
          .toList(),
      'isCurrentTerm': isCurrentTerm,
    };
  }

  ScheduleData copyWith({int? currentWeek}) {
    return ScheduleData(
      term: term,
      lessonTimes: lessonTimes,
      courses: courses,
      currentWeek: currentWeek ?? this.currentWeek,
      onlineCourses: onlineCourses,
      availableTerms: availableTerms,
      isCurrentTerm: isCurrentTerm,
    );
  }

  int get maxWeek {
    final totalWeeks = term.totalWeeks;
    var lastCourseWeek = 0;
    for (final course in courses) {
      final teachingWeeks = course.teachingWeeks;
      if (teachingWeeks.isNotEmpty && teachingWeeks.last > lastCourseWeek) {
        lastCourseWeek = teachingWeeks.last;
      }
    }
    if (lastCourseWeek > 0) {
      return totalWeeks != null && totalWeeks > 0
          ? lastCourseWeek.clamp(1, totalWeeks)
          : lastCourseWeek;
    }
    return totalWeeks != null && totalWeeks > 0 ? totalWeeks : 1;
  }

  List<ScheduleCourse> coursesForWeekday({
    required int week,
    required int weekday,
  }) {
    final result = courses
        .where(
          (course) => course.weekday == weekday && course.isHeldInWeek(week),
        )
        .toList();
    result.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    return result;
  }

  ScheduleLessonTime? lessonTimeForPeriod(int period) {
    for (final lessonTime in lessonTimes) {
      if (lessonTime.period == period) return lessonTime;
    }
    return null;
  }
}

class ScheduleTerm {
  const ScheduleTerm({
    required this.code,
    required this.name,
    this.startDate,
    this.endDate,
    this.totalWeeks,
  });

  final String code;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? totalWeeks;

  factory ScheduleTerm.fromCacheJson(Map<String, dynamic> json) {
    return ScheduleTerm(
      code: _string(json['code']),
      name: _string(json['name']),
      startDate: DateTime.tryParse(_string(json['startDate'])),
      endDate: DateTime.tryParse(_string(json['endDate'])),
      totalWeeks: _nullableInt(json['totalWeeks']),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'code': code,
      'name': name,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'totalWeeks': totalWeeks,
    };
  }

  ScheduleTerm copyWith({
    DateTime? startDate,
    DateTime? endDate,
    int? totalWeeks,
  }) {
    return ScheduleTerm(
      code: code,
      name: name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalWeeks: totalWeeks ?? this.totalWeeks,
    );
  }

  int weekFor(DateTime date, {required int maxWeek}) {
    final startDate = this.startDate;
    if (startDate == null) return 1;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final difference = normalizedDate.difference(normalizedStart).inDays;
    final week = difference < 0 ? 1 : difference ~/ 7 + 1;
    return clampWeek(week, fallbackMaxWeek: maxWeek);
  }

  int cachedWeekFor({
    required int cachedWeek,
    required DateTime cachedAt,
    required DateTime date,
    required int maxWeek,
  }) {
    if (startDate != null) return weekFor(date, maxWeek: maxWeek);
    final cachedWeekStart = _weekStart(cachedAt);
    final currentWeekStart = _weekStart(date);
    final weekOffset = currentWeekStart.difference(cachedWeekStart).inDays ~/ 7;
    return clampWeek(cachedWeek + weekOffset, fallbackMaxWeek: maxWeek);
  }

  int clampWeek(int week, {int fallbackMaxWeek = 1}) {
    final configuredMax = totalWeeks;
    final maxWeek = configuredMax != null && configuredMax > 0
        ? configuredMax
        : fallbackMaxWeek.clamp(1, 999);
    return week.clamp(1, maxWeek);
  }
}

DateTime _weekStart(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  return normalized.subtract(Duration(days: normalized.weekday - 1));
}

class ScheduleLessonTime {
  const ScheduleLessonTime({
    required this.period,
    required this.startTime,
    required this.endTime,
  });

  final int period;
  final String startTime;
  final String endTime;

  factory ScheduleLessonTime.fromCacheJson(Map<String, dynamic> json) {
    return ScheduleLessonTime(
      period: _int(json['period']),
      startTime: _string(json['startTime']),
      endTime: _string(json['endTime']),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'period': period,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class ScheduleCourse {
  const ScheduleCourse({
    required this.name,
    required this.courseCode,
    required this.teacher,
    required this.classroom,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weekBitmap,
    this.teachingClassId = '',
    this.sectionCode = '',
    this.teachingClass = '',
    this.startTime = '',
    this.endTime = '',
    this.weekdayLabel = '',
    this.totalHours = 0,
    this.credits = 0,
    this.assessmentType = '',
    this.courseNature = '',
    this.courseCategory = '',
    this.plannedSchedule = '',
    this.serverWeekDescription = '',
    this.building = '',
    this.campus = '',
    this.offeringDepartment = '',
  });

  factory ScheduleCourse.fromJson(Map<String, dynamic> json) {
    return ScheduleCourse(
      name: _text(json['KCM'], fallback: '未命名课程'),
      courseCode: _text(json['KCH']),
      teacher: _text(json['SKJS']),
      classroom: _text(json['JASMC']),
      weekday: _number(json['SKXQ']),
      startPeriod: _number(json['KSJC']),
      endPeriod: _number(json['JSJC']),
      weekBitmap: _text(json['SKZC']),
      teachingClassId: _text(json['JXBID']),
      sectionCode: _text(json['KXH']),
      teachingClass: _text(json['SKBJ']),
      startTime: _time(json['KSSJ']),
      endTime: _time(json['JSSJ']),
      weekdayLabel: _text(json['SKXQ_DISPLAY']),
      totalHours: _number(json['XS']),
      credits: _decimal(json['XF']),
      assessmentType: _text(json['KSLXDM_DISPLAY']),
      courseNature: _text(json['KCXZDM_DISPLAY']),
      courseCategory: _text(json['KCLBDM_DISPLAY']),
      plannedSchedule: _text(json['YPSJDD']),
      serverWeekDescription: _text(json['ZCMC']),
      building: _text(json['JXLDM_DISPLAY']),
      campus: _text(json['XXXQDM_DISPLAY']),
      offeringDepartment: _text(json['KKDWDM_DISPLAY']),
    );
  }

  factory ScheduleCourse.fromCacheJson(Map<String, dynamic> json) {
    return ScheduleCourse(
      name: _string(json['name'], fallback: '未命名课程'),
      courseCode: _string(json['courseCode']),
      teacher: _string(json['teacher']),
      classroom: _string(json['classroom']),
      weekday: _int(json['weekday']),
      startPeriod: _int(json['startPeriod']),
      endPeriod: _int(json['endPeriod']),
      weekBitmap: _string(json['weekBitmap']),
      teachingClassId: _string(json['teachingClassId']),
      sectionCode: _string(json['sectionCode']),
      teachingClass: _string(json['teachingClass']),
      startTime: _string(json['startTime']),
      endTime: _string(json['endTime']),
      weekdayLabel: _string(json['weekdayLabel']),
      totalHours: _int(json['totalHours']),
      credits: _double(json['credits']),
      assessmentType: _string(json['assessmentType']),
      courseNature: _string(json['courseNature']),
      courseCategory: _string(json['courseCategory']),
      plannedSchedule: _string(json['plannedSchedule']),
      serverWeekDescription: _string(json['serverWeekDescription']),
      building: _string(json['building']),
      campus: _string(json['campus']),
      offeringDepartment: _string(json['offeringDepartment']),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'name': name,
      'courseCode': courseCode,
      'teacher': teacher,
      'classroom': classroom,
      'weekday': weekday,
      'startPeriod': startPeriod,
      'endPeriod': endPeriod,
      'weekBitmap': weekBitmap,
      'teachingClassId': teachingClassId,
      'sectionCode': sectionCode,
      'teachingClass': teachingClass,
      'startTime': startTime,
      'endTime': endTime,
      'weekdayLabel': weekdayLabel,
      'totalHours': totalHours,
      'credits': credits,
      'assessmentType': assessmentType,
      'courseNature': courseNature,
      'courseCategory': courseCategory,
      'plannedSchedule': plannedSchedule,
      'serverWeekDescription': serverWeekDescription,
      'building': building,
      'campus': campus,
      'offeringDepartment': offeringDepartment,
    };
  }

  final String name;
  final String courseCode;
  final String teacher;
  final String classroom;
  final int weekday;
  final int startPeriod;
  final int endPeriod;
  final String weekBitmap;
  final String teachingClassId;
  final String sectionCode;
  final String teachingClass;
  final String startTime;
  final String endTime;
  final String weekdayLabel;
  final int totalHours;
  final double credits;
  final String assessmentType;
  final String courseNature;
  final String courseCategory;
  final String plannedSchedule;
  final String serverWeekDescription;
  final String building;
  final String campus;
  final String offeringDepartment;

  bool isHeldInWeek(int week) {
    final index = week - 1;
    return index >= 0 &&
        index < weekBitmap.length &&
        weekBitmap.codeUnitAt(index) == 49;
  }

  int get periodCount => endPeriod - startPeriod + 1;

  List<int> get teachingWeeks => ScheduleWeekBitmap.weeksFromBitmap(weekBitmap);

  String get weekDescription => ScheduleWeekBitmap.describe(weekBitmap);

  String get displayWeekday {
    if (weekdayLabel.isNotEmpty) return weekdayLabel;
    const names = <String>['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return weekday >= 1 && weekday <= names.length ? names[weekday - 1] : '';
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _number(Object? value) {
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _decimal(Object? value) {
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _time(Object? value) {
    final raw = _text(value);
    final match = RegExp(r'(\d{1,2}:\d{2})').firstMatch(raw);
    return match?.group(1) ?? raw;
  }
}

class ScheduleOnlineCourse {
  const ScheduleOnlineCourse({
    required this.name,
    required this.courseCode,
    required this.teacher,
    required this.weekDescription,
    this.sectionCode = '',
    this.totalHours = 0,
    this.credits = 0,
    this.teachingClassId = '',
    this.termCode = '',
  });

  factory ScheduleOnlineCourse.fromJson(Map<String, dynamic> json) {
    return ScheduleOnlineCourse(
      name: _text(json['KCM'], fallback: '未命名网络课程'),
      courseCode: _text(json['KCH']),
      teacher: _text(json['SKJS']),
      weekDescription: _text(json['SKZC']),
      sectionCode: _text(json['KXH']),
      totalHours: _number(json['XS']),
      credits: _decimal(json['XF']),
      teachingClassId: _text(json['JXBID']),
      termCode: _text(json['XNXQDM']),
    );
  }

  factory ScheduleOnlineCourse.fromCacheJson(Map<String, dynamic> json) {
    return ScheduleOnlineCourse(
      name: _string(json['name'], fallback: '未命名网络课程'),
      courseCode: _string(json['courseCode']),
      teacher: _string(json['teacher']),
      weekDescription: _string(json['weekDescription']),
      sectionCode: _string(json['sectionCode']),
      totalHours: _int(json['totalHours']),
      credits: _double(json['credits']),
      teachingClassId: _string(json['teachingClassId']),
      termCode: _string(json['termCode']),
    );
  }

  Map<String, dynamic> toCacheJson() {
    return <String, dynamic>{
      'name': name,
      'courseCode': courseCode,
      'teacher': teacher,
      'weekDescription': weekDescription,
      'sectionCode': sectionCode,
      'totalHours': totalHours,
      'credits': credits,
      'teachingClassId': teachingClassId,
      'termCode': termCode,
    };
  }

  final String name;
  final String courseCode;
  final String teacher;
  final String weekDescription;
  final String sectionCode;
  final int totalHours;
  final double credits;
  final String teachingClassId;
  final String termCode;

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _number(Object? value) {
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _decimal(Object? value) {
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) throw const FormatException('Invalid schedule cache map');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

Iterable<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) {
    throw const FormatException('Invalid schedule cache list');
  }
  return value.map(_map);
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value, {int fallback = 0}) {
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(Object? value) {
  return value == null ? null : int.tryParse(value.toString());
}

double _double(Object? value) {
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class ScheduleWeekBitmap {
  const ScheduleWeekBitmap._();

  static List<int> weeksFromBitmap(String bitmap) {
    final weeks = <int>[];
    for (var index = 0; index < bitmap.length; index += 1) {
      if (bitmap.codeUnitAt(index) == 49) {
        weeks.add(index + 1);
      }
    }
    return weeks;
  }

  static String describe(String bitmap) {
    return describeWeeks(weeksFromBitmap(bitmap));
  }

  static String describeWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '未排课';

    final ranges = <String>[];
    var rangeStart = weeks.first;
    var previous = rangeStart;
    for (final week in weeks.skip(1)) {
      if (week == previous + 1) {
        previous = week;
        continue;
      }
      ranges.add(_range(rangeStart, previous));
      rangeStart = week;
      previous = week;
    }
    ranges.add(_range(rangeStart, previous));
    return '${ranges.join(', ')}周';
  }

  static String _range(int start, int end) {
    return start == end ? '$start' : '$start-$end';
  }
}
