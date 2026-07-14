import EventKit
import Flutter
import UIKit
import WebKit
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let wkInjectorChannelName = "uwhlife/wkwebview_injector"
  private let browserDataChannelName = "uwhlife/browser_data"
  private let calendarChannelName = "uwhlife/calendar"
  private let documentExportChannelName = "uwhlife/document_export"
  private let eventStore = EKEventStore()
  private var documentExportDelegate: DocumentExportDelegate?
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

    let calendarChannel = FlutterMethodChannel(
      name: calendarChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    calendarChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleCalendar(call: call, result: result)
    }

    let documentExportChannel = FlutterMethodChannel(
      name: documentExportChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    documentExportChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleDocumentExport(call: call, result: result)
    }
  }

  private func handleDocumentExport(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "exportFile" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let sourcePath = args["sourcePath"] as? String
    else {
      result(FlutterError(code: "bad_args", message: "Missing sourcePath", details: nil))
      return
    }
    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(FlutterError(code: "file_missing", message: "Export file not found", details: nil))
      return
    }
    guard documentExportDelegate == nil else {
      result(FlutterError(code: "export_busy", message: "Another export is active", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_presenter", message: "No active view controller", details: nil))
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [sourceURL], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: sourceURL, in: .exportToService)
    }
    let delegate = DocumentExportDelegate { [weak self] error in
      self?.documentExportDelegate = nil
      if let error {
        result(error)
      } else {
        result(nil)
      }
    }
    documentExportDelegate = delegate
    picker.delegate = delegate
    presenter.present(picker, animated: true)
  }

  private func handleCalendar(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "addEvents" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let rawEvents = args["events"] as? [[String: Any]],
      !rawEvents.isEmpty
    else {
      result(FlutterError(code: "bad_args", message: "Missing events", details: nil))
      return
    }

    requestCalendarWriteAccess { [weak self] granted, error in
      guard let self else { return }
      if let error {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_failed", message: error.localizedDescription, details: nil))
        }
        return
      }
      guard granted else {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "日历写入权限未开启", details: nil))
        }
        return
      }
      do {
        guard let calendar = self.eventStore.defaultCalendarForNewEvents else {
          throw CalendarExportError.noDefaultCalendar
        }
        var savedCount = 0
        for rawEvent in rawEvents {
          guard
            let title = rawEvent["title"] as? String,
            let startMilliseconds = rawEvent["startMilliseconds"] as? NSNumber,
            let endMilliseconds = rawEvent["endMilliseconds"] as? NSNumber
          else {
            continue
          }
          let start = Date(timeIntervalSince1970: startMilliseconds.doubleValue / 1000)
          let end = Date(timeIntervalSince1970: endMilliseconds.doubleValue / 1000)
          guard end > start else { continue }

          let event = EKEvent(eventStore: self.eventStore)
          event.calendar = calendar
          event.title = title
          event.startDate = start
          event.endDate = end
          event.timeZone = TimeZone(identifier: "Asia/Shanghai")
          event.location = rawEvent["location"] as? String
          event.notes = rawEvent["notes"] as? String
          try self.eventStore.save(event, span: .thisEvent, commit: false)
          savedCount += 1
        }
        try self.eventStore.commit()
        DispatchQueue.main.async { result(savedCount) }
      } catch {
        self.eventStore.reset()
        DispatchQueue.main.async {
          result(FlutterError(code: "calendar_save_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func requestCalendarWriteAccess(
    completion: @escaping (Bool, Error?) -> Void
  ) {
    if #available(iOS 17.0, *) {
      eventStore.requestWriteOnlyAccessToEvents(completion: completion)
    } else {
      eventStore.requestAccess(to: .event, completion: completion)
    }
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    if let navigation = current as? UINavigationController {
      return navigation.visibleViewController ?? navigation
    }
    if let tabs = current as? UITabBarController {
      return tabs.selectedViewController ?? tabs
    }
    return current
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

private enum CalendarExportError: LocalizedError {
  case noDefaultCalendar

  var errorDescription: String? {
    switch self {
    case .noDefaultCalendar:
      return "没有可写入的默认日历"
    }
  }
}

private final class DocumentExportDelegate: NSObject, UIDocumentPickerDelegate {
  init(completion: @escaping (FlutterError?) -> Void) {
    self.completion = completion
  }

  private let completion: (FlutterError?) -> Void
  private var completed = false

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    finish(nil)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }

  private func finish(_ error: FlutterError?) {
    guard !completed else { return }
    completed = true
    completion(error)
  }
}
