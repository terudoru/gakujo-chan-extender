import CryptoKit
import UIKit
import XCTest
@testable import Runner

final class DriveFolderPickerTests: XCTestCase {
  private let clientID = "example.apps.googleusercontent.com"
  private let scheme = "com.googleusercontent.apps.example"
  private var auth: DrivePickerAuthorization {
    DrivePickerAuthorization(clientID: clientID, registeredSchemes: [scheme])!
  }

  private func parameters(_ url: URLComponents) -> [String: String] {
    Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) })
  }

  private func callback(_ auth: DrivePickerAuthorization, _ query: String) -> URL {
    let url = URLComponents(url: auth.authorizationURL(email: "a@example.org"), resolvingAgainstBaseURL: false)!
    return URL(string: "\(scheme):/oauth2redirect?state=\(parameters(url)["state"]!)&\(query)")!
  }

  func testConfigurationAndFreshPickerParameters() {
    XCTAssertNil(DrivePickerAuthorization(clientID: clientID, registeredSchemes: ["other"]))
    XCTAssertNil(DrivePickerAuthorization(clientID: "", registeredSchemes: [""]))
    let email = "account+tag@example.org"
    let url = auth.authorizationURL(email: email)
    let params = parameters(URLComponents(url: url, resolvingAgainstBaseURL: false)!)
    XCTAssertEqual(url.scheme, "https")
    XCTAssertEqual(url.host, "accounts.google.com")
    XCTAssertEqual(url.path, "/o/oauth2/v2/auth")
    XCTAssertEqual(params["client_id"], clientID)
    XCTAssertEqual(params["redirect_uri"], scheme + ":/oauth2redirect")
    XCTAssertEqual(params["response_type"], "code")
    XCTAssertEqual(params["scope"], "https://www.googleapis.com/auth/drive.file")
    XCTAssertEqual(params["access_type"], "online")
    XCTAssertEqual(params["include_granted_scopes"], "false")
    XCTAssertEqual(params["prompt"], "consent")
    XCTAssertEqual(params["trigger_onepick"], "true")
    XCTAssertEqual(params["allow_multiple"], "false")
    XCTAssertEqual(params["mimetypes"], "application/vnd.google-apps.folder")
    XCTAssertEqual(params["allow_folder_selection"], "true")
    XCTAssertEqual(params["login_hint"], email)
    XCTAssertTrue(url.absoluteString.contains("account%2Btag"))
    XCTAssertEqual(params["code_challenge_method"], "S256")
    XCTAssertEqual(params["state"]?.count, 43)
    XCTAssertNil(params["code_verifier"])
    XCTAssertNil(params["access_token"])
    let next = parameters(URLComponents(url: auth.authorizationURL(email: email), resolvingAgainstBaseURL: false)!)
    XCTAssertNotEqual(next["state"], params["state"])
    XCTAssertNotEqual(next["code_challenge"], params["code_challenge"])
  }

  func testSingleFolderDeliveredOnlyAfterMatchingPKCEExchange() throws {
    let attempt = auth
    let url = attempt.authorizationURL(email: "user@example.org")
    let params = parameters(URLComponents(url: url, resolvingAgainstBaseURL: false)!)
    var answer: Result<String?, DrivePickerError>?
    var reply: ((Data?, URLResponse?, Error?) -> Void)?
    let callbackURL = callback(attempt, "picked_file_ids=Folder_1-2&code=example%2Bcode")
    attempt.finish(callback: callbackURL, exchange: { request, completion in
      reply = completion
      XCTAssertEqual(request.url?.absoluteString, "https://oauth2.googleapis.com/token")
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      var body = URLComponents()
      body.percentEncodedQuery = String(data: request.httpBody!, encoding: .utf8)
      let fields = self.parameters(body)
      XCTAssertEqual(fields["grant_type"], "authorization_code")
      XCTAssertEqual(fields["client_id"], self.clientID)
      XCTAssertEqual(fields["redirect_uri"], params["redirect_uri"])
      XCTAssertEqual(fields["code"], "example+code")
      XCTAssertTrue(body.percentEncodedQuery!.contains("example%2Bcode"))
      let verifier = fields["code_verifier"]!
      XCTAssertEqual(verifier.count, 43)
      let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")
      XCTAssertEqual(challenge, params["code_challenge"])
    }) { answer = $0 }
    XCTAssertNil(answer)
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    try XCTUnwrap(reply)(Data(#"{"access_token":"test-only"}"#.utf8), response, nil)
    XCTAssertEqual(try XCTUnwrap(answer).get(), "Folder_1-2")
  }

  func testCancellationAndRejectedCallbacksNeverExchange() throws {
    let attempt = auth
    let rejectExchange: DrivePickerAuthorization.Exchange = { _, _ in XCTFail("unexpected token exchange") }
    var answer: Result<String?, DrivePickerError>?
    attempt.finish(callback: callback(attempt, "error=access_denied"), exchange: rejectExchange) { answer = $0 }
    XCTAssertNil(try XCTUnwrap(answer).get())
    let valid = callback(attempt, "code=example&picked_file_ids=one").absoluteString
    let invalid = [
      valid.replacingOccurrences(of: "state=", with: "state=other"),
      valid.replacingOccurrences(of: scheme, with: "wrong-scheme"),
      valid.replacingOccurrences(of: "/oauth2redirect", with: "//elsewhere/oauth2redirect"),
      valid.replacingOccurrences(of: "/oauth2redirect", with: "/oauth2callback"),
      valid + "#fragment",
      valid + "&picked_file_ids=two",
      valid + "&code=duplicate",
      valid + "&state=duplicate",
      valid + "&error=access_denied",
      valid + "&scope=openid",
      valid.replacingOccurrences(of: "one", with: "one%2Ctwo"),
      valid.replacingOccurrences(of: "one", with: "one%2Ftwo"),
      callback(attempt, "code=example").absoluteString,
      callback(attempt, "picked_file_ids=one").absoluteString,
      callback(attempt, "error=server_error").absoluteString,
    ]
    for raw in invalid {
      answer = nil
      attempt.finish(callback: URL(string: raw)!, exchange: rejectExchange) { answer = $0 }
      XCTAssertThrowsError(try XCTUnwrap(answer).get())
    }
  }

  func testRefusedOrInvalidExchangeDoesNotReleaseFolderID() throws {
    let attempt = auth
    let url = callback(attempt, "code=example&picked_file_ids=one")
    for (status, body) in [(400, #"{"access_token":"unused"}"#), (200, "{}"), (200, #"{"access_token":""}"#)] {
      var answer: Result<String?, DrivePickerError>?
      attempt.finish(callback: url, exchange: { request, completion in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)
        completion(Data(body.utf8), response, nil)
      }) { answer = $0 }
      XCTAssertThrowsError(try XCTUnwrap(answer).get()) { XCTAssertEqual($0 as? DrivePickerError, .failed) }
    }
    var offline: Result<String?, DrivePickerError>?
    var wrongScope: Result<String?, DrivePickerError>?
    attempt.finish(callback: url, exchange: { request, completion in
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
      completion(Data(#"{"access_token":"test-only","scope":"email"}"#.utf8), response, nil)
    }) { wrongScope = $0 }
    XCTAssertThrowsError(try XCTUnwrap(wrongScope).get()) { XCTAssertEqual($0 as? DrivePickerError, .permissionDenied) }
    attempt.finish(callback: url, exchange: { _, completion in
      completion(nil, nil, URLError(.notConnectedToInternet))
    }) { offline = $0 }
    XCTAssertThrowsError(try XCTUnwrap(offline).get()) { XCTAssertEqual($0 as? DrivePickerError, .network) }
  }

  @MainActor
  func testCancellationReleasesBrowserOrExchangeAndFencesLateCallbacks() throws {
    let picker = DriveFolderPicker()
    let window = UIWindow(frame: .zero)
    for exchanging in [false, true] {
      var firstReplies: [Any?] = []
      let first = try XCTUnwrap(picker.begin(window: window) { firstReplies.append($0) })
      XCTAssertNil(picker.begin(window: window) { _ in XCTFail("unexpected concurrent reply") })
      var browserStops = 0
      var exchangeStops = 0
      first.cancelOperation = {
        browserStops += 1
        XCTAssertFalse(picker.acceptAuthorizationCallback(for: first))
      }
      if exchanging {
        XCTAssertTrue(picker.acceptAuthorizationCallback(for: first))
        XCTAssertNil(first.cancelOperation)
        first.cancelOperation = {
          exchangeStops += 1
          picker.finish(first, .failure(.network))
        }
      }
      picker.cancelPick()
      picker.cancelPick()
      XCTAssertEqual(browserStops, exchanging ? 0 : 1)
      XCTAssertEqual(exchangeStops, exchanging ? 1 : 0)
      XCTAssertEqual(firstReplies.count, 1)
      XCTAssertNil(firstReplies.first ?? nil)
      var retryReplies: [Any?] = []
      let retry = try XCTUnwrap(picker.begin(window: window) { retryReplies.append($0) })
      XCTAssertFalse(picker.acceptAuthorizationCallback(for: first))
      picker.finish(first, .success("old"))
      XCTAssertTrue(retryReplies.isEmpty)
      XCTAssertEqual(firstReplies.count, 1)
      XCTAssertTrue(picker.acceptAuthorizationCallback(for: retry))
      XCTAssertFalse(picker.acceptAuthorizationCallback(for: retry))
      picker.finish(retry, .success("new"))
      picker.cancelPick()
      XCTAssertEqual(retryReplies.count, 1)
      XCTAssertEqual((retryReplies.first ?? nil) as? String, "new")
    }
  }
}
