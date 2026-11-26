import Foundation
import UserNotifications
#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import AppKit
import FlutterMacOS
#endif

final class AppleNotificationsBridge: NSObject, UNUserNotificationCenterDelegate {
  private static let channelName = "net.yoshida.morebettergakujo/notifications"
  private static let notificationURLKey = "url"

  private var channel: FlutterMethodChannel?
  private weak var messenger: FlutterBinaryMessenger?
  private let handoff = NotificationActivationHandoff()
  private let history = NotificationHistory()
  #if os(macOS)
  private var launchPair = NotificationLaunchPair()
  #endif

  override init() {
    super.init()
    UNUserNotificationCenter.current().delegate = self
    history.registerCategory()
  }

  func register(messenger: FlutterBinaryMessenger) {
    UNUserNotificationCenter.current().delegate = self
    guard self.messenger !== messenger else { return }
    history.collect(account: nil) { _ in }
    self.messenger = messenger
    self.channel?.setMethodCallHandler(nil)
    handoff.replaceMessenger()
    let channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    self.channel = channel
    handoff.deliver = { [weak channel] url, token, reply in
      guard let channel else { reply(false); return }
      var arguments = [Self.notificationURLKey: url]
      arguments["consumer"] = token
      channel.invokeMethod("deadlineNotificationTapped", arguments: arguments) { result in
        let accepted = result as? Bool == true
        DispatchQueue.main.async { reply(accepted) }
      }
    }
    channel.setMethodCallHandler { [weak self, weak channel] call, result in
      guard let self, let channel, self.channel === channel else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error {
            let nativeError = error as NSError
            NSLog("MoreBetterGakujo: notification authorization failed (%@ %ld): %@", nativeError.domain, nativeError.code, nativeError.localizedDescription)
          }
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "checkPermission":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async {
            switch settings.authorizationStatus {
            #if os(iOS)
            case .authorized, .provisional, .ephemeral:
              result(true)
            #else
            case .authorized, .provisional:
              result(true)
            #endif
            case .denied:
              result(false)
            case .notDetermined:
              result(nil)
            @unknown default:
              result(nil)
            }
          }
        }
      case "openNotificationSettings":
        #if os(iOS)
        let target: String
        if #available(iOS 16.0, *) {
          target = UIApplication.openNotificationSettingsURLString
        } else {
          target = UIApplication.openSettingsURLString
        }
        guard let url = URL(string: target) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          DispatchQueue.main.async {
            result(opened)
          }
        }
        #else
        for target in [
          "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
          "x-apple.systempreferences:com.apple.preference.notifications",
        ] {
          if let url = URL(string: target), NSWorkspace.shared.open(url) {
            result(true)
            return
          }
        }
        result(false)
        #endif
      case "loadNotificationHistory":
        let args = call.arguments as? [String: Any]
        self.history.collect(account: args?["account"] as? String) { collected in
          switch collected {
          case .success(let entries): result(entries)
          case .failure: result(FlutterError(code: "notification_history_failed", message: nil, details: nil))
          }
        }
      case "clearNotificationHistory":
        do {
          try self.history.clear()
          result(nil)
        } catch {
          result(FlutterError(code: "notification_history_failed", message: nil, details: nil))
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
        self.history.tag(content, arguments: args)
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
      case "scheduleReminders":
        // Replaces every booked reminder. The system keeps at most 64
        // pending requests, so only the earliest ones are booked.
        let args = call.arguments as? [String: Any]
        let items = args?["reminders"] as? [[String: Any]] ?? []
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
          let booked = requests.map(\.identifier).filter { $0.hasPrefix("reminder-") }
          center.removePendingNotificationRequests(withIdentifiers: booked)
          let now = Date()
          for item in items.prefix(60) {
            guard let id = (item["id"] as? NSNumber)?.intValue,
                  let atMillis = (item["atMillis"] as? NSNumber)?.doubleValue else {
              continue
            }
            let interval = Date(timeIntervalSince1970: atMillis / 1000).timeIntervalSince(now)
            if interval < 1 {
              continue
            }
            let content = UNMutableNotificationContent()
            content.title = item["title"] as? String ?? "課題の締切"
            content.body = item["body"] as? String ?? ""
            content.sound = .default
            if let url = item[Self.notificationURLKey] as? String, !url.isEmpty {
              content.userInfo = [Self.notificationURLKey: url]
            }
            self.history.tag(content, arguments: item)
            center.add(
              UNNotificationRequest(
                identifier: "reminder-\(id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
              )
            )
          }
          DispatchQueue.main.async {
            result(true)
          }
        }
      case "cancelOtherAccountsReminders":
        let args = call.arguments as? [String: Any]
        self.history.cancelOtherAccountsReminders(account: args?["account"] as? String) {
          result(nil)
        }
      case "takePendingNotificationUrl":
        if let args = call.arguments as? [String: Any], args["version"] as? Int == 1,
           let token = args["consumer"] as? String {
          let url = self.handoff.take(token)
          result(["version": 1, "consumer": token, "url": url as Any])
        } else {
          result(self.handoff.takeLegacy())
        }
      case "finishPendingNotification":
        if let args = call.arguments as? [String: Any], let token = args["consumer"] as? String {
          self.handoff.finish(token, accepted: args["accepted"] as? Bool == true)
        }
        result(nil)
      case "endNotificationConsumer":
        if let args = call.arguments as? [String: Any], let token = args["consumer"] as? String {
          self.handoff.end(token)
        }
        result(nil)
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
    DispatchQueue.main.async {
      self.history.observe(notification)
      #if os(iOS)
      completionHandler([.banner, .list, .sound, .badge])
      #else
      if #available(macOS 11.0, *) {
        completionHandler([.banner, .list, .sound, .badge])
      } else {
        completionHandler([.alert, .sound, .badge])
      }
      #endif
    }
  }

  #if os(macOS)
  func rememberLaunchResponse(_ response: UNNotificationResponse) {
    history.observe(response.notification)
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    guard let url = Self.url(of: response),
          launchPair.acceptLaunch(response.notification.request.identifier) else { return }
    NSLog("MoreBetterGakujo: app launched from a notification")
    handoff.receive(url)
  }

  private static func url(of response: UNNotificationResponse) -> String? {
    guard let url = response.notification.request.content.userInfo[notificationURLKey] as? String,
          !url.isEmpty else {
      return nil
    }
    return url
  }

  #endif
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    DispatchQueue.main.async {
      defer { completionHandler() }
      self.history.observe(response.notification)
      guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
      #if os(iOS)
      guard let url = response.notification.request.content.userInfo[Self.notificationURLKey] as? String,
            !url.isEmpty else { return }
      #else
      guard let url = Self.url(of: response),
            self.launchPair.acceptTap(response.notification.request.identifier) else { return }
      NSApp.activate(ignoringOtherApps: true)
      #endif
      self.handoff.receive(url)
    }
  }
}
