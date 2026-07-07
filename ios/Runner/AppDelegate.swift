import Flutter
import EventKit
import UIKit
import UserNotifications
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let downloadsBridge = IosDownloadsBridge()
  private let notificationsBridge = IosNotificationsBridge()
  private let calendarBridge = AppleCalendarBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    downloadsBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    notificationsBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    calendarBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

private final class AppleCalendarBridge {
  private static let channelName = "net.yoshida.morebettergakujo/calendar"
  private static let calendarIdentifierKey = "more_better_gakujo_calendar_identifier"
  private static let marker = "MBG_UID:"

  private let eventStore = EKEventStore()

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "bridge_unavailable",
          message: "カレンダーを準備できませんでした",
          details: nil
        ))
        return
      }

      switch call.method {
      case "syncEvents":
        self.requestAccess { granted in
          guard granted else {
            result(FlutterError(
              code: "calendar_permission_denied",
              message: "カレンダーへの追加が許可されませんでした",
              details: nil
            ))
            return
          }
          self.syncEvents(call: call, result: result)
        }
      case "deleteAddedEvents":
        self.requestAccess { granted in
          guard granted else {
            result(FlutterError(
              code: "calendar_permission_denied",
              message: "カレンダーへのアクセスが許可されませんでした",
              details: nil
            ))
            return
          }
          self.deleteAddedEvents(call: call, result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestAccess(completion: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, macOS 14.0, *) {
      eventStore.requestFullAccessToEvents { granted, _ in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    } else {
      eventStore.requestAccess(to: .event) { granted, _ in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    }
  }

  private func syncEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: "missing_arguments",
        message: "カレンダー情報を取得できませんでした",
        details: nil
      ))
      return
    }

    do {
      // Refresh the store so queries below see events committed by a previous
      // sync. EKEventStore can otherwise keep a stale snapshot and miss them,
      // which leaves old app-created events in place on repeated syncs.
      eventStore.reset()
      let title = args["calendarTitle"] as? String ?? "More Better Gakujo 授業"
      let startMillis = (args["rangeStartMillis"] as? NSNumber)?.doubleValue ?? 0
      let endMillis = (args["rangeEndMillis"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
      let rangeStart = Date(timeIntervalSince1970: startMillis / 1000)
      let rangeEnd = Date(timeIntervalSince1970: endMillis / 1000)
      let calendar = try writableCalendar(title: title)
      let removed = try removeExistingEvents(start: rangeStart, end: rangeEnd, calendars: [calendar])
      let events = args["events"] as? [[String: Any]] ?? []
      var added = 0
      for rawEvent in events {
        if try insertEvent(rawEvent, calendar: calendar) {
          added += 1
        }
      }
      if added > 0 {
        try eventStore.commit()
      }
      result([
        "added": added,
        "removed": removed,
        "openedFallback": false
      ])
    } catch {
      result(FlutterError(
        code: "calendar_sync_failed",
        message: "カレンダーに追加できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func deleteAddedEvents(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(
        code: "missing_arguments",
        message: "カレンダー情報を取得できませんでした",
        details: nil
      ))
      return
    }

    do {
      // See syncEvents: refresh before resolving calendars and querying
      // app-created events so deletion does not use a stale EventKit snapshot.
      eventStore.reset()
      let startMillis = (args["rangeStartMillis"] as? NSNumber)?.doubleValue ?? 0
      let endMillis = (args["rangeEndMillis"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
      let rangeStart = Date(timeIntervalSince1970: startMillis / 1000)
      let rangeEnd = Date(timeIntervalSince1970: endMillis / 1000)
      let calendarTitle = args["calendarTitle"] as? String
      let calendars: [EKCalendar]?
      if let calendarTitle, !calendarTitle.isEmpty {
        guard let calendar = existingCalendar(title: calendarTitle) else {
          result(["removed": 0])
          return
        }
        calendars = [calendar]
      } else {
        calendars = nil
      }
      let removed = try removeExistingEvents(start: rangeStart, end: rangeEnd, calendars: calendars)
      result(["removed": removed])
    } catch {
      result(FlutterError(
        code: "calendar_delete_failed",
        message: "カレンダー予定を削除できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func writableCalendar(title: String) throws -> EKCalendar {
    if let identifier = UserDefaults.standard.string(forKey: Self.calendarIdentifierKey),
       let calendar = eventStore.calendar(withIdentifier: identifier),
       calendar.title == title,
       calendar.allowsContentModifications {
      return calendar
    }

    if let existing = eventStore.calendars(for: .event).first(where: {
      $0.title == title && $0.allowsContentModifications
    }) {
      UserDefaults.standard.set(existing.calendarIdentifier, forKey: Self.calendarIdentifierKey)
      return existing
    }

    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.title = title
    calendar.source = eventStore.defaultCalendarForNewEvents?.source
      ?? eventStore.sources.first(where: { $0.sourceType == .local })
      ?? eventStore.sources.first
    guard calendar.source != nil else {
      if let fallback = eventStore.defaultCalendarForNewEvents,
         fallback.allowsContentModifications {
        return fallback
      }
      throw CalendarBridgeError.missingWritableCalendar
    }
    try eventStore.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarIdentifierKey)
    return calendar
  }

  private func existingCalendar(title: String) -> EKCalendar? {
    eventStore.calendars(for: .event).first {
      $0.title == title && $0.allowsContentModifications
    }
  }

  private func removeExistingEvents(start: Date, end: Date, calendars: [EKCalendar]? = nil) throws -> Int {
    let queryEnd = Calendar(identifier: .gregorian).date(
      byAdding: .day,
      value: 1,
      to: Calendar(identifier: .gregorian).startOfDay(for: end)
    ) ?? end
    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: queryEnd,
      calendars: calendars
    )
    let events = eventStore.events(matching: predicate).filter {
      $0.notes?.contains(Self.marker) == true
    }
    for event in events {
      try eventStore.remove(event, span: .thisEvent, commit: false)
    }
    if !events.isEmpty {
      try eventStore.commit()
    }
    return events.count
  }

  private func insertEvent(_ raw: [String: Any], calendar: EKCalendar) throws -> Bool {
    guard let title = stringValue(raw["title"]), !title.isEmpty,
          let startMillis = doubleValue(raw["startMillis"]),
          let endMillis = doubleValue(raw["endMillis"]) else {
      return false
    }

    let event = EKEvent(eventStore: eventStore)
    event.calendar = calendar
    event.title = title
    event.startDate = Date(timeIntervalSince1970: startMillis / 1000)
    event.endDate = Date(timeIntervalSince1970: endMillis / 1000)
    event.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    event.location = stringValue(raw["location"])
    var notes = ""
    if let displayNotes = stringValue(raw["notes"]) {
      notes = displayNotes
    } else if let teacher = stringValue(raw["teacher"]), !teacher.isEmpty {
      notes = "担当教員: \(teacher)"
    }
    if !notes.isEmpty {
      notes += "\n\n"
    }
    notes += "\(Self.marker)\(stringValue(raw["id"]) ?? "")"
    event.notes = notes
    try eventStore.save(event, span: .thisEvent, commit: false)
    return true
  }

  private func stringValue(_ raw: Any?) -> String? {
    if let value = raw as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let value = raw {
      let text = "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : text
    }
    return nil
  }

  private func doubleValue(_ raw: Any?) -> Double? {
    if let value = raw as? NSNumber {
      return value.doubleValue
    }
    if let value = raw as? Double {
      return value
    }
    if let value = raw as? Int {
      return Double(value)
    }
    if let value = raw as? Int64 {
      return Double(value)
    }
    if let value = raw as? String {
      return Double(value)
    }
    return nil
  }
}

private enum CalendarBridgeError: LocalizedError {
  case missingWritableCalendar

  var errorDescription: String? {
    switch self {
    case .missingWritableCalendar:
      return "書き込み可能なカレンダーが見つかりません"
    }
  }
}

private final class IosNotificationsBridge: NSObject, UNUserNotificationCenterDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/notifications"

  func register(messenger: FlutterBinaryMessenger) {
    UNUserNotificationCenter.current().delegate = self
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "notifyDeadline":
        let args = call.arguments as? [String: Any]
        let content = UNMutableNotificationContent()
        content.title = args?["title"] as? String ?? "課題期限"
        content.body = args?["body"] as? String ?? "提出期限を検出しました"
        content.sound = .default
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
    completionHandler([.alert, .sound, .badge])
  }
}

private final class IosDownloadsBridge: NSObject, UIDocumentPickerDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/downloads"
  private static let bookmarkKey = "more_better_gakujo_download_root_bookmark"

  private var pendingPickResult: FlutterResult?
  private var pendingExportResult: FlutterResult?
  private var pendingExportFileName: String?
  private var pendingExportURL: URL?

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
      let requestedFileName = sanitizeName(args["fileName"] as? String)
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
      let fileName = pendingExportFileName ?? pendingExportURL?.lastPathComponent ?? "document"
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
      guard isDescendant(destination, of: root) else {
        throw DownloadFolderError.invalidDestination
      }
      try typedData.data.write(to: destination, options: .atomic)
      result([
        "fileName": finalName,
        "courseName": autoSortByCourse ? parent.lastPathComponent : "",
        "location": destination.path
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
    let trimmingCharacters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "."))
    let cleaned = raw
      .orEmpty
      .components(separatedBy: invalid)
      .joined()
      .replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: trimmingCharacters)
    return cleaned == "." || cleaned == ".." ? "" : cleaned
  }

  private func isDescendant(_ url: URL, of root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    return path == rootPath || path.hasPrefix(rootPath + "/")
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

private extension Optional where Wrapped == String {
  var orEmpty: String {
    self ?? ""
  }
}
