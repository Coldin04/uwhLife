import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import '../../core/storage/portal_user_sync.dart';
import '../../core/theme/app_theme.dart';
import '../webview/portal_webview_page.dart';
import 'ids_http_auth.dart';
import 'ids_slider_captcha.dart';
import 'portal_auto_login.dart';
import 'widgets/ids_slider_captcha_dialog.dart';

class IdsLoginPage extends StatefulWidget {
  const IdsLoginPage({super.key});

  static final Uri serviceUri = PortalAutoLogin.serviceUri;

  @override
  State<IdsLoginPage> createState() => _IdsLoginPageState();
}

class _IdsLoginPageState extends State<IdsLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  String? _error;
  int _captchaAttempts = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final credentials = await PortalCredentials.read();
    final rememberMe = await LoginStateStore.readRememberMe();
    if (!mounted) return;
    if (credentials != null) {
      _usernameController.text = credentials.$1;
      _passwordController.text = credentials.$2;
    }
    setState(() => _rememberMe = rememberMe);
  }

  Future<void> _login() async {
    if (_loading || _formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _error = null;
      _captchaAttempts = 0;
    });

    final generation = PortalAutoLogin.instance.beginInteractiveLogin();
    final result = await IdsHttpAuthClient().login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      service: IdsLoginPage.serviceUri,
      rememberMe: _rememberMe,
      onSliderCaptcha: _showSliderCaptcha,
    );
    if (!mounted) return;

    switch (result.status) {
      case IdsLoginStatus.authenticated:
        try {
          final committed = await PortalAutoLogin.instance.completeInteractiveLogin(
            observedGeneration: generation,
            syncCookies: result.syncCookiesToWebView,
          );
          if (!committed) {
            if (mounted) setState(() => _error = '登录状态已更改，请重试');
            break;
          }
        } catch (_) {
          if (mounted) setState(() => _error = '登录信息同步失败，请重试');
          break;
        }
        await PortalCredentials.save(
          _usernameController.text.trim(),
          _passwordController.text,
        );
        await LoginStateStore.writeRememberMe(_rememberMe);
        PortalAutoLogin.instance.reset();
        if (!mounted) return;
        Navigator.of(context).pop(true);
      case IdsLoginStatus.captchaRequired:
        setState(() => _error = '滑块验证未通过，请重试或使用网页登录');
      case IdsLoginStatus.invalidCredentials:
      case IdsLoginStatus.failed:
        setState(() => _error = result.message ?? '登录失败，请重试');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<IdsSliderAnswer?> _showSliderCaptcha(
    IdsSliderChallenge challenge,
  ) {
    if (!mounted) return Future<IdsSliderAnswer?>.value();
    final message = _captchaAttempts > 0 ? '验证未通过，请再试一次' : null;
    _captchaAttempts++;
    return IdsSliderCaptchaDialog.show(context, challenge, message: message);
  }

  Future<void> _openWebLogin() async {
    PortalAutoLogin.instance.beginInteractiveLogin();
    await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => const PortalWebViewPage(
          title: '统一门户',
          icon: Icons.account_circle_outlined,
          initialUrl:
              'https://ids.uwh.edu.cn/authserver/login?service=https%3A%2F%2Fehall.uwh.edu.cn%2Flogin',
          autoRecoverIdsSession: false,
        ),
      ),
    );
    if (!mounted) return;
    final loggedIn = await LoginStateStore.readLoggedIn();
    if (!mounted) return;
    if (loggedIn) {
      await PortalUserSync.fromWebViewCookies();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = '网页登录尚未完成');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final inputFill = isDark ? const Color(0xFF1B1B1D) : Colors.white;
    final inputBorder = isDark
        ? const Color(0xFF8A8A8F)
        : const Color(0xFF737B86);
    final muted = scheme.onSurface.withValues(alpha: 0.66);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: appBackground(theme.brightness),
        body: Stack(
          children: [
          Positioned(
            top: -118,
            right: -74,
            child: IgnorePointer(
              child: Container(
                width: 264,
                height: 264,
                decoration: BoxDecoration(
                  color: brandGreen.withValues(alpha: isDark ? 0.17 : 0.09),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: '返回',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back_ios_new_rounded),
                            ),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            '欢迎回来',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 34,
                              fontWeight: wBold,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '登录统一门户，继续使用校园服务',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: wMedium,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 58),
                          TextFormField(
                            controller: _usernameController,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            style: TextStyle(color: scheme.onSurface),
                            decoration: _inputDecoration(
                              hintText: '学号 / 工号',
                              fillColor: inputFill,
                              borderColor: inputBorder,
                              hintColor: muted,
                            ),
                            validator: (value) {
                              return value == null || value.trim().isEmpty
                                  ? '请输入学号或工号'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            style: TextStyle(color: scheme.onSurface),
                            decoration: _inputDecoration(
                              hintText: '密码',
                              fillColor: inputFill,
                              borderColor: inputBorder,
                              hintColor: muted,
                            ).copyWith(
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: muted,
                                ),
                                onPressed: () {
                                  setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  );
                                },
                              ),
                            ),
                            validator: (value) {
                              return value == null || value.isEmpty
                                  ? '请输入密码'
                                  : null;
                            },
                          ),
                          CheckboxListTile(
                            value: _rememberMe,
                            onChanged: _loading
                                ? null
                                : (value) => setState(
                                    () => _rememberMe = value ?? false,
                                  ),
                            title: const Text('7 天免登录'),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 17,
                                    color: scheme.error,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 34),
                          Align(
                            child: SizedBox(
                              width: 220,
                              height: 52,
                              child: FilledButton(
                                onPressed: _loading ? null : _login,
                                style: FilledButton.styleFrom(
                                  backgroundColor: brandGreen,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      brandGreen.withValues(alpha: 0.45),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: wBold,
                                  ),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('登录'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 36),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: scheme.onSurface.withValues(alpha: 0.18),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  '或',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: muted,
                                    fontWeight: wBold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: scheme.onSurface.withValues(alpha: 0.18),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _loading ? null : _openWebLogin,
                            style: TextButton.styleFrom(
                              foregroundColor: brandGreen,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: wBold,
                              ),
                            ),
                            child: const Text('使用网页登录'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required Color fillColor,
    required Color borderColor,
    required Color hintColor,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: borderColor, width: 1.25),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: hintColor),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 21),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: brandGreen, width: 1.8),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFD44848), width: 1.5),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFD44848), width: 1.8),
      ),
    );
  }
}
