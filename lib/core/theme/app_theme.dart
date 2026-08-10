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
    brightness == Brightness.dark ? const Color(0xFF020503) : Colors.white;

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
    // 这里直接给纯白/纯深底并关掉 tint。
    backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
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
  return ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: brightness,
    primary: brandGreen,
    secondary: isDark ? const Color(0xFF7EE2A3) : const Color(0xFF57CF84),
    surface: isDark ? const Color(0xFF111513) : Colors.white,
    onSurface: isDark ? const Color(0xFFF2F5F2) : const Color(0xFF111827),
    error: const Color(0xFFD44848),
    onError: Colors.white,
  );
}
