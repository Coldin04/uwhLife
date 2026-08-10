import 'package:flutter/material.dart';

const FontWeight _overlayBold = FontWeight.w500;
const Color _overlayBrandGreen = Color(0xFF22C55E);

/// 悬浮胶囊（仅全屏小程序页使用）。`onDarkBackground` 由网页取色决定：
/// 网页顶部偏黑时整颗胶囊转成深色，避免白胶囊在夜间页面上刺眼。
class MiniProgramCapsule extends StatelessWidget {
  const MiniProgramCapsule({
    super.key,
    required this.onRefresh,
    required this.onOpenInBrowser,
    required this.onClose,
    this.onDarkBackground = false,
  });

  final VoidCallback onRefresh;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onClose;
  final bool onDarkBackground;

  static const double _height = 32;
  static const double _iconSize = 17;
  static const double _sideWidth = 44;

  @override
  Widget build(BuildContext context) {
    final iconColor = onDarkBackground ? Colors.white : const Color(0xFF111111);
    final background = onDarkBackground
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.78);
    final borderColor = onDarkBackground
        ? const Color(0x33FFFFFF)
        : const Color(0x1A000000);
    final dividerColor = onDarkBackground
        ? const Color(0x40FFFFFF)
        : const Color(0x33000000);

    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: borderColor, width: 0.5)),
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SizedBox(
        height: _height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WebViewMoreMenu(
              onRefresh: onRefresh,
              onOpenInBrowser: onOpenInBrowser,
              dark: onDarkBackground,
              builder: (context, open) => InkWell(
                customBorder: const StadiumBorder(),
                onTap: open,
                child: SizedBox(
                  width: _sideWidth,
                  height: _height,
                  child: Center(
                    child: Icon(
                      Icons.more_vert_rounded,
                      size: _iconSize,
                      color: iconColor,
                      semanticLabel: '更多',
                    ),
                  ),
                ),
              ),
            ),
            Container(width: 0.5, height: 16, color: dividerColor),
            InkWell(
              customBorder: const StadiumBorder(),
              onTap: onClose,
              child: SizedBox(
                width: _sideWidth,
                height: _height,
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: _iconSize,
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

/// 「刷新 / 在浏览器中打开」菜单，胶囊和顶部工具栏共用。
/// `dark` 由调用方给：胶囊按网页取色传，顶栏按 App 主题传，
/// 保证弹出的菜单和它挂着的那个控件同色。
class WebViewMoreMenu extends StatelessWidget {
  const WebViewMoreMenu({
    super.key,
    required this.onRefresh,
    required this.onOpenInBrowser,
    required this.builder,
    required this.dark,
  });

  final VoidCallback onRefresh;
  final VoidCallback onOpenInBrowser;
  final bool dark;
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = dark;
    final background = isDark ? const Color(0xFF1F1F21) : Colors.white;
    final foreground = isDark ? Colors.white : const Color(0xFF111111);
    final border = isDark ? const Color(0x22FFFFFF) : const Color(0x14000000);

    return MenuAnchor(
      alignmentOffset: const Offset(-120, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(background),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(3),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
      ),
      menuChildren: [
        MenuItemButton(
          onPressed: onRefresh,
          leadingIcon: Icon(Icons.refresh_rounded, size: 18, color: foreground),
          style: _itemStyle(foreground, scheme),
          child: const Text('刷新'),
        ),
        MenuItemButton(
          onPressed: onOpenInBrowser,
          leadingIcon: Icon(
            Icons.open_in_browser_rounded,
            size: 18,
            color: foreground,
          ),
          style: _itemStyle(foreground, scheme),
          child: const Text('在浏览器中打开'),
        ),
      ],
      builder: (context, controller, child) {
        return builder(
          context,
          () => controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }

  ButtonStyle _itemStyle(Color foreground, ColorScheme scheme) {
    return MenuItemButton.styleFrom(
      minimumSize: const Size(168, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      foregroundColor: foreground,
      backgroundColor: Colors.transparent,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    );
  }
}

/// 非全屏小程序页的顶部工具栏：上面一条，下面是网页。
/// 不做网页取色，直接跟随 App 的深色模式设置。
class WebViewTopBar extends StatelessWidget {
  const WebViewTopBar({
    super.key,
    required this.topInset,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenInBrowser,
    required this.onClose,
  });

  static const double toolbarHeight = 48;

  static Color backgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF141414)
        : Colors.white;
  }

  final double topInset;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final VoidCallback onOpenInBrowser;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF111111);
    final divider = isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000);

    return Material(
      color: backgroundColor(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: topInset),
          SizedBox(
            height: toolbarHeight,
            child: Row(
              children: [
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: foreground,
                  tooltip: '返回',
                ),
                const Spacer(),
                WebViewMoreMenu(
                  onRefresh: onRefresh,
                  onOpenInBrowser: onOpenInBrowser,
                  dark: isDark,
                  builder: (context, open) => IconButton(
                    onPressed: open,
                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                    color: foreground,
                    tooltip: '更多',
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: foreground,
                  tooltip: '关闭',
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 0.5, thickness: 0.5, color: divider),
        ],
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
    // 图标底色只取强调色的淡彩，图标本身也用强调色 —— 原来是「满饱和实底 + 白图标」，
    // 在加载这种一闪而过的过渡界面上对比太硬。
    final iconBgColor = accent.withValues(alpha: isDark ? 0.22 : 0.12);

    const ringSize = 88.0;
    const iconBgSize = 52.0;

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
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_filledVariant(icon), color: accent, size: 26),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: mutedColor),
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
    this.onDarkBackground = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onDarkBackground
          ? const Color(0xFF1C1C1E).withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.88),
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
              color: onDarkBackground ? Colors.white : const Color(0xFF111111),
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}
