import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let downloadsBridge = MacosDownloadsBridge()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      downloadsBridge.register(messenger: controller.engine.binaryMessenger)
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

    let fileName = sanitizedName(args["fileName"] as? String)
    let courseName = sanitizedName(args["courseName"] as? String)
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

      let finalName = uniqueFileName(in: parent, desiredName: fileName.isEmpty ? "document" : fileName)
      let destination = parent.appendingPathComponent(finalName, isDirectory: false)
      try bytes.write(to: destination, options: .atomic)
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

    if isStale {
      let refreshed = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
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
      ).map(\.lastPathComponent)) ?? []
    )
    if !existing.contains(desiredName) {
      return desiredName
    }

    let nsName = desiredName as NSString
    let ext = nsName.pathExtension
    let base = ext.isEmpty ? desiredName : nsName.deletingPathExtension
    var index = 1
    while true {
      let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
      if !existing.contains(candidate) {
        return candidate
      }
      index += 1
    }
  }

  private func dataArgument(_ value: Any?) -> Data? {
    if let typed = value as? FlutterStandardTypedData {
      return typed.data
    }
    return value as? Data
  }

  private func sanitizedName(_ value: String?) -> String {
    let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
      .union(.controlCharacters)
    return value?
      .components(separatedBy: forbidden)
      .joined()
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
  }
}

private enum MacosDownloadError: LocalizedError {
  case missingRoot

  var errorDescription: String? {
    switch self {
    case .missingRoot:
      return "ダウンロード保存先が未設定です"
    }
  }
}
