import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'models/app_entry.dart';
import 'widgets/app_tile.dart';

const FontWeight _appsBold = FontWeight.w500;
const FontWeight _appsSemiBold = FontWeight.w400;
const Color _appsBrandGreen = Color(0xFF22C55E);
const double _appsFloatingNavClearance = 112;
// 左右边距放在各子项上，分类切换的 PageView 才能整屏进出。
const double _appsHorizontalPadding = 20;
const EdgeInsets _appsContentPadding = EdgeInsets.symmetric(
  horizontal: _appsHorizontalPadding,
);

class _DampedPageScrollPhysics extends PageScrollPhysics {
  const _DampedPageScrollPhysics({super.parent, this.dragFactor = 0.82});

  final double dragFactor;

  @override
  _DampedPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _DampedPageScrollPhysics(
      parent: buildParent(ancestor),
      dragFactor: dragFactor,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset) * dragFactor;
  }
}

class AppListPage extends StatefulWidget {
  const AppListPage({super.key, required this.onOpenApp});

  final ValueChanged<AppEntry> onOpenApp;

  @override
  State<AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<AppListPage> {
  List<AppEntry> _allApps = const <AppEntry>[];
  List<String> _categories = const <String>['全部'];

  /// 按分类分好的结果，下标和 _categories 对齐（0 是「全部」）。
  /// 分类是加载时就定死的，没必要每帧在 PageView.builder 里重新过滤全表。
  List<List<AppEntry>> _appsByCategory = const <List<AppEntry>>[<AppEntry>[]];
  int _selected = 0;
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  final PageController _pageController = PageController();
  final ScrollController _categoryScrollController = ScrollController();
  List<GlobalKey> _categoryKeys = <GlobalKey>[GlobalKey()];
  String _search = '';
  // 搜索结果跟着输入变一次算一次，而不是每次 build 重新过滤 + toLowerCase。
  List<AppEntry> _searchResults = const <AppEntry>[];

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchCtrl.addListener(() {
      final v = _searchCtrl.text.trim();
      if (v == _search) return;
      final wasSearching = _search.isNotEmpty;
      setState(() {
        _search = v;
        _searchResults = _matchingApps(v);
      });
      if (wasSearching && v.isEmpty) _restorePagingPosition();
    });
  }

  /// 搜索时 PageView 整个被销毁，PageController 的位置会退回 initialPage（0）；
  /// 清空搜索框后如果不管，内容跳回「全部」而下划线还停在原来那个分类。
  void _restorePagingPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      if (_pageController.page?.round() == _selected) return;
      _pageController.jumpToPage(_selected);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _pageController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _selectCategory(int i, {bool animatePage = true}) {
    if (i == _selected || i < 0 || i >= _categories.length) return;
    setState(() => _selected = i);
    _scrollCategoryIntoView(i);
    if (!animatePage || !_pageController.hasClients) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollCategoryIntoView(int i) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || i >= _categoryKeys.length) return;
      final context = _categoryKeys[i].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  Future<void> _loadApps() async {
    try {
      final raw = await rootBundle.loadString('assets/app_list.json');
      final list = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(AppEntry.fromJson)
          .where((e) => e.url.isNotEmpty)
          .toList();
      final cats = <String>['全部'];
      final grouped = <String, List<AppEntry>>{};
      for (final a in list) {
        if (!cats.contains(a.category)) cats.add(a.category);
        (grouped[a.category] ??= <AppEntry>[]).add(a);
      }
      if (!mounted) return;
      setState(() {
        _allApps = list;
        _categories = cats;
        _appsByCategory = <List<AppEntry>>[
          list,
          for (final cat in cats.skip(1)) grouped[cat] ?? const <AppEntry>[],
        ];
        _categoryKeys = List<GlobalKey>.generate(
          cats.length,
          (_) => GlobalKey(),
        );
        _loading = false;
        _searchResults = _search.isEmpty
            ? const <AppEntry>[]
            : _matchingApps(_search);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<AppEntry> _matchingApps(String query) {
    final q = query.toLowerCase();
    return _allApps
        .where((a) => a.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<AppEntry> _appsForCategory(int i) {
    if (i < 0 || i >= _appsByCategory.length) return const <AppEntry>[];
    return _appsByCategory[i];
  }

  Widget _buildAppList(
    List<AppEntry> apps,
    Color labelColor,
    Color hintColor, {
    Key? key,
  }) {
    if (apps.isEmpty) {
      return Padding(
        key: key,
        padding: _appsContentPadding,
        child: Center(
          child: Text(
            '没有匹配的应用',
            style: TextStyle(color: hintColor, fontSize: 14),
          ),
        ),
      );
    }
    return ListView.builder(
      key: key,
      padding: const EdgeInsets.fromLTRB(
        _appsHorizontalPadding,
        4,
        _appsHorizontalPadding,
        _appsFloatingNavClearance,
      ),
      itemExtent: 64,
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        return AppTile(
          app: app,
          labelColor: labelColor,
          onTap: () => widget.onOpenApp(app),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = theme.colorScheme.onSurface;
    final inactiveColor = isDark
        ? const Color(0xFFBEBEBE)
        : const Color(0xFF6B7280);
    final activeColor = isDark ? const Color(0xFF7EE2A3) : _appsBrandGreen;
    final labelColor = isDark
        ? const Color(0xFFDEDEDE)
        : const Color(0xFF1F2937);
    // 搜索框按 MD2 走：中性灰底 + 小圆角，不再是绿味胶囊。
    final searchBg = md2SurfaceColor(theme.brightness);
    final searchBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final hintColor = isDark
        ? const Color(0xFF939393)
        : const Color(0xFFA0A0A0);
    final searching = _search.isNotEmpty;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _appsContentPadding,
              child: Text(
                '应用',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: titleColor,
                  fontWeight: _appsBold,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 48,
              margin: _appsContentPadding,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: searchBg,
                borderRadius: BorderRadius.circular(md2Radius),
                border: Border.all(color: searchBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: hintColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: TextStyle(
                        fontSize: 14,
                        color: labelColor,
                        fontWeight: _appsSemiBold,
                      ),
                      cursorColor: activeColor,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '搜索应用',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: hintColor,
                          fontWeight: _appsSemiBold,
                        ),
                      ),
                    ),
                  ),
                  if (searching)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _searchCtrl.clear,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.close_rounded,
                          color: hintColor,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (!searching)
              SizedBox(
                height: 36,
                child: ListView.separated(
                  controller: _categoryScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: _appsContentPadding,
                  itemCount: _categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (context, i) {
                    final selected = i == _selected;
                    return KeyedSubtree(
                      key: _categoryKeys[i],
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _selectCategory(i),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _categories[i],
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: selected
                                    ? _appsBold
                                    : _appsSemiBold,
                                color: selected ? activeColor : inactiveColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 3,
                              width: selected ? 22 : 0,
                              decoration: BoxDecoration(
                                color: activeColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Material(
                      color: Colors.transparent,
                      child: searching
                          ? _buildAppList(
                              _searchResults,
                              labelColor,
                              hintColor,
                              key: ValueKey<String>('search:$_search'),
                            )
                          : PageView.builder(
                              controller: _pageController,
                              physics: const _DampedPageScrollPhysics(
                                parent: ClampingScrollPhysics(),
                              ),
                              itemCount: _categories.length,
                              onPageChanged: (i) =>
                                  _selectCategory(i, animatePage: false),
                              itemBuilder: (context, i) {
                                return _buildAppList(
                                  _appsForCategory(i),
                                  labelColor,
                                  hintColor,
                                  key: PageStorageKey<String>(
                                    'app-category-${_categories[i]}',
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
