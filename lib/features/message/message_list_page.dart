import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'message_api.dart';
import 'message_conversation_page.dart';

const List<Color> _avatarColors = [
  Color(0xFF4A8AF4),
  Color(0xFFE94B3C),
  Color(0xFF22C55E),
  Color(0xFFFF7A00),
  Color(0xFF9B59B6),
  Color(0xFF1ABC9C),
  Color(0xFFE67E22),
  Color(0xFF3498DB),
  Color(0xFFE84393),
  Color(0xFF00B894),
];

class MessageListPage extends StatefulWidget {
  const MessageListPage({super.key, required this.active});

  final bool active;

  @override
  State<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends State<MessageListPage> {
  List<MessageCategory>? _categories;
  bool _initialLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    _loadFromCacheOrFetch();
  }

  @override
  void didUpdateWidget(covariant MessageListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _categories == null) {
      _loadFromCacheOrFetch();
    }
  }

  Future<void> _loadFromCacheOrFetch() async {
    // Try cache first
    final cached = MessageApi.cachedCategories;
    if (cached != null) {
      setState(() {
        _categories = cached.where((c) => c.hasMessages).toList();
        _initialLoading = false;
      });
      // Silent refresh in background
      _silentRefresh();
      return;
    }

    // No cache yet, wait for fetch
    setState(() => _initialLoading = true);
    try {
      final cats = await MessageApi.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats.where((c) => c.hasMessages).toList();
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initialLoading = false;
      });
    }
  }

  Future<void> _silentRefresh() async {
    await MessageApi.refreshCategoriesSilently();
    final updated = MessageApi.cachedCategories;
    if (!mounted || updated == null) return;
    setState(() {
      _categories = updated.where((c) => c.hasMessages).toList();
    });
  }

  Future<void> _pullRefresh() async {
    try {
      final cats = await MessageApi.fetchCategories(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _categories = cats.where((c) => c.hasMessages).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final subtitleColor = isDark
        ? const Color(0xFFB6C2BC)
        : const Color(0xFF777777);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              '消息',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: titleColor,
                fontWeight: wBold,
                letterSpacing: -0.8,
              ),
            ),
          ),
          Expanded(
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _categories == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '加载失败',
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: wBold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadFromCacheOrFetch,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _pullRefresh,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: _categories?.length ?? 0,
                      itemBuilder: (context, index) {
                        final cat = _categories![index];
                        return _CategoryTile(
                          category: cat,
                          color: _avatarColors[index % _avatarColors.length],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.color});

  final MessageCategory category;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF202124);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF5F6368);
    final hasUnread = category.unReadMsgCount > 0;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessageConversationPage(
              appId: category.appId,
              appName: category.appName,
              tagId: category.tagId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color,
                  child: Icon(
                    _iconForApp(category.appName),
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD44848),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF111513)
                              : Colors.white,
                          width: 2,
                        ),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        category.unReadMsgCount > 99
                            ? '99+'
                            : '${category.unReadMsgCount}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category.appName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: hasUnread
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: titleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (category.latestMsgSendDate != null)
                        Text(
                          _formatDate(category.latestMsgSendDate!),
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category.latestMsgContent ?? '暂无消息',
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForApp(String name) {
    if (name.contains('宿舍') || name.contains('水电')) {
      return Icons.water_drop_rounded;
    }
    if (name.contains('后勤') || name.contains('报修')) {
      return Icons.build_rounded;
    }
    if (name.contains('学工') || name.contains('签到')) {
      return Icons.school_rounded;
    }
    if (name.contains('必读')) return Icons.priority_high_rounded;
    if (name.contains('标旗')) return Icons.flag_rounded;
    if (name.contains('服务')) return Icons.miscellaneous_services_rounded;
    return Icons.notifications_rounded;
  }

  static String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final msgDay = DateTime(dt.year, dt.month, dt.day);
      if (msgDay == today) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final diff = today.difference(msgDay).inDays;
      if (diff == 1) return '昨天';
      if (dt.year == now.year) {
        return '${dt.month}/${dt.day}';
      }
      return '${dt.year}/${dt.month}/${dt.day}';
    } catch (_) {
      return dateStr;
    }
  }
}
