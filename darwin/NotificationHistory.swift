import Foundation
import UserNotifications

// Access the ledger on the main queue, including from notification delegates.
final class NotificationHistory {
  private static let category = "gakujo-notification-history"
  private var generation = 0

  private struct Entry: Codable {
    let id: String
    let account: String
    let title: String
    let body: String
    let postedAtMillis: Int64
    let url: String?

    var channelValue: [String: Any] {
      var value: [String: Any] = [
        "title": title, "body": body, "postedAtMillis": postedAtMillis
      ]
      if let url { value["url"] = url }
      return value
    }
  }

  func registerCategory() {
    let category = UNNotificationCategory(
      identifier: Self.category, actions: [], intentIdentifiers: [],
      options: .customDismissAction
    )
    UNUserNotificationCenter.current().setNotificationCategories([category])
  }

  func tag(_ content: UNMutableNotificationContent, arguments: [String: Any]?) {
    guard let account = arguments?["historyAccount"] as? String else { return }
    content.categoryIdentifier = Self.category
    content.userInfo["historyId"] = UUID().uuidString
    content.userInfo["historyAccount"] = account
    content.userInfo["historyUrl"] = arguments?["historyUrl"] as? String
  }

  func observe(_ notification: UNNotification) {
    do {
      _ = try merge([notification])
    } catch {
      NSLog("MoreBetterGakujo: failed to save notification history")
    }
  }

  func collect(account: String?, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
    let requestedGeneration = generation
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      DispatchQueue.main.async {
        guard self.generation == requestedGeneration else {
          completion(.success([]))
          return
        }
        completion(Result {
          let rows = try self.merge(notifications)
          return rows.filter { $0.account == account }.map(\.channelValue)
        })
      }
    }
  }

  func clear() throws {
    generation += 1
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    center.removeAllDeliveredNotifications()
    let file = try fileURL()
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
  }

  func cancelOtherAccountsReminders(account: String?, completion: @escaping () -> Void) {
    guard let account else { completion(); return }
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let foreign = requests.compactMap { request -> String? in
        guard request.identifier.hasPrefix("reminder-"),
              let owner = request.content.userInfo["historyAccount"] as? String,
              owner != account else { return nil }
        return request.identifier
      }
      if !foreign.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: foreign)
      }
      DispatchQueue.main.async { completion() }
    }
  }

  private func fileURL() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true
    )
    var directory = support
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "MoreBetterGakujo", isDirectory: true)
      .appendingPathComponent("NotificationHistory", isDirectory: true)
    if !FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    var flags = URLResourceValues()
    flags.isExcludedFromBackup = true
    try directory.setResourceValues(flags)
    return directory.appendingPathComponent("history.json")
  }

  private func merge(_ notifications: [UNNotification]) throws -> [Entry] {
    let file = try fileURL()
    let old = FileManager.default.fileExists(atPath: file.path)
      ? try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file)) : []
    var ids = Set(old.map(\.id))
    var added: [Entry] = []
    for notification in notifications {
      let content = notification.request.content
      guard let id = content.userInfo["historyId"] as? String,
            let account = content.userInfo["historyAccount"] as? String,
            ids.insert(id).inserted else { continue }
      added.append(Entry(
        id: id, account: account, title: content.title, body: content.body,
        postedAtMillis: Int64(notification.date.timeIntervalSince1970 * 1000),
        url: content.userInfo["historyUrl"] as? String
      ))
    }
    if added.isEmpty { return old }
    let rows = Array((old + added).sorted { $0.postedAtMillis > $1.postedAtMillis }.prefix(200))
    try JSONEncoder().encode(rows).write(to: file, options: .atomic)
    return rows
  }
}

// The notification delegate and both directions of the channel serialize here on main.
final class NotificationActivationHandoff {
  private final class Activation {
    let url: String
    var owner: String?
    init(_ url: String) { self.url = url }
  }

  private var latest: Activation?
  private var claims: [String: Activation] = [:]
  private var consumer: String?
  private var lastRegistration: (run: String, generation: Int)?
  private var retiredRuns = Set<String>()
  private static let legacy = "legacy"
  var deliver: (String, String?, @escaping (Bool) -> Void) -> Void = { _, _, reply in reply(false) }

  func replaceMessenger() {
    // Carry only the latest orphan. An old channel reply still holds its old object.
    latest = latest.map { Activation($0.url) }
    claims.removeAll()
    consumer = nil
    lastRegistration = nil
    retiredRuns.removeAll()
  }

  func receive(_ url: String) {
    let event = Activation(url)
    latest = event
    if let consumer { offer(event, to: consumer) }
  }

  private func offer(_ event: Activation, to token: String) {
    event.owner = token
    deliver(event.url, token == Self.legacy ? nil : token) { [weak self] accepted in
      self?.settle(event, token, accepted)
    }
  }

  private func settle(_ event: Activation, _ token: String, _ accepted: Bool) {
    guard latest === event, event.owner == token else { return }
    event.owner = nil
    if accepted {
      latest = nil
    } else if let consumer, consumer != token {
      offer(event, to: consumer)
    }
  }

  func take(_ token: String) -> String? {
    if consumer == token { return claims[token]?.url }
    let parts = token.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let generation = Int(parts[1]) else { return nil }
    let run = String(parts[0])
    if let previous = lastRegistration {
      guard !retiredRuns.contains(run),
            previous.run != run || generation > previous.generation else { return nil }
      if previous.run != run {
        retiredRuns.insert(previous.run)
        claims.removeAll()
        latest?.owner = nil
      }
    }
    lastRegistration = (run, generation)
    consumer = token
    guard let event = latest, event.owner == nil else { return nil }
    event.owner = token
    claims[token] = event
    return event.url
  }

  func takeLegacy() -> String? {
    guard lastRegistration == nil else { return nil }
    consumer = Self.legacy
    guard let event = latest, event.owner == nil else { return nil }
    latest = nil
    return event.url
  }

  func finish(_ token: String, accepted: Bool) {
    if let event = claims.removeValue(forKey: token) { settle(event, token, accepted) }
  }

  func end(_ token: String) {
    if consumer == token { consumer = nil }
  }
}
