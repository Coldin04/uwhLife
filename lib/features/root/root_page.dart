import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/deep_links/deep_link_destination.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/utils/route_utils.dart';
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
    if (app.nativeDestination == AppNativeDestination.schedule) {
      unawaited(_openSchedule());
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
          icon: Icons.shower_rounded,
          initialUrl: 'http://ymtpt.uwh.edu.cn:27072/uwc_webapp',
          accentColor: Color(0xFF06B6D4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shortHeaderBackground =
        _currentIndex == 1 || _currentIndex == 2 || _currentIndex == 3;
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
            Positioned.fill(
              child: _RootPageBackground(
                isDark: isDark,
                shortHeader: shortHeaderBackground,
              ),
            ),
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
  const _RootPageBackground({required this.isDark, required this.shortHeader});

  final bool isDark;
  final bool shortHeader;

  @override
  Widget build(BuildContext context) {
    final colors = isDark
        ? const [Color(0xFF123B24), Color(0xFF082413), Color(0xFF020503)]
        : const [Color(0xFFC8F1D8), Color(0xFFEAF8EF), Colors.white];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
          stops: shortHeader ? const [0, 0.15, 0.30] : const [0, 0.48, 1],
        ),
      ),
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
        ? const Color(0xFFD8E2DA)
        : const Color(0xFF111827);
    final activeColor = isDark
        ? const Color(0xFF1B7F44)
        : const Color(0xFF22C55E);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomOuterMargin = bottomPadding + 8;

    return Container(
      height: 72 + bottomPadding,
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomOuterMargin),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / _items.length;
          return ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: (isDark ? Colors.black : Colors.white).withValues(
                    alpha: isDark ? 0.16 : 0.36,
                  ),
                  border: Border.all(
                    color: (isDark ? Colors.white : const Color(0xFFBDEFCF))
                        .withValues(alpha: isDark ? 0.08 : 0.36),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.black : const Color(0xFF22C55E))
                          .withValues(alpha: isDark ? 0.16 : 0.06),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
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
          );
        },
      ),
    );
  }
}
