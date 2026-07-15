import 'package:flutter/services.dart';

import 'schedule_ics_exporter.dart';

class ScheduleCalendarBridge {
  const ScheduleCalendarBridge._();

  static const _channel = MethodChannel('uwhlife/calendar');

  static Future<int> addEvents(
    List<ScheduleCalendarEvent> events, {
    required String calendarKey,
    required String calendarTitle,
  }) async {
    final count = await _channel
        .invokeMethod<int>('addEvents', <String, Object>{
          'events': events.map((event) => event.toPlatformJson()).toList(),
          'calendarKey': calendarKey,
          'calendarTitle': calendarTitle,
        });
    return count ?? 0;
  }

  static Future<bool> requestFullAccess() async {
    final granted = await _channel.invokeMethod<bool>('requestFullAccess');
    return granted ?? false;
  }
}
