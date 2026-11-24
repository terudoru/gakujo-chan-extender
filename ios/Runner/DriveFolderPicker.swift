import AuthenticationServices
import CryptoKit
import Flutter
import UIKit

enum DrivePickerError: String, Error {
  case failed
  case network
  case permissionDenied = "permission_denied"
  case browserUnavailable = "browser_unavailable"
}

struct DrivePickerAuthorization {
  private static let scope = "https://www.googleapis.com/auth/drive.file"
  private let fileIds: [String]?
  private let clientID: String
  let scheme: String
  private var redirectURI: String { "\(scheme):/oauth2redirect" }
  private let state = DrivePickerAuthorization.randomSecret()
  private let verifier = DrivePickerAuthorization.randomSecret()

  init?(clientID: String, registeredSchemes: [String], fileIds: [String]? = nil) {
    if let fileIds, fileIds.isEmpty || fileIds.contains(where: {
      $0.isEmpty || $0.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) != nil
    }) { return nil }
    self.fileIds = fileIds
    let scheme = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
    guard clientID.hasSuffix(".apps.googleusercontent.com"),
          registeredSchemes.contains(scheme) else { return nil }
    self.clientID = clientID
    self.scheme = scheme
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func randomSecret() -> String {
    SymmetricKey(size: .bits256).withUnsafeBytes { base64URL(Data($0)) }
  }

  // A literal '+' in a login hint or authorization code must survive form decoding.
  private func form(_ items: [URLQueryItem]) -> String {
    var components = URLComponents()
    components.queryItems = items
    return components.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B")
  }

  func authorizationURL(email: String) -> URL {
    var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    var items = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: Self.scope),
      URLQueryItem(name: "access_type", value: "online"),
      URLQueryItem(name: "include_granted_scopes", value: "false"),
      URLQueryItem(name: "prompt", value: "consent"),
      URLQueryItem(name: "trigger_onepick", value: "true"),
      URLQueryItem(name: "allow_folder_selection", value: "true"),
      URLQueryItem(name: "mimetypes", value: "application/vnd.google-apps.folder"),
      URLQueryItem(name: "allow_multiple", value: "false"),
      URLQueryItem(name: "login_hint", value: email),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "code_challenge", value: challenge),
    ]
    if let fileIds {
      items.append(URLQueryItem(name: "file_ids", value: fileIds.joined(separator: ",")))
    }
    url.percentEncodedQuery = form(items)
    return url.url!
  }

  private func selection(from callback: URL) throws -> (id: String, code: String)? {
    guard var url = URLComponents(url: callback, resolvingAgainstBaseURL: false),
          let items = url.queryItems else { throw DrivePickerError.failed }
    url.query = nil
    guard url.string == redirectURI else { throw DrivePickerError.failed }
    var fields = [String: String]()
    for item in items where ["state", "error", "code", "scope", "picked_file_ids"].contains(item.name) {
      guard let value = item.value, fields[item.name] == nil else { throw DrivePickerError.failed }
      fields[item.name] = value
    }
    guard fields["state"] == state else { throw DrivePickerError.failed }
    if let error = fields["error"] {
      guard error == "access_denied", fields["code"] == nil else { throw DrivePickerError.failed }
      return nil
    }
    if let scope = fields["scope"], scope != Self.scope { throw DrivePickerError.permissionDenied }
    guard let code = fields["code"], !code.isEmpty,
          let id = fields["picked_file_ids"], !id.isEmpty,
          id.range(of: "[^A-Za-z0-9_-]", options: .regularExpression) == nil else {
      throw DrivePickerError.failed
    }
    if let fileIds, !fileIds.contains(id) { throw DrivePickerError.failed }
    return (id, code)
  }

  typealias Exchange = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void

  func finish(callback: URL, exchange: Exchange,
              completion: @escaping (Result<String?, DrivePickerError>) -> Void) {
    let selected: (id: String, code: String)
    do {
      guard let selection = try selection(from: callback) else {
        completion(.success(nil))
        return
      }
      selected = selection
    } catch let error as DrivePickerError {
      completion(.failure(error))
      return
    } catch {
      completion(.failure(.failed))
      return
    }
    var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(form([
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "grant_type", value: "authorization_code"),
      URLQueryItem(name: "code", value: selected.code),
      URLQueryItem(name: "code_verifier", value: verifier),
    ]).utf8)
    exchange(request) { data, response, error in
      guard error == nil else { return completion(.failure(.network)) }
      guard (response as? HTTPURLResponse)?.statusCode == 200, let data,
            let grant = try? JSONDecoder().decode(TokenResponse.self, from: data),
            !grant.access_token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return completion(.failure(.failed))
      }
      if let scope = grant.scope, scope != Self.scope { return completion(.failure(.permissionDenied)) }
      // The grant is complete. Star Sync validates the ID with its existing account.
      completion(.success(selected.id))
    }
  }

  private struct TokenResponse: Decodable {
    let access_token: String
    let scope: String?
  }
}

final class DrivePickerRequest: NSObject, ASWebAuthenticationPresentationContextProviding {
  let window: UIWindow
  let reply: FlutterResult
  fileprivate var awaitingAuthorization = true
  var cancelOperation: (() -> Void)?

  init(window: UIWindow, reply: @escaping FlutterResult) {
    self.window = window
    self.reply = reply
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}

private final class PickerExchangeDelegate: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

@MainActor
final class DriveFolderPicker {
  private var active: DrivePickerRequest?
  private let exchange: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    return URLSession(configuration: config, delegate: PickerExchangeDelegate(), delegateQueue: nil)
  }()

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "net.yoshida.morebettergakujo/drive_folder_picker", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "cancelPick" {
          self.cancelPick()
          return result(nil)
        }
        guard call.method == "pickFolder" else { return result(FlutterMethodNotImplemented) }
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } ?? []
        guard let args = call.arguments as? [String: Any], let email = args["email"] as? String, !email.isEmpty,
              let clientID = args["iosClientId"] as? String,
              args["fileIds"] == nil || args["fileIds"] is [String],
              let auth = DrivePickerAuthorization(clientID: clientID, registeredSchemes: schemes,
                                                fileIds: args["fileIds"] as? [String]) else {
          return result(FlutterError(code: "invalid_config", message: nil, details: nil))
        }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
          .filter({ $0.activationState == .foregroundActive })
          .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else {
          return result(FlutterError(code: DrivePickerError.browserUnavailable.rawValue, message: nil, details: nil))
        }
        guard let request = self.begin(window: window, reply: result) else {
          return result(FlutterError(code: "busy", message: nil, details: nil))
        }
        self.present(auth: auth, email: email, request: request)
      }
  }

  func begin(window: UIWindow, reply: @escaping FlutterResult) -> DrivePickerRequest? {
    guard active == nil else { return nil }
    let request = DrivePickerRequest(window: window, reply: reply)
    active = request
    return request
  }

  func acceptAuthorizationCallback(for request: DrivePickerRequest) -> Bool {
    guard active === request, request.awaitingAuthorization else { return false }
    request.awaitingAuthorization = false
    request.cancelOperation = nil
    return true
  }

  func cancelPick() {
    guard let request = active else { return }
    finish(request, .success(nil), stopping: request.cancelOperation)
  }

  func finish(_ request: DrivePickerRequest, _ outcome: Result<String?, DrivePickerError>,
              stopping cancelOperation: (() -> Void)? = nil) {
    guard active === request else { return }
    active = nil
    request.cancelOperation = nil
    cancelOperation?()
    switch outcome {
    case .success(let id): request.reply(id)
    case .failure(let error): request.reply(FlutterError(code: error.rawValue, message: nil, details: nil))
    }
  }

  private func present(auth: DrivePickerAuthorization, email: String, request: DrivePickerRequest) {
    let completeExchange: @Sendable (Result<String?, DrivePickerError>) -> Void = { outcome in
      DispatchQueue.main.async { self.finish(request, outcome) }
    }
    let handle: ASWebAuthenticationSession.CompletionHandler = { callback, error in
      DispatchQueue.main.async {
        guard self.acceptAuthorizationCallback(for: request) else { return }
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
          self.finish(request, .success(nil))
        } else if error == nil, let callback {
          auth.finish(callback: callback, exchange: { httpRequest, reply in
            let task = self.exchange.dataTask(with: httpRequest, completionHandler: reply)
            request.cancelOperation = { task.cancel() }
            task.resume()
          }, completion: completeExchange)
        } else {
          self.finish(request, .failure(.failed))
        }
      }
    }
    let url = auth.authorizationURL(email: email)
    let session: ASWebAuthenticationSession
    if #available(iOS 17.4, *) {
      session = ASWebAuthenticationSession(url: url, callback: .customScheme(auth.scheme), completionHandler: handle)
    } else {
      session = ASWebAuthenticationSession(url: url, callbackURLScheme: auth.scheme, completionHandler: handle)
    }
    session.presentationContextProvider = request
    request.cancelOperation = { session.cancel() }
    if !session.start() { finish(request, .failure(.browserUnavailable)) }
  }
}
