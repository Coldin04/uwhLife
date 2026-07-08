import Flutter
import UIKit
import WebKit
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let wkInjectorChannelName = "uwhlife/wkwebview_injector"
  private let browserDataChannelName = "uwhlife/browser_data"
  private weak var webViewPluginRegistry: FlutterPluginRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    webViewPluginRegistry = engineBridge.pluginRegistry

    DeepLinkBridge.shared.register(
      with: engineBridge.applicationRegistrar.messenger()
    )

    let channel = FlutterMethodChannel(
      name: wkInjectorChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleWebViewInjection(call: call, result: result)
    }

    let browserDataChannel = FlutterMethodChannel(
      name: browserDataChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    browserDataChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleBrowserData(call: call, result: result)
    }
  }

  private func handleWebViewInjection(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "injectDocumentStartScript" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let identifier = args["webViewIdentifier"] as? Int64,
      let script = args["script"] as? String
    else {
      result(
        FlutterError(code: "bad_args", message: "Missing webViewIdentifier or script", details: nil)
      )
      return
    }
    // 依次尝试两个可能的 registry：
    //   1) implicit engine bridge 捕获到的 pluginRegistry —— 正常情况这里就拿得到
    //   2) FlutterAppDelegate 自身（也实现了 FlutterPluginRegistry）—— 兜底，
    //      避免 implicit engine 与 GeneratedPluginRegistrant 注册到不同对象时取空。
    var lookupErrors: [String] = []
    var resolved: WKWebView?

    if let registry = webViewPluginRegistry {
      if let wv = FWFWebViewFlutterWKWebViewExternalAPI.webView(
        forIdentifier: identifier,
        withPluginRegistry: registry
      ) {
        resolved = wv
      } else {
        lookupErrors.append("implicit_registry_miss")
      }
    } else {
      lookupErrors.append("implicit_registry_nil")
    }

    if resolved == nil {
      if let wv = FWFWebViewFlutterWKWebViewExternalAPI.webView(
        forIdentifier: identifier,
        withPluginRegistry: self
      ) {
        resolved = wv
      } else {
        lookupErrors.append("self_registry_miss")
      }
    }

    guard let webView = resolved else {
      result(
        FlutterError(
          code: "no_webview",
          message: "WKWebView not found for identifier \(identifier)",
          details: lookupErrors.joined(separator: ",")
        )
      )
      return
    }

    let userScript = WKUserScript(
      source: script,
      injectionTime: .atDocumentStart,
      forMainFrameOnly: false
    )
    webView.configuration.userContentController.addUserScript(userScript)
    result(nil)
  }

  private func handleBrowserData(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "clearAppBrowserData":
      let dataStore = WKWebsiteDataStore.default()
      let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
      dataStore.removeData(
        ofTypes: dataTypes,
        modifiedSince: Date(timeIntervalSince1970: 0)
      ) {
        result(nil)
      }

    case "clearCookiesForUrl":
      guard
        let args = call.arguments as? [String: Any],
        let url = args["url"] as? String,
        let parsedUrl = URL(string: url),
        let names = args["names"] as? [String]
      else {
        result(FlutterError(code: "bad_args", message: "Missing url or names", details: nil))
        return
      }
      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      cookieStore.getAllCookies { cookies in
        let host = parsedUrl.host ?? ""
        let namesToDelete = Set(names)
        let matching = cookies.filter { cookie in
          namesToDelete.contains(cookie.name) &&
          (host.hasSuffix(cookie.domain) ||
           cookie.domain.hasPrefix(".") && host.hasSuffix(String(cookie.domain.dropFirst())))
        }
        if matching.isEmpty {
          result(nil)
          return
        }
        var remaining = matching.count
        for cookie in matching {
          cookieStore.delete(cookie) {
            remaining -= 1
            if remaining == 0 {
              result(nil)
            }
          }
        }
      }

    case "setCookiesForUrl":
      guard
        let args = call.arguments as? [String: Any],
        let url = args["url"] as? String,
        let parsedUrl = URL(string: url),
        let rawCookies = args["cookies"] as? [String]
      else {
        result(FlutterError(code: "bad_args", message: "Missing url or cookies", details: nil))
        return
      }
      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      let headerFields = rawCookies.map { ["Set-Cookie": $0] }
      let cookies = headerFields.flatMap {
        HTTPCookie.cookies(withResponseHeaderFields: $0, for: parsedUrl)
      }
      if cookies.isEmpty {
        result(nil)
        return
      }
      var remaining = cookies.count
      for cookie in cookies {
        cookieStore.setCookie(cookie) {
          remaining -= 1
          if remaining == 0 {
            result(nil)
          }
        }
      }

    case "getCookies":
      guard
        let args = call.arguments as? [String: Any],
        let url = args["url"] as? String,
        let parsedUrl = URL(string: url)
      else {
        result(FlutterError(code: "bad_args", message: "Missing url", details: nil))
        return
      }
      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      cookieStore.getAllCookies { cookies in
        let host = parsedUrl.host ?? ""
        let matching = cookies.filter { cookie in
          host.hasSuffix(cookie.domain) || cookie.domain.hasPrefix(".") && host.hasSuffix(String(cookie.domain.dropFirst()))
        }
        let cookieString = matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        result(cookieString)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
