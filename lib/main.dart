import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/platform/orientation_policy.dart';
import 'core/platform/side_navigation.dart';
import 'core/theme/app_theme.dart';
import 'features/root/root_page.dart';

final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
final _NavigatorChanges _navigatorChanges = _NavigatorChanges();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Start in portrait so Android phones never flash into landscape while the
  // first frame is loading. OrientationPolicy unlocks tablet-sized displays.
  if (defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(
    const OrientationPolicy(child: SideNavigationPolicy(child: UwhLifeApp())),
  );
}

class UwhLifeApp extends StatelessWidget {
  const UwhLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: <NavigatorObserver>[_navigatorChanges],
      builder: (context, child) => _WideRouteControls(
        navigatorChanges: _navigatorChanges,
        child: child ?? const SizedBox.shrink(),
      ),
      title: '芜忧芜院',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: buildColorScheme(Brightness.light),
        dialogTheme: buildDialogTheme(Brightness.light),
        bottomSheetTheme: buildBottomSheetTheme(Brightness.light),
        snackBarTheme: buildSnackBarTheme(Brightness.light),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: buildColorScheme(Brightness.dark),
        dialogTheme: buildDialogTheme(Brightness.dark),
        bottomSheetTheme: buildBottomSheetTheme(Brightness.dark),
        snackBarTheme: buildSnackBarTheme(Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RootPage(),
    );
  }
}

class _NavigatorChanges extends NavigatorObserver {
  VoidCallback? onChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged?.call();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged?.call();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onChanged?.call();
  }
}

/// Keeps secondary-page navigation reachable beside the right edge on wide
/// inner displays, where a top-left back button is difficult to reach.
class _WideRouteControls extends StatefulWidget {
  const _WideRouteControls({
    required this.navigatorChanges,
    required this.child,
  });

  final _NavigatorChanges navigatorChanges;
  final Widget child;

  @override
  State<_WideRouteControls> createState() => _WideRouteControlsState();
}

class _WideRouteControlsState extends State<_WideRouteControls> {
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.navigatorChanges.onChanged = _refresh;
  }

  @override
  void didUpdateWidget(covariant _WideRouteControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.navigatorChanges.onChanged = null;
    widget.navigatorChanges.onChanged = _refresh;
  }

  @override
  void dispose() {
    widget.navigatorChanges.onChanged = null;
    super.dispose();
  }

  void _refresh() {
    if (!mounted || _refreshScheduled) return;
    _refreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = usesSideNavigation(context);
    final canPop = _navigatorKey.currentState?.canPop() ?? false;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (wide &&
            canPop &&
            !routesWithOwnControls.any((route) => route.isCurrent))
          Positioned(
            right: systemVerticalEdge == 'left'
                ? null
                : sideControlRightInset(context, 56),
            left: systemVerticalEdge == 'left'
                ? sideControlRightInset(context, 56)
                : null,
            top: 0,
            child: SafeArea(
              left: false,
              top: true,
              right: false,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.only(
                  top: isDuoDevice ? systemReservedBottom + 8 : 12,
                ),
                child: SizedBox(
                  width: 56,
                  height: 112,
                  child: Overlay(
                    key: ValueKey<bool>(canPop),
                    initialEntries: [
                      OverlayEntry(
                        builder: (_) => _SecondaryPageDock(
                          onBack: () => _navigatorKey.currentState?.maybePop(),
                          onHome: () => _navigatorKey.currentState?.popUntil(
                            (route) => route.isFirst,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SecondaryPageDock extends StatelessWidget {
  const _SecondaryPageDock({required this.onBack, required this.onHome});

  final VoidCallback onBack;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final foreground = Theme.of(context).colorScheme.onSurface;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 56,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(28),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: foreground.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(56),
                  padding: EdgeInsets.zero,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(56),
                  padding: EdgeInsets.zero,
                ),
                onSelected: (_) => onHome(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'home', child: Text('返回主页面')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
