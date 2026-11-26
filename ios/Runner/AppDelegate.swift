import Flutter
import QuickLook
import UIKit
import UniformTypeIdentifiers
import WebKit
import ObjectiveC.runtime

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let downloadsBridge = IosDownloadsBridge()
  private let notificationsBridge = AppleNotificationsBridge()
  private let calendarBridge = AppleCalendarBridge()
  private let driveFolderPicker = DriveFolderPicker()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    IosPdfPreviewOverlay.install()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    downloadsBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    IosIncomingAttachments.shared.register(messenger: engineBridge.applicationRegistrar.messenger())
    notificationsBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    calendarBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    driveFolderPicker.register(messenger: engineBridge.applicationRegistrar.messenger())
    FlutterMethodChannel(
      name: "net.yoshida.morebettergakujo/pdf_preview",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "setViewerURL":
        guard let url = call.arguments as? String,
              IosPdfPreviewOverlay.setViewerURL(url) else {
          result(FlutterError(code: "invalid_viewer", message: nil, details: nil))
          return
        }
      case "setPreviewState":
        guard let state = call.arguments as? String,
              ["visible", "hidden", "none"].contains(state) else {
          result(FlutterError(code: "invalid_visibility", message: nil, details: nil))
          return
        }
        if state != "none" {
          IosPdfPreviewOverlay.setVisible(state == "visible")
        }
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }
}

private final class IosDownloadsBridge: NSObject, UIDocumentPickerDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/downloads"
  private static let bookmarkKey = "more_better_gakujo_download_root_bookmark"

  private var pendingPickResult: FlutterResult?
  private var pendingExportResult: FlutterResult?
  private var pendingExportFileName: String?
  private var pendingExportURL: URL?
  private var openPreview: SavedFilePreview?

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
      case "exportDownloadedFile":
        self.exportDownloadedFile(call: call, result: result)
      case "openDownloadedFile":
        self.openDownloadedFile(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickDownloadRoot(result: @escaping FlutterResult) {
    if pendingPickResult != nil || pendingExportResult != nil {
      result(FlutterError(
        code: "picker_active",
        message: "フォルダ選択がすでに開いています",
        details: nil
      ))
      return
    }

    guard let presenter = topViewController() else {
      result(FlutterError(
        code: "missing_presenter",
        message: "保存先選択を表示できませんでした",
        details: nil
      ))
      return
    }

    pendingPickResult = result
    guard #available(iOS 14.0, *) else {
      pendingPickResult = nil
      result(FlutterError(
        code: "unsupported_ios_version",
        message: "フォルダ選択には iOS 14 以降が必要です",
        details: nil
      ))
      return
    }

    let picker = UIDocumentPickerViewController(
      forOpeningContentTypes: [UTType.folder],
      asCopy: false
    )
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  private func exportDownloadedFile(
    call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    if pendingExportResult != nil || pendingPickResult != nil {
      result(FlutterError(
        code: "picker_active",
        message: "保存先選択がすでに開いています",
        details: nil
      ))
      return
    }

    guard let presenter = topViewController() else {
      result(FlutterError(
        code: "missing_presenter",
        message: "保存先選択を表示できませんでした",
        details: nil
      ))
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typedData = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(
        code: "missing_arguments",
        message: "保存するファイルを取得できませんでした",
        details: nil
      ))
      return
    }

    do {
      let requestedFileName = sanitizeDownloadName(args["fileName"] as? String)
      let fileName = requestedFileName.isEmpty ? "document" : requestedFileName
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
      let exportURL = directory.appendingPathComponent(fileName)
      try typedData.data.write(to: exportURL, options: .atomic)

      pendingExportResult = result
      pendingExportFileName = fileName
      pendingExportURL = exportURL

      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(
          forExporting: [exportURL],
          asCopy: true
        )
      } else {
        picker = UIDocumentPickerViewController(
          url: exportURL,
          in: .exportToService
        )
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      presenter.present(picker, animated: true)
    } catch {
      result(FlutterError(
        code: "export_failed",
        message: "保存ファイルを準備できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    if let result = pendingExportResult {
      // The picker lets the student rename the file; report the saved name.
      let fileName = urls.first?.lastPathComponent ?? pendingExportFileName ??
        pendingExportURL?.lastPathComponent ?? "document"
      let pickedLocation = urls.first?.path
      clearPendingExport()
      result([
        "fileName": fileName,
        "courseName": "",
        "location": pickedLocation ?? ""
      ])
      return
    }

    guard let result = pendingPickResult else {
      return
    }
    pendingPickResult = nil

    guard let url = urls.first else {
      result(FlutterError(
        code: "missing_root_url",
        message: "保存先フォルダを取得できませんでした",
        details: nil
      ))
      return
    }

    do {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      let bookmark = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
      result(downloadRootState())
    } catch {
      result(FlutterError(
        code: "bookmark_failed",
        message: "保存先フォルダを記憶できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let result = pendingExportResult {
      clearPendingExport()
      result(FlutterError(
        code: "cancelled",
        message: "保存をキャンセルしました",
        details: nil
      ))
      return
    }

    guard let result = pendingPickResult else {
      return
    }
    pendingPickResult = nil
    result(downloadRootState())
  }

  private func clearPendingExport() {
    pendingExportResult = nil
    pendingExportFileName = nil
    if let url = pendingExportURL {
      let directory = url.deletingLastPathComponent()
      try? FileManager.default.removeItem(at: directory)
    }
    pendingExportURL = nil
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
    guard let typedData = args["bytes"] as? FlutterStandardTypedData else {
      result(FlutterError(
        code: "missing_bytes",
        message: "保存するファイルを取得できませんでした",
        details: nil
      ))
      return
    }

    do {
      let root = try resolveDownloadRoot()
      let didAccess = root.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          root.stopAccessingSecurityScopedResource()
        }
      }

      let requestedFileName = sanitizeDownloadName(args["fileName"] as? String)
      let fileName = requestedFileName.isEmpty ? "document" : requestedFileName
      let courseName = sanitizeDownloadName(args["courseName"] as? String)
      let autoSortByCourse = args["autoSortByCourse"] as? Bool ?? true
      let parent = try parentDirectory(
        root: root,
        courseName: courseName,
        autoSortByCourse: autoSortByCourse
      )
      let finalName = try uniqueFileName(in: parent, desiredName: fileName)
      let destination = parent.appendingPathComponent(finalName)
      guard isDownloadPathWithinRoot(destination, of: root) else {
        throw DownloadFolderError.invalidDestination
      }
      try typedData.data.write(to: destination, options: .withoutOverwriting)
      let existing = findIdenticalDownload(in: parent, desiredName: fileName, newFile: destination)
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
      return ["isConfigured": false]
    }
    let didAccess = root.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        root.stopAccessingSecurityScopedResource()
      }
    }
    let exists = FileManager.default.fileExists(atPath: root.path)
    return [
      "isConfigured": exists,
      "displayName": exists ? root.lastPathComponent : nil,
      "path": exists ? root.path : nil
    ]
  }

  private func resolveDownloadRoot() throws -> URL {
    guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
      throw DownloadFolderError.missingRoot
    }

    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmark,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    if stale {
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      let updated = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      UserDefaults.standard.set(updated, forKey: Self.bookmarkKey)
    }
    return url
  }

  private func parentDirectory(
    root: URL,
    courseName: String,
    autoSortByCourse: Bool
  ) throws -> URL {
    if !autoSortByCourse {
      return root
    }
    let folderName = courseName.isEmpty ? "未分類" : courseName
    let directory = root.appendingPathComponent(folderName, isDirectory: true)
    if isDirectory(directory) {
      return directory
    }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(
      atPath: url.path,
      isDirectory: &isDirectory
    ) && isDirectory.boolValue
  }

  private func uniqueFileName(in directory: URL, desiredName: String) throws -> String {
    let existing = try FileManager.default.contentsOfDirectory(
      atPath: directory.path
    ).map { $0.lowercased() }
    return uniqueDownloadFileName(desiredName: desiredName, existingLowercaseNames: Set(existing))
  }

  /// Shows a saved file in Quick Look; iOS opens no file URL from another
  /// app. A file in the chosen folder is read while the folder's access is
  /// held, until the preview closes.
  private func openDownloadedFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    guard let location = args?["location"] as? String,
          let url = URL(string: location),
          url.isFileURL,
          let presenter = topViewController() else {
      result(false)
      return
    }
    var scope: URL?
    if let root = try? resolveDownloadRoot(), isDownloadPathWithinRoot(url, of: root),
       root.startAccessingSecurityScopedResource() {
      scope = root
    }
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      scope?.stopAccessingSecurityScopedResource()
      result(false)
      return
    }
    let preview = SavedFilePreview(url: url, scope: scope) { [weak self] in
      self?.openPreview = nil
    }
    openPreview = preview
    let controller = QLPreviewController()
    controller.dataSource = preview
    controller.delegate = preview
    presenter.present(controller, animated: true)
    result(true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let root = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let navigation = root as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    return root
  }
}

private final class SavedFilePreview: NSObject, QLPreviewControllerDataSource,
  QLPreviewControllerDelegate {
  private let url: URL
  private var scope: URL?
  private let onClose: () -> Void

  init(url: URL, scope: URL?, onClose: @escaping () -> Void) {
    self.url = url
    self.scope = scope
    self.onClose = onClose
  }

  deinit {
    scope?.stopAccessingSecurityScopedResource()
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    1
  }

  func previewController(
    _ controller: QLPreviewController,
    previewItemAt index: Int
  ) -> QLPreviewItem {
    url as NSURL
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    scope?.stopAccessingSecurityScopedResource()
    scope = nil
    onClose()
  }
}

private enum DownloadFolderError: LocalizedError {
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

/// Hosts the capability-protected PDF viewer over its opener WebView.
/// A separate WebView avoids WebKit's mixed-content block on HTTP iframes.
private final class IosPdfPreviewOverlay: NSObject, WKUIDelegate, WKNavigationDelegate {
  private typealias CreateView = @convention(c) (
    AnyObject, Selector, WKWebView, WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures
  ) -> Unmanaged<AnyObject>?
  private static let selector = NSSelectorFromString(
    "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:"
  )
  private typealias UIDelegateSetter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
  private static var installed = false
  private static var installedClasses = Set<ObjectIdentifier>()
  private static var allowedURL: URL?
  private static var overlays: [IosPdfPreviewOverlay] = []
  private weak var opener: WKWebView?
  private weak var viewer: WKWebView?
  private let url: URL

  private init(url: URL) { self.url = url }

  static func setViewerURL(_ value: String) -> Bool {
    guard let parts = URLComponents(string: value), parts.scheme == "http",
          parts.host == "127.0.0.1", let port = parts.port, (1...65535).contains(port),
          parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
      return false
    }
    let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
    guard path.count == 2, path[1] == "index.html", path[0].count == 43,
          path[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
          parts.path == "/\(path[0])/index.html", let url = parts.url else { return false }
    allowedURL = url
    return true
  }

  static func install() {
    guard !installed else { return }
    installed = true
    let setter = #selector(setter: WKWebView.uiDelegate)
    guard let method = class_getInstanceMethod(WKWebView.self, setter) else { return }
    let original = unsafeBitCast(method_getImplementation(method), to: UIDelegateSetter.self)
    let block: @convention(block) (AnyObject, AnyObject?) -> Void = { webView, delegate in
      if let delegate, !(delegate is IosPdfPreviewOverlay),
         let delegateClass = object_getClass(delegate) {
        // Unlike macOS, iOS defaults this to false. The viewer opens after async work,
        // so window.open returns nil and no viewer appears unless this is enabled.
        (webView as? WKWebView)?.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        install(on: delegateClass)
      }
      original(webView, setter, delegate)
    }
    method_setImplementation(
      method, imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
    )
  }

  private static func install(on delegateClass: AnyClass) {
    let identity = ObjectIdentifier(delegateClass)
    guard !installedClasses.contains(identity),
          let template = class_getInstanceMethod(IosPdfPreviewOverlay.self, selector) else { return }
    let method = class_getInstanceMethod(delegateClass, selector)
    let original: CreateView? = method.map {
      unsafeBitCast(method_getImplementation($0), to: CreateView.self)
    }
    installedClasses.insert(identity)
    let block: @convention(block) (
      AnyObject, WKWebView, WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures
    ) -> WKWebView? = { delegate, opener, configuration, action, features in
      let origin = action.sourceFrame.securityOrigin
      if let allowed = allowedURL, action.request.url == allowed,
         origin.protocol == "https", origin.host == "gakujo.iess.niigata-u.ac.jp" {
        return open(url: allowed, configuration: configuration, opener: opener)
      }
      return original?(delegate, selector, opener, configuration, action, features)?
        .takeUnretainedValue() as? WKWebView
    }
    let implementation = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
    if !class_addMethod(delegateClass, selector, implementation, method_getTypeEncoding(method ?? template)),
       let method = method {
      method_setImplementation(method, implementation)
    }
  }

  static func setVisible(_ visible: Bool) {
    for owner in overlays {
      owner.viewer?.isHidden = !visible
    }
  }

  static func opener(for viewer: WKWebView) -> WKWebView? {
    overlays.first { $0.viewer === viewer }?.opener
  }

  private static func open(url: URL, configuration: WKWebViewConfiguration, opener: WKWebView) -> WKWebView {
    let owner = IosPdfPreviewOverlay(url: url)
    // Do not expose the main page's native script-message channels to a PDF
    // viewer. WebKit still uses the supplied configuration for opener links.
    configuration.userContentController = WKUserContentController()
    let webView = WKWebView(frame: opener.bounds, configuration: configuration)
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    webView.allowsLinkPreview = false
    owner.opener = opener
    owner.viewer = webView
    webView.uiDelegate = owner
    webView.navigationDelegate = owner
    overlays.append(owner)
    opener.addSubview(webView)
    return webView
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    decisionHandler(navigationAction.request.url == url ? .allow : .cancel)
  }

  // Provides the Objective-C method signature when a delegate has no implementation.
  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for navigationAction: WKNavigationAction,
               windowFeatures: WKWindowFeatures) -> WKWebView? {
    nil
  }

  func webViewDidClose(_ webView: WKWebView) {
    webView.removeFromSuperview()
    Self.overlays.removeAll { $0 === self }
  }
}
