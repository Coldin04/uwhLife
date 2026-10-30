import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool isDuoDevice = false;
double systemReservedBottom = 0;
double systemReservedRightWidth = 0;
double systemSideCenterInset = 0;
String systemVerticalEdge = 'none';
bool systemAdaptivePhone = false;

/// Refreshes native traits when the window changes size or pose.
class SideNavigationPolicy extends StatefulWidget {
  const SideNavigationPolicy({required this.child, super.key});
  final Widget child;
  @override
  State<SideNavigationPolicy> createState() => _SideNavigationPolicyState();
}

class _SideNavigationPolicyState extends State<SideNavigationPolicy>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  Future<void> _update() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final data = await const MethodChannel(
        'uwhlife/device',
      ).invokeMapMethod<String, dynamic>('layout');
      if (!mounted || data == null) return;
      final edge = data['edge'] as String? ?? 'none';
      final bottom = (data['reservedBottom'] as num?)?.toDouble() ?? 0;
      final rightWidth = (data['reservedRightWidth'] as num?)?.toDouble() ?? 0;
      final sideCenter = (data['sideCenterInset'] as num?)?.toDouble() ?? 0;
      final phone = data['adaptivePhone'] as bool? ?? false;
      final view = View.of(context);
      debugPrint(
        '[DuoLayout] flutter size=${view.physicalSize / view.devicePixelRatio} '
        'padding=${MediaQuery.paddingOf(context)} '
        'viewPadding=${MediaQuery.viewPaddingOf(context)} data=$data',
      );
      if (edge != systemVerticalEdge ||
          bottom != systemReservedBottom ||
          rightWidth != systemReservedRightWidth ||
          sideCenter != systemSideCenterInset ||
          phone != systemAdaptivePhone) {
        setState(() {
          systemVerticalEdge = edge;
          systemAdaptivePhone = phone;
          isDuoDevice = edge != 'none';
          systemReservedBottom = bottom;
          systemReservedRightWidth = rightWidth;
          systemSideCenterInset = sideCenter;
        });
      }
    } on PlatformException {
      // Older iOS builds do not expose the layout channel; keep defaults.
    } on MissingPluginException {
      // Non-iOS platforms have no side layout region to report.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LayoutScope(
    edge: systemVerticalEdge,
    bottom: systemReservedBottom,
    rightWidth: systemReservedRightWidth,
    sideCenter: systemSideCenterInset,
    phone: systemAdaptivePhone,
    child: widget.child,
  );
}

class _LayoutScope extends InheritedWidget {
  const _LayoutScope({
    required this.edge,
    required this.bottom,
    required this.rightWidth,
    required this.sideCenter,
    required this.phone,
    required super.child,
  });
  final String edge;
  final double bottom;
  final double rightWidth;
  final double sideCenter;
  final bool phone;
  @override
  bool updateShouldNotify(_LayoutScope oldWidget) =>
      edge != oldWidget.edge ||
      bottom != oldWidget.bottom ||
      rightWidth != oldWidget.rightWidth ||
      sideCenter != oldWidget.sideCenter ||
      phone != oldWidget.phone;
}

bool usesSideNavigation(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<_LayoutScope>();
  return systemAdaptivePhone
      ? systemVerticalEdge != 'none'
      : isDuoDevice || MediaQuery.sizeOf(context).shortestSide >= 600;
}

/// Positions a side control on the system cluster's centre line.
///
/// The caller must place the control relative to the full view edge. UIKit
/// supplies a real occlusion centre when available; viewPadding is the
/// fallback. Callers must not consume the side inset before positioning.
double sideControlRightInset(BuildContext context, double width) {
  context.dependOnInheritedWidgetOfExactType<_LayoutScope>();
  if (systemVerticalEdge == 'none') return 8;
  final padding = MediaQuery.viewPaddingOf(context);
  final sideInset = systemVerticalEdge == 'left' ? padding.left : padding.right;
  final center = systemSideCenterInset > 0
      ? systemSideCenterInset
      : sideInset / 2;
  if (center <= 0) return 8;
  return (center - width / 2).clamp(0.0, double.infinity);
}

final Set<Route<dynamic>> routesWithOwnControls = <Route<dynamic>>{};
