/// A small visual gap above the home indicator for floating portrait controls.
/// iOS does not expose the indicator's frame; the system inset remains the
/// boundary for foreground content outside the floating control itself.
double portraitFloatingBottomGap(double systemInset) =>
    (systemInset - 16).clamp(0.0, double.infinity);
