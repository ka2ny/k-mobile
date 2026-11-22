import Foundation
import WebKit

/// What the Share Sheet left (KHoleShare puts files and text in the App Group's share-inbox and opens khole://share):
/// the app opens k-beam, and once k-beam says it is ready (`share-ready`) hands it each file, which k-beam sends to
/// the computer as anything picked on the phone (remote/share/app.js `kholeBeamReceive`).
enum ShareInbox {
    static let maxBytes = 200 << 20        // what one share may hand over (k-beam's own limits still apply)

    @MainActor
    static func deliver(to web: WKWebView?) {
        guard let web, let dir = Shared.inbox,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path), !names.isEmpty else { return }
        var total = 0
        for name in names.sorted() where !name.hasPrefix(".") {
            let file = dir.appendingPathComponent(name)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), total + data.count <= maxBytes else { continue }
            total += data.count
            let shown = String(name.drop { $0 != "-" }.dropFirst())      // "<n>-<original name>"
            let item: [String: Any] = ["name": shown.isEmpty ? name : shown, "type": mime(for: shown), "data": data.base64EncodedString()]
            guard let json = try? JSONSerialization.data(withJSONObject: item), let text = String(data: json, encoding: .utf8) else { continue }
            web.evaluateJavaScript("window.kholeBeamReceive && window.kholeBeamReceive(\(text))")
        }
    }

    static func mime(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
