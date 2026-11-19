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
