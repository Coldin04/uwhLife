import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_entry.dart';
import 'widgets/app_tile.dart';

const FontWeight _appsBold = FontWeight.w500;
const FontWeight _appsSemiBold = FontWeight.w400;
const Color _appsBrandGreen = Color(0xFF22C55E);
const double _appsFloatingNavClearance = 112;
const double _appsTopBarHeight = 64;
const double _appsCategoryBarHeight = 46;
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
  State<AppListPage> createState() => AppListPageState();
}

class AppListPageState extends State<AppListPage> {
  List<AppEntry> _allApps = const <AppEntry>[];
  List<String> _categories = const <String>['全部'];

  /// 按分类分好的结果，下标和 _categories 对齐（0 是「全部」）。
  /// 分类是加载时就定死的，没必要每帧在 PageView.builder 里重新过滤全表。
  List<List<AppEntry>> _appsByCategory = const <List<AppEntry>>[<AppEntry>[]];
  int _selected = 0;
  bool _loading = true;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final PageController _pageController = PageController();
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _searchScrollController = ScrollController();
  List<ScrollController> _appListControllers = <ScrollController>[];
  List<GlobalKey> _categoryKeys = <GlobalKey>[GlobalKey()];
  String _search = '';
  bool _searchMode = false;
  bool _searchResultsReady = false;
  bool _hasReselectedToTop = false;
  Timer? _searchDebounce;
  // 搜索结果跟着输入变一次算一次，而不是每次 build 重新过滤 + toLowerCase。
  List<AppEntry> _searchResults = const <AppEntry>[];

  @override
  void initState() {
    super.initState();
    _loadApps();
    _searchCtrl.addListener(() {
      if (!_searchMode) return;
      final v = _searchCtrl.text.trim();
      if (v == _search) return;
      _searchDebounce?.cancel();
      setState(() {
        _search = v;
        _searchResults = const <AppEntry>[];
        _searchResultsReady = false;
        _hasReselectedToTop = false;
      });
      if (v.isEmpty) return;
      _searchDebounce = Timer(const Duration(seconds: 1), () {
        if (!mounted || !_searchMode || _search != v) return;
        setState(() {
          _searchResults = _matchingApps(v);
          _searchResultsReady = true;
        });
      });
    });
  }

  /// 搜索时 PageView 整个被销毁，PageController 的位置会退回 initialPage（0）；
  /// 关闭搜索后需要回到原分类，避免内容和分类下划线不同步。
  void _restorePagingPosition({int retries = 1}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        if (retries > 0) _restorePagingPosition(retries: retries - 1);
        return;
      }
      if (_pageController.page?.round() == _selected) return;
      _pageController.jumpToPage(_selected);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _categoryScrollController.dispose();
    _searchScrollController.dispose();
    for (final controller in _appListControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectCategory(int i, {bool animatePage = true}) {
    if (i == _selected || i < 0 || i >= _categories.length) return;
    setState(() {
      _selected = i;
      _hasReselectedToTop = false;
    });
    _scrollCategoryIntoView(i);
    if (!animatePage || !_pageController.hasClients) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _openSearch() {
    setState(() {
      _searchMode = true;
      _search = '';
      _searchResults = const <AppEntry>[];
      _searchResultsReady = false;
      _hasReselectedToTop = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searchMode) return;
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _searchMode = false;
      _search = '';
      _searchResults = const <AppEntry>[];
      _searchResultsReady = false;
      _hasReselectedToTop = false;
    });
    _searchCtrl.clear();
    _restorePagingPosition();
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
      final previousControllers = _appListControllers;
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
        _appListControllers = List<ScrollController>.generate(
          cats.length,
          (_) => ScrollController(),
        );
        _loading = false;
        _searchResults = const <AppEntry>[];
      });
      for (final controller in previousControllers) {
        controller.dispose();
      }
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

  /// 已在「应用」tab 时，第一次点底栏只回当前内容顶部；第二次才回「全部」。
  void handleTabReselect() {
    if (!_hasReselectedToTop) {
      _hasReselectedToTop = true;
      _scrollToTop(_activeListController);
      return;
    }

    _hasReselectedToTop = false;
    _returnToAllTop();
  }

  ScrollController? get _activeListController {
    if (_searchMode) return _searchScrollController;
    if (_selected < 0 || _selected >= _appListControllers.length) return null;
    return _appListControllers[_selected];
  }

  void _returnToAllTop() {
    if (_selected != 0) {
      setState(() => _selected = 0);
      _scrollCategoryIntoView(0);
    }
    if (_searchMode) _closeSearch();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients && _pageController.page?.round() != 0) {
        _pageController.jumpToPage(0);
      }
      if (_appListControllers.isNotEmpty) {
        _scrollToTop(_appListControllers.first);
      }
    });
  }

  void _scrollToTop(ScrollController? controller) {
    if (controller == null || !controller.hasClients) return;
    if (controller.position.pixels <= 0) return;
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildAppList(
    List<AppEntry> apps,
    Color labelColor,
    Color hintColor, {
    Key? key,
    ScrollController? controller,
    required double topPadding,
  }) {
    if (apps.isEmpty) {
      return Padding(
        key: key,
        padding: EdgeInsets.fromLTRB(
          _appsHorizontalPadding,
          topPadding,
          _appsHorizontalPadding,
          _appsFloatingNavClearance,
        ),
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
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        _appsHorizontalPadding,
        topPadding,
        _appsHorizontalPadding,
        _appsFloatingNavClearance,
      ),
      itemExtent: 58,
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
    // 搜索框与底部悬浮导航保持同一套胶囊圆角。之前两种主题都直接借用
    // md2SurfaceColor，是纯 R=G=B 灰（浅色 #EEEEEE、深色 #2A2A2A），
    // 没有色相，浅色偏深、深色又容易被看成发绿；这里单独给搜索框换成
    // Tailwind 灰阶（浅色 gray-100、深色 gray-800），不动 md2SurfaceColor
    // 本身（菜单/弹层还在用它）。
    final searchBg = isDark
        ? const Color(0xFF1F2937) // Tailwind gray-800
        : const Color(0xFFF3F4F6); // Tailwind gray-100
    final searchBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    // 之前是纯 R=G=B 的灰（#939393 / #A0A0A0），没有色相，在真机（尤其
    // OLED）暗态下反而容易被感知成发绿。换成 Tailwind gray-400，带一点
    // 冷调，是设计系统里公认更「干净」的中性灰。
    const hintColor = Color(0xFF9CA3AF);
    final searching = _searchMode;

    final topInset = MediaQuery.paddingOf(context).top;
    final topBarHeight = topInset + _appsTopBarHeight;
    // 分类栏是顶层毛玻璃，列表首项在分割线后留出一点呼吸距离；继续
    // 滚动时，列表仍会从顶栏下方穿过并被毛玻璃采样。
    final overlayHeight =
        topBarHeight + (searching ? 0 : _appsCategoryBarHeight);
    final listTopPadding = searching ? topBarHeight : overlayHeight + 12;
    final overlayColor = isDark
        ? const Color(0xFF111827).withValues(alpha: 0.46)
        : theme.colorScheme.surface.withValues(alpha: 0.42);

    return PopScope(
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && searching) _closeSearch();
      },
      child: Stack(
        children: [
          Positioned.fill(
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
                        ? _searchResults.isEmpty
                              ? _SearchPlaceholder(
                                  query: _search,
                                  ready: _searchResultsReady,
                                  topPadding: listTopPadding,
                                  color: hintColor,
                                )
                              : _buildAppList(
                                  _searchResults,
                                  labelColor,
                                  hintColor,
                                  key: ValueKey<String>('search:$_search'),
                                  controller: _searchScrollController,
                                  topPadding: listTopPadding,
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
                                controller: _appListControllers[i],
                                topPadding: listTopPadding,
                              );
                            },
                          ),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: overlayHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: overlayColor,
                      border: Border(
                        bottom: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: topInset),
                      child: Column(
                        children: [
                          SizedBox(
                            height: _appsTopBarHeight,
                            child: searching
                                ? Padding(
                                    padding: const EdgeInsets.only(
                                      right: _appsHorizontalPadding,
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          tooltip: '关闭搜索',
                                          onPressed: _closeSearch,
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 44,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: searchBg,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: searchBorder,
                                              ),
                                            ),
                                            child: TextField(
                                              controller: _searchCtrl,
                                              focusNode: _searchFocusNode,
                                              expands: true,
                                              maxLines: null,
                                              minLines: null,
                                              textAlignVertical:
                                                  TextAlignVertical.center,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: labelColor,
                                                fontWeight: _appsSemiBold,
                                              ),
                                              cursorColor: activeColor,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
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
                                        ),
                                      ],
                                    ),
                                  )
                                : Padding(
                                    padding: _appsContentPadding,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '应用',
                                            style: theme.textTheme.headlineSmall
                                                ?.copyWith(
                                                  color: titleColor,
                                                  fontWeight: _appsBold,
                                                  letterSpacing: -0.8,
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '搜索应用',
                                          onPressed: _openSearch,
                                          icon: const Icon(
                                            Icons.search_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          if (!searching)
                            SizedBox(
                              height: _appsCategoryBarHeight,
                              child: ListView.separated(
                                controller: _categoryScrollController,
                                scrollDirection: Axis.horizontal,
                                padding: _appsContentPadding,
                                itemCount: _categories.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 18),
                                itemBuilder: (context, i) {
                                  final selected = i == _selected;
                                  return KeyedSubtree(
                                    key: _categoryKeys[i],
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _selectCategory(i),
                                      child: SizedBox(
                                        height: _appsCategoryBarHeight,
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 3,
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _categories[i],
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: selected
                                                        ? _appsBold
                                                        : _appsSemiBold,
                                                    color: selected
                                                        ? activeColor
                                                        : inactiveColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  height: 3,
                                                  width: selected ? 22 : 0,
                                                  decoration: BoxDecoration(
                                                    color: activeColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
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
    );
  }
}

class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder({
    required this.query,
    required this.ready,
    required this.topPadding,
    required this.color,
  });

  final String query;
  final bool ready;
  final double topPadding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = query.isEmpty
        ? '输入关键词搜索应用'
        : ready
        ? '没有匹配的应用'
        : '停止输入后开始搜索';
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 28, color: color),
            const SizedBox(height: 10),
            Text(text, style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
