import 'package:flutter/material.dart';

enum AppNativeDestination { schedule }

const Map<String, IconData> iconRegistry = <String, IconData>{
  'receipt_long_rounded': Icons.receipt_long_rounded,
  'handshake_rounded': Icons.handshake_rounded,
  'account_balance_wallet_rounded': Icons.account_balance_wallet_rounded,
  'savings_rounded': Icons.savings_rounded,
  'bolt_rounded': Icons.bolt_rounded,
  'shower_rounded': Icons.shower_rounded,
  'event_seat_rounded': Icons.event_seat_rounded,
  'record_voice_over_rounded': Icons.record_voice_over_rounded,
  'event_note_rounded': Icons.event_note_rounded,
  'rate_review_rounded': Icons.rate_review_rounded,
  'calendar_month_rounded': Icons.calendar_month_rounded,
  'event_available_rounded': Icons.event_available_rounded,
  'grade_rounded': Icons.grade_rounded,
  'schedule_send_rounded': Icons.schedule_send_rounded,
  'face_rounded': Icons.face_rounded,
  'school_rounded': Icons.school_rounded,
  'celebration_rounded': Icons.celebration_rounded,
  'emoji_events_rounded': Icons.emoji_events_rounded,
  'groups_rounded': Icons.groups_rounded,
  'admin_panel_settings_rounded': Icons.admin_panel_settings_rounded,
  'badge_rounded': Icons.badge_rounded,
  'event_busy_rounded': Icons.event_busy_rounded,
  'format_list_numbered_rounded': Icons.format_list_numbered_rounded,
  'assessment_rounded': Icons.assessment_rounded,
  'psychology_rounded': Icons.psychology_rounded,
  'reviews_rounded': Icons.reviews_rounded,
  'how_to_reg_rounded': Icons.how_to_reg_rounded,
  'notifications_active_rounded': Icons.notifications_active_rounded,
  'poll_rounded': Icons.poll_rounded,
  'bed_rounded': Icons.bed_rounded,
  'forum_rounded': Icons.forum_rounded,
  'payments_rounded': Icons.payments_rounded,
  'receipt_rounded': Icons.receipt_rounded,
  'request_quote_rounded': Icons.request_quote_rounded,
  'assignment_rounded': Icons.assignment_rounded,
  'query_stats_rounded': Icons.query_stats_rounded,
  'account_balance_rounded': Icons.account_balance_rounded,
  'volunteer_activism_rounded': Icons.volunteer_activism_rounded,
  'menu_book_rounded': Icons.menu_book_rounded,
  'library_books_rounded': Icons.library_books_rounded,
  'build_rounded': Icons.build_rounded,
  'support_agent_rounded': Icons.support_agent_rounded,
  'work_rounded': Icons.work_rounded,
  'description_rounded': Icons.description_rounded,
  'business_center_rounded': Icons.business_center_rounded,
  'person_add_alt_1_rounded': Icons.person_add_alt_1_rounded,
  'school_outlined': Icons.school_outlined,
  'face_retouching_natural_rounded': Icons.face_retouching_natural_rounded,
  'map_rounded': Icons.map_rounded,
  'vpn_key_rounded': Icons.vpn_key_rounded,
  'headset_mic_rounded': Icons.headset_mic_rounded,
  'apps_rounded': Icons.apps_rounded,
};

class AppEntry {
  AppEntry({
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.url,
    this.topSafeArea = true,
    this.bottomSafeArea = true,
    this.nativeDestination,
  }) : lightColor = color.withValues(alpha: 0.14);

  factory AppEntry.fromJson(Map<String, dynamic> j) {
    final iconKey = (j['icon'] as String?) ?? '';
    final colorHex = (j['color'] as String?) ?? '999999';
    return AppEntry(
      name: (j['name'] as String?) ?? '未命名',
      category: (j['category'] as String?) ?? '其他',
      icon: iconRegistry[iconKey] ?? Icons.apps_rounded,
      color: Color(int.parse('FF$colorHex', radix: 16)),
      url: (j['url'] as String?) ?? '',
      topSafeArea: (j['topSafeArea'] as bool?) ?? true,
      bottomSafeArea: (j['bottomSafeArea'] as bool?) ?? true,
      nativeDestination: switch (j['nativeDestination']) {
        'schedule' => AppNativeDestination.schedule,
        _ => null,
      },
    );
  }

  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final Color lightColor;
  final String url;
  final bool topSafeArea;
  final bool bottomSafeArea;
  final AppNativeDestination? nativeDestination;
}
