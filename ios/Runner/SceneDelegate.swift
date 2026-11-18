import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    IosIncomingAttachments.shared.prune()
    receiveDocuments(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let otherContexts = Set(URLContexts.filter { !$0.url.isFileURL })
    if !otherContexts.isEmpty {
      super.scene(scene, openURLContexts: otherContexts)
    }
    receiveDocuments(URLContexts)
  }

  private func receiveDocuments(_ contexts: Set<UIOpenURLContext>) {
    let documents = contexts.filter { $0.url.isFileURL }
    guard documents.count == 1, let document = documents.first else { return }
    IosIncomingAttachments.shared.receive(
      document.url, removeInboxCopy: !document.options.openInPlace
    )
  }
}

final class IosIncomingAttachments {
  static let shared = IosIncomingAttachments()

  private static let maximumBytes = 64 * 1024 * 1024
  private static let cacheLifetime: TimeInterval = 24 * 60 * 60
  private static let mimeTypes = [
    "pdf": "application/pdf",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
    "gif": "image/gif",
    "heic": "image/heic",
    "heif": "image/heif",
    "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xls": "application/vnd.ms-excel",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "ppt": "application/vnd.ms-powerpoint",
    "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ]

  private enum ImportError: Error {
    case unavailable
    case tooLarge
  }

  private let worker = DispatchQueue(label: "net.yoshida.morebettergakujo.incoming-attachment")
  private var revision = 0
  private var channel: FlutterMethodChannel?
  private var pending: [String: String]?

  private init() {}

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "net.yoshida.morebettergakujo/incoming_attachment",
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "takePendingAttachment":
        let attachment = self?.pending
        self?.pending = nil
        result(attachment)
      case "discardAttachment":
        if let id = call.arguments as? String, UUID(uuidString: id) != nil {
          self?.worker.async {
            guard let root = try? Self.cacheDirectory() else { return }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(id))
          }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func receive(_ url: URL, removeInboxCopy: Bool) {
    revision += 1
    let request = revision
    let hasScope = url.startAccessingSecurityScopedResource()
    worker.async { [weak self] in
      defer {
        if hasScope { url.stopAccessingSecurityScopedResource() }
      }
      let attachment = Self.importDocument(url, removeInboxCopy: removeInboxCopy)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.revision == request else {
          Self.removeUnclaimed(attachment)
          return
        }
        Self.removeUnclaimed(self.pending)
        self.pending = attachment
        self.channel?.invokeMethod("attachmentAvailable", arguments: nil)
      }
    }
  }

  func prune() {
    worker.async {
      let manager = FileManager.default
      guard let folder = try? Self.cacheDirectory(),
            let entries = try? manager.contentsOfDirectory(
              at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
      let cutoff = Date().addingTimeInterval(-Self.cacheLifetime)
      for entry in entries {
        guard UUID(uuidString: entry.lastPathComponent) != nil,
              let modified = try? entry.resourceValues(
                forKeys: [.contentModificationDateKey]
              ).contentModificationDate,
              modified < cutoff else { continue }
        try? manager.removeItem(at: entry)
      }
    }
  }

  private static func importDocument(
    _ originalURL: URL, removeInboxCopy: Bool
  ) -> [String: String] {
    var coordinatorError: NSError?
    var data = ["error": "unavailable"]
    NSFileCoordinator().coordinate(readingItemAt: originalURL, options: .withoutChanges,
                                  error: &coordinatorError) { readableURL in
      do {
        data = try copy(readableURL)
      } catch ImportError.tooLarge {
        data = ["error": "too_large"]
      } catch {
        // Keep provider paths and provider exception text out of app reports.
      }
    }
    if removeInboxCopy { deleteInboxCopy(originalURL) }
    if coordinatorError != nil {
      removeUnclaimed(data)
      return ["error": "unavailable"]
    }
    return data
  }

  private static func copy(_ source: URL) throws -> [String: String] {
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true else { throw ImportError.unavailable }
    if let size = values.fileSize, size > maximumBytes { throw ImportError.tooLarge }

    let suffix = source.pathExtension
    guard let mime = mimeTypes[suffix.lowercased()] else { throw ImportError.unavailable }
    let name = source.deletingPathExtension().lastPathComponent.replacingOccurrences(
      of: #"[\x00-\x1f\x7f<>:"/\\|?*]"#, with: "_", options: .regularExpression
    )
    let stem = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
      .prefix(48).map { String($0) }.joined()
    let fileName = (stem.isEmpty ? "添付ファイル" : stem) + "." + suffix
    let directory = try cacheDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
    let target = directory.appendingPathComponent(fileName)
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    var copied = false
    defer {
      if !copied { try? manager.removeItem(at: directory) }
    }
    guard manager.createFile(atPath: target.path, contents: nil) else {
      throw ImportError.unavailable
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: target)
    defer { try? output.close() }
    var total = 0
    while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
      total += chunk.count
      guard total <= maximumBytes else { throw ImportError.tooLarge }
      try output.write(contentsOf: chunk)
    }
    guard total > 0 else { throw ImportError.unavailable }
    copied = true
    return ["path": target.path, "name": fileName, "mimeType": mime]
  }

  private static func cacheDirectory() throws -> URL {
    guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { throw ImportError.unavailable }
    return caches.appendingPathComponent("mbg-incoming-attachments", isDirectory: true)
  }

  private static func deleteInboxCopy(_ url: URL) {
    let manager = FileManager.default
    guard let documents = manager.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    let inbox = documents.appendingPathComponent("Inbox", isDirectory: true)
    let original = url.standardizedFileURL
    guard original.deletingLastPathComponent().resolvingSymlinksInPath() ==
      inbox.resolvingSymlinksInPath(),
      (try? original.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else { return }
    try? manager.removeItem(at: original)
  }

  private static func removeUnclaimed(_ data: [String: String]?) {
    guard let path = data?["path"] else { return }
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    try? FileManager.default.removeItem(at: directory)
  }
}
