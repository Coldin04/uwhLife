import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/boundary_debug_settings.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import '../../core/storage/portal_user_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/route_utils.dart';
import '../update/android_version_code.dart';
import '../paycode/pay_result_sheet.dart';
import '../update/update_dialogs.dart';
import '../webview/portal_webview_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  bool _loggedIn = false;
  String? _userName;
  String? _userAccount;
  bool _hasSavedPassword = false;
  bool _boundaryDebugEnabled = false;
  bool _testingPageVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final loggedIn = await LoginStateStore.readLoggedIn();
    final user = await PortalUserStore.read();
    final creds = await PortalCredentials.read();
    final boundaryDebug = await BoundaryDebugSettings.read();
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _userName = user.userName;
      _userAccount = user.userAccount ?? creds?.$1;
      _hasSavedPassword = creds != null;
      _boundaryDebugEnabled = boundaryDebug.enabled;
      _testingPageVisible = boundaryDebug.menuVisible;
    });
  }

  Future<void> _openPortal() async {
    await Navigator.of(context).push<String?>(
      createSlideFadeRoute(
        const PortalWebViewPage(
          title: '统一门户',
          icon: Icons.account_circle_outlined,
          initialUrl:
              'https://ids.uwh.edu.cn/authserver/login?service=https%3A%2F%2Fehall.uwh.edu.cn%2Flogin',
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _confirmClearLoginState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除登录状态'),
          content: const Text(
            '将清除 App 内全局浏览器数据（Cookie、缓存、站点存储），并重置登录状态；不会删除已保存的密码。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await BrowserDataCleaner.clear();
    await LoginStateStore.markLoggedOut();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除登录状态')));
    await _refresh();
  }

  Future<void> _confirmDeleteSavedPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除已保存的密码'),
          content: const Text('将删除保存在本机的统一门户账号与密码，下次登录需要重新输入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD44848),
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await PortalCredentials.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除已保存的密码')));
    await _refresh();
  }

  Future<void> _setBoundaryDebugEnabled(bool enabled) async {
    final current = await BoundaryDebugSettings.read();
    await current.copyWith(enabled: enabled).save();
    if (!mounted) return;
    setState(() => _boundaryDebugEnabled = enabled);
  }

  void _showPaymentSheetTest() {
    showPayResultSheet(
      context: context,
      success: true,
      money: '12.34',
      payTypeName: '一码通',
      primaryLabel: '关闭',
    );
  }

  Future<void> _openBoundaryDebugSettings() async {
    if (!_testingPageVisible) return;
    if (!_boundaryDebugEnabled) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const _BoundaryDebugSettingsPage()));
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openTestingPage() async {
    await Navigator.of(context).push(
      createSlideFadeRoute(
        _TestingPage(
          boundaryDebugEnabled: _boundaryDebugEnabled,
          onBoundaryDebugChanged: _setBoundaryDebugEnabled,
          onOpenBoundaryDebugSettings: _openBoundaryDebugSettings,
          onShowPaymentSheetTest: _showPaymentSheetTest,
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openAboutPage() async {
    await Navigator.of(context).push(createSlideFadeRoute(const _AboutPage()));
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _resetBoundaryDebugDefaultsIfVisible() async {
    final settings = await BoundaryDebugSettings.read();
    if (!settings.menuVisible) return;
    if (!settings.enabled) return;

    await BoundaryDebugSettings.resetToDefaults(menuVisible: true);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('边界测试参数已恢复默认值')));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final hasUserName = _userName?.trim().isNotEmpty ?? false;
    final hasUserAccount = _userAccount?.trim().isNotEmpty ?? false;
    final title = _loggedIn
        ? (hasUserName
              ? _userName!.trim()
              : (hasUserAccount ? _userAccount!.trim() : '已登录'))
        : '未登录';
    final titleColor = scheme.onSurface;
    final subtitleColor = isDark
        ? const Color(0xFFB6C2BC)
        : const Color(0xFF777777);
    final avatarColor = isDark ? const Color(0xFF1B7F44) : brandGreen;
    final accountText = _loggedIn
        ? (hasUserName && hasUserAccount ? _userAccount!.trim() : null)
        : '点击进入统一门户登录';
    final dividerColor = isDark
        ? const Color(0xFF26312A)
        : const Color(0xFFE2E8E2);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
        children: [
          Text(
            '我的',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: titleColor,
              fontWeight: wBold,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 22),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openPortal,
              onLongPress: _confirmClearLoginState,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: avatarColor,
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: wBold,
                              color: titleColor,
                              height: 1.2,
                            ),
                          ),
                          if (accountText != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              accountText,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: subtitleColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (_loggedIn || _hasSavedPassword) ...[
            if (_loggedIn)
              _ProfileActionRow(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFD44848),
                title: '退出登录',
                onTap: _confirmClearLoginState,
              ),
            if (_loggedIn && _hasSavedPassword)
              _SectionDivider(color: dividerColor),
            if (_hasSavedPassword)
              _ProfileActionRow(
                icon: Icons.lock_reset_rounded,
                iconColor: const Color(0xFFD44848),
                title: '删除已保存的密码',
                onTap: _confirmDeleteSavedPassword,
              ),
            const SizedBox(height: 10),
          ],
          _ProfileActionRow(
            icon: Icons.system_update_alt_rounded,
            iconColor: subtitleColor,
            title: '检查更新',
            onTap: () => UpdateDialogs.checkAndShow(context),
          ),
          _SectionDivider(color: dividerColor),
          _ProfileActionRow(
            icon: Icons.info_outline_rounded,
            iconColor: subtitleColor,
            title: '关于',
            onTap: _openAboutPage,
            onLongPress: _resetBoundaryDebugDefaultsIfVisible,
          ),
          if (_testingPageVisible) ...[
            _SectionDivider(color: dividerColor),
            _ProfileActionRow(
              icon: Icons.science_outlined,
              iconColor: subtitleColor,
              title: '测试与调试',
              onTap: _openTestingPage,
            ),
          ],
        ],
      ),
    );
  }
}

class _TestingPage extends StatefulWidget {
  const _TestingPage({
    required this.boundaryDebugEnabled,
    required this.onBoundaryDebugChanged,
    required this.onOpenBoundaryDebugSettings,
    required this.onShowPaymentSheetTest,
  });

  final bool boundaryDebugEnabled;
  final ValueChanged<bool> onBoundaryDebugChanged;
  final VoidCallback onOpenBoundaryDebugSettings;
  final VoidCallback onShowPaymentSheetTest;

  @override
  State<_TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends State<_TestingPage> {
  late bool _boundaryDebugEnabled = widget.boundaryDebugEnabled;

  Future<void> _setBoundaryDebugEnabled(bool value) async {
    widget.onBoundaryDebugChanged(value);
    if (!mounted) return;
    setState(() => _boundaryDebugEnabled = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = isDark
        ? const Color(0xFFB6C2BC)
        : const Color(0xFF777777);
    final dividerColor = isDark
        ? const Color(0xFF26312A)
        : const Color(0xFFE2E8E2);

    return Scaffold(
      appBar: AppBar(title: const Text('测试与调试')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _ProfileActionRow(
              icon: Icons.bug_report_outlined,
              iconColor: _boundaryDebugEnabled ? brandGreen : subtitleColor,
              title: '边界测试',
              onTap: _boundaryDebugEnabled
                  ? widget.onOpenBoundaryDebugSettings
                  : null,
              trailing: Switch.adaptive(
                value: _boundaryDebugEnabled,
                onChanged: _setBoundaryDebugEnabled,
              ),
            ),
            _SectionDivider(color: dividerColor),
            _ProfileActionRow(
              icon: Icons.receipt_long_rounded,
              iconColor: subtitleColor,
              title: '测试支付成功弹窗',
              onTap: widget.onShowPaymentSheetTest,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileActionRow extends StatelessWidget {
  const _ProfileActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = theme.colorScheme.onSurface;
    final chevronColor = isDark
        ? const Color(0xFFB6C2BC)
        : const Color(0xFF8A938B);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: wBold,
                    color: titleColor,
                  ),
                ),
              ),
              trailing ??
                  Icon(Icons.chevron_right_rounded, color: chevronColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 38),
      child: Divider(height: 1, thickness: 1, color: color),
    );
  }
}

class _AboutPage extends StatefulWidget {
  const _AboutPage();

  @override
  State<_AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<_AboutPage> {
  static const int _debugTapThreshold = 10;
  String _versionText = '读取中';
  int _versionTapCount = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    final buildNumber = AndroidVersionCode.logicalBuildNumber(info.buildNumber);
    if (!mounted) return;
    setState(() {
      _versionText = '${info.version}($buildNumber)';
    });
  }

  Future<void> _handleVersionTap() async {
    _versionTapCount += 1;
    if (_versionTapCount < _debugTapThreshold) return;
    _versionTapCount = 0;

    final settings = await BoundaryDebugSettings.read();
    final nextVisible = !settings.menuVisible;
    await settings.copyWith(menuVisible: nextVisible, enabled: false).save();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(nextVisible ? '测试与调试已显示' : '测试与调试已隐藏')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = theme.colorScheme.onSurface;
    final subtitleColor = isDark
        ? const Color(0xFFB6C2BC)
        : const Color(0xFF777777);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Center(
            child: Column(
              children: [
                const Spacer(flex: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'icon.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '芜忧皖江',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: titleColor,
                    fontWeight: wBold,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleVersionTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    child: Text(
                      '版本 $_versionText',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const Spacer(flex: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BoundaryDebugSettingsPage extends StatefulWidget {
  const _BoundaryDebugSettingsPage();

  @override
  State<_BoundaryDebugSettingsPage> createState() =>
      _BoundaryDebugSettingsPageState();
}

class _BoundaryDebugSettingsPageState
    extends State<_BoundaryDebugSettingsPage> {
  final _lngController = TextEditingController();
  final _latController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lngController.dispose();
    _latController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await BoundaryDebugSettings.read();
    if (!mounted) return;
    setState(() {
      _enabled = settings.enabled;
      _lngController.text = settings.longitudeBd09.toStringAsFixed(5);
      _latController.text = settings.latitudeBd09.toStringAsFixed(5);
      _addressController.text = settings.address;
      _cityController.text = settings.city;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final lng = double.tryParse(_lngController.text.trim());
    final lat = double.tryParse(_latController.text.trim());
    final address = _addressController.text.trim();
    final city = _cityController.text.trim();
    if (lng == null || lat == null || address.isEmpty || city.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写有效的经纬度、地址和城市')));
      return;
    }
    final current = await BoundaryDebugSettings.read();
    await current
        .copyWith(
          enabled: _enabled,
          longitudeBd09: lng,
          latitudeBd09: lat,
          address: address,
          city: city,
        )
        .save();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('边界测试参数已保存')));
  }

  Future<void> _resetToDefaults() async {
    await BoundaryDebugSettings.resetToDefaults(menuVisible: true);
    final next = await BoundaryDebugSettings.read();
    if (!mounted) return;
    setState(() {
      _enabled = next.enabled;
      _lngController.text = next.longitudeBd09.toStringAsFixed(5);
      _latController.text = next.latitudeBd09.toStringAsFixed(5);
      _addressController.text = next.address;
      _cityController.text = next.city;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('边界测试参数已恢复默认值')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('边界测试'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  SwitchListTile.adaptive(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '启用边界测试',
                      style: TextStyle(
                        fontWeight: wBold,
                        color: scheme.onSurface,
                      ),
                    ),
                    subtitle: const Text('匹配签到页 URL 时注入测试定位参数'),
                  ),
                  const SizedBox(height: 10),
                  _DebugTextField(
                    controller: _lngController,
                    label: 'BD-09 经度',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DebugTextField(
                    controller: _latController,
                    label: 'BD-09 纬度',
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DebugTextField(controller: _addressController, label: '地址'),
                  const SizedBox(height: 12),
                  _DebugTextField(controller: _cityController, label: '城市'),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _resetToDefaults,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('重置默认值'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    BoundaryDebugSettings.targetPattern,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DebugTextField extends StatelessWidget {
  const _DebugTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
