import 'package:flutter/material.dart';

Route<T> createSlideFadeRoute<T>(Widget page) {
  const curve = Curves.easeOutCubic;

  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final offsetAnimation = animation.drive(
        Tween(begin: const Offset(0.0, 0.06), end: Offset.zero)
            .chain(CurveTween(curve: curve)),
      );

      final fadeAnimation = animation.drive(
        Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: curve)),
      );

      return FadeTransition(
        opacity: fadeAnimation,
        child: SlideTransition(
          position: offsetAnimation,
          child: child,
        ),
      );
    },
  );
}
