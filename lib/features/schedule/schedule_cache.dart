import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/portal_user_store.dart';
import 'models/schedule_models.dart';
import 'schedule_api.dart';

typedef ScheduleFetcher = Future<ScheduleData> Function({String? termCode});

class ScheduleCache {
  const ScheduleCache._();

  static const int schemaVersion = 2;
  static const int validityDays = int.fromEnvironment(
    'SCHEDULE_CACHE_TTL_DAYS',
    defaultValue: 7,
  );
  static const String _cacheKey = 'schedule_cache_v1';

  static Duration get defaultValidity {
    return Duration(days: validityDays < 0 ? 0 : validityDays);
  }

  static Future<ScheduleCacheEntry?> read({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Invalid cache root');
      final json = decoded.map((key, value) => MapEntry(key.toString(), value));
      if (json['version'] != schemaVersion) {
        await prefs.remove(_cacheKey);
        return null;
      }
      final ownerAccount = json['ownerAccount']?.toString().trim() ?? '';
      final currentUser = await PortalUserStore.read();
      final currentAccount = currentUser.userAccount?.trim() ?? '';
      if (ownerAccount != currentAccount) {
        if (currentAccount.isNotEmpty) await prefs.remove(_cacheKey);
        return null;
      }
      final savedAt = DateTime.parse(json['savedAt'].toString());
      final scheduleJson = json['schedule'];
      if (scheduleJson is! Map) {
        throw const FormatException('Invalid cached schedule');
      }
      var schedule = ScheduleData.fromCacheJson(
        scheduleJson.map((key, value) => MapEntry(key.toString(), value)),
      );
      final currentDate = now ?? DateTime.now();
      if (schedule.isCurrentTerm) {
        schedule = schedule.copyWith(
          currentWeek: schedule.term.cachedWeekFor(
            cachedWeek: schedule.currentWeek,
            cachedAt: savedAt,
            date: currentDate,
            maxWeek: schedule.maxWeek,
          ),
        );
      }
      return ScheduleCacheEntry(schedule: schedule, savedAt: savedAt);
    } catch (error) {
      debugPrint('[ScheduleCache] discard invalid cache: $error');
      await prefs.remove(_cacheKey);
      return null;
    }
  }

  static Future<void> write(ScheduleData schedule, {DateTime? savedAt}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUser = await PortalUserStore.read();
    final payload = <String, dynamic>{
      'version': schemaVersion,
      'ownerAccount': currentUser.userAccount,
      'savedAt': (savedAt ?? DateTime.now()).toIso8601String(),
      'schedule': schedule.toCacheJson(),
    };
    await prefs.setString(_cacheKey, jsonEncode(payload));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }
}

class ScheduleCacheEntry {
  const ScheduleCacheEntry({required this.schedule, required this.savedAt});

  final ScheduleData schedule;
  final DateTime savedAt;

  bool isFreshAt(DateTime now, {required Duration validity}) {
    if (validity <= Duration.zero) return false;
    final age = now.difference(savedAt);
    return !age.isNegative && age <= validity;
  }
}

class ScheduleRepository {
  ScheduleRepository({
    ScheduleFetcher? fetcher,
    DateTime Function()? now,
    Duration? cacheValidity,
  }) : _fetcher = fetcher ?? ScheduleApi.fetchSchedule,
       _now = now ?? DateTime.now,
       _cacheValidity = cacheValidity ?? ScheduleCache.defaultValidity;

  final ScheduleFetcher _fetcher;
  final DateTime Function() _now;
  final Duration _cacheValidity;

  Future<ScheduleData> load({
    bool forceRefresh = false,
    String? termCode,
  }) async {
    final now = _now();
    final cached = await ScheduleCache.read(now: now);
    final matchingCache =
        termCode == null || cached?.schedule.term.code == termCode
        ? cached
        : null;
    if (!forceRefresh &&
        matchingCache != null &&
        matchingCache.isFreshAt(now, validity: _cacheValidity)) {
      return matchingCache.schedule;
    }

    try {
      final schedule = await _fetcher(termCode: termCode);
      try {
        await ScheduleCache.write(schedule, savedAt: _now());
      } catch (error) {
        debugPrint('[ScheduleCache] failed to persist cache: $error');
      }
      return schedule;
    } catch (error) {
      if (matchingCache != null) {
        debugPrint('[ScheduleCache] refresh failed, use stale cache: $error');
        return matchingCache.schedule;
      }
      rethrow;
    }
  }
}
