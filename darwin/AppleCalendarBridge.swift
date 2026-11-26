import EventKit
import Foundation
#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif

final class AppleCalendarBridge {
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
        throw CalendarBridgeError.invalidEvent
      }
      // Refresh the store so queries below see events committed by a previous
      // sync. EKEventStore can otherwise keep a stale snapshot and miss them,
      // which leaves old app-created events in place on repeated syncs.
      eventStore.reset()
      let title = args["calendarTitle"] as? String ?? "More Better Gakujo 授業"
      guard (title == Self.validationCalendarTitle)
        == (uidNamespace == Self.validationUidNamespace) else {
        throw CalendarBridgeError.invalidEvent
      }
      let startMillis = (args["rangeStartMillis"] as? NSNumber)?.doubleValue ?? 0
      let endMillis = (args["rangeEndMillis"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000
      let rangeStart = Date(timeIntervalSince1970: startMillis / 1000)
      let rangeEnd = Date(timeIntervalSince1970: endMillis / 1000)
      guard rangeEnd > rangeStart else {
        throw CalendarBridgeError.invalidRange
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
          throw CalendarBridgeError.invalidEvent
        }
        added += 1
      }
      try eventStore.commit()
      // Only this namespace was cleaned. Keep old calendar identifiers so
      // later imports can still find events belonging to other terms.
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
      // A date-limited deletion may leave other app events in old calendars.
      // Keep their identifiers for subsequent imports and deletions.
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

    // The default calendar's account may not allow new calendars (Google or
    // Exchange, for example), which made every import fall back to a file.
    // Try each account that can hold one until a calendar can be created.
    var lastError: Error?
    for source in calendarSourceCandidates() {
      let calendar = EKCalendar(for: .event, eventStore: eventStore)
      calendar.title = title
      calendar.source = source
      do {
        try eventStore.saveCalendar(calendar, commit: true)
        rememberCalendar(calendar, title: title, managedByApp: true)
        return calendar
      } catch {
        lastError = error
      }
    }
    throw lastError ?? CalendarBridgeError.missingWritableCalendar
  }

  /// Accounts that may hold a new calendar, most preferred first: the default
  /// calendar's account, iCloud, then the on-device store and the rest.
  private func calendarSourceCandidates() -> [EKSource] {
    var candidates: [EKSource] = []
    func add(_ source: EKSource?) {
      guard let source,
            source.sourceType != .subscribed,
            source.sourceType != .birthdays,
            !candidates.contains(where: {
              $0.sourceIdentifier == source.sourceIdentifier
            }) else {
        return
      }
      candidates.append(source)
    }
    add(eventStore.defaultCalendarForNewEvents?.source)
    for source in eventStore.sources
      where source.sourceType == .calDAV && source.title == "iCloud" {
      add(source)
    }
    for source in eventStore.sources where source.sourceType == .local {
      add(source)
    }
    for source in eventStore.sources {
      add(source)
    }
    return candidates
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
        throw CalendarBridgeError.invalidEvent
      }
      let candidate = String(identifier[..<separator])
      if let namespace, namespace != candidate {
        throw CalendarBridgeError.invalidEvent
      }
      namespace = candidate
    }
    guard let namespace else {
      throw CalendarBridgeError.invalidEvent
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

private enum CalendarBridgeError: LocalizedError {
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
