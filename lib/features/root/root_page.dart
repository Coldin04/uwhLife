import 'dart:async';
import 'dart:ui';

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
import '../message/message_list_page.dart';
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
  int _currentIndex = 0;
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
    _initDeepLinks();
    _scheduleAutomaticUpdateCheck();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _animController.dispose();
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
    if (index == _currentIndex) return;
    _previousIndex = _currentIndex;
    setState(() => _currentIndex = index);
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
    if (_currentIndex == 1) return;
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
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const SchedulePage()));
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
    final pages = <Widget>[
      HomePage(
        key: _homeKey,
        onOpenAppList: _openAppList,
        onOpenPortal: _openPortal,
        onOpenPayCode: _openPayCode,
        onOpenSchedule: _openSchedule,
        onOpenClassroom: _openClassroom,
        onOpenBath: _openBath,
      ),
      AppListPage(onOpenApp: _openAppEntry),
      MessageListPage(active: _currentIndex == 2),
      const ProfilePage(),
    ];

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
              child: IndexedStack(index: _currentIndex, children: pages),
            ),
          ],
        ),
        bottomNavigationBar: _SlidingNavBar(
          currentIndex: _currentIndex,
          onTap: _switchTab,
          isDark: isDark,
          scheme: scheme,
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
// Bottom nav bar with a sliding pill indicator
// ---------------------------------------------------------------------------

class _NavItem {
  const _NavItem(this.icon, this.activeIcon);
  final IconData icon;
  final IconData activeIcon;
}

const _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded),
  _NavItem(Icons.apps_outlined, Icons.apps_rounded),
  _NavItem(Icons.mail_outlined, Icons.mail_rounded),
  _NavItem(Icons.account_circle_outlined, Icons.account_circle),
];

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
    final inactiveColor = isDark
        ? const Color(0xFFDEDEDE)
        : const Color(0xFF111827);
    final activeColor = isDark
        ? const Color(0xFF1B7F44)
        : const Color(0xFF22C55E);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomOuterMargin = bottomPadding + 8;

    // 悬浮胶囊（仿 iOS 26）：四周留外边距浮在内容之上，靠毛玻璃透出下层。
    // 外边距 / 圆角 / 高度都不要动，动了就不悬浮了。
    const radius = BorderRadius.all(Radius.circular(28));

    return Container(
      height: 72 + bottomPadding,
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomOuterMargin),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / _items.length;
          // 投影必须画在 ClipRRect 外面。之前它挂在被裁剪的 DecoratedBox 上，
          // 直接被裁掉了 —— 结果胶囊只有毛玻璃、没有落影，透出的背景反而让它
          // 看着像陷在内容下层。这里在外层单独铺一层投影把它抬起来。
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.44 : 0.16),
                  blurRadius: 24,
                  spreadRadius: -6,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // 深色下不再拿黑色当底：页面底色本来就接近纯黑，压黑之后胶囊
                    // 整条看着像挖了个洞。换成中等灰、透明度高一点，抬起来一档。
                    color: isDark
                        ? const Color(0xFF4A4A4A).withValues(alpha: 0.62)
                        : Colors.white.withValues(alpha: 0.36),
                    // 描边只去掉了原来的浅绿（0xFFBDEFCF），换成同透明度的中性色，
                    // 胶囊的形状和毛玻璃质感保持不变。
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: isDark ? 0.08 : 0.10,
                      ),
                      width: 1,
                    ),
                    borderRadius: radius,
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        left: tabWidth * currentIndex + (tabWidth - 64) / 2,
                        top: 12,
                        child: Container(
                          width: 64,
                          height: 32,
                          decoration: BoxDecoration(
                            color: activeColor,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(_items.length, (i) {
                          final selected = i == currentIndex;
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onTap(i),
                              child: SizedBox(
                                height: 56,
                                child: Center(
                                  child: Icon(
                                    selected
                                        ? _items[i].activeIcon
                                        : _items[i].icon,
                                    color: selected
                                        ? (isDark
                                              ? const Color(0xFFBFF7D0)
                                              : Colors.white)
                                        : inactiveColor,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
