import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class OpenSourcePage extends StatelessWidget {
  const OpenSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBackground = appBackground(theme.brightness);
    final bodyColor = theme.colorScheme.onSurface;
    final secondaryColor = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: Text(
          '开源声明',
          style: TextStyle(color: bodyColor, fontSize: 18, fontWeight: wBold),
        ),
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '芜忧皖江基于 Flutter 与开源社区的优秀组件构建而成。我们尊重并感谢每一位开发者的贡献。',
            style: TextStyle(color: secondaryColor, fontSize: 15, height: 1.6),
          ),
          const SizedBox(height: 32),
          _buildLicenseSection(
            context,
            title: 'uwhLife',
            content: '本项目采用 MIT License，完整许可文本请参阅项目仓库中的 LICENSE 文件。',
          ),
          _buildLicenseSection(
            context,
            title: 'Flutter SDK 与 Dart',
            content: '由 Flutter 与 Dart 社区提供，遵循其各自的 BSD-style 开源许可。',
          ),
          _buildLicenseSection(
            context,
            title: 'webview_flutter',
            content: '用于承载统一门户及校园服务页面，许可信息以其项目仓库声明为准。',
          ),
          _buildLicenseSection(
            context,
            title: 'mobile_scanner、qr_flutter',
            content: '用于二维码扫描与生成，许可信息以各自项目仓库声明为准。',
          ),
          _buildLicenseSection(
            context,
            title: 'flutter_reactive_ble、permission_handler',
            content: '用于蓝牙连接及系统权限管理，许可信息以各自项目仓库声明为准。',
          ),
          _buildLicenseSection(
            context,
            title: 'shared_preferences、flutter_secure_storage、share_plus',
            content: '用于本地状态、安全存储及系统分享，许可信息以各自项目仓库声明为准。',
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseSection(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 17,
              fontWeight: wBold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
