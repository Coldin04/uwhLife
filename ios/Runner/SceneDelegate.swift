import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    // 冷启动时如果是被 URL 唤起的，先暂存，等 Dart 主动来取
    if let url = connectionOptions.urlContexts.first?.url {
      DeepLinkBridge.shared.setInitialLink(url.absoluteString)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    guard let url = URLContexts.first?.url else { return }
    // 应用已在后台/前台时再次被 uwhlife://... 唤起
    DeepLinkBridge.shared.dispatch(url.absoluteString)
  }
}
