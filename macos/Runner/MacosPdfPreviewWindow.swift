import AppKit
import WebKit
import ObjectiveC.runtime

/// Hosts the capability-protected PDF viewer over its opener WebView.
/// A separate WebView avoids WebKit's mixed-content block on HTTP iframes.
final class MacosPdfPreviewWindow: NSObject, WKUIDelegate, WKNavigationDelegate {
  private typealias CreateView = @convention(c) (
    AnyObject, Selector, WKWebView, WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures
  ) -> Unmanaged<AnyObject>?
  private static let selector = NSSelectorFromString(
    "webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:"
  )
  private static var installedClasses = Set<ObjectIdentifier>()
  private static var allowedURL: URL?
  private static var overlays: [MacosPdfPreviewWindow] = []
  private weak var opener: WKWebView?
  private weak var viewer: WKWebView?
  private let url: URL

  private init(url: URL) { self.url = url }

  static func setViewerURL(_ value: String) -> Bool {
    guard let parts = URLComponents(string: value), parts.scheme == "http",
          parts.host == "127.0.0.1", let port = parts.port, (1...65535).contains(port),
          parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
      return false
    }
    let path = parts.path.split(separator: "/", omittingEmptySubsequences: true)
    guard path.count == 2, path[1] == "index.html", path[0].count == 43,
          path[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
          parts.path == "/\(path[0])/index.html", let url = parts.url else { return false }
    allowedURL = url
    return true
  }

  static func install(on delegateClass: AnyClass) {
    let identity = ObjectIdentifier(delegateClass)
    guard !installedClasses.contains(identity),
          let method = class_getInstanceMethod(delegateClass, selector) else { return }
    installedClasses.insert(identity)
    let original = unsafeBitCast(method_getImplementation(method), to: CreateView.self)
    let block: @convention(block) (
      AnyObject, WKWebView, WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures
    ) -> WKWebView? = { delegate, opener, configuration, action, features in
      if let allowed = allowedURL, action.request.url == allowed {
        let origin = action.sourceFrame.securityOrigin
        guard origin.protocol == "https", origin.host == "gakujo.iess.niigata-u.ac.jp" else {
          return nil
        }
        return open(url: allowed, configuration: configuration, opener: opener)
      }
      return original(delegate, selector, opener, configuration, action, features)?
        .takeUnretainedValue() as? WKWebView
    }
    let implementation = imp_implementationWithBlock(unsafeBitCast(block, to: AnyObject.self))
    if !class_addMethod(delegateClass, selector, implementation, method_getTypeEncoding(method)) {
      method_setImplementation(method, implementation)
    }
  }

  static func setVisible(_ visible: Bool, mainWindow: NSWindow?) {
    for owner in overlays {
      owner.viewer?.isHidden = !visible
      if visible, let viewer = owner.viewer {
        viewer.window?.makeFirstResponder(viewer)
      } else if let opener = owner.opener {
        opener.window?.makeFirstResponder(opener)
      }
    }
  }

  static func opener(for viewer: WKWebView) -> WKWebView? {
    overlays.first { $0.viewer === viewer }?.opener
  }

  private static func open(url: URL, configuration: WKWebViewConfiguration, opener: WKWebView) -> WKWebView {
    let owner = MacosPdfPreviewWindow(url: url)
    // Do not expose the main page's native script-message channels to a PDF
    // viewer. WebKit still uses the supplied configuration for opener links.
    configuration.userContentController = WKUserContentController()
    let webView = WKWebView(frame: opener.bounds, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    webView.allowsLinkPreview = false
    owner.opener = opener
    owner.viewer = webView
    webView.uiDelegate = owner
    webView.navigationDelegate = owner
    overlays.append(owner)
    opener.addSubview(webView)
    opener.window?.makeFirstResponder(webView)
    return webView
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    decisionHandler(navigationAction.request.url == url ? .allow : .cancel)
  }

  func webViewDidClose(_ webView: WKWebView) {
    webView.removeFromSuperview()
    if let opener = opener {
      opener.window?.makeFirstResponder(opener)
    }
    Self.overlays.removeAll { $0 === self }
  }
}
