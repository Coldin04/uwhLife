import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/boundary_debug_settings.dart';
import '../../core/storage/home_page_settings.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_user_store.dart';
import '../../core/theme/app_theme.dart';
import '../auth/portal_auto_login.dart';
import '../auth/portal_session_cookies.dart';
import '../door/door_api.dart';
import '../schedule/models/schedule_models.dart';
import '../schedule/schedule_cache.dart';
import '../schedule/schedule_occurrences.dart';
import 'widgets/home_cards.dart';
import 'widgets/status_indicator.dart';

// 只用在问候语上，比正文重一档（普惠体真实档位只有 400/500/700）。
const FontWeight _homePageSemiBold = FontWeight.w500;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onOpenAppList,
    this.onOpenPortal,
    this.onOpenPayCode,
    this.onOpenSchedule,
    this.onOpenClassroom,
    this.onOpenBath,
  });

  final VoidCallback? onOpenAppList;
  final Future<void> Function()? onOpenPortal;
  final Future<void> Function()? onOpenPayCode;
  final Future<void> Function()? onOpenSchedule;
  final Future<void> Function()? onOpenClassroom;
  final Future<void> Function()? onOpenBath;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _probeUrl = 'https://ehall.uwh.edu.cn/getLoginUser';
  static const _idsSsoProbeUrl =
      'https://ids.uwh.edu.cn/authserver/login'
      '?service=https%3A%2F%2Fehall.uwh.edu.cn%2Flogin';
  static const _hitokotoCacheKey = 'home_hitokoto_text';
  static const _hitokotoUrl = 'https://v1.hitokoto.cn/?encode=json&c=i&c=k';
  static const _defaultHitokoto = '读万卷书，行万里路';
  bool _loggedIn = false;
  String _hitokoto = _defaultHitokoto;
  final ScheduleRepository _scheduleRepository = ScheduleRepository();
  ScheduleCourseOccurrence? _scheduleHintCourse;
  bool _scheduleHintIsCurrent = false;
  bool _hasScheduleHintData = false;
  bool _mockScheduleHint = false;
  bool _iconOnlyMode = false;
  bool _loadingScheduleHint = false;
  Timer? _scheduleHintTimer;
  late final WebViewController _probeController;
  Completer<({String body, String url})>? _probeCompleter;
  Object _probeToken = Object();
  bool _probing = false;

  bool _doorBusy = false;
  String? _doorMessage;
  Timer? _doorMessageTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            final token = _probeToken;
            final c = _probeCompleter;
            if (c == null || c.isCompleted) return;
            try {
              final r = await _probeController.runJavaScriptReturningResult(
                'document.body ? document.body.innerText : ""',
              );
              if (!mounted || token != _probeToken || c.isCompleted) return;
              c.complete((body: r.toString(), url: url));
            } catch (_) {
              if (!mounted || token != _probeToken || c.isCompleted) return;
              c.complete((body: '', url: url));
            }
          },
          onWebResourceError: (_) {
            final token = _probeToken;
            final c = _probeCompleter;
            if (c != null && token == _probeToken && !c.isCompleted) {
              c.complete((body: '', url: ''));
            }
          },
        ),
      );
    _loadLoginState();
    _loadMockScheduleHint();
    _loadHomePageSettings();
    _loadHitokoto();
    unawaited(_refreshScheduleHint());
    _probeAndSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doorMessageTimer?.cancel();
    _scheduleHintTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLoginState();
      _loadMockScheduleHint();
      _loadHomePageSettings();
      unawaited(_refreshScheduleHint());
      _probeAndSync();
    }
  }

  Future<void> refreshDebugSettings() async {
    await Future.wait(<Future<void>>[
      _loadMockScheduleHint(),
      _loadHomePageSettings(),
    ]);
  }

  Future<void> _loadMockScheduleHint() async {
    final settings = await BoundaryDebugSettings.read();
    if (!mounted || _mockScheduleHint == settings.mockScheduleHint) return;
    setState(() => _mockScheduleHint = settings.mockScheduleHint);
  }

  Future<void> _loadHomePageSettings() async {
    final settings = await HomePageSettings.read();
    if (!mounted || _iconOnlyMode == settings.iconOnlyMode) return;
    setState(() => _iconOnlyMode = settings.iconOnlyMode);
  }

  Future<void> triggerDoorFromDeepLink() => _triggerDoor();

  Future<void> _loadLoginState() async {
    final loggedIn = await LoginStateStore.readLoggedIn();
    if (!mounted) return;
    if (!loggedIn) _scheduleHintTimer?.cancel();
    setState(() => _loggedIn = loggedIn);
    if (!loggedIn && _hasScheduleHintData) {
      setState(() {
        _hasScheduleHintData = false;
        _scheduleHintCourse = null;
        _scheduleHintIsCurrent = false;
      });
    }
  }

  Future<void> _refreshScheduleHint() async {
    if (_loadingScheduleHint) return;
    _loadingScheduleHint = true;
    try {
      if (!await LoginStateStore.readLoggedIn()) {
        if (!mounted) return;
        _scheduleHintTimer?.cancel();
        if (_hasScheduleHintData) {
          setState(() {
            _hasScheduleHintData = false;
            _scheduleHintCourse = null;
            _scheduleHintIsCurrent = false;
          });
        }
        return;
      }
      final now = DateTime.now();
      final cached = await ScheduleCache.read(now: now);
      ScheduleData? schedule;
      if (cached?.schedule.isCurrentTerm == true) {
        schedule = cached!.schedule;
      } else {
        try {
          schedule = await _scheduleRepository.load(
            forceRefresh: cached != null,
          );
          if (!schedule.isCurrentTerm) schedule = null;
        } catch (_) {
          schedule = null;
        }
      }
      if (!mounted) return;
      if (schedule == null) {
        _scheduleHintTimer?.cancel();
        if (_hasScheduleHintData) {
          setState(() {
            _hasScheduleHintData = false;
            _scheduleHintCourse = null;
            _scheduleHintIsCurrent = false;
          });
        }
        return;
      }
      _applyScheduleHint(schedule);
    } finally {
      _loadingScheduleHint = false;
    }
  }

  void _applyScheduleHint(ScheduleData schedule) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final windowEnd = today.add(const Duration(days: 2));
    final current = ScheduleOccurrenceMapper.currentAt(schedule, now: now);
    final next = current == null
        ? ScheduleOccurrenceMapper.nextBefore(
            schedule,
            now: now,
            endExclusive: windowEnd,
          )
        : null;
    final displayedCourse = current ?? next;
    if (mounted) {
      setState(() {
        _hasScheduleHintData = true;
        _scheduleHintCourse = displayedCourse;
        _scheduleHintIsCurrent = current != null;
      });
    }

    _scheduleHintTimer?.cancel();
    final boundary =
        current?.end ?? next?.start ?? today.add(const Duration(days: 1));
    final delay = boundary.difference(now) + const Duration(seconds: 1);
    if (delay <= Duration.zero) return;
    _scheduleHintTimer = Timer(delay, () {
      if (mounted) _applyScheduleHint(schedule);
    });
  }

  void _loadHitokoto() {
    unawaited(_loadCachedHitokoto());
    unawaited(_refreshHitokoto());
  }

  Future<void> _loadCachedHitokoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_hitokotoCacheKey)?.trim();
      if (cached == null || cached.isEmpty || !mounted) return;
      if (_hitokoto == cached) return;
      setState(() {
        _hitokoto = cached;
      });
    } catch (_) {}
  }

  Future<void> _refreshHitokoto() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse(_hitokotoUrl));
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is Map && data['hitokoto'] is String) {
        final text = (data['hitokoto'] as String).trim();
        if (text.isEmpty || !mounted) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_hitokotoCacheKey, text);
        if (!mounted || _hitokoto == text) return;
        setState(() {
          _hitokoto = text;
        });
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _probeAndSync() async {
    if (_probing) return;
    _probing = true;
    try {
      var res = await _runProbe();

      // Ehall 会话失效而 IDS SSO 仍有效时，getLoginUser 可能先落到 IDS。
      // 先实际跑一遍 IDS → Ehall 的 SSO 链，而不是立刻显示“掉登录”。
      if (_isIdsLoginResult(res)) {
        final sso = await _runRequest(_idsSsoProbeUrl);
        if (!_isIdsLoginResult(sso) && sso.url.isNotEmpty) {
          res = await _runProbe();
        }
      }

      final portalVerified = await _syncPortalUser(res);
      if (portalVerified) {
        // 反向检查 IDS：Ehall Cookie 可以独立于 IDS SSO Cookie 存活。只有
        // IDS 最终停在登录页时才需要恢复；网络异常保持当前 Ehall 状态。
        final sso = await _runRequest(_idsSsoProbeUrl);
        if (_isIdsLoginResult(sso)) {
          final restored = await _restoreSessionOnce();
          if (!restored) return;
          res = await _runProbe();
          if (!await _syncPortalUser(res)) {
            await LoginStateStore.markLoggedOut();
            return;
          }
        }
      } else if (_isIdsLoginResult(res)) {
        if (!await _restoreSessionOnce()) return;
        res = await _runProbe();
        if (!await _syncPortalUser(res)) {
          await LoginStateStore.markLoggedOut();
          return;
        }
      } else if (!await LoginStateStore.readLoggedIn()) {
        return;
      }
      if (mounted) {
        await _loadLoginState();
        unawaited(_refreshScheduleHint());
      }
    } finally {
      _probing = false;
    }
  }

  Future<({String body, String url})> _runProbe() async {
    return _runRequest(_probeUrl);
  }

  Future<({String body, String url})> _runRequest(String url) async {
    final token = Object();
    final completer = Completer<({String body, String url})>();
    _probeToken = token;
    _probeCompleter = completer;
    try {
      await _probeController.loadRequest(Uri.parse(url));
      return await completer.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => (body: '', url: ''),
      );
    } finally {
      if (_probeToken == token && identical(_probeCompleter, completer)) {
        _probeCompleter = null;
        _probeToken = Object();
      }
    }
  }

  bool _isIdsLoginResult(({String body, String url}) result) {
    final uri = Uri.tryParse(result.url);
    return uri?.host.toLowerCase() == 'ids.uwh.edu.cn' &&
        uri?.path.toLowerCase().contains('/authserver/login') == true;
  }

  Future<bool> _syncPortalUser(({String body, String url}) result) async {
    if (!await PortalUserStore.saveFromLoginUserResponse(result.body)) {
      return false;
    }
    await LoginStateStore.markLoggedIn();
    return true;
  }

  Future<bool> _restoreSessionOnce() async {
    final outcome = await PortalAutoLogin.instance.restoreSession(force: true);
    if (outcome == PortalAutoLoginOutcome.restored) return true;
    await LoginStateStore.markLoggedOut();
    if (mounted) await _loadLoginState();
    return false;
  }

  Future<void> _clearLoginState() async {
    await LoginStateStore.markManualLogout();
    if (!mounted) return;
    _scheduleHintTimer?.cancel();
    setState(() {
      _loggedIn = false;
      _hasScheduleHintData = false;
      _scheduleHintCourse = null;
      _scheduleHintIsCurrent = false;
    });
  }

  Future<void> _openPortal() async {
    await widget.onOpenPortal?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openPayCode() async {
    await widget.onOpenPayCode?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openSchedule() async {
    await widget.onOpenSchedule?.call();
    if (!mounted) return;
    await _refreshScheduleHint();
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openClassroom() async {
    await widget.onOpenClassroom?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openBath() async {
    await widget.onOpenBath?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _confirmClearLoginState() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除登录状态'),
          content: const Text(
            '将清除 App 内全局浏览器数据（Cookie、缓存、站点存储），并重置右上角状态；不会删除已保存的密码。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: dialogQuietAction(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: dialogPrimaryAction(context),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await BrowserDataCleaner.clear();
    await PortalSessionCookies.clear();
    await _clearLoginState();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除登录状态')));
  }

  Future<void> _triggerDoor() async {
    if (_doorBusy) return;
    _doorMessageTimer?.cancel();
    setState(() {
      _doorBusy = true;
      _doorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await DoorApi.openDoor();

      if (!mounted) return;
      switch (result.status) {
        case DoorOpenStatus.opened:
          _showDoorMessage(result.message);
          break;
        case DoorOpenStatus.needsLogin:
          _showDoorMessage(result.message);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.message),
              action: SnackBarAction(label: '去登录', onPressed: _openPortal),
            ),
          );
          break;
        case DoorOpenStatus.failed:
          _showDoorMessage(result.message);
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _doorBusy = false;
        });
      } else {
        _doorBusy = false;
      }
    }
  }

  void _showDoorMessage(String text) {
    _doorMessageTimer?.cancel();
    setState(() {
      _doorMessage = text;
    });
    _doorMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _doorMessage = null;
      });
    });
  }

  LoginStatus get _status {
    return _loggedIn ? LoginStatus.loggedIn : LoginStatus.loggedOut;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour >= 23) return '晚安';
    if (hour < 12) return '上午好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  ScheduleCourseOccurrence _mockScheduleHintOccurrence() {
    final start = DateTime.now().add(const Duration(minutes: 90));
    final end = start.add(const Duration(minutes: 50));
    final course = ScheduleCourse(
      name: '产品设计与用户体验',
      courseCode: 'MOCK-001',
      teacher: '示例老师',
      classroom: 'A101',
      building: '创新楼',
      campus: '主校区',
      weekday: start.weekday,
      startPeriod: 3,
      endPeriod: 4,
      weekBitmap: '1',
    );
    return ScheduleCourseOccurrence(
      course: course,
      week: 1,
      start: start,
      end: end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 首页背景永远是这张蓝灰照片，不跟随主题切换（没有浅色版素材）。
    // 之前浅色模式下文字改用深蓝灰，实测对着照片只有 ~1.6:1 的对比度，
    // 基本读不出来。文字和图标不再分主题，统一沿用深色模式那套白色系，
    // 状态栏图标也保持浅色（白色）风格，跟这张照片长期匹配。
    const headerColor = Color(0xFFF1F5F9);
    // 云母底不该跟着背景取色，也不该叠一层黑——用近黑做底即使透光度很低，
    // 视觉上仍然是「整体压暗」的墨镜感，跟参考图那种「跟底色几乎融为
    // 一体，只是糊了一层玻璃」的质感不一样。真正的毛玻璃是给模糊后的
    // 背景叠一层极淡的白（不改变色相、只轻微提亮+磨砂），图标统一白色。
    const actionCircleColor = Colors.white;
    const actionForegroundColor = Colors.white;
    const actionLabelColor = Color(0xFFF1F5F9);
    final displayedScheduleHint = _mockScheduleHint
        ? _mockScheduleHintOccurrence()
        : _scheduleHintCourse;
    // 底色由 RootPage 统一铺，这里不再单独画一层背景。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        // 首页顶部永远是背景照片，不是主题色，状态栏图标固定用浅色（白）。
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        // 底部系统手势条盖在 App 自己的底栏上，那条栏本身会跟随主题变浅/变
        // 深，所以这个仍然按主题分，不能跟状态栏一样写死。
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/home_backgroud/background.jpg',
              fit: BoxFit.cover,
              // 小尺寸设备装不下整张图时，保留最左边、多出来的部分从右边
              // 裁掉，而不是左右两边均匀裁切。
              alignment: Alignment.centerRight,
            ),
          ),
          // 背景图只有一张，不分深浅色版本。深色模式下原样显示会太亮，
          // 跟同一页面里其它已经改深的控件（状态栏、卡片）不搭，叠一层
          // 半透明黑压暗它，浅色模式不受影响。
          if (isDark)
            const Positioned.fill(
              child: ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.38)),
            ),
          // 圆形入口、课程卡片、底部 tab 栏这些"云母玻璃"控件的可读性，
          // 之前完全指望背景图本身别太亮/别太杂——这是在赌，换一张白天
          // 建筑的背景图就可能读不清。这里叠一层固定的从上到下加深的
          // 黑色渐变（越往下越暗，最深到 28% 黑），不随背景图内容变化，
          // 给底部这一整块操作区域一个跟图片无关的最低可读性保底；
          // 顶部问候语区域不受影响（渐变从屏幕中段才开始起效）。
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1.0],
                  colors: [
                    Color.fromRGBO(0, 0, 0, 0),
                    Color.fromRGBO(0, 0, 0, 0.28),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final contentWidth = width > 720 ? 720.0 : width;
                final tileHeight = ((contentWidth - 40 - 12) / 2).clamp(
                  0.0,
                  220.0,
                );

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: contentWidth,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _greeting(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineLarge
                                            ?.copyWith(
                                              color: headerColor,
                                              fontWeight: _homePageSemiBold,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      FractionallySizedBox(
                                        widthFactor: 0.75,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _hitokoto,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: headerColor.withValues(
                                                  alpha: 0.55,
                                                ),
                                                height: 1.35,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                // 跟问候语列同一个顶部内边距，让状态徽标的高度
                                // 对齐"上午好"这行文字，而不是对齐整个 Row。
                                padding: const EdgeInsets.only(top: 8),
                                child: StatusIndicator(
                                  status: _status,
                                  onTap: _openPortal,
                                  onLongPress: _confirmClearLoginState,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          SizedBox(
                            height: tileHeight,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: CircularFeatureButton(
                                        icon: Icons.lock_rounded,
                                        title: '门锁',
                                        status: _doorBusy
                                            ? '开门中…'
                                            : _doorMessage,
                                        busy: _doorBusy,
                                        backgroundColor: const Color(
                                          0xFF22C55E,
                                        ),
                                        foregroundColor: actionForegroundColor,
                                        micaOpacity: isDark ? 0.62 : 0.58,
                                        labelColor: actionLabelColor,
                                        iconOnly: _iconOnlyMode,
                                        onTap: _triggerDoor,
                                      ),
                                    ),
                                    Expanded(
                                      child: CircularFeatureButton(
                                        icon: Icons.credit_card_rounded,
                                        title: '付款码',
                                        backgroundColor: actionCircleColor,
                                        foregroundColor: actionForegroundColor,
                                        micaOpacity: 0.12,
                                        labelColor: actionLabelColor,
                                        iconOnly: _iconOnlyMode,
                                        onTap: _openPayCode,
                                      ),
                                    ),
                                    Expanded(
                                      child: CircularFeatureButton(
                                        icon: Icons.school_outlined,
                                        title: '二课',
                                        backgroundColor: actionCircleColor,
                                        foregroundColor: actionForegroundColor,
                                        micaOpacity: 0.12,
                                        labelColor: actionLabelColor,
                                        iconOnly: _iconOnlyMode,
                                        onTap: _openClassroom,
                                      ),
                                    ),
                                    Expanded(
                                      child: CircularFeatureButton(
                                        icon: Icons.shower_outlined,
                                        title: '洗浴',
                                        backgroundColor: actionCircleColor,
                                        foregroundColor: actionForegroundColor,
                                        micaOpacity: 0.12,
                                        labelColor: actionLabelColor,
                                        iconOnly: _iconOnlyMode,
                                        onTap: _openBath,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Transform.translate(
                              offset: const Offset(0, -8),
                              child: _UpcomingCourseQuote(
                                occurrence: displayedScheduleHint,
                                isCurrent: _mockScheduleHint
                                    ? false
                                    : _scheduleHintIsCurrent,
                                onTap: () => unawaited(_openSchedule()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: -10,
            top: -10,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: WebViewWidget(controller: _probeController),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingCourseQuote extends StatelessWidget {
  const _UpcomingCourseQuote({
    required this.occurrence,
    required this.isCurrent,
    required this.onTap,
  });

  final ScheduleCourseOccurrence? occurrence;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occurrence = this.occurrence;
    // 跟圆形入口一样：毛玻璃基色不叠黑、不取背景色，固定用极淡的白
    // （只轻微提亮 + 磨砂，不改变背景本身的色相），文字统一白色。
    // 卡片上是三行正文，比图标更需要一点分量，透光度比圆形入口
    // （0.16）略高，但依然是「跟背景融为一体」的玻璃，不是实心底板。
    const cardColor = Colors.white;
    const cardForegroundColor = Color(0xFFF1F5F9);
    const cardFillAlpha = 0.22;
    const scheduleLineAlpha = 0.82;
    const minorLineAlpha = 0.68;
    final radius = BorderRadius.circular(16);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = (constraints.maxWidth / 3).clamp(112.0, 180.0);
        final title = occurrence?.course.name ?? '暂无课程安排';
        final scheduleLine = occurrence == null
            ? '今天没有课程'
            : '${isCurrent ? '本节课' : '下一节'}  ${_clock(occurrence.start)}~${_clock(occurrence.end)}';
        final locationLine = occurrence == null
            ? ''
            : _courseLocation(occurrence);
        final teacherLine = occurrence == null
            ? '放松一下吧'
            : (occurrence.course.teacher.trim().isEmpty
                  ? '—'
                  : occurrence.course.teacher);

        return SizedBox(
          width: double.infinity,
          height: cardHeight,
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Material(
                color: cardColor.withValues(alpha: cardFillAlpha),
                shape: RoundedRectangleBorder(borderRadius: radius),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: radius,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: cardForegroundColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Icon(
                              Icons.today_outlined,
                              color: cardForegroundColor.withValues(
                                alpha: scheduleLineAlpha,
                              ),
                              size: 22,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          scheduleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cardForegroundColor.withValues(
                                  alpha: scheduleLineAlpha,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          locationLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cardForegroundColor.withValues(
                                  alpha: minorLineAlpha,
                                ),
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          teacherLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cardForegroundColor.withValues(
                                  alpha: minorLineAlpha,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _courseLocation(ScheduleCourseOccurrence occurrence) {
    final locations = <String>[
      occurrence.course.classroom,
      occurrence.course.building,
      occurrence.course.campus,
    ].where((value) => value.trim().isNotEmpty).toList();
    return locations.isEmpty ? '—' : locations.join(' · ');
  }

  String _clock(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
