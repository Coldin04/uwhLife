import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/boundary_debug_settings.dart';
import '../../core/storage/home_page_settings.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/paycode_brightness_settings.dart';
import '../../core/storage/portal_credentials.dart';
import '../../core/storage/portal_user_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/external_link.dart';
import '../../core/utils/route_utils.dart';
import '../auth/ids_login_page.dart';
import '../auth/portal_session_cookies.dart';
import '../message/message_list_page.dart';
import '../update/android_version_code.dart';
import '../paycode/pay_result_sheet.dart';
import '../update/update_dialogs.dart';
import '../webview/portal_webview_page.dart';
import 'open_source_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  bool _loggedIn = false;
  String? _userName;
  String? _userAccount;

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
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _userName = user.userName;
      _userAccount = user.userAccount ?? creds?.$1;
    });
  }

  Future<void> _openPortal() async {
    final loggedIn = await LoginStateStore.readLoggedIn();
    if (!mounted) return;
    if (loggedIn) {
      await Navigator.of(context).push<String?>(
        createSlideFadeRoute(
          const PortalWebViewPage(
            title: '统一门户',
            icon: Icons.account_circle_outlined,
            initialUrl: 'https://ehall.uwh.edu.cn/login',
          ),
        ),
      );
    } else {
      await Navigator.of(
        context,
      ).push<bool>(createSlideFadeRoute(const IdsLoginPage()));
    }
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _confirmClearLoginState() async {
    final confirmed = await showAppDialog<bool>(
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
              style: dialogQuietAction(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: dialogPrimaryAction(context),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await BrowserDataCleaner.clear();
    await PortalSessionCookies.clear();
    await LoginStateStore.markManualLogout();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除登录状态')));
    await _refresh();
  }

  Future<void> _openAboutPage() async {
    await Navigator.of(context).push(createSlideFadeRoute(const _AboutPage()));
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const _SettingsPage()));
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _openMessagesPage() async {
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const MessageListPage(standalone: true)));
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
        ? const Color(0xFFBEBEBE)
        : const Color(0xFF777777);
    final avatarBackground = isDark
        ? const Color(0xFF2A2A2C)
        : const Color(0xFFF5F5F5);
    final avatarIconColor = isDark
        ? const Color(0xFFB7B7BA)
        : const Color(0xFFBDBDBD);
    final accountText = _loggedIn
        ? (hasUserAccount ? _userAccount!.trim() : '点击登录以访问更多功能')
        : '点击登录以访问更多功能';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 12,
          20,
          20,
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openPortal,
                onLongPress: _confirmClearLoginState,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: avatarBackground,
                        child: Icon(
                          Icons.person_rounded,
                          size: 28,
                          color: avatarIconColor,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              accountText,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 14,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: subtitleColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            if (_loggedIn) ...[
              _ProfileActionRow(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFD44848),
                title: '退出登录',
                onTap: _confirmClearLoginState,
              ),
              const SizedBox(height: 10),
            ],
            _ProfileActionRow(
              icon: Icons.mail_outline_rounded,
              iconColor: subtitleColor,
              title: '我的消息',
              onTap: _openMessagesPage,
            ),
            _ProfileActionRow(
              icon: Icons.settings_outlined,
              iconColor: subtitleColor,
              title: '设置',
              onTap: _openSettingsPage,
            ),
            _ProfileActionRow(
              icon: Icons.info_outline_rounded,
              iconColor: subtitleColor,
              title: '关于',
              onTap: _openAboutPage,
              onLongPress: _resetBoundaryDebugDefaultsIfVisible,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage();

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _loading = true;
  bool _hasSavedPassword = false;
  bool _boundaryDebugEnabled = false;
  bool _mockScheduleHint = false;
  bool _testingPageVisible = false;
  HomePageSettings _homePageSettings = HomePageSettings.defaults;
  PayCodeBrightnessSettings _payCodeBrightness =
      PayCodeBrightnessSettings.defaults;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final credentialsFuture = PortalCredentials.read();
    final payCodeBrightnessFuture = PayCodeBrightnessSettings.read();
    final boundaryDebugFuture = BoundaryDebugSettings.read();
    final homePageSettingsFuture = HomePageSettings.read();
    final credentials = await credentialsFuture;
    final payCodeBrightness = await payCodeBrightnessFuture;
    final boundaryDebug = await boundaryDebugFuture;
    final homePageSettings = await homePageSettingsFuture;
    if (!mounted) return;
    setState(() {
      _hasSavedPassword = credentials != null;
      _payCodeBrightness = payCodeBrightness;
      _boundaryDebugEnabled = boundaryDebug.enabled;
      _mockScheduleHint = boundaryDebug.mockScheduleHint;
      _testingPageVisible = boundaryDebug.menuVisible;
      _homePageSettings = homePageSettings;
      _loading = false;
    });
  }

  Future<void> _setPayCodeAutoBoost(bool value) async {
    await _savePayCodeBrightness(_payCodeBrightness.copyWith(autoBoost: value));
  }

  Future<void> _setPayCodeBoostInDarkMode(bool value) async {
    await _savePayCodeBrightness(
      _payCodeBrightness.copyWith(boostInDarkMode: value),
    );
  }

  Future<void> _savePayCodeBrightness(
    PayCodeBrightnessSettings settings,
  ) async {
    setState(() => _payCodeBrightness = settings);
    await settings.save();
  }

  Future<void> _setBoundaryDebugEnabled(bool enabled) async {
    final current = await BoundaryDebugSettings.read();
    await current.copyWith(enabled: enabled).save();
    if (!mounted) return;
    setState(() => _boundaryDebugEnabled = enabled);
  }

  Future<void> _setMockScheduleHint(bool enabled) async {
    final current = await BoundaryDebugSettings.read();
    await current.copyWith(mockScheduleHint: enabled).save();
    if (!mounted) return;
    setState(() => _mockScheduleHint = enabled);
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
    if (!_boundaryDebugEnabled) return;
    await Navigator.of(
      context,
    ).push(createSlideFadeRoute(const _BoundaryDebugSettingsPage()));
    if (!mounted) return;
    await _load();
  }

  Future<void> _setHomeIconOnlyMode(bool value) async {
    final next = _homePageSettings.copyWith(iconOnlyMode: value);
    setState(() => _homePageSettings = next);
    await next.save();
  }

  Future<void> _confirmDeleteSavedPassword() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除已保存的密码'),
          content: const Text('将删除保存在本机的统一门户账号与密码，下次登录需要重新输入。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: dialogQuietAction(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: dialogDangerAction(context),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await PortalCredentials.clear();
    if (!mounted) return;
    setState(() => _hasSavedPassword = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已删除已保存的密码')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subtitleColor = isDark
        ? const Color(0xFFBEBEBE)
        : const Color(0xFF777777);
    final pageBackground = appBackground(theme.brightness);

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  Text(
                    '首页',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: subtitleColor,
                      fontWeight: wMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ProfileActionRow(
                    icon: Icons.text_fields_rounded,
                    iconColor: subtitleColor,
                    title: 'icon 无字模式',
                    trailing: Switch.adaptive(
                      value: _homePageSettings.iconOnlyMode,
                      onChanged: _setHomeIconOnlyMode,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '付款码',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: subtitleColor,
                      fontWeight: wMedium,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ProfileActionRow(
                    icon: Icons.brightness_high_rounded,
                    iconColor: subtitleColor,
                    title: '付款码自动增亮',
                    trailing: Switch.adaptive(
                      value: _payCodeBrightness.autoBoost,
                      onChanged: _setPayCodeAutoBoost,
                    ),
                  ),
                  _ProfileActionRow(
                    icon: Icons.nightlight_round,
                    iconColor: subtitleColor,
                    title: '深色模式下增亮',
                    trailing: Switch.adaptive(
                      value: _payCodeBrightness.boostInDarkMode,
                      onChanged: _payCodeBrightness.autoBoost
                          ? _setPayCodeBoostInDarkMode
                          : null,
                    ),
                  ),
                  if (_hasSavedPassword) ...[
                    const SizedBox(height: 22),
                    Text(
                      '账号与安全',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: subtitleColor,
                        fontWeight: wMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ProfileActionRow(
                      icon: Icons.lock_reset_rounded,
                      iconColor: const Color(0xFFD44848),
                      title: '删除已保存的密码',
                      onTap: _confirmDeleteSavedPassword,
                    ),
                  ],
                  if (_testingPageVisible) ...[
                    const SizedBox(height: 22),
                    Text(
                      '测试与调试',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: subtitleColor,
                        fontWeight: wMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ProfileActionRow(
                      icon: Icons.bug_report_outlined,
                      iconColor: _boundaryDebugEnabled
                          ? brandGreen
                          : subtitleColor,
                      title: '边界测试',
                      onTap: _boundaryDebugEnabled
                          ? _openBoundaryDebugSettings
                          : null,
                      trailing: Switch.adaptive(
                        value: _boundaryDebugEnabled,
                        onChanged: _setBoundaryDebugEnabled,
                      ),
                    ),
                    _ProfileActionRow(
                      icon: Icons.receipt_long_rounded,
                      iconColor: subtitleColor,
                      title: '测试支付成功弹窗',
                      onTap: _showPaymentSheetTest,
                    ),
                    _ProfileActionRow(
                      icon: Icons.view_agenda_outlined,
                      iconColor: _mockScheduleHint ? brandGreen : subtitleColor,
                      title: '预览首页课表卡片',
                      trailing: Switch.adaptive(
                        value: _mockScheduleHint,
                        onChanged: _setMockScheduleHint,
                      ),
                    ),
                  ],
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
        ? const Color(0xFFBEBEBE)
        : const Color(0xFF8F8F8F);

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
                    fontSize: 16,
                    fontWeight: wMedium,
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

  Future<void> _openLink(String url) async {
    await openInExternalBrowser(context, url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = theme.colorScheme.onSurface;
    final versionColor = isDark
        ? const Color(0xFF9CA3AF) // Tailwind gray-400
        : const Color(0xFF6B7280); // Tailwind gray-500
    final pageBackground = appBackground(theme.brightness);

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 32, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    image: const DecorationImage(
                      image: AssetImage('icon.png'),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '芜忧芜院',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: wBold,
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleVersionTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Version $_versionText',
                    style: TextStyle(
                      color: versionColor,
                      fontSize: 14,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _AboutActionRow(
                title: '检查更新',
                onTap: () => UpdateDialogs.checkAndShow(context),
              ),
              _AboutActionRow(
                title: '开源声明',
                onTap: () => Navigator.of(
                  context,
                ).push(createSlideFadeRoute(const OpenSourcePage())),
              ),
              const SizedBox(height: 8),
              _AboutActionRow(
                title: '官网',
                onTap: () => _openLink('https://uwh.cold04.com'),
              ),
              _AboutActionRow(
                title: 'GitHub',
                onTap: () => _openLink('https://github.com/Coldin04/uwhLife'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutActionRow extends StatelessWidget {
  const _AboutActionRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
        child: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w400,
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
                        fontSize: 16,
                        fontWeight: wMedium,
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
