import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'external_link.dart';

/// 唤起本机已安装的 App（如学习通 `cxstudy://cxstudy`）。
///
/// 两端都走 URL scheme：iOS 直接支持，Android 侧 url_launcher 只会发
/// ACTION_VIEW，拿不到按包名启动的能力，所以同样依赖 scheme
/// （需要在 AndroidManifest 的 `<queries>` 里登记该 scheme 才查得到）。
/// 唤起失败（没装 / 没注册 scheme）时用浏览器打开 [fallbackUrl] 兜底。
Future<bool> launchAppScheme(
  BuildContext context, {
  required String scheme,
  String? fallbackUrl,
}) async {
  final uri = Uri.tryParse(scheme);
  if (uri != null) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Android 未安装时抛 ActivityNotFoundException，iOS 返回 false。
    }
  }

  if (fallbackUrl == null || fallbackUrl.isEmpty) return false;
  if (!context.mounted) return false;
  return openInExternalBrowser(context, fallbackUrl);
}
