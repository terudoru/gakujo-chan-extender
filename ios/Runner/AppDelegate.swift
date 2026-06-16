import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let downloadsBridge = IosDownloadsBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    downloadsBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

private final class IosDownloadsBridge: NSObject, UIDocumentPickerDelegate {
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickDownloadRoot(result: @escaping FlutterResult) {
    if pendingPickResult != nil {
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

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
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
    guard let result = pendingPickResult else {
      return
    }
    pendingPickResult = nil
    result(downloadRootState())
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

      let requestedFileName = sanitizeName(args["fileName"] as? String)
      let fileName = requestedFileName.isEmpty ? "document" : requestedFileName
      let courseName = sanitizeName(args["courseName"] as? String)
      let autoSortByCourse = args["autoSortByCourse"] as? Bool ?? true
      let parent = try parentDirectory(
        root: root,
        courseName: courseName,
        autoSortByCourse: autoSortByCourse
      )
      let finalName = try uniqueFileName(in: parent, desiredName: fileName)
      let destination = parent.appendingPathComponent(finalName)
      try typedData.data.write(to: destination, options: .atomic)
      result([
        "fileName": finalName,
        "courseName": autoSortByCourse ? parent.lastPathComponent : ""
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
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func uniqueFileName(in directory: URL, desiredName: String) throws -> String {
    let existing = try FileManager.default.contentsOfDirectory(
      atPath: directory.path
    )
    if !existing.contains(desiredName) {
      return desiredName
    }

    let name = desiredName as NSString
    let base = name.deletingPathExtension
    let ext = name.pathExtension
    var index = 1
    while true {
      let candidate = ext.isEmpty
        ? "\(base) (\(index))"
        : "\(base) (\(index)).\(ext)"
      if !existing.contains(candidate) {
        return candidate
      }
      index += 1
    }
  }

  private func sanitizeName(_ raw: String?) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
      .union(.controlCharacters)
    return raw
      .orEmpty
      .components(separatedBy: invalid)
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum DownloadFolderError: LocalizedError {
  case missingRoot

  var errorDescription: String? {
    switch self {
    case .missingRoot:
      return "ダウンロード保存先が未設定です"
    }
  }
}

private extension Optional where Wrapped == String {
  var orEmpty: String {
    self ?? ""
  }
}
