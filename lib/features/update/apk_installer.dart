import 'package:flutter/services.dart';

class ApkInstaller {
  static const MethodChannel _channel = MethodChannel('uwhlife/apk_installer');

  static Future<bool> canRequestPackageInstalls() async {
    final result = await _channel.invokeMethod<bool>(
      'canRequestPackageInstalls',
    );
    return result ?? false;
  }

  static Future<void> openInstallPermissionSettings() {
    return _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<void> install(String filePath) {
    return _channel.invokeMethod<void>('installApk', {'path': filePath});
  }
}
