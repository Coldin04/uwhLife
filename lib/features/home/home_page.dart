import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/platform/browser_data_cleaner.dart';
import '../../core/storage/login_state_store.dart';
import '../../core/storage/portal_user_store.dart';
import 'widgets/home_cards.dart';
import 'widgets/status_indicator.dart';

const FontWeight _homePageSemiBold = FontWeight.w500;
const Color _homePageBrandGreen = Color(0xFF22C55E);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.onOpenAppList,
    this.onOpenPortal,
    this.onOpenPayCode,
    this.onOpenSchedule,
    this.onOpenClassroom,
    this.onOpenBath,
  });

  final VoidCallback? onOpenAppList;
  final Future<void> Function()? onOpenPortal;
  final Future<void> Function()? onOpenPayCode;
  final Future<void> Function()? onOpenSchedule;
  final Future<void> Function()? onOpenClassroom;
  final Future<void> Function()? onOpenBath;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _probeUrl = 'https://ehall.uwh.edu.cn/getLoginUser';
  static const _hitokotoCacheKey = 'home_hitokoto_text';
  static const _hitokotoUrl = 'https://v1.hitokoto.cn/?encode=json&c=i&c=k';
  static const _defaultHitokoto = '读万卷书，行万里路';
  static const String _doorSubmitScript = r'''
(function(){
  var form = document.getElementById('aspnetForm');
  if (!form) return;
  ['x','y'].forEach(function(s){
    var n = 'ctl00$btnOpen.' + s;
    if (!form.querySelector('input[name="' + n + '"]')){
      var i = document.createElement('input');
      i.type = 'hidden'; i.name = n; i.value = '1';
      form.appendChild(i);
    }
  });
  form.submit();
})();
''';

  bool _loggedIn = false;
  String _hitokoto = _defaultHitokoto;
  late final WebViewController _probeController;
  Completer<({String body, String url})>? _probeCompleter;
  bool _probing = false;

  WebViewController? _doorController;
  Completer<String?>? _doorCompleter;
  bool _doorBusy = false;
  int _doorStep = 0;
  String? _doorMessage;
  Timer? _doorMessageTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _probeController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            final c = _probeCompleter;
            if (c == null || c.isCompleted) return;
            try {
              final r = await _probeController.runJavaScriptReturningResult(
                'document.body ? document.body.innerText : ""',
              );
              c.complete((body: r.toString(), url: url));
            } catch (_) {
              c.complete((body: '', url: url));
            }
          },
          onWebResourceError: (_) {
            final c = _probeCompleter;
            if (c != null && !c.isCompleted) {
              c.complete((body: '', url: ''));
            }
          },
        ),
      );
    _loadLoginState();
    _loadHitokoto();
    _probeAndSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doorMessageTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadLoginState();
      _probeAndSync();
    }
  }

  Future<void> triggerDoorFromDeepLink() => _triggerDoor();

  Future<void> _loadLoginState() async {
    final loggedIn = await LoginStateStore.readLoggedIn();
    if (!mounted) return;
    setState(() => _loggedIn = loggedIn);
  }

  void _loadHitokoto() {
    unawaited(_loadCachedHitokoto());
    unawaited(_refreshHitokoto());
  }

  Future<void> _loadCachedHitokoto() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_hitokotoCacheKey)?.trim();
      if (cached == null || cached.isEmpty || !mounted) return;
      if (_hitokoto == cached) return;
      setState(() {
        _hitokoto = cached;
      });
    } catch (_) {}
  }

  Future<void> _refreshHitokoto() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse(_hitokotoUrl));
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is Map && data['hitokoto'] is String) {
        final text = (data['hitokoto'] as String).trim();
        if (text.isEmpty || !mounted) return;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_hitokotoCacheKey, text);
        if (!mounted || _hitokoto == text) return;
        setState(() {
          _hitokoto = text;
        });
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _probeAndSync() async {
    if (_probing) return;
    _probing = true;
    try {
      _probeCompleter = Completer<({String body, String url})>();
      await _probeController.loadRequest(Uri.parse(_probeUrl));
      final res = await _probeCompleter!.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => (body: '', url: ''),
      );

      final finalUri = Uri.tryParse(res.url);
      final finalHost = finalUri?.host.toLowerCase() ?? '';
      if (finalHost == 'ids.uwh.edu.cn') {
        await LoginStateStore.markLoggedOut();
        if (mounted) await _loadLoginState();
        return;
      }

      var bodyText = res.body;
      if (bodyText.startsWith('"')) {
        try {
          final unwrapped = jsonDecode(bodyText);
          if (unwrapped is String) bodyText = unwrapped;
        } catch (_) {}
      }
      if (bodyText.isEmpty) return;

      try {
        final parsed = jsonDecode(bodyText);
        if (parsed is Map && parsed['data'] is Map) {
          final data = (parsed['data'] as Map).cast<String, dynamic>();
          final userName = data['userName']?.toString();
          if (userName != null && userName.isNotEmpty) {
            String? className;
            final orgs = data['orgs'];
            if (orgs is List && orgs.isNotEmpty) {
              final first = orgs.first;
              if (first is Map) {
                final name = first['name']?.toString();
                if (name != null && name.isNotEmpty) className = name;
              }
            }
            if (className == null) {
              final deptRaw = data['deptName']?.toString();
              if (deptRaw != null && deptRaw.isNotEmpty) {
                final segs = deptRaw
                    .split('/')
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (segs.isNotEmpty) className = segs.last;
              }
            }

            await LoginStateStore.markLoggedIn();
            await PortalUserStore.save(
              userName: userName,
              userAccount: data['userAccount']?.toString(),
              categoryName: data['categoryName']?.toString(),
              className: className,
            );
            if (mounted) await _loadLoginState();
            return;
          }
        }
      } catch (_) {}
    } finally {
      _probing = false;
    }
  }

  Future<void> _clearLoginState() async {
    await LoginStateStore.markLoggedOut();
    if (!mounted) return;
    setState(() => _loggedIn = false);
  }

  Future<void> _openPortal() async {
    await widget.onOpenPortal?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openPayCode() async {
    await widget.onOpenPayCode?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openSchedule() async {
    await widget.onOpenSchedule?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openClassroom() async {
    await widget.onOpenClassroom?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _openBath() async {
    await widget.onOpenBath?.call();
    if (!mounted) return;
    await _loadLoginState();
    await _probeAndSync();
  }

  Future<void> _confirmClearLoginState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清除登录状态'),
          content: const Text(
            '将清除 App 内全局浏览器数据（Cookie、缓存、站点存储），并重置右上角状态；不会删除已保存的密码。',
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
    await _clearLoginState();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已清除登录状态')));
  }

  Future<WebViewController> _ensureDoorController() async {
    final existing = _doorController;
    if (existing != null) return existing;

    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            final c = _doorCompleter;
            if (c == null || c.isCompleted) return;
            final uri = Uri.tryParse(url);
            final host = uri?.host.toLowerCase() ?? '';

            if (_doorStep == 1) {
              if (host == 'ids.uwh.edu.cn') {
                c.complete('__needs_login__');
                return;
              }
              _doorStep = 2;
              try {
                await controller.runJavaScript(_doorSubmitScript);
              } catch (_) {
                if (!c.isCompleted) c.complete(null);
              }
            } else if (_doorStep == 2) {
              try {
                final r = await controller.runJavaScriptReturningResult(
                  "(function(){var e=document.getElementById('ctl00_lblInfo');return e?(e.textContent||'').trim():'';})()",
                );
                var text = r.toString();
                if (text.startsWith('"')) {
                  try {
                    final unwrapped = jsonDecode(text);
                    if (unwrapped is String) text = unwrapped;
                  } catch (_) {}
                }
                c.complete(text);
              } catch (_) {
                c.complete('');
              }
            }
          },
          onWebResourceError: (_) {
            final c = _doorCompleter;
            if (c != null && !c.isCompleted) c.complete(null);
          },
        ),
      );

    _doorController = controller;
    if (mounted) setState(() {});
    return controller;
  }

  Future<void> _triggerDoor() async {
    if (_doorBusy) return;
    _doorMessageTimer?.cancel();
    setState(() {
      _doorBusy = true;
      _doorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);

    try {
      final controller = await _ensureDoorController();
      _doorStep = 1;
      _doorCompleter = Completer<String?>();
      await controller.loadRequest(
        Uri.parse('http://opendoor.uwh.edu.cn:46010/Default.aspx'),
      );
      final result = await _doorCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );

      if (!mounted) return;
      if (result == '__needs_login__') {
        _showDoorMessage('需要先登录统一门户');
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('需要先登录统一门户'),
            action: SnackBarAction(label: '去登录', onPressed: _openPortal),
          ),
        );
      } else if (result == null) {
        _showDoorMessage('开门超时，请重试');
      } else {
        _showDoorMessage(result.isEmpty ? '已发送开门指令' : result);
      }
    } finally {
      if (mounted) {
        setState(() {
          _doorBusy = false;
        });
      } else {
        _doorBusy = false;
      }
      _doorStep = 0;
    }
  }

  void _showDoorMessage(String text) {
    _doorMessageTimer?.cancel();
    setState(() {
      _doorMessage = text;
    });
    _doorMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _doorMessage = null;
      });
    });
  }

  LoginStatus get _status {
    return _loggedIn ? LoginStatus.loggedIn : LoginStatus.loggedOut;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return '夜深了';
    if (hour < 11) return '早上好';
    if (hour < 13) return '中午好';
    if (hour < 18) return '下午好';
    if (hour < 23) return '晚上好';
    return '夜深了';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = scheme.onSurface;
    final lockCardColor = isDark
        ? const Color(0xFF1B7F44)
        : _homePageBrandGreen;
    final smallCardColor = isDark
        ? const Color(0xFF151C18)
        : const Color(0xFFF0F8F2);
    final moreCardColor = isDark
        ? const Color(0xFF122018)
        : const Color(0xFFE6F6EA);

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? const [
                        Color(0xFF123B24),
                        Color(0xFF082413),
                        Color(0xFF020503),
                      ]
                    : const [
                        Color(0xFFC8F1D8),
                        Color(0xFFEAF8EF),
                        Colors.white,
                      ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final contentWidth = width > 720 ? 720.0 : width;
              final tileHeight = ((contentWidth - 40 - 12) / 2).clamp(
                0.0,
                double.infinity,
              );

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: contentWidth,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_greeting()}，同学',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                          color: headerColor,
                                          fontWeight: _homePageSemiBold,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _hitokoto,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: headerColor.withValues(
                                            alpha: 0.55,
                                          ),
                                          height: 1.35,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            StatusIndicator(
                              status: _status,
                              onTap: _openPortal,
                              onLongPress: _confirmClearLoginState,
                            ),
                          ],
                        ),
                        const Spacer(),
                        SizedBox(
                          height: tileHeight,
                          child: Row(
                            children: [
                              Expanded(
                                child: PrimaryFeatureCard(
                                  title: '门锁',
                                  subtitle: _doorBusy
                                      ? '开门中…'
                                      : (_doorMessage ?? '准备就绪'),
                                  icon: Icons.lock_open_rounded,
                                  backgroundColor: lockCardColor,
                                  foregroundColor: Colors.white,
                                  onTap: _triggerDoor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GridView.count(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: 1,
                                  children: [
                                    SecondaryFeatureCard(
                                      icon: Icons.calendar_month_outlined,
                                      backgroundColor: smallCardColor,
                                      foregroundColor: headerColor,
                                      onTap: _openSchedule,
                                    ),
                                    SecondaryFeatureCard(
                                      icon: Icons.qr_code_2_outlined,
                                      backgroundColor: smallCardColor,
                                      foregroundColor: headerColor,
                                      onTap: _openPayCode,
                                    ),
                                    SecondaryFeatureCard(
                                      icon: Icons.school_outlined,
                                      backgroundColor: smallCardColor,
                                      foregroundColor: headerColor,
                                      onTap: _openClassroom,
                                    ),
                                    SecondaryFeatureCard(
                                      icon: Icons.shower_rounded,
                                      backgroundColor: moreCardColor,
                                      foregroundColor: headerColor,
                                      onTap: _openBath,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: -10,
          top: -10,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: WebViewWidget(controller: _probeController),
            ),
          ),
        ),
        if (_doorController != null)
          Positioned(
            left: -10,
            top: -10,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: WebViewWidget(controller: _doorController!),
              ),
            ),
          ),
      ],
    );
  }
}
