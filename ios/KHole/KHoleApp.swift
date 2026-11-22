import SwiftUI
import WebKit

/// k-hole for iPhone. Its screens are the phone app's own (the computer serves them; one design for both), drawn
/// edge to edge in a web view; the app adds what a web page can't do on an iPhone.
@main
struct KHoleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onOpenURL { model.open($0) }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// The phone app's address on the computer; nil until paired.
    @Published var computer: URL? = Shared.computer
    /// A page to open in the shell next (a pairing link, a k-beam step); the shell takes it and clears it.
    @Published var pending: URL?
    /// The k-chain setup sheet.
    @Published var settingUpBoard = false
    /// The shell's web view: what the app asks the computer goes through it, with the phone app's own pairing.
    weak var web: WKWebView?

    struct PageAnswer { let status: Int; let json: [String: Any] }
    /// GET one of the computer's /app/ paths as the phone app would (its cookie, same origin).
    func ask(_ path: String) async throws -> PageAnswer {
        guard let web, path.hasPrefix("/app/") else { throw URLError(.notConnectedToInternet) }
        let js = """
        const r = await fetch(path, { credentials: "same-origin", cache: "no-store" });
        return { status: r.status, body: await r.text() };
        """
        let out = try await web.callAsyncJavaScript(js, arguments: ["path": path], contentWorld: .defaultClient) as? [String: Any] ?? [:]
        let status = (out["status"] as? NSNumber)?.intValue ?? 0
        let body = (out["body"] as? String ?? "").data(using: .utf8) ?? Data()
        return PageAnswer(status: status, json: (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])
    }

    /// A computer's pairing code (what Settings > Remote > Pair a phone shows): `https://<name>:<port>/#ticket=…`.
    /// Only https, and only the fragment carries the ticket (never a request line), as the phone app expects.
    func paired(with link: URL) -> Bool {
        guard link.scheme == "https", let host = link.host, !host.isEmpty else { return false }
        var c = URLComponents(); c.scheme = "https"; c.host = host; c.port = link.port; c.path = "/"
        guard let home = c.url else { return false }
        Shared.computer = home
        computer = home
        pending = link
        return true
    }

    func forget() {
        Shared.computer = nil
        computer = nil
    }

    /// khole://share (the Share Sheet left files for k-beam), khole://kchain (set up a board), khole://open?path=/agents/
    func open(_ url: URL) {
        guard url.scheme == "khole" else { return }
        switch url.host {
        case "share": if let base = computer { pending = base.appendingPathComponent("beam/").appending(queryItems: [URLQueryItem(name: "native-share", value: "1")]) }
        case "kchain": settingUpBoard = true
        case "open":
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value ?? "/"
            if let base = computer, path.hasPrefix("/"), !path.hasPrefix("//") { pending = URL(string: path, relativeTo: base)?.absoluteURL }
        default: break
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.computer != nil {
                ShellView()
            } else {
                ConnectView()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $model.settingUpBoard) { KChainSetupView() }
    }
}
