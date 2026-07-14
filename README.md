# uwhLife / 芜忧皖江

> 本项目使用 vibe coding 方式编写。

本项目灵感来自 [自在东湖](https://chilleast.soilzhu.su/)

uwhLife / 芜忧皖江 是一个面向芜湖学院校园生活场景的 Flutter 移动端应用。项目当前聚焦常用校园入口和移动端体验：统一门户、校园应用列表、付款码、开门、热水/洗浴、智慧课堂、消息与个人页等。


<div align="center" style="display: flex; justify-content: center; align-items: center; gap: 16px; flex-wrap: wrap;">
  <a href="https://stikstore.app/altdirect/?url=https://raw.giteeusercontent.com/coldin04/uwhlife_source/raw/main/source.json" target="_blank">
    <img src="https://raw.githubusercontent.com/stikstore/altdirect/main/assets/png/AltSource_Blue.png" alt="Add AltSource" width="200">
  </a>
  <a href="https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_unsigned.ipa" target="_blank">
    <img src="https://raw.githubusercontent.com/stikstore/altdirect/main/assets/png/Download_Blue.png" alt="Download .ipa" width="200">
  </a>
  <a href="https://gitee.com/coldin04/uwhlife_source/releases/download/latest/UWHLife_android_arm64-v8a.apk" target="_blank">
    <img src="https://img.shields.io/badge/Download-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Download Android APK" width="200">
  </a>
</div>

## 功能概览

- 校园首页：轻量绿色视觉、常用服务入口、登录状态提示。
- 统一门户 WebView：承载学校统一认证和校内服务页面。
- 应用列表：通过本地 JSON 维护校园服务入口。
- 付款码：生成并展示付款相关二维码界面。
- 扫码能力：基于移动端相机扫描二维码。
- 深链接：支持从系统链接进入开门、付款码、洗浴等目标页。
- 本地状态：保存登录状态、门户用户信息和调试开关。
- Android/iOS：包含原生平台桥接、iOS no-sign 打包脚本和 Android release 构建配置。

## 更新日志

### 1.3.1

- 固定 Android release 签名，后续版本可正常覆盖更新。
- 优化 CI 的 Flutter、Dart、Gradle 与 CocoaPods 缓存。
- iOS 课表导入独立日历，便于单独管理与删除。

### 1.3.0

- 全新的课表系统：课表现在以应用原生界面显示，并支持查看更多课程隐藏信息。
- 优化门锁响应体验，开门流程更顺畅好用。
- 解决了一些已知问题。

## 项目结构

```text
.
├── android/                  # Android 原生工程与 Gradle 配置
├── assets/                   # 应用入口 JSON、字体等静态资源
├── ios/                      # iOS 原生工程、Podfile 与 Swift 桥接代码
├── lib/
│   ├── core/                 # 主题、存储、平台清理、深链接、路由工具
│   └── features/             # 首页、应用列表、消息、付款码、个人页、WebView 等功能
├── scripts/
│   └── package_unsigned_ipa.sh
├── test/                     # Flutter widget/unit tests
├── web/                      # 未来 GitHub Pages / 项目主页占位目录
├── .github/workflows/        # CI 与正式 tag 自动构建流程
├── pubspec.yaml              # Flutter 依赖与资源声明
└── pubspec.lock              # 锁定依赖版本
```

## 依赖说明

主要运行时依赖：

- `webview_flutter`、`webview_flutter_android`、`webview_flutter_wkwebview`：校内门户与服务页面 WebView。
- `shared_preferences`：轻量状态缓存。
- `flutter_secure_storage`：本地敏感信息存储。
- `mobile_scanner`：二维码扫描。
- `qr_flutter`：二维码渲染。
- `flutter_reactive_ble`、`permission_handler`：蓝牙与权限能力。
- `image_picker`：图片选择能力。
- `package_info_plus`：读取应用版本信息，后续可用于更新检测。
- `cupertino_icons`：iOS 风格图标补充。

开发与测试依赖：

- `flutter_test`：Flutter 官方测试框架。
- `flutter_lints`：推荐 lint 规则。
- `package_info_plus_platform_interface`、`webview_flutter_platform_interface`：测试中的平台接口替身。

## 致谢

- [自在东湖](https://chilleast.soilzhu.su/)：为本项目提供了灵感。
- [SleepIn 课程表](https://github.com/Kurosu-Ti01/SleepIn)：为本应用课表模块的界面设计提供了思路；本项目未参考或使用其相关代码。
- [Flutter](https://flutter.dev/) 与 [Dart](https://dart.dev/)：提供跨平台应用框架与语言基础。
- `webview_flutter`、`mobile_scanner`、`qr_flutter`、`flutter_reactive_ble`、`permission_handler`、`flutter_secure_storage`、`shared_preferences`、`share_plus` 等开源组件：为校园服务页面、扫码、蓝牙、权限、本地存储和文件分享能力提供支持。

## 本地开发

准备 Flutter stable 环境后执行：

```bash
flutter pub get
flutter analyze
flutter test
```

运行到设备：

```bash
flutter run
```

构建 Android APK：

```bash
flutter build apk --release --split-per-abi
```

课表默认缓存 7 天。构建时可通过 `SCHEDULE_CACHE_TTL_DAYS` 修改失效天数，设为 `0` 可让每次进入课表时都重新请求：

```bash
flutter build apk --release --dart-define=SCHEDULE_CACHE_TTL_DAYS=3
```

构建 iOS no-sign App：

```bash
flutter build ios --release --no-codesign
```

打包 iOS 未签名 IPA：

```bash
bash scripts/package_unsigned_ipa.sh --build --name UWHLife_unsigned.ipa
```

## GitHub Actions

仓库包含两条自动化流程：

- `CI`：推送到 `main` 或创建 Pull Request 时，自动执行 `flutter pub get`、`flutter analyze`、`flutter test`，并构建 Android APK artifact。
- `Release`：在 `main` 上推送正式版本 tag 时触发，例如：

```bash
git tag v1.2.0
git push origin main
git push origin v1.2.0
```

Release 流程会自动构建：

- Android release APK：`UWHLife_android_armeabi-v7a.apk`、`UWHLife_android_arm64-v8a.apk`、`UWHLife_android_x86_64.apk`
- iOS unsigned IPA：通过 `scripts/package_unsigned_ipa.sh` 打包 `UWHLife_unsigned.ipa`

这些产物会上传到对应的 GitHub Release。发布流程还会自动更新 GitHub 仓库里的 `source.json` 和 `update.json`；如果要同步到 Gitee，将这两个 JSON 以及 APK/IPA 产物同步到 `uwhlife_source` 仓库即可。

### Android Release 签名

Android 更新必须始终使用同一把 release keystore，否则系统会把新 APK 识别为不同签名，无法覆盖安装。请只生成一次 keystore，并妥善离线备份：

```bash
keytool -genkeypair -v \
  -keystore uwhlife-release.keystore \
  -alias uwhlife \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -storetype PKCS12
```

本地构建时，将 `android/key.properties.example` 复制为 `android/key.properties` 后填入该 keystore 的路径与密码。`android/key.properties` 和 keystore 文件均已被 Git 忽略。

GitHub Actions 发布前，需要在仓库 Actions secrets 中配置：

- `ANDROID_KEYSTORE_BASE64`：`uwhlife-release.keystore` 的 Base64 单行内容。
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

macOS 可使用以下命令生成 Base64 内容：

```bash
base64 -i uwhlife-release.keystore | tr -d '\n'
```

## 未来 Web 页面

`web/` 目录已预留给未来项目主页、GitHub Pages 或下载页。当前它只是静态内容占位，不参与 Flutter 移动端构建。

## 发布前检查

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

如果要发布 iOS 未签名 IPA：

```bash
bash scripts/package_unsigned_ipa.sh --build --name UWHLife_unsigned.ipa
```

## License

MIT License. See [LICENSE](LICENSE).
