import Cocoa
import EventKit
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  private let downloadsBridge = MacosDownloadsBridge()
  private let notificationsBridge = MacosNotificationsBridge()
  private let calendarBridge = MacosCalendarBridge()
  private let inputFocusBridge = MacosInputFocusBridge()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      downloadsBridge.register(messenger: controller.engine.binaryMessenger)
      notificationsBridge.register(messenger: controller.engine.binaryMessenger)
      calendarBridge.register(messenger: controller.engine.binaryMessenger)
      inputFocusBridge.register(
        controller: controller,
        messenger: controller.engine.binaryMessenger
      )
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

private final class MacosCalendarBridge {
  private static let channelName = "net.yoshida.morebettergakujo/calendar"
  private static let calendarIdentifierKey = "more_better_gakujo_calendar_identifier"
  private static let validationCalendarIdentifierKey = "more_better_gakujo_validation_calendar_identifier"
  private static let calendarManagedKey = "more_better_gakujo_calendar_managed_by_app"
  private static let validationCalendarManagedKey = "more_better_gakujo_validation_calendar_managed_by_app"
  private static let pendingCalendarCleanupKey = "more_better_gakujo_pending_calendar_cleanup_identifiers"
  private static let validationPendingCalendarCleanupKey = "more_better_gakujo_validation_pending_calendar_cleanup_identifiers"
  private static let syncedCalendarRangesKey = "more_better_gakujo_synced_calendar_ranges"
  private static let validationCalendarTitle = "More Better Gakujo 検証"
  private static let validationUidNamespace = "calendar-validation"
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
    guard let events = args["events"] as? [[String: Any]], !events.isEmpty else {
      result(FlutterError(
        code: "calendar_empty_events",
        message: "追加対象のカレンダー予定がありません",
        details: nil
      ))
      return
    }

    do {
      let uidNamespace = try eventNamespace(from: events)
      if let requestedNamespace = stringValue(args["uidNamespace"]),
         requestedNamespace != uidNamespace {
        throw MacosCalendarBridgeError.invalidEvent
      }
      // Refresh the store so the query below sees events committed by a
      // previous sync. EKEventStore can otherwise return a stale snapshot and
      // miss them, leaving the old events in place and accumulating duplicates
      // on repeated syncs. Done before fetching the calendar so the calendar
      // reference stays valid.
      eventStore.reset()
      let title = args["calendarTitle"] as? String ?? "More Better Gakujo 授業"
      guard (title == Self.validationCalendarTitle)
        == (uidNamespace == Self.validationUidNamespace) else {
        throw MacosCalendarBridgeError.invalidEvent
      }
      let startMillis = (args["rangeStartMillis"] as? NSNumber)?.doubleValue ?? 0
      let endMillis = (args["rangeEndMillis"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
      let rangeStart = Date(timeIntervalSince1970: startMillis / 1000)
      let rangeEnd = Date(timeIntervalSince1970: endMillis / 1000)
      guard rangeEnd > rangeStart else {
        throw MacosCalendarBridgeError.invalidRange
      }
      let calendar = try writableCalendar(title: title)
      let calendarsToClean = uniqueCalendars(
        [calendar] + pendingCleanupCalendars(title: title)
      )
      let cleanupRange = cleanupRange(
        calendars: calendarsToClean,
        uidNamespace: uidNamespace,
        currentStart: rangeStart,
        currentEnd: rangeEnd
      )
      let removed = try removeExistingEvents(
        start: cleanupRange.start,
        end: cleanupRange.end,
        calendars: calendarsToClean,
        uidNamespace: uidNamespace,
        commitChanges: false
      )
      var added = 0
      for rawEvent in events {
        let inserted = try insertEvent(rawEvent, calendar: calendar)
        guard inserted else {
          throw MacosCalendarBridgeError.invalidEvent
        }
        added += 1
      }
      try eventStore.commit()
      clearPendingCleanupCalendars(title: title)
      rememberSyncedRange(
        calendar: calendar,
        uidNamespace: uidNamespace,
        start: rangeStart,
        end: rangeEnd
      )
      result([
        "added": added,
        "removed": removed,
        "openedFallback": false
      ])
    } catch {
      eventStore.reset()
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
        let resolved = existingCalendar(title: calendarTitle)
        let candidates = uniqueCalendars(
          [resolved].compactMap { $0 }
            + pendingCleanupCalendars(title: calendarTitle)
        )
        guard !candidates.isEmpty else {
          result(["removed": 0])
          return
        }
        calendars = candidates
      } else {
        calendars = nil
      }
      let uidNamespace = calendarTitle == Self.validationCalendarTitle
        ? Self.validationUidNamespace
        : nil
      let removed = try removeExistingEvents(
        start: rangeStart,
        end: rangeEnd,
        calendars: calendars,
        uidNamespace: uidNamespace
      )
      if let calendarTitle, !calendarTitle.isEmpty {
        clearPendingCleanupCalendars(title: calendarTitle)
      }
      result(["removed": removed])
    } catch {
      eventStore.reset()
      result(FlutterError(
        code: "calendar_delete_failed",
        message: "カレンダー予定を削除できませんでした: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func writableCalendar(title: String) throws -> EKCalendar {
    if let calendar = storedCalendar(title: title) {
      if calendar.title == title {
        return calendar
      }
      if isManagedCalendar(calendar, title: title) {
        calendar.title = title
        try eventStore.saveCalendar(calendar, commit: true)
        return calendar
      }
      queueCalendarForCleanup(calendar, title: title)
      forgetStoredCalendar(title: title)
    }

    if let existing = eventStore.calendars(for: .event).first(where: {
      $0.title == title && $0.allowsContentModifications
    }) {
      rememberCalendar(existing, title: title, managedByApp: false)
      return existing
    }

    let calendar = EKCalendar(for: .event, eventStore: eventStore)
    calendar.title = title
    calendar.source = eventStore.defaultCalendarForNewEvents?.source
      ?? eventStore.sources.first(where: { $0.sourceType == .local })
      ?? eventStore.sources.first
    guard calendar.source != nil else {
      throw MacosCalendarBridgeError.missingWritableCalendar
    }
    try eventStore.saveCalendar(calendar, commit: true)
    rememberCalendar(calendar, title: title, managedByApp: true)
    return calendar
  }

  private func existingCalendar(title: String) -> EKCalendar? {
    if let calendar = storedCalendar(title: title) {
      if calendar.title == title || isManagedCalendar(calendar, title: title) {
        return calendar
      }
      queueCalendarForCleanup(calendar, title: title)
      forgetStoredCalendar(title: title)
    }
    return eventStore.calendars(for: .event).first {
      $0.title == title && $0.allowsContentModifications
    }
  }

  private func calendarIdentifierKey(for title: String) -> String {
    title == Self.validationCalendarTitle
      ? Self.validationCalendarIdentifierKey
      : Self.calendarIdentifierKey
  }

  private func calendarManagedKey(for title: String) -> String {
    title == Self.validationCalendarTitle
      ? Self.validationCalendarManagedKey
      : Self.calendarManagedKey
  }

  private func isManagedCalendar(_ calendar: EKCalendar, title: String) -> Bool {
    let defaults = UserDefaults.standard
    return defaults.string(forKey: calendarIdentifierKey(for: title))
        == calendar.calendarIdentifier
      && defaults.bool(forKey: calendarManagedKey(for: title))
  }

  private func rememberCalendar(
    _ calendar: EKCalendar,
    title: String,
    managedByApp: Bool
  ) {
    let defaults = UserDefaults.standard
    defaults.set(
      calendar.calendarIdentifier,
      forKey: calendarIdentifierKey(for: title)
    )
    defaults.set(managedByApp, forKey: calendarManagedKey(for: title))
  }

  private func forgetStoredCalendar(title: String) {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: calendarIdentifierKey(for: title))
    defaults.removeObject(forKey: calendarManagedKey(for: title))
  }

  private func pendingCalendarCleanupKey(for title: String) -> String {
    title == Self.validationCalendarTitle
      ? Self.validationPendingCalendarCleanupKey
      : Self.pendingCalendarCleanupKey
  }

  private func queueCalendarForCleanup(_ calendar: EKCalendar, title: String) {
    let defaults = UserDefaults.standard
    let key = pendingCalendarCleanupKey(for: title)
    var identifiers = defaults.stringArray(forKey: key) ?? []
    if !identifiers.contains(calendar.calendarIdentifier) {
      identifiers.append(calendar.calendarIdentifier)
      defaults.set(identifiers, forKey: key)
    }
  }

  private func pendingCleanupCalendars(title: String) -> [EKCalendar] {
    let identifiers = UserDefaults.standard.stringArray(
      forKey: pendingCalendarCleanupKey(for: title)
    ) ?? []
    return identifiers.compactMap { identifier in
      guard let calendar = eventStore.calendar(withIdentifier: identifier),
            calendar.allowsContentModifications else {
        return nil
      }
      return calendar
    }
  }

  private func clearPendingCleanupCalendars(title: String) {
    UserDefaults.standard.removeObject(
      forKey: pendingCalendarCleanupKey(for: title)
    )
  }

  private func uniqueCalendars(_ calendars: [EKCalendar]) -> [EKCalendar] {
    var identifiers = Set<String>()
    return calendars.filter {
      identifiers.insert($0.calendarIdentifier).inserted
    }
  }

  private func migrateStoredCalendar(
    identifier: String,
    fromIdentifierKey: String,
    fromManagedKey: String,
    toIdentifierKey: String,
    toManagedKey: String
  ) {
    let defaults = UserDefaults.standard
    let managedByApp = defaults.object(forKey: fromManagedKey) != nil
      && defaults.bool(forKey: fromManagedKey)
    defaults.set(identifier, forKey: toIdentifierKey)
    defaults.set(managedByApp, forKey: toManagedKey)
    defaults.removeObject(forKey: fromIdentifierKey)
    defaults.removeObject(forKey: fromManagedKey)
  }

  private func storedCalendar(title: String) -> EKCalendar? {
    let defaults = UserDefaults.standard
    if title == Self.validationCalendarTitle {
      if let identifier = defaults.string(forKey: Self.validationCalendarIdentifierKey),
         let calendar = eventStore.calendar(withIdentifier: identifier),
         calendar.allowsContentModifications {
        return calendar
      }
      if let legacyIdentifier = defaults.string(forKey: Self.calendarIdentifierKey),
         let legacyCalendar = eventStore.calendar(withIdentifier: legacyIdentifier),
         legacyCalendar.title == Self.validationCalendarTitle,
         legacyCalendar.allowsContentModifications {
        migrateStoredCalendar(
          identifier: legacyIdentifier,
          fromIdentifierKey: Self.calendarIdentifierKey,
          fromManagedKey: Self.calendarManagedKey,
          toIdentifierKey: Self.validationCalendarIdentifierKey,
          toManagedKey: Self.validationCalendarManagedKey
        )
        return legacyCalendar
      }
      return nil
    }

    if let identifier = defaults.string(forKey: Self.calendarIdentifierKey),
       let calendar = eventStore.calendar(withIdentifier: identifier),
       calendar.allowsContentModifications {
      if calendar.title == Self.validationCalendarTitle {
        migrateStoredCalendar(
          identifier: identifier,
          fromIdentifierKey: Self.calendarIdentifierKey,
          fromManagedKey: Self.calendarManagedKey,
          toIdentifierKey: Self.validationCalendarIdentifierKey,
          toManagedKey: Self.validationCalendarManagedKey
        )
        return nil
      }
      return calendar
    }
    return nil
  }

  private func removeExistingEvents(
    start: Date,
    end: Date,
    calendars: [EKCalendar]? = nil,
    uidNamespace: String? = nil,
    commitChanges: Bool = true
  ) throws -> Int {
    let predicate = eventStore.predicateForEvents(
      withStart: start,
      end: end,
      calendars: calendars
    )
    let events = eventStore.events(matching: predicate).filter {
      guard let notes = $0.notes else {
        return false
      }
      if let uidNamespace {
        return eventNotes(notes, match: uidNamespace)
      }
      return notes.contains(Self.marker)
    }
    for event in events {
      try eventStore.remove(event, span: .thisEvent, commit: false)
    }
    if commitChanges && !events.isEmpty {
      try eventStore.commit()
    }
    return events.count
  }

  private func eventNotes(_ notes: String, match uidNamespace: String) -> Bool {
    guard let markerRange = notes.range(of: Self.marker, options: .backwards) else {
      return false
    }
    let identifier = notes[markerRange.upperBound...]
    guard let separator = identifier.firstIndex(of: "|") else {
      return false
    }
    let storedNamespace = String(identifier[..<separator])
    return storedNamespace == uidNamespace
      || legacyManualNamespace(storedNamespace, matches: uidNamespace)
  }

  private func legacyManualNamespace(
    _ storedNamespace: String,
    matches uidNamespace: String
  ) -> Bool {
    let currentParts = uidNamespace.split(separator: "-", omittingEmptySubsequences: false)
    guard currentParts.count == 3,
          currentParts[0] == "niigata",
          Int(currentParts[1]) != nil,
          ["第1ターム", "第2ターム", "第3ターム", "第4ターム"].contains(String(currentParts[2])) else {
      return false
    }
    let legacyParts = storedNamespace.split(separator: "-", omittingEmptySubsequences: false)
    guard legacyParts.count == 3,
          legacyParts[0] == "manual" else {
      return false
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let start = dateFromLegacyNamespaceStamp(legacyParts[1], calendar: calendar),
          let end = dateFromLegacyNamespaceStamp(legacyParts[2], calendar: calendar),
          let dayCount = calendar.dateComponents([.day], from: start, to: end).day,
          dayCount >= 0,
          let midpoint = calendar.date(byAdding: .day, value: dayCount / 2, to: start) else {
      return false
    }

    let startComponents = calendar.dateComponents([.year, .month], from: start)
    guard let startYear = startComponents.year,
          let startMonth = startComponents.month else {
      return false
    }
    let academicYear = startMonth >= 4 ? startYear : startYear - 1
    let termNumber: Int
    switch calendar.component(.month, from: midpoint) {
    case 4, 5:
      termNumber = 1
    case 6, 7, 8, 9:
      termNumber = 2
    case 10, 11:
      termNumber = 3
    default:
      termNumber = 4
    }
    return uidNamespace == "niigata-\(academicYear)-第\(termNumber)ターム"
  }

  private func dateFromLegacyNamespaceStamp(
    _ stamp: Substring,
    calendar: Calendar
  ) -> Date? {
    let value = String(stamp)
    guard value.count == 8,
          let year = Int(value.prefix(4)),
          let month = Int(value.dropFirst(4).prefix(2)),
          let day = Int(value.suffix(2)) else {
      return nil
    }
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    guard let date = calendar.date(from: components) else {
      return nil
    }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    guard resolved.year == year,
          resolved.month == month,
          resolved.day == day else {
      return nil
    }
    return date
  }

  private func eventNamespace(from events: [[String: Any]]) throws -> String {
    var namespace: String?
    for rawEvent in events {
      guard let identifier = stringValue(rawEvent["id"]),
            let separator = identifier.firstIndex(of: "|"),
            separator != identifier.startIndex else {
        throw MacosCalendarBridgeError.invalidEvent
      }
      let candidate = String(identifier[..<separator])
      if let namespace, namespace != candidate {
        throw MacosCalendarBridgeError.invalidEvent
      }
      namespace = candidate
    }
    guard let namespace else {
      throw MacosCalendarBridgeError.invalidEvent
    }
    return namespace
  }

  private func cleanupRange(
    calendars: [EKCalendar],
    uidNamespace: String,
    currentStart: Date,
    currentEnd: Date
  ) -> (start: Date, end: Date) {
    var earliest = currentStart
    var latest = currentEnd
    var hasMissingStoredRange = false
    for calendar in calendars {
      guard let previous = previouslySyncedRange(
        calendar: calendar,
        uidNamespace: uidNamespace
      ) else {
        hasMissingStoredRange = true
        continue
      }
      earliest = min(earliest, previous.start)
      latest = max(latest, previous.end)
    }
    if hasMissingStoredRange {
      // Older releases wrote namespace markers but did not persist their
      // successful sync range. On the first post-upgrade sync, search the
      // surrounding academic year so a narrower corrected range cannot leave
      // old events from the same namespace behind.
      let calendarMath = Calendar(identifier: .gregorian)
      earliest = min(
        earliest,
        calendarMath.date(byAdding: .year, value: -1, to: currentStart)
          ?? currentStart
      )
      latest = max(
        latest,
        calendarMath.date(byAdding: .year, value: 1, to: currentEnd)
          ?? currentEnd
      )
    }
    return (earliest, latest)
  }

  private func previouslySyncedRange(
    calendar: EKCalendar,
    uidNamespace: String
  ) -> (start: Date, end: Date)? {
    let key = syncedRangeStorageKey(
      calendar: calendar,
      uidNamespace: uidNamespace
    )
    guard let ranges = UserDefaults.standard.dictionary(forKey: Self.syncedCalendarRangesKey),
          let rawRange = ranges[key] as? [String: Any],
          let startMillis = doubleValue(rawRange["startMillis"]),
          let endMillis = doubleValue(rawRange["endMillis"]) else {
      return nil
    }
    let start = Date(timeIntervalSince1970: startMillis / 1000)
    let end = Date(timeIntervalSince1970: endMillis / 1000)
    return end > start ? (start, end) : nil
  }

  private func rememberSyncedRange(
    calendar: EKCalendar,
    uidNamespace: String,
    start: Date,
    end: Date
  ) {
    let key = syncedRangeStorageKey(
      calendar: calendar,
      uidNamespace: uidNamespace
    )
    var ranges = UserDefaults.standard.dictionary(
      forKey: Self.syncedCalendarRangesKey
    ) ?? [:]
    ranges[key] = [
      "startMillis": start.timeIntervalSince1970 * 1000,
      "endMillis": end.timeIntervalSince1970 * 1000
    ]
    UserDefaults.standard.set(ranges, forKey: Self.syncedCalendarRangesKey)
  }

  private func syncedRangeStorageKey(
    calendar: EKCalendar,
    uidNamespace: String
  ) -> String {
    let identifier = calendar.calendarIdentifier
    return "\(identifier.utf8.count):\(identifier)\(uidNamespace)"
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
  case invalidEvent
  case invalidRange

  var errorDescription: String? {
    switch self {
    case .missingWritableCalendar:
      return "書き込み可能なカレンダーが見つかりません"
    case .invalidEvent:
      return "追加する予定の情報が不正です"
    case .invalidRange:
      return "カレンダー同期期間が不正です"
    }
  }
}

private final class MacosNotificationsBridge: NSObject, UNUserNotificationCenterDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/notifications"
  private static let notificationURLKey = "url"

  private var channel: FlutterMethodChannel?
  private var pendingNotificationURL: String?

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
  }

  func register(messenger: FlutterBinaryMessenger) {
    UNUserNotificationCenter.current().delegate = self
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
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
        if let url = args?[Self.notificationURLKey] as? String, !url.isEmpty {
          content.userInfo = [Self.notificationURLKey: url]
        }
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
      case "takePendingNotificationUrl":
        let url = self?.pendingNotificationURL
        self?.pendingNotificationURL = nil
        result(url)
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

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    defer { completionHandler() }
    guard let url = response.notification.request.content.userInfo[Self.notificationURLKey] as? String,
          !url.isEmpty else {
      return
    }
    pendingNotificationURL = url
    NSApp.activate(ignoringOtherApps: true)
    channel?.invokeMethod(
      "deadlineNotificationTapped",
      arguments: [Self.notificationURLKey: url]
    ) { [weak self] result in
      if result as? Bool == true, self?.pendingNotificationURL == url {
        self?.pendingNotificationURL = nil
      }
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
