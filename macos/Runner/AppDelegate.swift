import Cocoa
import FlutterMacOS
import UserNotifications
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  private let downloadsBridge = MacosDownloadsBridge()
  private let notificationsBridge = MacosNotificationsBridge()
  private let calendarBridge = AppleCalendarBridge()
  private let inputFocusBridge = MacosInputFocusBridge()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // A notification that launched the app arrives here rather than (or
    // before) the notification center delegate.
    if let response = notification.userInfo?[NSApplication.launchUserNotificationUserInfoKey]
      as? UNNotificationResponse {
      notificationsBridge.rememberLaunchResponse(response)
    }
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      downloadsBridge.register(messenger: controller.engine.binaryMessenger)
      notificationsBridge.register(messenger: controller.engine.binaryMessenger)
      calendarBridge.register(messenger: controller.engine.binaryMessenger)
      inputFocusBridge.register(
        controller: controller,
        messenger: controller.engine.binaryMessenger
      )
      FlutterMethodChannel(
        name: "net.yoshida.morebettergakujo/pdf_preview",
        binaryMessenger: controller.engine.binaryMessenger
      ).setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "setViewerURL":
          guard let url = call.arguments as? String,
                MacosPdfPreviewWindow.setViewerURL(url) else {
            result(FlutterError(code: "invalid_viewer", message: nil, details: nil))
            return
          }
        case "setPreviewState":
          guard let state = call.arguments as? String,
                ["visible", "hidden", "none"].contains(state) else {
            result(FlutterError(code: "invalid_visibility", message: nil, details: nil))
            return
          }
          MacosWebViewMouseNavigation.setPreviewActive(state != "none", mainWindow: self?.mainFlutterWindow)
          if state != "none" {
            MacosPdfPreviewWindow.setVisible(state == "visible", mainWindow: self?.mainFlutterWindow)
          }
        default:
          result(FlutterMethodNotImplemented)
          return
        }
        result(nil)
      }
    }
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// webview_flutter_wkwebview's WKUIDelegate does not implement the open panel
/// callback, so WKWebView silently ignores clicks on `<input type="file">` and
/// assignment attachments cannot be chosen. Add an NSOpenPanel implementation
/// to each UI delegate class before WebKit caches which callbacks it supports.
enum MacosWebViewFileUploadSupport {
  private typealias UIDelegateSetter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
  private typealias OpenPanelCompletion = @convention(block) (NSArray?) -> Void
  private typealias OpenPanelHandler = @convention(block) (
    AnyObject, WKWebView, WKOpenPanelParameters, WKFrameInfo, @escaping OpenPanelCompletion
  ) -> Void

  private static var installed = false
  private static let openPanelSelector = NSSelectorFromString(
    "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:"
  )

  static func install() {
    guard !installed else { return }
    installed = true

    let setterSelector = #selector(setter: WKWebView.uiDelegate)
    guard let method = class_getInstanceMethod(WKWebView.self, setterSelector) else {
      NSLog("MoreBetterGakujo: WKWebView.setUIDelegate: is unavailable; file uploads are disabled")
      return
    }
    let originalSetter = unsafeBitCast(method_getImplementation(method), to: UIDelegateSetter.self)
    let replacement: @convention(block) (AnyObject, AnyObject?) -> Void = { webView, delegate in
      if let delegate, let delegateClass = object_getClass(delegate) {
        Self.addOpenPanelHandlerIfNeeded(to: delegateClass)
        MacosPdfPreviewWindow.install(on: delegateClass)
      }
      originalSetter(webView, setterSelector, delegate)
    }
    method_setImplementation(
      method,
      imp_implementationWithBlock(unsafeBitCast(replacement, to: AnyObject.self))
    )
  }

  private static func addOpenPanelHandlerIfNeeded(to delegateClass: AnyClass) {
    guard !class_respondsToSelector(delegateClass, openPanelSelector) else { return }

    let handler: OpenPanelHandler = { _, webView, parameters, _, completion in
      let panel = NSOpenPanel()
      panel.canChooseFiles = true
      panel.canChooseDirectories = parameters.allowsDirectories
      panel.allowsMultipleSelection = parameters.allowsMultipleSelection
      panel.resolvesAliases = true

      let finish: (NSApplication.ModalResponse) -> Void = { response in
        completion(response == .OK ? panel.urls as NSArray : nil)
      }
      if let window = webView.window {
        panel.beginSheetModal(for: window, completionHandler: finish)
      } else {
        finish(panel.runModal())
      }
    }
    // v = void, @ = self, : = _cmd, then webView, parameters, frame, block.
    class_addMethod(
      delegateClass,
      openPanelSelector,
      imp_implementationWithBlock(unsafeBitCast(handler, to: AnyObject.self)),
      "v@:@@@@?"
    )
  }
}

/// WKWebView ignores the back/forward buttons of multi-button mice and the
/// Cmd+[ / Cmd+] shortcuts, so route them to the WebView's history like
/// Safari does (Windows gets Alt+Left/Right from WebView2).
enum MacosWebViewMouseNavigation {
  private static let backButtonNumber = 3
  private static let forwardButtonNumber = 4
  private static var monitor: Any?
  private static var keyMonitor: Any?

  static func setPreviewActive(_ active: Bool, mainWindow: NSWindow?) {
    if let mainWindow, let webView = webView(in: mainWindow) {
      // Preview content owns two-finger scrolling and pinching. Explicit
      // mouse buttons and Cmd+[ / Cmd+] still navigate through the preview.
      webView.allowsBackForwardNavigationGestures = !active
    }
  }

  static func install() {
    guard monitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard modifiers == .command,
            let key = event.charactersIgnoringModifiers,
            key == "[" || key == "]",
            let window = event.window,
            let webView = Self.webView(in: window) else {
        return event
      }
      Self.navigate(webView, back: key == "[")
      return nil
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
      guard event.buttonNumber == Self.backButtonNumber ||
              event.buttonNumber == Self.forwardButtonNumber,
            let webView = Self.webView(under: event) else {
        return event
      }
      Self.navigate(webView, back: event.buttonNumber == Self.backButtonNumber)
      return nil
    }
  }

  private static func navigate(_ webView: WKWebView, back: Bool) {
    let target = MacosPdfPreviewWindow.opener(for: webView) ?? webView
    let direction = back ? "back" : "forward"
    target.evaluateJavaScript("window.__MBG_PREVIEW_NAVIGATE ? window.__MBG_PREVIEW_NAVIGATE('\(direction)') : false") { result, error in
      guard error == nil, (result as? Bool) != true else { return }
      if back && target.canGoBack { target.goBack() }
      else if !back && target.canGoForward { target.goForward() }
    }
  }

  /// The focused WebView, or else the window's only WebView.
  private static func webView(in window: NSWindow) -> WKWebView? {
    var responder: NSResponder? = window.firstResponder
    while let current = responder {
      if let webView = current as? WKWebView {
        return webView
      }
      responder = current.nextResponder
    }
    guard let contentView = window.contentView else { return nil }
    return firstWebView(in: contentView)
  }

  private static func firstWebView(in view: NSView) -> WKWebView? {
    if let webView = view as? WKWebView {
      return webView.isHiddenOrHasHiddenAncestor ? nil : webView
    }
    for subview in view.subviews {
      if let webView = firstWebView(in: subview) {
        return webView
      }
    }
    return nil
  }

  private static func webView(under event: NSEvent) -> WKWebView? {
    guard let contentView = event.window?.contentView else { return nil }
    // hitTest expects a point in the coordinate system of the view's superview.
    let point = contentView.superview?.convert(event.locationInWindow, from: nil)
      ?? event.locationInWindow
    var view = contentView.hitTest(point)
    while let current = view {
      if let webView = current as? WKWebView {
        return webView
      }
      view = current.superview
    }
    return nil
  }
}

private final class MacosInputFocusBridge {
  private static let channelName = "net.yoshida.morebettergakujo/input_focus"

  func register(
    controller: FlutterViewController,
    messenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak controller] call, result in
      guard call.method == "restoreFlutterFirstResponder" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let controller, let window = controller.view.window else {
        result(FlutterError(
          code: "flutter_window_unavailable",
          message: "Flutter window is not available",
          details: nil
        ))
        return
      }

      guard window.makeFirstResponder(nil) else {
        result(false)
        return
      }
      result(window.makeFirstResponder(controller.view))
    }
  }
}

struct NotificationLaunchPair {
  private var launched: String?
  private var tapped: String?

  mutating func acceptLaunch(_ identifier: String) -> Bool {
    guard identifier != tapped else { return false }
    launched = identifier
    return true
  }

  mutating func acceptTap(_ identifier: String) -> Bool {
    if identifier == launched {
      launched = nil
      return false
    }
    tapped = identifier
    return true
  }
}

private final class MacosNotificationsBridge: NSObject, UNUserNotificationCenterDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/notifications"
  private static let notificationURLKey = "url"

  private var channel: FlutterMethodChannel?
  private weak var messenger: FlutterBinaryMessenger?
  private let handoff = NotificationActivationHandoff()
  private let history = NotificationHistory()
  private var launchPair = NotificationLaunchPair()

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
    history.registerCategory()
  }

  func register(messenger: FlutterBinaryMessenger) {
    UNUserNotificationCenter.current().delegate = self
    guard self.messenger !== messenger else { return }
    history.collect(account: nil) { _ in }
    self.messenger = messenger
    self.channel?.setMethodCallHandler(nil)
    handoff.replaceMessenger()
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    self.channel = channel
    handoff.deliver = { [weak channel] url, token, reply in
      guard let channel else { reply(false); return }
      var arguments = [Self.notificationURLKey: url]
      arguments["consumer"] = token
      channel.invokeMethod("deadlineNotificationTapped", arguments: arguments) { result in
        let accepted = result as? Bool == true
        DispatchQueue.main.async { reply(accepted) }
      }
    }
    channel.setMethodCallHandler { [weak self, weak channel] call, result in
      guard let self, let channel, self.channel === channel else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error {
            let nativeError = error as NSError
            NSLog("MoreBetterGakujo: notification authorization failed (%@ %ld): %@", nativeError.domain, nativeError.code, nativeError.localizedDescription)
          }
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "checkPermission":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            switch settings.authorizationStatus {
            case .authorized, .provisional:
              result(true)
            case .denied:
              result(false)
            case .notDetermined:
              result(nil)
            @unknown default:
              result(nil)
            }
          }
        }
      case "openNotificationSettings":
        for target in [
          "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
          "x-apple.systempreferences:com.apple.preference.notifications",
        ] {
          if let url = URL(string: target), NSWorkspace.shared.open(url) {
            result(true)
            return
          }
        }
        result(false)
      case "loadNotificationHistory":
        let args = call.arguments as? [String: Any]
        self.history.collect(account: args?["account"] as? String) { collected in
          switch collected {
          case .success(let entries): result(entries)
          case .failure: result(FlutterError(code: "notification_history_failed", message: nil, details: nil))
          }
        }
      case "clearNotificationHistory":
        do {
          try self.history.clear()
          result(nil)
        } catch {
          result(FlutterError(code: "notification_history_failed", message: nil, details: nil))
        }
      case "notifyDeadline":
        let args = call.arguments as? [String: Any]
        let content = UNMutableNotificationContent()
        content.title = args?["title"] as? String ?? "課題期限"
        content.body = args?["body"] as? String ?? "提出期限を検出しました"
        content.sound = .default
        if let url = args?[Self.notificationURLKey] as? String, !url.isEmpty {
          content.userInfo = [Self.notificationURLKey: url]
        }
        self.history.tag(content, arguments: args)
        let request = UNNotificationRequest(
          identifier: "deadline-\(Date().timeIntervalSince1970)",
          content: content,
          trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
          DispatchQueue.main.async {
            if let error {
              result(FlutterError(code: "notification_failed", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
      case "scheduleReminders":
        // Replaces every booked reminder. The system keeps at most 64
        // pending requests, so only the earliest ones are booked.
        let args = call.arguments as? [String: Any]
        let items = args?["reminders"] as? [[String: Any]] ?? []
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
          let booked = requests.map(\.identifier).filter { $0.hasPrefix("reminder-") }
          center.removePendingNotificationRequests(withIdentifiers: booked)
          let now = Date()
          for item in items.prefix(60) {
            guard let id = (item["id"] as? NSNumber)?.intValue,
                  let atMillis = (item["atMillis"] as? NSNumber)?.doubleValue else {
              continue
            }
            let interval = Date(timeIntervalSince1970: atMillis / 1000).timeIntervalSince(now)
            if interval < 1 {
              continue
            }
            let content = UNMutableNotificationContent()
            content.title = item["title"] as? String ?? "課題の締切"
            content.body = item["body"] as? String ?? ""
            content.sound = .default
            if let url = item[Self.notificationURLKey] as? String, !url.isEmpty {
              content.userInfo = [Self.notificationURLKey: url]
            }
            self.history.tag(content, arguments: item)
            center.add(
              UNNotificationRequest(
                identifier: "reminder-\(id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
              )
            )
          }
          DispatchQueue.main.async {
            result(true)
          }
        }
      case "cancelOtherAccountsReminders":
        let args = call.arguments as? [String: Any]
        self.history.cancelOtherAccountsReminders(account: args?["account"] as? String) {
          result(nil)
        }
      case "takePendingNotificationUrl":
        if let args = call.arguments as? [String: Any], args["version"] as? Int == 1,
           let token = args["consumer"] as? String {
          let url = self.handoff.take(token)
          result(["version": 1, "consumer": token, "url": url as Any])
        } else {
          result(self.handoff.takeLegacy())
        }
      case "finishPendingNotification":
        if let args = call.arguments as? [String: Any], let token = args["consumer"] as? String {
          self.handoff.finish(token, accepted: args["accepted"] as? Bool == true)
        }
        result(nil)
      case "endNotificationConsumer":
        if let args = call.arguments as? [String: Any], let token = args["consumer"] as? String {
          self.handoff.end(token)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    DispatchQueue.main.async {
      self.history.observe(notification)
      if #available(macOS 11.0, *) {
        completionHandler([.banner, .list, .sound, .badge])
      } else {
        completionHandler([.alert, .sound, .badge])
      }
    }
  }

  func rememberLaunchResponse(_ response: UNNotificationResponse) {
    history.observe(response.notification)
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    guard let url = Self.url(of: response),
          launchPair.acceptLaunch(response.notification.request.identifier) else { return }
    NSLog("MoreBetterGakujo: app launched from a notification")
    handoff.receive(url)
  }

  private static func url(of response: UNNotificationResponse) -> String? {
    guard let url = response.notification.request.content.userInfo[notificationURLKey] as? String,
          !url.isEmpty else {
      return nil
    }
    return url
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    DispatchQueue.main.async {
      defer { completionHandler() }
      self.history.observe(response.notification)
      guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
      guard let url = Self.url(of: response),
            self.launchPair.acceptTap(response.notification.request.identifier) else { return }
      NSApp.activate(ignoringOtherApps: true)
      self.handoff.receive(url)
    }
  }
}

private final class MacosDownloadsBridge: NSObject {
  private static let channelName = "net.yoshida.morebettergakujo/downloads"
  private static let bookmarkKey = "more_better_gakujo_download_root_bookmark"

  private var pendingPickResult: FlutterResult?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "bridge_unavailable",
          message: "保存先を準備できませんでした",
          details: nil
        ))
        return
      }

      switch call.method {
      case "getDownloadRoot":
        result(self.downloadRootState())
      case "pickDownloadRoot":
        self.pickDownloadRoot(result: result)
      case "clearDownloadRoot":
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        result(self.downloadRootState())
      case "saveDownloadedFileToConfiguredFolder":
        self.saveDownloadedFileToConfiguredFolder(call: call, result: result)
      case "openDownloadedFile":
        self.openDownloadedFile(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickDownloadRoot(result: @escaping FlutterResult) {
    if pendingPickResult != nil {
      result(FlutterError(
        code: "picker_active",
        message: "保存先選択がすでに開いています",
        details: nil
      ))
      return
    }

    pendingPickResult = result
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "保存先にする"

    panel.begin { [weak self] response in
      guard let self else { return }
      let pending = self.pendingPickResult
      self.pendingPickResult = nil

      guard response == .OK, let url = panel.url else {
        pending?(self.downloadRootState())
        return
      }

      do {
        let bookmark = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        pending?(self.downloadRootState())
      } catch {
        pending?(FlutterError(
          code: "bookmark_failed",
          message: "保存先フォルダを記憶できませんでした: \(error.localizedDescription)",
          details: nil
        ))
      }
    }
  }

  private func saveDownloadedFileToConfiguredFolder(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: "missing_arguments",
        message: "ダウンロード情報を取得できませんでした",
        details: nil
      ))
      return
    }
    guard let bytes = dataArgument(args["bytes"]) else {
      result(FlutterError(
        code: "missing_bytes",
        message: "保存するファイルを取得できませんでした",
        details: nil
      ))
      return
    }

    let fileName = sanitizeDownloadName(args["fileName"] as? String)
    let courseName = sanitizeDownloadName(args["courseName"] as? String)
    let autoSortByCourse = args["autoSortByCourse"] as? Bool ?? true

    do {
      let root = try resolveDownloadRoot()
      let accessed = root.startAccessingSecurityScopedResource()
      defer {
        if accessed {
          root.stopAccessingSecurityScopedResource()
        }
      }

      let parent = autoSortByCourse
        ? root.appendingPathComponent(courseName.isEmpty ? "未分類" : courseName, isDirectory: true)
        : root
      try FileManager.default.createDirectory(
        at: parent,
        withIntermediateDirectories: true
      )

      let desiredName = fileName.isEmpty ? "document" : fileName
      let finalName = uniqueFileName(in: parent, desiredName: desiredName)
      let destination = parent.appendingPathComponent(finalName, isDirectory: false)
      guard isDownloadPathWithinRoot(destination, of: root) else {
        throw MacosDownloadError.invalidDestination
      }
      try bytes.write(to: destination, options: .withoutOverwriting)
      let existing = findIdenticalDownload(in: parent, desiredName: desiredName, newFile: destination)
      if existing != nil {
        try FileManager.default.removeItem(at: destination)
      }
      let savedFile = existing ?? destination
      result([
        "fileName": savedFile.lastPathComponent,
        "courseName": autoSortByCourse ? parent.lastPathComponent : "",
        "location": savedFile.path,
        "alreadySaved": existing != nil
      ])
    } catch {
      result(FlutterError(
        code: "download_failed",
        message: "保存できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func downloadRootState() -> [String: Any?] {
    guard let root = try? resolveDownloadRoot() else {
      return [
        "isConfigured": false,
        "displayName": nil,
        "path": nil
      ]
    }
    return [
      "isConfigured": true,
      "displayName": root.lastPathComponent,
      "path": root.path
    ]
  }

  private func resolveDownloadRoot() throws -> URL {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
      throw MacosDownloadError.missingRoot
    }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: bookmark,
      options: .withSecurityScope,
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }

    // A stale bookmark can only be recreated while its resource is accessed.
    if isStale, accessed,
       let refreshed = try? url.bookmarkData(
         options: .withSecurityScope,
         includingResourceValuesForKeys: nil,
         relativeTo: nil
       ) {
      UserDefaults.standard.set(refreshed, forKey: Self.bookmarkKey)
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw MacosDownloadError.missingRoot
    }
    return url
  }

  private func uniqueFileName(in directory: URL, desiredName: String) -> String {
    let existing = Set(
      (try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
      ).map { $0.lastPathComponent.lowercased() }) ?? []
    )
    return uniqueDownloadFileName(desiredName: desiredName, existingLowercaseNames: existing)
  }

  private func dataArgument(_ value: Any?) -> Data? {
    if let typed = value as? FlutterStandardTypedData {
      return typed.data
    }
    return value as? Data
  }

  private func openDownloadedFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    guard let location = args?["location"] as? String,
          let url = URL(string: location),
          url.isFileURL else {
      result(false)
      return
    }
    var scope: URL?
    if let root = try? resolveDownloadRoot(), isDownloadPathWithinRoot(url, of: root),
       root.startAccessingSecurityScopedResource() {
      scope = root
    }
    defer {
      scope?.stopAccessingSecurityScopedResource()
    }
    guard FileManager.default.fileExists(atPath: url.path),
          FileManager.default.isReadableFile(atPath: url.path) else {
      result(false)
      return
    }
    result(NSWorkspace.shared.open(url))
  }

}

private enum MacosDownloadError: LocalizedError {
  case missingRoot
  case invalidDestination

  var errorDescription: String? {
    switch self {
    case .missingRoot:
      return "ダウンロード保存先が未設定です"
    case .invalidDestination:
      return "保存先フォルダの外には保存できません"
    }
  }
}
