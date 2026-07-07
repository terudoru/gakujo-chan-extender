import Cocoa
import EventKit
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  private let downloadsBridge = MacosDownloadsBridge()
  private let notificationsBridge = MacosNotificationsBridge()
  private let calendarBridge = MacosCalendarBridge()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      downloadsBridge.register(messenger: controller.engine.binaryMessenger)
      notificationsBridge.register(messenger: controller.engine.binaryMessenger)
      calendarBridge.register(messenger: controller.engine.binaryMessenger)
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

private final class MacosCalendarBridge {
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
    if #available(macOS 14.0, *) {
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
      // Refresh the store so the query below sees events committed by a
      // previous sync. EKEventStore can otherwise return a stale snapshot and
      // miss them, leaving the old events in place and accumulating duplicates
      // on repeated syncs. Done before fetching the calendar so the calendar
      // reference stays valid.
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
      // See syncEvents: refresh so the delete query sees the latest committed
      // events instead of a stale snapshot.
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
      throw MacosCalendarBridgeError.missingWritableCalendar
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
    let calendar = Calendar(identifier: .gregorian)
    let queryEnd = calendar.date(
      byAdding: .day,
      value: 1,
      to: calendar.startOfDay(for: end)
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

private enum MacosCalendarBridgeError: LocalizedError {
  case missingWritableCalendar

  var errorDescription: String? {
    switch self {
    case .missingWritableCalendar:
      return "書き込み可能なカレンダーが見つかりません"
    }
  }
}

private final class MacosNotificationsBridge: NSObject, UNUserNotificationCenterDelegate {
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
      guard isDescendant(destination, of: root) else {
        throw MacosDownloadError.invalidDestination
      }
      try bytes.write(to: destination, options: .atomic)
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

    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
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
    let trimmingCharacters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "."))
    let cleaned = value?
      .components(separatedBy: forbidden)
      .joined()
      .replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: trimmingCharacters)
      ?? ""
    return cleaned == "." || cleaned == ".." ? "" : cleaned
  }

  private func isDescendant(_ url: URL, of root: URL) -> Bool {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    return path == rootPath || path.hasPrefix(rootPath + "/")
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
