import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// 全局字体是内置的阿里普惠体，pubspec 里只声明了 400 / 500 / 700 三个字重，
// 这三档之外（w600、w800）都会被就近映射，写了也看不出区别。
// 整体字重比 v1.5.0 降了一档：原来的 700 → 500，原来的 500 → 400。
const FontWeight wBold = FontWeight.w500; // 页面标题、需要强调的文字
const FontWeight wMedium = FontWeight.w400; // 正文、列表项
const Color brandGreen = Color(0xFF22C55E);

/// 全局页面底色。所有页面（含首页）都不再铺绿色渐变，统一纯色。
/// 取值就是原来那套渐变的末端色，所以内容区观感和 v1.5.0 一致。
Color appBackground(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFF111827) : Colors.white;

// ---------------------------------------------------------------------------
// MD2 风格弹窗
// ---------------------------------------------------------------------------

// 主操作用比品牌绿深一档的绿：纯文字按钮比实心底弱得多，
// #22C55E 那种亮绿放在白底上当文字会发飘、看不清。
const Color _dialogAccentLight = Color(0xFF16A34A);
const Color _dialogAccentDark = Color(0xFF4ADE80);
const Color _dialogDangerLight = Color(0xFFC62828);
const Color _dialogDangerDark = Color(0xFFEF9A9A);

DialogThemeData buildDialogTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return DialogThemeData(
    // M3 默认会把种子色当 surfaceTint 混进弹窗背景，弹窗因此整体泛绿。
    // 这里直接给纯白/gray-700 并关掉 tint。
    backgroundColor: isDark ? const Color(0xFF374151) : Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    ),
  );
}

/// 统一的 App 对话框路由：淡化背景，并保留少量内容轮廓，减少突兀感。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible
        ? MaterialLocalizations.of(context).modalBarrierDismissLabel
        : null,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    transitionDuration: const Duration(milliseconds: 180),
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (dialogContext, _, _) {
      return SizedBox.expand(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: SafeArea(child: Builder(builder: builder)),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// MD2 的小圆角。弹出菜单、搜索框这类浮层都用它，不再走 M3 的大圆角。
const double md2Radius = 4;

/// 浮层/输入框的灰底。页面本身保持纯白，靠这层灰分出层级，
/// 也顺手甩掉 M3 那套带品牌色 tint 的 surface。
Color md2SurfaceColor(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0xFF2A2A2A)
    : const Color(0xFFEEEEEE);

/// MD2 弹出菜单：灰底 + 小圆角 + 真实投影，无描边、无 tint。
MenuStyle buildMd2MenuStyle(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return MenuStyle(
    backgroundColor: WidgetStatePropertyAll(md2SurfaceColor(brightness)),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(8),
    shadowColor: WidgetStatePropertyAll(
      Colors.black.withValues(alpha: isDark ? 0.6 : 0.32),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(md2Radius)),
      ),
    ),
    // MD2 菜单只在上下留白，菜单项自己铺满整宽。
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
  );
}

/// 菜单里的文字和图标都用这一个中性色，跟小程序的「更多」菜单一致：
/// 深色下纯白，浅色下近黑，不带品牌绿。
Color md2MenuForeground(Brightness brightness) =>
    brightness == Brightness.dark ? Colors.white : const Color(0xFF111111);

/// MD2 菜单项：铺满整宽的直角条目，高亮不带圆角。
ButtonStyle buildMd2MenuItemStyle(
  Brightness brightness, {
  double minWidth = 194,
}) {
  final foreground = md2MenuForeground(brightness);
  return MenuItemButton.styleFrom(
    minimumSize: Size(minWidth, 48),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    foregroundColor: foreground,
    iconColor: foreground,
    disabledForegroundColor: foreground.withValues(alpha: 0.34),
    disabledIconColor: foreground.withValues(alpha: 0.28),
    backgroundColor: Colors.transparent,
    textStyle: const TextStyle(fontSize: 14, fontWeight: wMedium),
    shape: const RoundedRectangleBorder(),
  );
}

/// MD2 底部弹层：白底、顶部小圆角、无 tint，也不要 M3 的拖拽把手。
BottomSheetThemeData buildBottomSheetTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return BottomSheetThemeData(
    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(md2Radius)),
    ),
  );
}

/// MD2 提示条（SnackBar / toast）。M3 默认拿 inverseSurface 当底，
/// 深色下会翻成白底黑字；这里两种模式都用深灰底白字，深色也不压到纯黑。
SnackBarThemeData buildSnackBarTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return SnackBarThemeData(
    backgroundColor: isDark ? const Color(0xFF2E2E2E) : const Color(0xFF323232),
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: wMedium,
    ),
    actionTextColor: _dialogAccentDark,
    elevation: 6,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(md2Radius)),
    ),
  );
}

/// 弹窗主操作（清除 / 确定 / 更新…）。纯文字、无填充无描边。
ButtonStyle dialogPrimaryAction(BuildContext context) => TextButton.styleFrom(
  foregroundColor: Theme.of(context).brightness == Brightness.dark
      ? _dialogAccentDark
      : _dialogAccentLight,
);

/// 弹窗破坏性操作（删除）。同样是纯文字，只是换成红色。
ButtonStyle dialogDangerAction(BuildContext context) => TextButton.styleFrom(
  foregroundColor: Theme.of(context).brightness == Brightness.dark
      ? _dialogDangerDark
      : _dialogDangerLight,
);

/// 弹窗次要操作（取消）。颜色比主操作淡，不跟它抢注意力。
ButtonStyle dialogQuietAction(BuildContext context) => TextButton.styleFrom(
  foregroundColor: Theme.of(
    context,
  ).colorScheme.onSurface.withValues(alpha: 0.5),
);

ColorScheme buildColorScheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  // fromSeed 会把品牌绿揉进所有 surface / outline 色阶，深色下整块底就泛绿了。
  // 这里把中性面全部改回真中性灰，只让 primary / secondary 保留绿。
  return ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: brightness,
    primary: brandGreen,
    secondary: isDark ? const Color(0xFF7EE2A3) : const Color(0xFF57CF84),
    surface: isDark ? const Color(0xFF141414) : Colors.white,
    onSurface: isDark ? const Color(0xFFF4F4F4) : const Color(0xFF111827),
    surfaceTint: Colors.transparent,
    surfaceContainerLowest: isDark ? const Color(0xFF0A0A0A) : Colors.white,
    surfaceContainerLow: isDark
        ? const Color(0xFF141414)
        : const Color(0xFFF7F7F7),
    surfaceContainer: isDark
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFF2F2F2),
    surfaceContainerHigh: isDark
        ? const Color(0xFF232323)
        : const Color(0xFFECECEC),
    surfaceContainerHighest: isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE6E6E6),
    onSurfaceVariant: isDark
        ? const Color(0xFFBEBEBE)
        : const Color(0xFF5F5F5F),
    outline: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF9E9E9E),
    outlineVariant: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD6D6D6),
    error: const Color(0xFFD44848),
    onError: Colors.white,
  );
}
