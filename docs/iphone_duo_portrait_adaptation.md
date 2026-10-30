# iPhone Duo 内屏竖屏适配指南

## 概述

本文档说明如何正确适配 iPhone Duo（苹果折叠屏）的内屏竖屏模式，确保 UI 控件不与右侧状态栏（时间、WiFi 等）重叠。

## 关键适配规范

根据 [Apple 官方文档](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)，iPhone Duo 内屏竖屏时：

1. **状态栏位置**：右侧垂直显示（时间、网络状态等）
2. **Dynamic Island**：位于右上角
3. **UI 控件要求**：所有交互式按钮必须绕开右侧保留区域
4. **安全区处理**：使用 `reservedRegions(kind: .occlusion)` 和 `statusBarFrame`

## 构建环境要求

| 配置 | 取值 | 说明 |
| --- | --- | --- |
| 编译 SDK（Xcode） | **iOS 27.1 或 27.2** | `verticalBarEdge`、`reservedRegions(kind:)` 只在 iOS 27.1+ SDK 中存在，用旧 Xcode 编译会直接报“无此成员” |
| 部署目标 `IPHONEOS_DEPLOYMENT_TARGET` | **15.0** | 保持 iOS 15–26 设备可安装；新 API 由 `if #available(iOS 27.1, *)` 兜底 |
| `source.json` `minOSVersion` | **15.0** | 与部署目标一致，AltStore/侧载按此判断可安装性 |

因此**不要**把部署目标抬到 27.1/27.2：那会让 iOS 15–26 的用户完全装不上，而 Duo 相关能力本身只需要运行时判版本即可。

构建机检查：

```bash
xcodebuild -version                 # 期望 Xcode 27.1 / 27.2
xcrun --sdk iphoneos --show-sdk-version   # 期望 >= 27.1
```

`Release` 工作流已固定 `maxim-lobanov/setup-xcode` 选择 Xcode 27.1，并在构建前校验 `xcrun --sdk iphoneos --show-sdk-version >= 27.1`，避免换个 runner 镜像后悄悄编译失败。

## 实现细节

### iOS 原生层 (AppDelegate.swift)

```swift
if #available(iOS 27.1, *) {
  let edge = view.traitCollection.verticalBarEdge
  let status = window.windowScene?.statusBarManager?.statusBarFrame ?? .zero
  // 底部安全区：只使用状态栏底部位置，不叠加其他遮挡区域
  let bottom = status.maxY
  // 计算右侧保留宽度（用于按钮定位）
  let rightReservedWidth = edge != .unspecified ? status.width : 0
  result([
    "edge": edgeName,
    "reservedBottom": bottom,
    "reservedRightWidth": rightReservedWidth,
    "adaptivePhone": view.traitCollection.userInterfaceIdiom == .phone
  ])
}
```

**关键改动**：
- ✅ `reservedBottom` 只使用 `status.maxY`，避免双重计算导致底栏过高
- ✅ 新增 `reservedRightWidth` 字段，精确报告右侧保留宽度

### Flutter 层 (side_navigation.dart)

```dart
/// iPhone Duo 内屏竖屏时，返回控件距离右边缘的安全距离
double sideControlRightInset(BuildContext context, double width) {
  // 右侧有状态栏时，使用系统报告的保留宽度
  if (systemVerticalEdge == 'right' && systemReservedRightWidth > 0) {
    return systemReservedRightWidth + 8; // 保留区域宽度 + 8pt 间距
  }
  
  // 左侧布局时使用 MediaQuery padding
  if (systemVerticalEdge == 'left') {
    final inset = MediaQuery.paddingOf(context).left;
    return inset > width ? (inset - width) / 2 : 8;
  }
  
  // 标准布局
  final inset = MediaQuery.paddingOf(context).right;
  return inset > width ? (inset - width) / 2 : 8;
}
```

### WebView 侧边栏优化 (portal_webview_page.dart)

**尺寸调整**：
- 宽度：56pt → **48pt**（更紧凑）
- 圆角：28pt → **24pt**
- 图标：24pt → **20pt**
- 按钮最小尺寸：48x48 → **36x36**
- 垂直间距：8pt → **6pt**

**定位优化**：
```dart
Padding(
  padding: EdgeInsets.only(
    right: systemVerticalEdge == 'left' ? 0 : sideControlRightInset(context, 48),
    left: systemVerticalEdge == 'left' ? sideControlRightInset(context, 48) : 0,
    top: isDuoDevice ? systemReservedBottom + 4 : 12, // 状态栏底部 + 4pt
  ),
  // ...
)
```

**底部安全区修复**：
```dart
final double webviewBottomPadding = widget.bottomSafeArea
    ? (wideLayout ? 0 : mq.padding.bottom) // 侧边栏模式时不添加底部 padding
    : 0;
```

## 已修复的问题

### 1. ✅ 顶栏按钮绕开右侧时间显示
- **原因**：未使用 `reservedRightWidth`，按钮定位仅基于 padding
- **修复**：使用原生层报告的精确状态栏宽度，按钮完全位于保留区域外侧

### 2. ✅ 底栏双重安全区问题
- **原因**：`reservedBottom` 计算时叠加了多个遮挡区域
- **修复**：只使用 `statusBarFrame.maxY`，不使用 `reduce` 累加

### 3. ✅ 工具栏宽度过粗
- **原因**：56pt 宽度在折叠屏竖屏模式下过于宽大
- **修复**：缩小至 48pt，并等比缩小图标和间距

### 4. ✅ 图片返回按钮定位偏右
- **原因**：`sideControlRightInset` 未区分右侧状态栏场景
- **修复**：在右侧状态栏模式下使用 `systemReservedRightWidth + 8` 定位

## 测试验证

运行测试：
```bash
flutter test test/side_navigation_test.dart
```

测试覆盖：
- ✅ 右侧状态栏模式下的控件定位
- ✅ 左侧布局模式的 padding 计算
- ✅ 标准手机模式的回退行为
- ✅ Duo 外屏的侧边导航检测

## 参考资料

- [Apple HIG: Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [iPhone Duo Safe Area Measurements](https://www.reddit.com/r/iOSDevelopment/comments/1wlkggd/i_measured_iphone_duos_safe_area_insets_and/)
- [Expo iPhone Duo Support](https://expo.dev/blog/supporting-iphone-duo)

## 最佳实践

1. **使用 UIKit 获取实时布局信息**：不要硬编码尺寸
2. **测试多种姿态**：内屏竖屏、外屏、横屏等
3. **保持触控目标尺寸**：按钮最小 44x44pt（或 36x36pt 在紧凑布局）
4. **避免遮挡状态栏**：所有交互元素必须留出右侧保留区域

---

*最后更新：2026-10-29*
