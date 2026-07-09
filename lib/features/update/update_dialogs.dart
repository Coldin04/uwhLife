import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/app_theme.dart';
import 'apk_installer.dart';
import 'update_check_cooldown.dart';
import 'update_manifest.dart';
import 'update_service.dart';

class UpdateDialogs {
  UpdateDialogs._();

  static bool _automaticCheckShown = false;

  static Future<void> checkAndShow(
    BuildContext context, {
    bool automatic = false,
    UpdateService service = const UpdateService(),
    UpdateCheckCooldown? cooldown,
  }) async {
    final checkCooldown = cooldown ?? UpdateCheckCooldown();
    if (automatic) {
      if (_automaticCheckShown) return;
      _automaticCheckShown = true;
      if (await checkCooldown.shouldSkipAutomaticCheck()) return;
      if (!context.mounted) return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!automatic) {
      messenger?.showSnackBar(const SnackBar(content: Text('正在检查更新...')));
    }

    PackageInfo info;
    UpdateManifest? manifest;
    try {
      info = await PackageInfo.fromPlatform();
      manifest = await service.fetchManifest();
    } catch (_) {
      if (!context.mounted) return;
      if (!automatic) {
        messenger?.showSnackBar(const SnackBar(content: Text('暂时无法获取更新信息')));
      }
      return;
    }
    if (!context.mounted) return;

    if (manifest == null) {
      if (!automatic) {
        messenger?.showSnackBar(const SnackBar(content: Text('暂时无法获取更新信息')));
      }
      return;
    }

    if (Platform.isAndroid) {
      final update = manifest.android;
      final hasUpdate = update.isNewerThan(buildNumber: info.buildNumber);
      final forceUpdate = update.requiresUpdate(buildNumber: info.buildNumber);
      if (!hasUpdate && !forceUpdate) {
        await service.cleanupStaleAndroidApks();
        if (!automatic) {
          messenger?.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        }
        return;
      }
      await _showAndroidUpdateDialog(
        context,
        service: service,
        cooldown: checkCooldown,
        update: update,
        forceUpdate: update.mandatory,
      );
      return;
    }

    if (Platform.isIOS) {
      final update = manifest.ios;
      if (!update.isNewerThan(buildNumber: info.buildNumber)) {
        if (!automatic) {
          messenger?.showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
        }
        return;
      }
      await _showIosUpdateDialog(context, update, cooldown: checkCooldown);
    }
  }

  static Future<void> _showAndroidUpdateDialog(
    BuildContext context, {
    required UpdateService service,
    required UpdateCheckCooldown cooldown,
    required AndroidUpdateInfo update,
    required bool forceUpdate,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(update.title),
          content: _UpdateNotes(
            versionText: 'Android ${update.versionName}(${update.versionCode})',
            notes: update.notes,
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () async {
                  await cooldown.recordUserCancelled();
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('取消'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _downloadAndInstall(context, service, update);
              },
              child: const Text('立即更新'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showIosUpdateDialog(
    BuildContext context,
    IosUpdateInfo update, {
    required UpdateCheckCooldown cooldown,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(update.title),
          content: _UpdateNotes(
            versionText: 'iOS ${update.versionName}(${update.buildVersion})',
            notes: update.notes,
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await cooldown.recordUserCancelled();
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(
                  ClipboardData(text: update.altSourceUrl),
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('AltStore 源链接已复制')),
                );
              },
              child: const Text('复制源链接'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _downloadAndInstall(
    BuildContext context,
    UpdateService service,
    AndroidUpdateInfo update,
  ) async {
    final file = await showDialog<File?>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _DownloadApkDialog(service: service, update: update),
    );

    if (!context.mounted) return;
    if (file == null) return;

    final canInstall = await ApkInstaller.canRequestPackageInstalls();
    if (!context.mounted) return;
    if (!canInstall) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _InstallPermissionDialog(
          apkFile: file,
          onInstall: () => _installApk(context, file),
        ),
      );
      return;
    }

    await _installApk(context, file);
  }

  static Future<void> _installApk(BuildContext context, File file) async {
    try {
      await ApkInstaller.install(file.path);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开安装器，请稍后重试')),
      );
    }
  }
}

class _InstallPermissionDialog extends StatefulWidget {
  const _InstallPermissionDialog({
    required this.apkFile,
    required this.onInstall,
  });

  final File apkFile;
  final Future<void> Function() onInstall;

  @override
  State<_InstallPermissionDialog> createState() =>
      _InstallPermissionDialogState();
}

class _InstallPermissionDialogState extends State<_InstallPermissionDialog>
    with WidgetsBindingObserver {
  bool _openingSettings = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openingSettings) {
      _openingSettings = false;
      _tryInstallAfterPermission();
    }
  }

  Future<void> _tryInstallAfterPermission() async {
    if (_installing) return;
    final canInstall = await ApkInstaller.canRequestPackageInstalls();
    if (!mounted || !canInstall) return;
    setState(() => _installing = true);
    Navigator.of(context).pop();
    await widget.onInstall();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('允许安装应用'),
      content: const Text(
        'Android 需要先允许芜忧皖江安装未知来源应用，开启后回到 App 会继续安装已下载的更新包。',
      ),
      actions: [
        TextButton(
          onPressed: _installing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _installing
              ? null
              : () async {
                  setState(() => _openingSettings = true);
                  await ApkInstaller.openInstallPermissionSettings();
                },
          child: Text(_installing ? '正在打开' : '去设置'),
        ),
      ],
    );
  }
}

class _DownloadApkDialog extends StatefulWidget {
  const _DownloadApkDialog({required this.service, required this.update});

  final UpdateService service;
  final AndroidUpdateInfo update;

  @override
  State<_DownloadApkDialog> createState() => _DownloadApkDialogState();
}

class _DownloadApkDialogState extends State<_DownloadApkDialog> {
  int _received = 0;
  int? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final file = await widget.service.downloadAndroidApk(
        widget.update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_error == null ? '正在下载更新' : '下载失败'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _total == null || _total == 0 ? null : _received / _total!,
            ),
            const SizedBox(height: 12),
            Text(
              _formatProgress(_received, _total),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Text(_error!),
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('关闭'),
          ),
      ],
    );
  }

  static String _formatProgress(int received, int? total) {
    final current = _formatBytes(received);
    if (total == null || total <= 0) return current;
    return '$current / ${_formatBytes(total)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _UpdateNotes extends StatelessWidget {
  const _UpdateNotes({required this.versionText, required this.notes});

  final String versionText;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          versionText,
          style: theme.textTheme.bodySmall?.copyWith(color: brandGreen),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $note'),
            ),
        ],
      ],
    );
  }
}
