import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/deep_links/deep_link_destination.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/utils/route_utils.dart';
import '../../core/utils/app_scheme_launcher.dart';
import '../apps/app_list_page.dart';
import '../apps/models/app_entry.dart';
import '../auth/ids_login_page.dart';
import '../home/home_page.dart';
import '../paycode/paycode_screen.dart';
import '../profile/profile_page.dart';
import '../schedule/schedule_page.dart';
import '../update/update_dialogs.dart';
import '../webview/portal_webview_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _deepLinkMethodChannel = MethodChannel(
    'uwhlife/deep_links',
  );
  static const EventChannel _deepLinkEventChannel = EventChannel(
    'uwhlife/deep_links/events',
  );

  final _homeKey = GlobalKey<HomePageState>();
  final _appsKey = GlobalKey<AppListPageState>();
  final _scheduleKey = GlobalKey<SchedulePageState>();
  // 切 tab 只该动 IndexedStack 和底栏，不该重建 RootPage 整棵树 —— 四个页面
  // 都挂在 IndexedStack 上，setState 一次就是四棵子树全部重建。
  final ValueNotifier<int> _currentIndex = ValueNotifier<int>(0);
  late final List<Widget> _pages;
  int _previousIndex = 0;
  late final AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  StreamSubscription<dynamic>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(_fadeAnimation);
    _animController.value = 1.0;
    // 页面只 new 一次：Element.updateChild 遇到同一个 widget 实例会整棵跳过，
    // 切 tab 时这四棵子树就都不用重建了。
    _pages = <Widget>[
      HomePage(
        key: _homeKey,
        onOpenAppList: _openAppList,
        onOpenPortal: _openPortal,
        onOpenPayCode: _openPayCode,
        onOpenSchedule: _openSchedule,
        onOpenClassroom: _openClassroom,
        onOpenBath: _openBath,
      ),
      AppListPage(key: _appsKey, onOpenApp: _openAppEntry),
      SchedulePage(key: _scheduleKey),
      const ProfilePage(),
    ];
    _initDeepLinks();
    _scheduleAutomaticUpdateCheck();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _animController.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _deepLinkSub = _deepLinkEventChannel.receiveBroadcastStream().listen((
      event,
    ) {
      if (event is String) _scheduleDeepLink(event);
    }, onError: (_) {});
    try {
      final initial = await _deepLinkMethodChannel.invokeMethod<String>(
        'getInitialLink',
      );
      if (initial != null && initial.isNotEmpty) {
        _scheduleDeepLink(initial);
      }
    } catch (_) {}
  }

  void _scheduleAutomaticUpdateCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(UpdateDialogs.checkAndShow(context, automatic: true));
    });
  }

  void _scheduleDeepLink(String link) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleDeepLink(link);
    });
  }

  void _handleDeepLink(String link) {
    switch (DeepLinkDestination.parse(link)) {
      case DeepLinkDestination.openDoor:
        _switchTab(0);
        unawaited(_homeKey.currentState?.triggerDoorFromDeepLink());
      case DeepLinkDestination.payCode:
        unawaited(_openPayCode());
      case DeepLinkDestination.bath:
        unawaited(_openBath());
      case null:
        return;
    }
  }

  void _switchTab(int index) {
    if (index == _currentIndex.value) {
      switch (index) {
        case 1:
          _appsKey.currentState?.handleTabReselect();
        case 2:
          _scheduleKey.currentState?.handleTabReselect();
      }
      return;
    }
    _previousIndex = _currentIndex.value;
    _currentIndex.value = index;
    if (index == 0) unawaited(_homeKey.currentState?.refreshDebugSettings());
    final goingRight = index > _previousIndex;
    _slideAnimation =
        Tween<Offset>(
          begin: Offset(goingRight ? 0.035 : -0.035, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );
    _animController.forward(from: 0);
  }

  void _openAppList() {
    if (_currentIndex.value == 1) return;
    _switchTab(1);
  }

  void _openAppEntry(AppEntry app) {
    switch (app.nativeDestination) {
      case AppNativeDestination.schedule:
        unawaited(_openSchedule());
        return;
      case AppNativeDestination.payCode:
        unawaited(_openPayCode());
        return;
      case null:
        break;
    }

    // 指向本机 App 的入口（学习通等）先唤起 App，失败再开 url 兜底。
    final scheme = app.appScheme;
    if (scheme != null && scheme.isNotEmpty) {
      unawaited(launchAppScheme(context, scheme: scheme, fallbackUrl: app.url));
      return;
    }

    Navigator.of(context).push(
      createSlideFadeRoute(
        PortalWebViewPage(
          title: app.name,
          icon: app.icon,
          initialUrl: app.url,
          topSafeArea: app.topSafeArea,
          bottomSafeArea: app.bottomSafeArea,
          accentColor: app.color,
        ),
      ),
    );
  }

  Future<void> _openPortal() async {
    final loggedIn = await LoginStateStore.readLoggedIn();
    if (!mounted) return;
    if (loggedIn) {
      await Navigator.of(context).push<String?>(
        createSlideFadeRoute(
          const PortalWebViewPage(
            title: '统一门户',
            icon: Icons.account_circle_outlined,
            initialUrl: 'https://ehall.uwh.edu.cn/login',
          ),
        ),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push<bool>(createSlideFadeRoute(const IdsLoginPage()));
  }

  Future<void> _openPayCode() async {
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const PayCodeScreen()));
  }

  Future<void> _openSchedule() async {
    _switchTab(2);
  }

  Future<void> _openClassroom() async {
    await Navigator.of(context).push(
      createSlideFadeRoute(
        const PortalWebViewPage(
          title: '智慧团学',
          icon: Icons.school_outlined,
          initialUrl: 'https://ekta.uwh.edu.cn/wjcahnulogin',
          accentColor: Color(0xFFE94B3C),
        ),
      ),
    );
  }

  Future<void> _openBath() async {
    await Navigator.of(context).push(
      createSlideFadeRoute(
        const PortalWebViewPage(
          title: '开水洗浴',
          icon: Icons.shower_outlined,
          initialUrl: 'http://ymtpt.uwh.edu.cn:27072/uwc_webapp',
          accentColor: Color(0xFF06B6D4),
          topSafeArea: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: scheme.surface,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            Positioned.fill(child: _RootPageBackground(isDark: isDark)),
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: child,
                  ),
                );
              },
              // 页面内容单独成层：底栏那层毛玻璃每帧都要采样它下面的画面，
              // 不切开的话内容重绘会连带整条底栏重绘。
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _currentIndex,
                  builder: (context, index, _) =>
                      IndexedStack(index: index, children: _pages),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: RepaintBoundary(
          child: ValueListenableBuilder<int>(
            valueListenable: _currentIndex,
            builder: (context, index, _) => _SlidingNavBar(
              currentIndex: index,
              onTap: _switchTab,
              isDark: isDark,
              scheme: scheme,
            ),
          ),
        ),
      ),
    );
  }
}

class _RootPageBackground extends StatelessWidget {
  const _RootPageBackground({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // 所有 tab（含首页）都是纯色底，绿色渐变已全部取消。
    return ColoredBox(
      color: appBackground(isDark ? Brightness.dark : Brightness.light),
    );
  }
}

// ---------------------------------------------------------------------------
// Standard bottom navigation bar
// ---------------------------------------------------------------------------

class _NavItem {
  const _NavItem(this.icon, this.activeIcon);
  final IconData icon;
  final IconData activeIcon;
}

const _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded),
  _NavItem(Icons.widgets_outlined, Icons.widgets_rounded),
  _NavItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _NavItem(Icons.account_circle_outlined, Icons.account_circle),
];

const _itemLabels = ['首页', '应用', '课表', '我的'];

class _SlidingNavBar extends StatelessWidget {
  const _SlidingNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
    required this.scheme,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // 首页背景是照片，跟另外三个纯色页面的主题背景不是一回事：那三页
    // 的底栏跟着系统主题走（浅色主题=浅色底栏）没问题，但停在首页时,
    // 底栏得跟首页那几个圆形入口用同一套「不取色、不叠黑，只用极淡的
    // 白磨砂 + 白图标白文字」的玻璃质感，否则会跟首页整体风格脱节。
    final onHomeTab = currentIndex == 0;
    final inactiveColor = onHomeTab
        ? Colors.white.withValues(alpha: 0.62)
        : isDark
        ? const Color(0xFF7D8798)
        : const Color(0xFF6B7280);
    final activeColor = onHomeTab || isDark
        ? Colors.white
        : const Color(0xFF111827);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          // 比之前缩短 5px；图标组同步上移 5px，保持其相对屏幕位置。
          height: 66 + bottomPadding,
          padding: EdgeInsets.only(bottom: bottomPadding + 3),
          decoration: BoxDecoration(
            color: onHomeTab
                ? Colors.white.withValues(alpha: 0.16)
                : isDark
                ? const Color(0xFF0B0E13).withValues(alpha: 0.62)
                : scheme.surface.withValues(alpha: 0.56),
            border: Border(
              top: BorderSide(
                color: (onHomeTab || isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.08),
              ),
            ),
          ),
          child: Row(
            children: List.generate(_items.length, (i) {
              final selected = i == currentIndex;
              final color = selected ? activeColor : inactiveColor;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: _itemLabels[i],
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1, bottom: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? _items[i].activeIcon : _items[i].icon,
                            color: color,
                            size: 24,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _itemLabels[i],
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
