import 'package:flutter/services.dart';

import 'schedule_ics_exporter.dart';

class ScheduleCalendarBridge {
  const ScheduleCalendarBridge._();

  static const _channel = MethodChannel('uwhlife/calendar');

  static Future<int> addEvents(List<ScheduleCalendarEvent> events) async {
    final count = await _channel.invokeMethod<int>(
      'addEvents',
      <String, Object>{
        'events': events.map((event) => event.toPlatformJson()).toList(),
      },
    );
    return count ?? 0;
  }
}
