import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import 'models/schedule_models.dart';
import 'schedule_file_exporter.dart';

class ScheduleCalendarEvent {
  const ScheduleCalendarEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    required this.location,
    required this.notes,
  });

  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String notes;

  Map<String, Object> toPlatformJson() => <String, Object>{
    'uid': uid,
    'title': title,
    'startMilliseconds': _shanghaiMilliseconds(start),
    'endMilliseconds': _shanghaiMilliseconds(end),
    'location': location,
    'notes': notes,
  };

  static int _shanghaiMilliseconds(DateTime value) {
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    ).subtract(const Duration(hours: 8)).millisecondsSinceEpoch;
  }
}

class ScheduleIcsExporter {
  const ScheduleIcsExporter._();

  static List<ScheduleCalendarEvent> events(ScheduleData schedule) {
    final termStart = schedule.term.startDate;
    if (termStart == null) return const <ScheduleCalendarEvent>[];

    final result = <ScheduleCalendarEvent>[];
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

        final identity = <Object>[
          schedule.term.code,
          course.courseCode,
          course.sectionCode,
          course.name,
          course.weekday,
          course.startPeriod,
          course.endPeriod,
          week,
        ].join('|');
        result.add(
          ScheduleCalendarEvent(
            uid: '${sha256.convert(utf8.encode(identity))}@uwhlife',
            title: course.name,
            start: start,
            end: end,
            location: course.classroom,
            notes: _notes(course),
          ),
        );
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static int exportableEventCount(ScheduleData schedule) =>
      events(schedule).length;

  static String encode(ScheduleData schedule, {DateTime? generatedAt}) {
    final timestamp = _formatUtc((generatedAt ?? DateTime.now()).toUtc());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//uwhLife//Schedule//ZH-CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_escapeText(schedule.term.name)}',
      'X-WR-TIMEZONE:Asia/Shanghai',
      'BEGIN:VTIMEZONE',
      'TZID:Asia/Shanghai',
      'X-LIC-LOCATION:Asia/Shanghai',
      'BEGIN:STANDARD',
      'TZOFFSETFROM:+0800',
      'TZOFFSETTO:+0800',
      'TZNAME:CST',
      'DTSTART:19700101T000000',
      'END:STANDARD',
      'END:VTIMEZONE',
    ];
    for (final event in events(schedule)) {
      lines.addAll(<String>[
        'BEGIN:VEVENT',
        'UID:${event.uid}',
        'DTSTAMP:$timestamp',
        'DTSTART;TZID=Asia/Shanghai:${_formatLocal(event.start)}',
        'DTEND;TZID=Asia/Shanghai:${_formatLocal(event.end)}',
        'SUMMARY:${_escapeText(event.title)}',
        if (event.location.isNotEmpty)
          'LOCATION:${_escapeText(event.location)}',
        if (event.notes.isNotEmpty) 'DESCRIPTION:${_escapeText(event.notes)}',
        'STATUS:CONFIRMED',
        'TRANSP:OPAQUE',
        'END:VEVENT',
      ]);
    }
    lines.add('END:VCALENDAR');
    return '${lines.map(_foldLine).join('\r\n')}\r\n';
  }

  static Future<void> export(BuildContext context, ScheduleData schedule) {
    final fileName = '课表_${_safeFilePart(schedule.term.code)}.ics';
    return ScheduleFileExporter.saveOrShare(
      context,
      bytes: Uint8List.fromList(utf8.encode(encode(schedule))),
      fileName: fileName,
      mimeType: 'text/calendar',
      title: '导出 ICS 课表',
      subject: schedule.term.name,
      chooseLocationOnIOS: true,
    );
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

  static String _notes(ScheduleCourse course) {
    return <String>[
      if (course.teacher.isNotEmpty) '教师：${course.teacher}',
      if (course.weekDescription.isNotEmpty) '周次：${course.weekDescription}',
      if (course.courseCode.isNotEmpty) '课程号：${course.courseCode}',
      if (course.sectionCode.isNotEmpty) '课序号：${course.sectionCode}',
      if (course.campus.isNotEmpty) '校区：${course.campus}',
    ].join('\n');
  }

  static String _escapeText(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll(',', r'\,')
        .replaceAll(';', r'\;');
  }

  static String _formatLocal(DateTime value) {
    return '${_digits(value.year, 4)}${_digits(value.month, 2)}'
        '${_digits(value.day, 2)}T${_digits(value.hour, 2)}'
        '${_digits(value.minute, 2)}${_digits(value.second, 2)}';
  }

  static String _formatUtc(DateTime value) => '${_formatLocal(value)}Z';

  static String _digits(int value, int width) =>
      value.toString().padLeft(width, '0');

  static String _foldLine(String line) {
    final chunks = <String>[];
    var current = StringBuffer();
    var bytes = 0;
    var limit = 75;
    for (final rune in line.runes) {
      final character = String.fromCharCode(rune);
      final characterBytes = utf8.encode(character).length;
      if (bytes + characterBytes > limit && current.isNotEmpty) {
        chunks.add(current.toString());
        current = StringBuffer();
        bytes = 0;
        limit = 74;
      }
      current.write(character);
      bytes += characterBytes;
    }
    chunks.add(current.toString());
    return chunks.join('\r\n ');
  }

  static String _safeFilePart(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^0-9A-Za-z_-]+'), '_');
    return safe.isEmpty ? 'schedule' : safe;
  }
}
