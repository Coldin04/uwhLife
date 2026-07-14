import 'package:flutter/material.dart';

import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_credentials.dart';
import '../../core/storage/portal_user_sync.dart';
import '../webview/portal_webview_page.dart';
import 'ids_http_auth.dart';

class IdsLoginPage extends StatefulWidget {
  const IdsLoginPage({super.key});

  static final Uri serviceUri = Uri.parse('https://ehall.uwh.edu.cn/login');

  @override
  State<IdsLoginPage> createState() => _IdsLoginPageState();
}

class _IdsLoginPageState extends State<IdsLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

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
    if (credentials == null || !mounted) return;
    _usernameController.text = credentials.$1;
    _passwordController.text = credentials.$2;
  }

  Future<void> _login() async {
    if (_loading || _formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await IdsHttpAuthClient().login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      service: IdsLoginPage.serviceUri,
    );
    if (!mounted) return;

    switch (result.status) {
      case IdsLoginStatus.authenticated:
        await result.syncCookiesToWebView();
        await LoginStateStore.markLoggedIn();
        await PortalCredentials.save(
          _usernameController.text.trim(),
          _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      case IdsLoginStatus.captchaRequired:
        setState(() => _error = '当前账号需要滑块验证，请使用网页登录');
      case IdsLoginStatus.invalidCredentials:
      case IdsLoginStatus.failed:
        setState(() => _error = result.message ?? '登录失败，请重试');
    }

    if (mounted && result.status != IdsLoginStatus.authenticated) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openWebLogin() async {
    await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => const PortalWebViewPage(
          title: '统一门户',
          icon: Icons.account_circle_outlined,
          initialUrl:
              'https://ids.uwh.edu.cn/authserver/login?service=https%3A%2F%2Fehall.uwh.edu.cn%2Flogin',
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
    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('登录统一门户', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _usernameController,
                  keyboardType: TextInputType.text,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: '学号 / 工号',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    return value == null || value.trim().isEmpty
                        ? '请输入学号或工号'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  validator: (value) {
                    return value == null || value.isEmpty ? '请输入密码' : null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                TextButton(
                  onPressed: _loading ? null : _openWebLogin,
                  child: const Text('使用网页登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('统一门户登录')),
      body: SafeArea(child: content),
    );
  }
}
