import 'package:shared_preferences/shared_preferences.dart';

typedef DateTimeProvider = DateTime Function();

class UpdateCheckCooldown {
  UpdateCheckCooldown({DateTimeProvider? now}) : _now = now ?? DateTime.now;

  static const Duration cooldown = Duration(days: 10);
  static const String _cancelledAtKey = 'update_check_cancelled_at';

  final DateTimeProvider _now;

  Future<bool> shouldSkipAutomaticCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final cancelledAt = DateTime.tryParse(
      prefs.getString(_cancelledAtKey) ?? '',
    );
    if (cancelledAt == null) return false;
    return _now().difference(cancelledAt) < cooldown;
  }

  Future<void> recordUserCancelled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cancelledAtKey, _now().toIso8601String());
  }
}
