import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The Android definition of a tablet-sized display in logical pixels.
const double tabletShortestSideBreakpoint = 600;

/// Returns the orientations supported by the current display size.
///
/// Use the display's shortest side rather than the window's current width so a
/// phone does not become eligible for landscape merely because it is rotated.
List<DeviceOrientation> orientationsForShortestSide(double shortestSide) {
  if (shortestSide >= tabletShortestSideBreakpoint) {
    return DeviceOrientation.values;
  }

  return const <DeviceOrientation>[DeviceOrientation.portraitUp];
}

/// Keeps phones in portrait while allowing tablets and larger displays to
/// follow the device orientation.
class OrientationPolicy extends StatefulWidget {
  const OrientationPolicy({required this.child, super.key});

  final Widget child;

  @override
  State<OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<OrientationPolicy>
    with WidgetsBindingObserver {
  List<DeviceOrientation>? _appliedOrientations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateOrientations());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateOrientations();
  }

  void _updateOrientations() {
    if (!mounted) {
      return;
    }

    final display = View.of(context).display;
    final shortestSide = display.size.shortestSide / display.devicePixelRatio;
    final orientations = orientationsForShortestSide(shortestSide);
    if (listEquals(_appliedOrientations, orientations)) {
      return;
    }

    _appliedOrientations = orientations;
    unawaited(SystemChrome.setPreferredOrientations(orientations));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
