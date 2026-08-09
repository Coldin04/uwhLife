import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 交给系统浏览器打开，不走 App 内的 WebView。
/// 打不开时提示一次，调用方不需要再处理异常。
Future<bool> openInExternalBrowser(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final uri = Uri.tryParse(url);
  if (uri != null) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // 没有可用浏览器 / 平台拒绝，走下面的提示。
    }
  }
  messenger?.showSnackBar(const SnackBar(content: Text('无法打开系统浏览器')));
  return false;
}
