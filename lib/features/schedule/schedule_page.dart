import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/schedule_models.dart';
import 'schedule_api.dart';
import 'schedule_cache.dart';
import 'schedule_calendar_bridge.dart';
import 'schedule_csv_exporter.dart';
import 'schedule_ics_exporter.dart';
import '../webview/portal_webview_page.dart';

const _scheduleGreen = Color(0xFF22C55E);
const _scheduleGridLine = Color(0xFFE1ECE4);
const _lightScheduleGradient = <Color>[
  Color(0xFFC8F1D8),
  Color(0xFFEAF8EF),
  Colors.white,
];
const _darkScheduleGradient = <Color>[
  Color(0xFF123B24),
  Color(0xFF082413),
  Color(0xFF020503),
];
const _weekdayLabels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const _scheduleWebUrl =
    'http://ehall.uwh.edu.cn/jwmobile/auth/index?serviceKey=PK.WDKB';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final ScheduleRepository _repository = ScheduleRepository();
  Future<ScheduleData>? _scheduleFuture;
  int? _selectedWeek;

  @override
  void initState() {
    super.initState();
    _scheduleFuture = _createScheduleFuture();
  }

  void _load({String? termCode}) {
    final future = _createScheduleFuture(
      forceRefresh: true,
      termCode: termCode,
    );
    setState(() {
      _selectedWeek = null;
      _scheduleFuture = future;
    });
  }

  Future<ScheduleData> _createScheduleFuture({
    bool forceRefresh = false,
    String? termCode,
  }) {
    return Future<ScheduleData>.microtask(
      () => _repository.load(forceRefresh: forceRefresh, termCode: termCode),
    );
  }

  void _changeWeek(int week, ScheduleData schedule) {
    if (week < 1 || week > schedule.maxWeek) return;
    setState(() => _selectedWeek = week);
  }

  void _openScheduleWebPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PortalWebViewPage(
          title: '课表网页',
          icon: Icons.calendar_month_rounded,
          initialUrl: _scheduleWebUrl,
          accentColor: _scheduleGreen,
        ),
      ),
    );
  }

  Future<void> _exportCsv(ScheduleData schedule) async {
    final count = ScheduleCsvExporter.exportableCourseCount(schedule);
    if (count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前学期没有可导出的实体课程')));
      return;
    }
    try {
      await ScheduleCsvExporter.share(context, schedule);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV 导出失败：$error')));
    }
  }

  Future<void> _exportIcs(ScheduleData schedule) async {
    final count = ScheduleIcsExporter.exportableEventCount(schedule);
    if (count == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少学期日期或上课时间，暂时无法导出日历')));
      return;
    }
    try {
      await ScheduleIcsExporter.export(context, schedule);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ICS 导出失败：$error')));
    }
  }

  Future<void> _addToCalendar(ScheduleData schedule) async {
    final events = ScheduleIcsExporter.events(schedule);
    if (events.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缺少学期日期或上课时间，暂时无法添加到日历')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加到系统日历'),
        content: Text(
          '将创建或使用“芜忧皖江课表 ${schedule.term.name}”日历，并添加 '
          '${events.length} 个课程日程。之后可在系统日历的日历列表中单独管理或删除该日历。'
          '不会写入已有日历。重复执行可能产生重复日程，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _saveToDedicatedCalendar(schedule, events);
  }

  Future<void> _saveToDedicatedCalendar(
    ScheduleData schedule,
    List<ScheduleCalendarEvent> events, {
    bool canRequestFullAccess = true,
  }) async {
    try {
      final count = await ScheduleCalendarBridge.addEvents(
        events,
        calendarKey: schedule.term.code,
        calendarTitle: '芜忧皖江课表 ${schedule.term.name}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加 $count 个课程日程')));
    } on PlatformException catch (error) {
      if (!mounted) return;
      if (error.code == 'full_access_required' && canRequestFullAccess) {
        await _handleFullAccessRequired(schedule, events);
        return;
      }
      final message = switch (error.code) {
        'permission_denied' => '尚未获得日历权限，无法创建独立课表日历。',
        'calendar_save_failed' => '当前日历账户不允许创建独立日历。可以改用系统的 ICS 导入窗口。',
        _ => '创建独立课表日历失败。可以改用系统的 ICS 导入窗口。',
      };
      await _offerIcsImport(schedule, message);
    } catch (_) {
      if (!mounted) return;
      await _offerIcsImport(schedule, '创建独立课表日历失败。可以改用系统的 ICS 导入窗口。');
    }
  }

  Future<void> _handleFullAccessRequired(
    ScheduleData schedule,
    List<ScheduleCalendarEvent> events,
  ) async {
    final grantAccess = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要完整日历访问'),
        content: const Text(
          '“仅添加日程”权限不能创建新的独立日历。为了确保课程不会写入你的已有日历，'
          '需要授予完整访问权限来创建“芜忧皖江课表”日历。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('改用 ICS'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('授予完整访问'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (grantAccess != true) {
      await _openIcsImportSheet(schedule);
      return;
    }

    try {
      final granted = await ScheduleCalendarBridge.requestFullAccess();
      if (!mounted) return;
      if (granted) {
        await _saveToDedicatedCalendar(
          schedule,
          events,
          canRequestFullAccess: false,
        );
      } else {
        await _offerIcsImport(schedule, '未获得完整日历访问权限，无法创建独立课表日历。');
      }
    } on PlatformException {
      if (!mounted) return;
      await _offerIcsImport(schedule, '完整日历访问授权未完成，无法创建独立课表日历。');
    }
  }

  Future<void> _offerIcsImport(ScheduleData schedule, String message) async {
    final openImport = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法创建独立日历'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('打开 ICS 导入'),
          ),
        ],
      ),
    );
    if (openImport == true && mounted) {
      await _openIcsImportSheet(schedule);
    }
  }

  Future<void> _openIcsImportSheet(ScheduleData schedule) async {
    try {
      await ScheduleIcsExporter.openImportSheet(context, schedule);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 ICS 导入窗口')));
    }
  }

  Future<void> _chooseTerm(ScheduleData schedule) async {
    if (schedule.availableTerms.length < 2) return;
    final selectedCode = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.68,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '选择学期',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: schedule.availableTerms.length,
                  itemBuilder: (context, index) {
                    final term = schedule.availableTerms[index];
                    final selected = term.code == schedule.term.code;
                    return ListTile(
                      title: Text(term.name),
                      subtitle: term.name == term.code ? null : Text(term.code),
                      trailing: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: _scheduleGreen,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, term.code),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        selectedCode == null ||
        selectedCode == schedule.term.code) {
      return;
    }
    _load(termCode: selectedCode);
  }

  @override
  Widget build(BuildContext context) {
    final future = _scheduleFuture;
    if (future == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? _darkScheduleGradient
        : _lightScheduleGradient;

    return FutureBuilder<ScheduleData>(
      future: future,
      builder: (context, snapshot) {
        final schedule = snapshot.data;
        final selectedWeek = schedule == null
            ? null
            : (_selectedWeek ?? schedule.currentWeek)
                  .clamp(1, schedule.maxWeek)
                  .toInt();
        Widget body;
        if (snapshot.connectionState != ConnectionState.done) {
          body = const _ScheduleLoading();
        } else if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is ScheduleApiException
              ? error.message
              : '课表加载失败';
          body = _ScheduleError(
            message: message,
            onRetry: () => _load(termCode: schedule?.term.code),
          );
        } else {
          body = _ScheduleView(
            schedule: schedule!,
            selectedWeek: selectedWeek!,
            onChangeWeek: (week) => _changeWeek(week, schedule),
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
              stops: const [0, 0.15, 0.30],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              toolbarHeight: 64,
              titleSpacing: 2,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: schedule == null || selectedWeek == null
                  ? const Text('我的课表')
                  : _ScheduleAppBarTitle(
                      schedule: schedule,
                      onTap: () => _chooseTerm(schedule),
                    ),
              actions: [
                _ScheduleActionsMenu(
                  onRefresh: () => _load(termCode: schedule?.term.code),
                  onOpenWeb: _openScheduleWebPage,
                  onExportWakeUp: schedule == null
                      ? null
                      : () => unawaited(_exportCsv(schedule)),
                  onExportIcs: schedule == null
                      ? null
                      : () => unawaited(_exportIcs(schedule)),
                  onAddToCalendar:
                      schedule != null &&
                          defaultTargetPlatform == TargetPlatform.iOS
                      ? () => unawaited(_addToCalendar(schedule))
                      : null,
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: body,
          ),
        );
      },
    );
  }
}

class _ScheduleActionsMenu extends StatelessWidget {
  const _ScheduleActionsMenu({
    required this.onRefresh,
    required this.onOpenWeb,
    this.onExportWakeUp,
    this.onExportIcs,
    this.onAddToCalendar,
  });

  final VoidCallback onRefresh;
  final VoidCallback onOpenWeb;
  final VoidCallback? onExportWakeUp;
  final VoidCallback? onExportIcs;
  final VoidCallback? onAddToCalendar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final menuBackground = isDark
        ? const Color(0xFF13251A)
        : const Color(0xFFF4FAF6);
    final menuBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : _scheduleGreen.withValues(alpha: 0.16);
    return MenuAnchor(
      alignmentOffset: const Offset(-162, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(menuBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: menuBorder)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(5)),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: onRefresh,
          leadingIcon: const Icon(Icons.refresh_rounded, size: 19),
          style: _menuItemStyle(scheme),
          child: const Text('刷新缓存'),
        ),
        MenuItemButton(
          onPressed: onOpenWeb,
          leadingIcon: const Icon(Icons.open_in_browser_rounded, size: 19),
          style: _menuItemStyle(scheme),
          child: const Text('打开课表网页'),
        ),
        Divider(height: 9, indent: 10, endIndent: 10, color: menuBorder),
        MenuItemButton(
          onPressed: onExportWakeUp,
          leadingIcon: const Icon(Icons.file_download_outlined, size: 19),
          style: _menuItemStyle(scheme),
          child: const Text('导出 WakeUp'),
        ),
        MenuItemButton(
          onPressed: onExportIcs,
          leadingIcon: const Icon(Icons.calendar_month_outlined, size: 19),
          style: _menuItemStyle(scheme),
          child: const Text('导出 ICS 日历'),
        ),
        if (onAddToCalendar != null)
          MenuItemButton(
            onPressed: onAddToCalendar,
            leadingIcon: const Icon(Icons.event_available_outlined, size: 19),
            style: _menuItemStyle(scheme),
            child: const Text('添加到系统日历'),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        tooltip: '课表操作',
        onPressed: controller.isOpen ? controller.close : controller.open,
        icon: const Icon(Icons.more_vert_rounded),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          hoverColor: _scheduleGreen.withValues(alpha: 0.08),
          highlightColor: _scheduleGreen.withValues(alpha: 0.12),
          foregroundColor: scheme.onSurface,
        ),
      ),
    );
  }

  ButtonStyle _menuItemStyle(ColorScheme scheme) {
    return MenuItemButton.styleFrom(
      minimumSize: const Size(194, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      foregroundColor: scheme.onSurface,
      iconColor: _scheduleGreen,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.30),
      disabledIconColor: scheme.onSurface.withValues(alpha: 0.24),
      backgroundColor: Colors.transparent,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }
}

class _ScheduleAppBarTitle extends StatelessWidget {
  const _ScheduleAppBarTitle({required this.schedule, required this.onTap});

  final ScheduleData schedule;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: schedule.availableTerms.length > 1 ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                schedule.term.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (schedule.availableTerms.length > 1) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleView extends StatefulWidget {
  const _ScheduleView({
    required this.schedule,
    required this.selectedWeek,
    required this.onChangeWeek,
  });

  final ScheduleData schedule;
  final int selectedWeek;
  final ValueChanged<int> onChangeWeek;

  @override
  State<_ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<_ScheduleView> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.selectedWeek - 1);
  }

  @override
  void didUpdateWidget(covariant _ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWeek == widget.selectedWeek) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final currentPage = _pageController.page?.round();
      final targetPage = widget.selectedWeek - 1;
      if (currentPage != targetPage) _pageController.jumpToPage(targetPage);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectWeek(int week) {
    if (week < 1 || week > widget.schedule.maxWeek) return;
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      week - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 32),
      children: [
        _ScheduleHeader(
          schedule: widget.schedule,
          selectedWeek: widget.selectedWeek,
          onChangeWeek: _selectWeek,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: _ScheduleGrid.heightFor(widget.schedule),
          child: PageView.builder(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.schedule.maxWeek,
            onPageChanged: (index) => widget.onChangeWeek(index + 1),
            itemBuilder: (context, index) {
              return _ScheduleGrid(
                key: ValueKey<int>(index + 1),
                schedule: widget.schedule,
                week: index + 1,
              );
            },
          ),
        ),
        if (widget.schedule.onlineCourses.isNotEmpty) ...[
          const SizedBox(height: 20),
          _OnlineCourses(courses: widget.schedule.onlineCourses),
        ],
      ],
    );
  }
}

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({
    required this.schedule,
    required this.selectedWeek,
    required this.onChangeWeek,
  });

  final ScheduleData schedule;
  final int selectedWeek;
  final ValueChanged<int> onChangeWeek;

  @override
  Widget build(BuildContext context) {
    final canGoBack = selectedWeek > 1;
    final canGoForward = selectedWeek < schedule.maxWeek;
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          _WeekArrowButton(
            tooltip: '上一周',
            enabled: canGoBack,
            icon: Icons.chevron_left_rounded,
            onPressed: () => onChangeWeek(selectedWeek - 1),
          ),
          Expanded(
            child: Center(
              child: Text(
                '第 $selectedWeek 周',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _scheduleGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _WeekArrowButton(
            tooltip: '下一周',
            enabled: canGoForward,
            icon: Icons.chevron_right_rounded,
            onPressed: () => onChangeWeek(selectedWeek + 1),
          ),
        ],
      ),
    );
  }
}

class _WeekArrowButton extends StatelessWidget {
  const _WeekArrowButton({
    required this.tooltip,
    required this.enabled,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool enabled;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      iconSize: 22,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        foregroundColor: _scheduleGreen,
        disabledForegroundColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.25),
      ),
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  const _ScheduleGrid({super.key, required this.schedule, required this.week});

  final ScheduleData schedule;
  final int week;

  static const _timeColumnWidth = 44.0;
  static const _headerHeight = 58.0;
  static const _periodHeight = 64.0;

  static double heightFor(ScheduleData schedule) {
    final maxPeriod = _maxPeriod(schedule);
    return maxPeriod == 0 ? 220 : _headerHeight + maxPeriod * _periodHeight;
  }

  @override
  Widget build(BuildContext context) {
    final periods = _periodsFor(schedule);
    if (periods.isEmpty) return const _EmptySchedule();

    final minPeriod = periods.first;
    final gridHeight = periods.length * _periodHeight;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = isDark ? const Color(0xFF2B3930) : _scheduleGridLine;
    final weekStart = schedule.term.startDate?.add(
      Duration(days: (week - 1) * 7),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - _timeColumnWidth;
        final dayWidth = gridWidth / _weekdayLabels.length;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            children: [
              SizedBox(
                height: _headerHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Center(
                        child: Text(
                          weekStart == null ? '节次' : '${weekStart.month}月',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: _subtleText(context)),
                        ),
                      ),
                    ),
                    ...List<Widget>.generate(_weekdayLabels.length, (index) {
                      final weekday = index + 1;
                      final hasCourse = schedule
                          .coursesForWeekday(week: week, weekday: weekday)
                          .isNotEmpty;
                      final date = weekStart?.add(Duration(days: index));
                      final isToday =
                          date != null &&
                          DateUtils.isSameDay(date, DateTime.now());
                      return SizedBox(
                        width: dayWidth,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _weekdayLabels[index].replaceFirst('周', ''),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: _subtleText(context)),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? _scheduleGreen
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  date?.day.toString() ?? '',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: isToday
                                            ? Colors.white
                                            : hasCourse
                                            ? _scheduleGreen
                                            : _subtleText(context),
                                        fontWeight: hasCourse || isToday
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              SizedBox(
                height: gridHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Column(
                        children: periods
                            .map(
                              (period) => SizedBox(
                                height: _periodHeight,
                                child: _PeriodLabel(
                                  period: period,
                                  lessonTime: schedule.lessonTimeForPeriod(
                                    period,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    SizedBox(
                      width: gridWidth,
                      height: gridHeight,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: Size(gridWidth, gridHeight),
                            painter: _ScheduleGridPainter(
                              dayWidth: dayWidth,
                              periodHeight: _periodHeight,
                              dayCount: _weekdayLabels.length,
                              periodCount: periods.length,
                              lineColor: line,
                            ),
                          ),
                          for (
                            var weekday = 1;
                            weekday <= _weekdayLabels.length;
                            weekday += 1
                          )
                            ...schedule
                                .coursesForWeekday(week: week, weekday: weekday)
                                .map(
                                  (course) => _CourseBlock(
                                    course: course,
                                    left: (weekday - 1) * dayWidth + 2,
                                    top:
                                        (course.startPeriod - minPeriod) *
                                            _periodHeight +
                                        2,
                                    width: dayWidth - 4,
                                    height:
                                        course.periodCount * _periodHeight - 4,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<int> _periodsFor(ScheduleData schedule) {
    final maxPeriod = _maxPeriod(schedule);
    if (maxPeriod == 0) return const <int>[];
    return List<int>.generate(maxPeriod, (index) => index + 1);
  }

  static int _maxPeriod(ScheduleData schedule) {
    var maxPeriod = 0;
    for (final course in schedule.courses) {
      if (course.endPeriod > maxPeriod) {
        maxPeriod = course.endPeriod;
      }
    }
    for (final lessonTime in schedule.lessonTimes) {
      if (lessonTime.period > maxPeriod) maxPeriod = lessonTime.period;
    }
    return maxPeriod;
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.period, required this.lessonTime});

  final int period;
  final ScheduleLessonTime? lessonTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        children: [
          Text(
            period.toString(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _scheduleGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lessonTime != null) ...[
            const SizedBox(height: 2),
            Text(
              lessonTime!.startTime,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _subtleText(context),
                fontSize: 9,
              ),
            ),
            Text(
              lessonTime!.endTime,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _subtleText(context),
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleGridPainter extends CustomPainter {
  const _ScheduleGridPainter({
    required this.dayWidth,
    required this.periodHeight,
    required this.dayCount,
    required this.periodCount,
    required this.lineColor,
  });

  final double dayWidth;
  final double periodHeight;
  final int dayCount;
  final int periodCount;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var day = 0; day <= dayCount; day += 1) {
      final x = day * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var period = 0; period <= periodCount; period += 1) {
      final y = period * periodHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScheduleGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _CourseBlock extends StatelessWidget {
  const _CourseBlock({
    required this.course,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final ScheduleCourse course;
  final double left;
  final double top;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = _courseColor(course.name, Theme.of(context).brightness);
    final section = course.sectionCode.isEmpty ? '' : '[${course.sectionCode}]';
    final classroom = course.classroom.isEmpty
        ? ''
        : '@${_compactClassroom(course.classroom)}';
    final label = <String>[
      course.name,
      section,
      classroom,
    ].where((part) => part.isNotEmpty).join('\n');
    final maxLines = (height / 14).floor().clamp(1, 14).toInt();
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScheduleCourseDetailPage(course: course),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.foreground,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoursePalette {
  const _CoursePalette(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

_CoursePalette _courseColor(String courseName, Brightness brightness) {
  const lightPalettes = <_CoursePalette>[
    _CoursePalette(Color(0xFF70A7E8), Colors.white),
    _CoursePalette(Color(0xFF63BE91), Colors.white),
    _CoursePalette(Color(0xFFE58B72), Colors.white),
    _CoursePalette(Color(0xFFD97898), Colors.white),
    _CoursePalette(Color(0xFF8797D8), Colors.white),
    _CoursePalette(Color(0xFFA17FD0), Colors.white),
    _CoursePalette(Color(0xFF55B7AD), Colors.white),
    _CoursePalette(Color(0xFFD97EAF), Colors.white),
    _CoursePalette(Color(0xFF669FDC), Colors.white),
    _CoursePalette(Color(0xFF55AFCA), Colors.white),
    _CoursePalette(Color(0xFF83AD55), Colors.white),
    _CoursePalette(Color(0xFFD99B50), Colors.white),
  ];
  const darkPalettes = <_CoursePalette>[
    _CoursePalette(Color(0xFF2F6FB9), Colors.white),
    _CoursePalette(Color(0xFF1F7F4B), Colors.white),
    _CoursePalette(Color(0xFFA85410), Colors.white),
    _CoursePalette(Color(0xFFB83E4E), Colors.white),
    _CoursePalette(Color(0xFF68727E), Colors.white),
    _CoursePalette(Color(0xFF8053B8), Colors.white),
    _CoursePalette(Color(0xFF0E746B), Colors.white),
    _CoursePalette(Color(0xFFC13E75), Colors.white),
    _CoursePalette(Color(0xFF4D5FB5), Colors.white),
    _CoursePalette(Color(0xFF187F9A), Colors.white),
    _CoursePalette(Color(0xFF477A18), Colors.white),
    _CoursePalette(Color(0xFF8A5707), Colors.white),
  ];
  final palettes = brightness == Brightness.dark ? darkPalettes : lightPalettes;
  var hash = 0;
  for (final codeUnit in courseName.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return palettes[hash % palettes.length];
}

String _compactClassroom(String classroom) {
  return classroom.replaceAll('教学楼', '·');
}

class _OnlineCourses extends StatelessWidget {
  const _OnlineCourses({required this.courses});

  final List<ScheduleOnlineCourse> courses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '网络课程',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...courses.map((course) {
          final palette = _courseColor(
            course.name,
            Theme.of(context).brightness,
          );
          final title = course.sectionCode.isEmpty
              ? course.name
              : '${course.name}[${course.sectionCode}]';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: palette.background,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          _ScheduleOnlineCourseDetail(course: course),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: palette.foreground,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            if (course.teacher.isNotEmpty ||
                                course.weekDescription.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                _joinPresent(<String>[
                                  course.teacher,
                                  course.weekDescription,
                                ]),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: palette.foreground.withValues(
                                        alpha: 0.84,
                                      ),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.foreground.withValues(alpha: 0.72),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF17251C)
            : const Color(0xFFEAF7EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            color: _scheduleGreen.withValues(alpha: 0.7),
            size: 36,
          ),
          const SizedBox(height: 10),
          Text(
            '这一周没有课程安排',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _subtleText(context)),
          ),
        ],
      ),
    );
  }
}

class ScheduleCourseDetailPage extends StatelessWidget {
  const ScheduleCourseDetailPage({super.key, required this.course});

  final ScheduleCourse course;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final gradientColors = brightness == Brightness.dark
        ? _darkScheduleGradient
        : _lightScheduleGradient;
    final palette = _courseColor(course.name, brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
          stops: const [0, 0.15, 0.30],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('课程详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _CourseDetailHero(course: course, palette: palette),
            const SizedBox(height: 16),
            _DetailSection(
              icon: Icons.school_outlined,
              title: '课程信息',
              children: [
                _DetailRow(label: '课程号', value: course.courseCode),
                _DetailRow(label: '课序号', value: course.sectionCode),
                _DetailRow(label: '上课班级', value: course.teachingClass),
                _DetailRow(label: '学分', value: _formatNumber(course.credits)),
                _DetailRow(label: '学时', value: course.totalHours.toString()),
                _DetailRow(label: '考核方式', value: course.assessmentType),
                _DetailRow(label: '课程性质', value: course.courseNature),
                _DetailRow(label: '课程类别', value: course.courseCategory),
                _DetailRow(label: '开课单位', value: course.offeringDepartment),
              ],
            ),
            const SizedBox(height: 12),
            _DetailSection(
              icon: Icons.schedule_rounded,
              title: '上课安排',
              children: [
                _DetailRow(label: '星期', value: course.displayWeekday),
                _DetailRow(
                  label: '节次',
                  value: '第 ${course.startPeriod}-${course.endPeriod} 节',
                ),
                _DetailRow(
                  label: '时间',
                  value: _joinPresent(<String>[
                    course.startTime,
                    course.endTime,
                  ], separator: ' - '),
                ),
                _DetailRow(label: '上课周次', value: course.weekDescription),
                _DetailRow(label: '服务端周次', value: course.serverWeekDescription),
                _DetailRow(label: '本次教室', value: course.classroom),
                _DetailRow(label: '教学楼', value: course.building),
                _DetailRow(label: '校区', value: course.campus),
              ],
            ),
            if (course.plannedSchedule.isNotEmpty) ...[
              const SizedBox(height: 12),
              _DetailSection(
                icon: Icons.format_list_bulleted_rounded,
                title: '完整排课',
                children: [
                  _DetailRow(
                    label: '排课信息',
                    value: course.plannedSchedule,
                    stacked: true,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleOnlineCourseDetail extends StatelessWidget {
  const _ScheduleOnlineCourseDetail({required this.course});

  final ScheduleOnlineCourse course;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final gradientColors = brightness == Brightness.dark
        ? _darkScheduleGradient
        : _lightScheduleGradient;
    final palette = _courseColor(course.name, brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
          stops: const [0, 0.15, 0.30],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('网络课程详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _OnlineCourseDetailHero(course: course, palette: palette),
            const SizedBox(height: 16),
            _DetailSection(
              icon: Icons.school_outlined,
              title: '课程信息',
              children: [
                _DetailRow(label: '课程号', value: course.courseCode),
                _DetailRow(label: '课序号', value: course.sectionCode),
                _DetailRow(label: '教师', value: course.teacher),
                _DetailRow(label: '学分', value: _formatNumber(course.credits)),
                _DetailRow(label: '学时', value: course.totalHours.toString()),
                _DetailRow(label: '学期', value: course.termCode),
              ],
            ),
            const SizedBox(height: 12),
            _DetailSection(
              icon: Icons.calendar_month_outlined,
              title: '学习安排',
              children: [
                _DetailRow(label: '开课周次', value: course.weekDescription),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlineCourseDetailHero extends StatelessWidget {
  const _OnlineCourseDetailHero({required this.course, required this.palette});

  final ScheduleOnlineCourse course;
  final _CoursePalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: palette.background.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.language_rounded, color: palette.foreground, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  course.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.foreground,
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                  ),
                ),
              ),
            ],
          ),
          if (course.sectionCode.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '课序号 ${course.sectionCode}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.foreground.withValues(alpha: 0.86),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (course.teacher.isNotEmpty)
            _DetailHeroLine(
              icon: Icons.person_outline_rounded,
              value: course.teacher,
            ),
          if (course.weekDescription.isNotEmpty)
            _DetailHeroLine(
              icon: Icons.calendar_month_outlined,
              value: course.weekDescription,
            ),
        ],
      ),
    );
  }
}

class _CourseDetailHero extends StatelessWidget {
  const _CourseDetailHero({required this.course, required this.palette});

  final ScheduleCourse course;
  final _CoursePalette palette;

  @override
  Widget build(BuildContext context) {
    final time = _joinPresent(<String>[
      course.displayWeekday,
      '第 ${course.startPeriod}-${course.endPeriod} 节',
    ]);
    final location = _joinPresent(<String>[course.classroom, course.campus]);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            course.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.foreground,
              fontWeight: FontWeight.w800,
              height: 1.22,
            ),
          ),
          if (course.sectionCode.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '课序号 ${course.sectionCode}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.foreground.withValues(alpha: 0.86),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (course.teacher.isNotEmpty)
            _DetailHeroLine(
              icon: Icons.person_outline_rounded,
              value: course.teacher,
            ),
          _DetailHeroLine(icon: Icons.schedule_rounded, value: time),
          if (location.isNotEmpty)
            _DetailHeroLine(icon: Icons.location_on_outlined, value: location),
        ],
      ),
    );
  }
}

class _DetailHeroLine extends StatelessWidget {
  const _DetailHeroLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF14251A).withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFD9EBDF).withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: _scheduleGreen),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.stacked = false,
  });

  final String label;
  final String value;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == '0') return const SizedBox.shrink();
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: _subtleText(context));
    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: 6),
            SelectableText(value),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 82, child: Text(label, style: labelStyle)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _ScheduleLoading extends StatelessWidget {
  const _ScheduleLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: _scheduleGreen),
    );
  }
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 40),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新抓取'),
            ),
          ],
        ),
      ),
    );
  }
}

Color _subtleText(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.58);
}

String _joinPresent(List<String> values, {String separator = ' · '}) {
  return values.where((value) => value.trim().isNotEmpty).join(separator);
}

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}
