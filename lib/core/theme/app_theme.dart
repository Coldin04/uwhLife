import 'package:flutter/material.dart';

const FontWeight wBold = FontWeight.w700;
const FontWeight wSemiBold = FontWeight.w500;
const Color brandGreen = Color(0xFF22C55E);

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
