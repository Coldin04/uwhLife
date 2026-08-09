import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// 临时把屏幕拉亮（付款码扫码用），离开时还原。
///
/// 用的是 application 级别的亮度：Android 只作用于本 App 的窗口，
/// 切后台由系统自动恢复；iOS 是系统级的，必须自己调 [restore]。
/// 两端都不碰屏幕超时设置。
class ScreenBrightnessBoost {
  ScreenBrightnessBoost({this.level = 1.0});

  final double level;
  bool _applied = false;

  bool get isApplied => _applied;

  Future<void> apply() async {
    if (_applied) return;
    _applied = true;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(level);
    } catch (e) {
      _applied = false;
      debugPrint('[Brightness] boost failed: $e');
    }
  }

  Future<void> restore() async {
    if (!_applied) return;
    // 先落状态再 await，避免 restore 还没回来又触发一次 apply。
    _applied = false;
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('[Brightness] restore failed: $e');
    }
  }
}
