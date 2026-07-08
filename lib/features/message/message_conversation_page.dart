import 'package:flutter/material.dart';

import '../../core/utils/route_utils.dart';
import '../webview/portal_webview_page.dart';
import 'message_api.dart';

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

class MessageConversationPage extends StatefulWidget {
  const MessageConversationPage({
    super.key,
    required this.appId,
    required this.appName,
    required this.tagId,
  });

  final String appId;
  final String appName;
  final int tagId;

  @override
  State<MessageConversationPage> createState() =>
      _MessageConversationPageState();
}

class _MessageConversationPageState extends State<MessageConversationPage> {
  final List<MessageItem> _messages = [];
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  int _totalPages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  late final Color _avatarColor;
  late final IconData _avatarIcon;

  @override
  void initState() {
    super.initState();
    _avatarColor =
        _avatarColors[widget.appName.hashCode.abs() % _avatarColors.length];
    _avatarIcon = _iconForApp(widget.appName);
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _currentPage < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await MessageApi.fetchMessages(
        appId: widget.appId,
        current: 1,
      );
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(result.records);
        _currentPage = result.current;
        _totalPages = result.pages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _currentPage >= _totalPages) return;
    _loadingMore = true;
    setState(() {});
    try {
      final nextPage = _currentPage + 1;
      final result = await MessageApi.fetchMessages(
        appId: widget.appId,
        current: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _messages.addAll(result.records);
        _currentPage = result.current;
        _totalPages = result.pages;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
      if (mounted) setState(() {});
    }
  }

  void _showMessageSheet(MessageItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      barrierColor: Colors.black54,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onTap: () {},
          child: _MessageDetailSheet(
          message: item,
          avatarColor: _avatarColor,
          avatarIcon: _avatarIcon,
          appName: widget.appName,
          parentContext: context,
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = scheme.onSurface;
    final bgColor = isDark ? const Color(0xFF111513) : const Color(0xFFF5F5F3);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.appName),
        backgroundColor: scheme.surface,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('加载失败', style: TextStyle(color: titleColor)),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text('暂无消息',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        itemCount:
                            _messages.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          return _MessageCard(
                            message: _messages[index],
                            avatarColor: _avatarColor,
                            avatarIcon: _avatarIcon,
                            appName: widget.appName,
                            onTap: () => _showMessageSheet(_messages[index]),
                          );
                        },
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
}

// ---------------------------------------------------------------------------
// Card in list (truncated)
// ---------------------------------------------------------------------------

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.avatarColor,
    required this.avatarIcon,
    required this.appName,
    required this.onTap,
  });

  final MessageItem message;
  final Color avatarColor;
  final IconData avatarIcon;
  final String appName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1F1C) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF202124);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF5F6368);
    final metaColor = isDark ? Colors.white38 : const Color(0xFF9AA0A6);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: avatarColor,
                      child:
                          Icon(avatarIcon, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                          Text(
                            _formatTime(message.msgSendDate),
                            style:
                                TextStyle(fontSize: 12, color: metaColor),
                          ),
                        ],
                      ),
                    ),
                    if (!message.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFD44848),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // Title
                Text(
                  message.msgTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Content (truncated)
                if (message.msgContent.isNotEmpty &&
                    message.msgContent != message.msgTitle) ...[
                  const SizedBox(height: 8),
                  Text(
                    message.msgContent,
                    style: TextStyle(
                      fontSize: 14,
                      color: bodyColor,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail bottom sheet (half → full screen draggable)
// ---------------------------------------------------------------------------

class _MessageDetailSheet extends StatefulWidget {
  const _MessageDetailSheet({
    required this.message,
    required this.avatarColor,
    required this.avatarIcon,
    required this.appName,
    required this.parentContext,
  });

  final MessageItem message;
  final Color avatarColor;
  final IconData avatarIcon;
  final String appName;
  final BuildContext parentContext;

  @override
  State<_MessageDetailSheet> createState() => _MessageDetailSheetState();
}

class _MessageDetailSheetState extends State<_MessageDetailSheet> {
  MessageDetail? _detail;
  bool _loadingDetail = true;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    try {
      final d = await MessageApi.fetchDetail(
        id: widget.message.id,
        msgId: widget.message.msgId,
      );
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loadingDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetail = false);
    }
  }

  void _openLink(String url, String title) {
    Navigator.of(context).pop();
    Navigator.of(widget.parentContext).push(
      createSlideFadeRoute(
        PortalWebViewPage(
          title: title,
          icon: Icons.open_in_new_rounded,
          initialUrl: url,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1A1F1C) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF202124);
    final bodyColor = isDark ? Colors.white70 : const Color(0xFF2C3E50);
    final metaColor = isDark ? Colors.white38 : const Color(0xFF9AA0A6);
    final dividerColor =
        isDark ? const Color(0xFF2A2F2C) : const Color(0xFFE8E8E5);

    final content = _detail?.msgContent ?? widget.message.msgContent;
    final title = _detail?.msgTitle ?? widget.message.msgTitle;
    final redirectUrl = _detail?.redirectUrl;
    final directUrl = widget.message.mobileUrl ?? widget.message.pcUrl;
    final linkUrl = redirectUrl ?? directUrl;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.0,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.55, 0.92],
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: metaColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    // Header
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: widget.avatarColor,
                          child: Icon(widget.avatarIcon,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _detail?.appName ?? widget.appName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: titleColor,
                                ),
                              ),
                              Text(
                                _detail?.msgSendDate ??
                                    widget.message.msgSendDate,
                                style: TextStyle(
                                    fontSize: 13, color: metaColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.4,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, thickness: 0.5, color: dividerColor),
                    const SizedBox(height: 16),
                    // Body
                    if (_loadingDetail && content == widget.message.msgContent)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: metaColor,
                            ),
                          ),
                        ),
                      )
                    else
                      Text(
                        content,
                        style: TextStyle(
                          fontSize: 15,
                          color: bodyColor,
                          height: 1.7,
                        ),
                      ),
                    // Link button
                    if (linkUrl != null && linkUrl.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Divider(
                          height: 1, thickness: 0.5, color: dividerColor),
                      InkWell(
                        onTap: () => _openLink(linkUrl, title),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              Text(
                                '查看详情',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: titleColor,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded,
                                  size: 20, color: metaColor),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _formatTime(String dateStr) {
  try {
    final dt = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    String dayPart;
    final diff = today.difference(msgDay).inDays;
    if (diff == 0) {
      dayPart = '今天';
    } else if (diff == 1) {
      dayPart = '昨天';
    } else if (diff < 7) {
      dayPart = weekdays[dt.weekday - 1];
    } else {
      dayPart =
          '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    }
    final timePart =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$dayPart $timePart';
  } catch (_) {
    return dateStr;
  }
}
