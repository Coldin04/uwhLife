import 'package:flutter/material.dart';

const FontWeight _overlayBold = FontWeight.w700;
const Color _overlayBrandGreen = Color(0xFF22C55E);

class MiniProgramCapsule extends StatelessWidget {
  const MiniProgramCapsule({
    super.key,
    required this.onRefresh,
    required this.onClose,
  });

  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const double height = 32;
    const double iconSize = 17;
    const double sideWidth = 44;
    const Color iconColor = Color(0xFF111111);

    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      shape: const StadiumBorder(
        side: BorderSide(color: Color(0x1A000000), width: 0.5),
      ),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              customBorder: const StadiumBorder(),
              onTap: onRefresh,
              child: const SizedBox(
                width: sideWidth,
                height: height,
                child: Center(
                  child: Icon(
                    Icons.refresh_rounded,
                    size: iconSize,
                    color: iconColor,
                    semanticLabel: '刷新',
                  ),
                ),
              ),
            ),
            Container(
              width: 0.5,
              height: 16,
              color: const Color(0x33000000),
            ),
            InkWell(
              customBorder: const StadiumBorder(),
              onTap: onClose,
              child: const SizedBox(
                width: sideWidth,
                height: height,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: iconSize,
                    color: iconColor,
                    semanticLabel: '关闭',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniProgramLaunchView extends StatelessWidget {
  const MiniProgramLaunchView({
    super.key,
    required this.icon,
    required this.title,
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        accentColor ?? (isDark ? const Color(0xFF1B7F44) : _overlayBrandGreen);
    final trackColor = accent.withValues(alpha: 0.16);
    final titleColor = scheme.onSurface;
    final mutedColor = scheme.onSurface.withValues(alpha: 0.55);

    const ringSize = 88.0;
    const iconBgSize = 64.0;

    return ColoredBox(
      color: scheme.surface,
      child: Align(
        alignment: const Alignment(0, -0.18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: ringSize,
              height: ringSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: ringSize,
                    height: ringSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      strokeCap: StrokeCap.round,
                      color: trackColor,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  Container(
                    width: iconBgSize,
                    height: iconBgSize,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _filledVariant(icon),
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: titleColor,
                fontWeight: _overlayBold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '正在打开…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: mutedColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _filledVariant(IconData src) {
    if (src == Icons.shower_outlined) return Icons.shower_rounded;
    if (src == Icons.calendar_month_outlined) {
      return Icons.calendar_month_rounded;
    }
    if (src == Icons.qr_code_2_outlined) return Icons.qr_code_2_rounded;
    if (src == Icons.school_outlined) {
      return Icons.school_rounded;
    }
    return src;
  }
}

class FloatingNavButton extends StatelessWidget {
  const FloatingNavButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.88),
      shape: const CircleBorder(),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              icon,
              size: 18,
              color: const Color(0xFF111111),
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}
