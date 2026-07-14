import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models/schedule_models.dart';
import 'schedule_file_exporter.dart';

class ScheduleCsvExporter {
  const ScheduleCsvExporter._();

  static const _header = <String>[
    '课程名称',
    '星期',
    '开始节数',
    '结束节数',
    '老师',
    '地点',
    '周数',
  ];

  static String encode(ScheduleData schedule) {
    final rows = <List<String>>[_header];
    for (final course in schedule.courses) {
      if (!_isExportable(course)) continue;
      rows.add(<String>[
        course.name,
        course.weekday.toString(),
        course.startPeriod.toString(),
        course.endPeriod.toString(),
        course.teacher,
        course.classroom,
        _formatWeeks(course.teachingWeeks),
      ]);
    }
    return rows.map(_encodeRow).join('\r\n');
  }

  static int exportableCourseCount(ScheduleData schedule) {
    return schedule.courses.where(_isExportable).length;
  }

  static Future<void> share(BuildContext context, ScheduleData schedule) {
    final fileName = 'WakeUp课表_${_safeFilePart(schedule.term.code)}.csv';
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF${encode(schedule)}'));
    return ScheduleFileExporter.saveOrShare(
      context,
      bytes: bytes,
      fileName: fileName,
      mimeType: 'text/csv',
      title: '导出 WakeUp 课表',
      subject: schedule.term.name,
      chooseLocationOnIOS: true,
    );
  }

  static bool _isExportable(ScheduleCourse course) {
    return course.weekday >= 1 &&
        course.weekday <= 7 &&
        course.startPeriod > 0 &&
        course.endPeriod >= course.startPeriod &&
        course.teachingWeeks.isNotEmpty;
  }

  static String _formatWeeks(List<int> weeks) {
    if (weeks.isEmpty) return '';
    final segments = <String>[];
    var start = weeks.first;
    var end = start;
    for (final week in weeks.skip(1)) {
      if (week == end + 1) {
        end = week;
        continue;
      }
      segments.add(start == end ? '$start' : '$start-$end');
      start = week;
      end = week;
    }
    segments.add(start == end ? '$start' : '$start-$end');
    return segments.join('、');
  }

  static String _encodeRow(List<String> cells) {
    return cells.map(_escapeCell).join(',');
  }

  static String _escapeCell(String value) {
    if (!value.contains(RegExp('[,"\\r\\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static String _safeFilePart(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^0-9A-Za-z_-]+'), '_');
    return safe.isEmpty ? 'schedule' : safe;
  }
}
