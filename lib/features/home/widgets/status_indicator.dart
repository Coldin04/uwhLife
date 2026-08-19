import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

enum LoginStatus { loggedIn, loggedOut }

class StatusIndicator extends StatelessWidget {
  const StatusIndicator({
    super.key,
    required this.status,
    this.onTap,
    this.onLongPress,
  });

  final LoginStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (status == LoginStatus.loggedIn) {
      return const SizedBox.shrink();
    }

    // 与首页快捷入口保持一致的轻量真实模糊。
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              onLongPress: onLongPress,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Icon(
                        Icons.priority_high_rounded,
                        color: Colors.white,
                        size: 10,
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
  }
}
