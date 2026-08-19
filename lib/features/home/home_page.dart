import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/boundary_debug_settings.dart';
import '../../core/storage/home_page_settings.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_user_store.dart';
import '../../core/theme/app_theme.dart';
import '../auth/ids_http_auth.dart';
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

enum _DoorButtonState { idle, busy, needsLogin, opened }

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
  final ScheduleRepository _scheduleRepository = ScheduleRepository.shared;
  ScheduleCourseOccurrence? _scheduleHintCourse;
  bool _scheduleHintIsCurrent = false;
  bool _hasScheduleHintData = false;
  bool _mockScheduleHint = false;
  bool _iconOnlyMode = false;
  bool _scheduleHintLoading = true;
  bool _loadingScheduleHint = false;
  Timer? _scheduleHintTimer;
  Timer? _deferredScheduleRefreshTimer;
  Timer? _hitokotoDelayTimer;
  final HttpClient _probeClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);
  HttpCookieJar? _probeCookies;
  bool _probing = false;

  _DoorButtonState _doorState = _DoorButtonState.idle;
  Timer? _doorStateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LoginStateStore.notifier.addListener(_onLoginStateChanged);
    _loadLoginState();
    _loadMockScheduleHint();
    _loadHomePageSettings();
    unawaited(_initializeScheduleHint());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Start the fast HTTP probe immediately after the first useful frame,
      // so auth freshness never competes with the home layout's first build.
      unawaited(_probeAndSync());
      // Neither a cached quote nor a second network request is needed to
      // make the first frame useful. Let the home/door controls settle first.
      _hitokotoDelayTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) _loadHitokoto();
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LoginStateStore.notifier.removeListener(_onLoginStateChanged);
    _doorStateTimer?.cancel();
    _scheduleHintTimer?.cancel();
    _deferredScheduleRefreshTimer?.cancel();
    _hitokotoDelayTimer?.cancel();
    _probeClient.close(force: true);
    super.dispose();
  }

  void _onLoginStateChanged() {
    if (!mounted || _loggedIn == LoginStateStore.notifier.value) return;
    final loggedIn = LoginStateStore.notifier.value;
    setState(() {
      _loggedIn = loggedIn;
      if (!loggedIn) {
        _hasScheduleHintData = false;
        _scheduleHintCourse = null;
        _scheduleHintIsCurrent = false;
      }
    });
    if (!loggedIn) _scheduleHintTimer?.cancel();
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
    await LoginStateStore.readLoggedIn();
  }

  Future<void> _initializeScheduleHint() async {
    var waitingForRefresh = false;
    try {
      if (!await LoginStateStore.readLoggedIn()) {
        if (mounted) setState(() => _scheduleHintLoading = false);
        return;
      }
      final cached = await ScheduleCache.read(now: DateTime.now());
      if (!mounted) return;
      if (cached?.schedule.isCurrentTerm == true) {
        _applyScheduleHint(cached!.schedule);
        setState(() => _scheduleHintLoading = false);
        return;
      }

      // If there is no usable cache, show a stable card first and let the
      // full schedule request happen after the home controls are interactive.
      _deferredScheduleRefreshTimer = Timer(
        const Duration(milliseconds: 900),
        () {
          if (mounted) unawaited(_refreshScheduleHint());
        },
      );
      waitingForRefresh = true;
    } finally {
      if (!waitingForRefresh && mounted && _scheduleHintLoading) {
        setState(() => _scheduleHintLoading = false);
      }
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
        _scheduleHintLoading = false;
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
        _scheduleHintLoading = false;
        return;
      }
      _applyScheduleHint(schedule);
    } finally {
      _loadingScheduleHint = false;
      if (mounted && _scheduleHintLoading) {
        setState(() => _scheduleHintLoading = false);
      }
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
    _probeCookies = null;
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
    try {
      final start = Uri.parse(url);
      final cookies = _probeCookies ??= HttpCookieJar();
      await _seedProbeCookies(start, cookies);

      var next = start;
      for (var hop = 0; hop < 8; hop++) {
        final request = await _probeClient
            .getUrl(next)
            .timeout(const Duration(seconds: 6));
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/json,text/html;q=0.9,*/*;q=0.8',
        );
        final cookieHeader = cookies.cookieHeaderFor(next);
        if (cookieHeader.isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
        }

        final response = await request.close().timeout(
          const Duration(seconds: 6),
        );
        cookies.save(next, response.cookies);
        final body = await response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 6));
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null ||
            response.statusCode < 300 ||
            response.statusCode >= 400) {
          return (body: body, url: next.toString());
        }
        next = next.resolve(location);
        await _seedProbeCookies(next, cookies);
      }
    } catch (_) {
      // Login probing is best-effort and must never surface an uncaught
      // network exception from the background startup task.
    }
    return (body: '', url: '');
  }

  Future<void> _seedProbeCookies(Uri uri, HttpCookieJar jar) async {
    final hasPersisted = await PortalSessionCookies.seedFor(uri, jar);
    if (hasPersisted && jar.cookieHeaderFor(uri).isNotEmpty) return;
    final header = await BrowserDataCleaner.getCookies(url: uri.toString());
    if (header.trim().isNotEmpty) jar.addCookieHeader(uri, header);
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
    final cookies = _probeCookies;
    if (cookies != null) {
      await PortalSessionCookies.rememberHttpCookies(cookies);
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
    if (_doorState == _DoorButtonState.busy) return;
    _doorStateTimer?.cancel();
    setState(() {
      _doorState = _DoorButtonState.busy;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await DoorApi.openDoor();

      if (!mounted) return;
      switch (result.status) {
        case DoorOpenStatus.opened:
          _showDoorState(
            _DoorButtonState.opened,
            duration: const Duration(seconds: 3),
          );
          break;
        case DoorOpenStatus.needsLogin:
          _showDoorState(
            _DoorButtonState.needsLogin,
            duration: const Duration(seconds: 4),
          );
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(result.message),
              action: SnackBarAction(label: '去登录', onPressed: _openPortal),
            ),
          );
          break;
        case DoorOpenStatus.failed:
          _showDoorState(_DoorButtonState.idle);
          messenger.showSnackBar(SnackBar(content: Text(result.message)));
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          if (_doorState == _DoorButtonState.busy) {
            _doorState = _DoorButtonState.idle;
          }
        });
      }
    }
  }

  void _showDoorState(_DoorButtonState state, {Duration? duration}) {
    _doorStateTimer?.cancel();
    setState(() {
      _doorState = state;
    });
    if (duration == null) return;
    _doorStateTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _doorState = _DoorButtonState.idle;
      });
    });
  }

  String get _doorTitle => switch (_doorState) {
    _DoorButtonState.busy => '开锁中',
    _DoorButtonState.needsLogin => '请登录',
    _DoorButtonState.opened => '已开锁',
    _DoorButtonState.idle => '门锁',
  };

  IconData get _doorIcon => switch (_doorState) {
    _DoorButtonState.needsLogin => Icons.priority_high_rounded,
    _DoorButtonState.opened => Icons.lock_open_rounded,
    _ => Icons.lock_rounded,
  };

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

  String _homeBackgroundAsset(Size size) {
    // The tablet crop deliberately keeps the left-side architecture visible;
    // the phone crop keeps the right-side subject used by the old alignment.
    if (size.shortestSide >= 600) {
      return 'assets/home_backgroud/variants/background_tablet_left.jpg';
    }
    if (size.width > size.height) {
      return 'assets/home_backgroud/variants/background_compact.jpg';
    }
    return 'assets/home_backgroud/variants/background_phone_right.jpg';
  }

  int _homeBackgroundCacheWidth(Size size, double devicePixelRatio) {
    final assetWidth = size.shortestSide >= 600
        ? 1600
        : size.width > size.height
        ? 1024
        : 1080;
    final requested = (size.width * devicePixelRatio).round();
    return requested.clamp(480, assetWidth).toInt();
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
    final viewport = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final backgroundAsset = _homeBackgroundAsset(viewport);
    final backgroundCacheWidth = _homeBackgroundCacheWidth(
      viewport,
      devicePixelRatio,
    );
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
            // 背景图、暗色遮罩和可读性渐变在首帧后不会变化。把它们做成
            // 单独的 paint layer，课表/登录态/开门按钮刷新不会重新绘制照片。
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    backgroundAsset,
                    cacheWidth: backgroundCacheWidth,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                  ),
                  // 背景图只有一张，不分深浅色版本。深色模式下原样显示会太亮，
                  // 跟同一页面里其它已经改深的控件（状态栏、卡片）不搭，叠一层
                  // 半透明黑压暗它，浅色模式不受影响。
                  if (isDark)
                    const ColoredBox(color: Color.fromRGBO(0, 0, 0, 0.38)),
                  // 圆形入口、课程卡片和底栏的可读性不依赖照片内容：越往下
                  // 越暗的固定渐变为文字与图标保留稳定对比度。
                  const DecoratedBox(
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
                ],
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
                                child: RepaintBoundary(
                                  child: StatusIndicator(
                                    status: _status,
                                    onTap: _openPortal,
                                    onLongPress: _confirmClearLoginState,
                                  ),
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
                                      child: RepaintBoundary(
                                        child: CircularFeatureButton(
                                          icon: _doorIcon,
                                          title: _doorTitle,
                                          busy:
                                              _doorState ==
                                              _DoorButtonState.busy,
                                          backgroundColor: const Color(
                                            0xFF22C55E,
                                          ),
                                          foregroundColor:
                                              actionForegroundColor,
                                          micaOpacity: isDark ? 0.62 : 0.58,
                                          labelColor: actionLabelColor,
                                          iconOnly: _iconOnlyMode,
                                          onTap: _triggerDoor,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: RepaintBoundary(
                                        child: CircularFeatureButton(
                                          icon: Icons.credit_card_rounded,
                                          title: '付款码',
                                          backgroundColor: actionCircleColor,
                                          foregroundColor:
                                              actionForegroundColor,
                                          micaOpacity: 0.12,
                                          labelColor: actionLabelColor,
                                          iconOnly: _iconOnlyMode,
                                          onTap: _openPayCode,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: RepaintBoundary(
                                        child: CircularFeatureButton(
                                          icon: Icons.school_outlined,
                                          title: '二课',
                                          backgroundColor: actionCircleColor,
                                          foregroundColor:
                                              actionForegroundColor,
                                          micaOpacity: 0.12,
                                          labelColor: actionLabelColor,
                                          iconOnly: _iconOnlyMode,
                                          onTap: _openClassroom,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: RepaintBoundary(
                                        child: CircularFeatureButton(
                                          icon: Icons.shower_outlined,
                                          title: '洗浴',
                                          backgroundColor: actionCircleColor,
                                          foregroundColor:
                                              actionForegroundColor,
                                          micaOpacity: 0.12,
                                          labelColor: actionLabelColor,
                                          iconOnly: _iconOnlyMode,
                                          onTap: _openBath,
                                        ),
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
                              child: RepaintBoundary(
                                child: _UpcomingCourseQuote(
                                  occurrence: displayedScheduleHint,
                                  isCurrent: _mockScheduleHint
                                      ? false
                                      : _scheduleHintIsCurrent,
                                  loading: _scheduleHintLoading,
                                  onTap: () => unawaited(_openSchedule()),
                                ),
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
        ],
      ),
    );
  }
}

class _UpcomingCourseQuote extends StatelessWidget {
  const _UpcomingCourseQuote({
    required this.occurrence,
    required this.isCurrent,
    required this.loading,
    required this.onTap,
  });

  final ScheduleCourseOccurrence? occurrence;
  final bool isCurrent;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final occurrence = this.occurrence;
    // 课程卡保持与底栏一致的轻量真实模糊，半径统一为 8。
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
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
                      children: loading
                          ? const [
                              _SkeletonLine(widthFactor: 0.48, height: 18),
                              SizedBox(height: 10),
                              _SkeletonLine(widthFactor: 0.72, height: 12),
                              SizedBox(height: 8),
                              _SkeletonLine(widthFactor: 0.56, height: 12),
                              SizedBox(height: 8),
                              _SkeletonLine(widthFactor: 0.40, height: 12),
                            ]
                          : [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
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

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: SizedBox(height: height),
      ),
    );
  }
}
