import SwiftUI
import WebKit
import WidgetKit

/// The phone app itself, edge to edge: the pages the computer serves (Home, Remote, k-beam, Agents, Projects,
/// Assistant), in a web view that keeps its own storage (its pairing) and stays on the computer's address.
/// The page learns it runs in the app (`window.kholeNative`) and asks the app for what only it can do.
struct ShellView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        WebShell(model: model).ignoresSafeArea()
    }
}

struct WebShell: UIViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Bridge { Bridge(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true              // Remote's live picture
        config.mediaTypesRequiringUserActionForPlayback = []
        let ucc = config.userContentController
        ucc.add(context.coordinator, name: "khole")
        ucc.addUserScript(WKUserScript(source: Bridge.announce, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never   // the page lays out its own safe areas (viewport-fit=cover)
        web.allowsBackForwardNavigationGestures = false           // the phone app has its own edge swipe
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        if #available(iOS 16.4, *) { web.isInspectable = true }
        context.coordinator.web = web
        model.web = web
        if let start = model.pending ?? model.computer { web.load(URLRequest(url: start)); model.pending = nil }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if let next = model.pending {
            model.pending = nil
            web.load(URLRequest(url: next))
        }
    }

    @MainActor
    final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let model: AppModel
        weak var web: WKWebView?
        init(model: AppModel) { self.model = model }

        /// What the page sees: the app's features, so switch.js shows Set up a k-chain and the like only here.
        static let announce = """
        window.kholeNative = Object.freeze({ version: 1, features: ["kchain", "widgets", "share", "haptics"],
          post: (m) => window.webkit.messageHandlers.khole.postMessage(m) });
        """

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            // only the computer's own pages speak to the app
            guard let origin = model.computer, message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.host == origin.host,
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "readings": readings(body)
            case "kchain": model.settingUpBoard = true
            case "haptic":
                switch body["style"] as? String {
                case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
                case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
                default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            case "unpaired": model.forget()
            case "share-ready": ShareInbox.deliver(to: web)
            default: break
            }
        }

        /// Home's readings (hub.js, from /app/widgets it already reads): kept for the widgets, which never ask the computer.
        private func readings(_ b: [String: Any]) {
            var r = Readings(at: Date())
            r.needs = b["needs"] as? Int ?? 0
            r.working = b["working"] as? Int ?? 0
            r.first = String((b["first"] as? String ?? "").prefix(60))
            r.assistant = String((b["assistant"] as? String ?? "").prefix(40))
            if let bat = b["battery"] as? [String: Any], let level = bat["level"] as? Int {
                r.battery = .init(level: max(0, min(100, level)), charging: bat["charging"] as? Bool ?? false)
            }
            r.storageFree = b["storageFree"] as? Double
            r.memoryPercent = b["memory"] as? Int
            if r != Readings.load().map({ var o = $0; o.at = r.at; return o }) {
                r.save()
                WidgetCenter.shared.reloadAllTimelines()
            } else { r.save() }
        }

        // the computer's pages stay here; anything else opens in Safari
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" || url.host == model.computer?.host { return decisionHandler(.allow) }
            if action.targetFrame?.isMainFrame ?? true, ["https", "http", "mailto", "tel"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
        // window.open (k-beam's links): the same rule
        func webView(_ web: WKWebView, createWebViewWith c: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if url.host == model.computer?.host { web.load(action.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }
        // the camera and microphone the pages ask for (the Assistant's voice, k-beam's camera) go to the system's own prompt
        func webView(_ web: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == model.computer?.host ? .prompt : .deny)
        }
        func webViewWebContentProcessDidTerminate(_ web: WKWebView) { web.reload() }
    }
}
