import Flutter
import Foundation

/// 把原生收到的 uwhlife:// URL 转发到 Dart。
/// - SceneDelegate 在冷启动时调 setInitialLink；Dart 起来后通过 MethodChannel 主动取一次。
/// - SceneDelegate 在热启动时调 dispatch；EventChannel 把 URL 推给 Dart。
final class DeepLinkBridge {
  static let shared = DeepLinkBridge()

  private let methodChannelName = "uwhlife/deep_links"
  private let eventChannelName = "uwhlife/deep_links/events"

  private var eventSink: FlutterEventSink?
  private var initialLink: String?
  private var initialLinkConsumed = false

  private init() {}

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      if call.method == "getInitialLink" {
        if self.initialLinkConsumed {
          result(nil)
        } else {
          self.initialLinkConsumed = true
          result(self.initialLink)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(DeepLinkStreamHandler(bridge: self))
  }

  func setInitialLink(_ link: String) {
    initialLink = link
    initialLinkConsumed = false
  }

  func dispatch(_ link: String) {
    eventSink?(link)
  }

  fileprivate func attach(sink: FlutterEventSink?) {
    eventSink = sink
  }
}

private final class DeepLinkStreamHandler: NSObject, FlutterStreamHandler {
  private weak var bridge: DeepLinkBridge?

  init(bridge: DeepLinkBridge) {
    self.bridge = bridge
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    bridge?.attach(sink: events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    bridge?.attach(sink: nil)
    return nil
  }
}
