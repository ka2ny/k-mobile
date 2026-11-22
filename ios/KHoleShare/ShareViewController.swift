import UIKit
import UniformTypeIdentifiers

/// The Share Sheet's k-beam: whatever you share from another app (photos, videos, files, text, a link) is put in the
/// App Group's share-inbox, then k-hole opens on k-beam, which sends it to the computer as anything picked on the
/// phone (it asks first unless the phone is trusted, as k-beam always does). Nothing leaves the phone from here.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        let label = UILabel()
        label.text = "sending to k-beam…"
        label.textColor = UIColor(red: 0.933, green: 0.945, blue: 0.925, alpha: 1)
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        Task { await collect() }
    }

    private func collect() async {
        guard let inbox = Shared.inbox else { return done(open: false) }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var n = 0
        for item in items {
            for provider in item.attachments ?? [] {
                n += 1
                if let url = await fileURL(provider) {
                    let target = inbox.appendingPathComponent("\(n)-\(url.lastPathComponent)")
                    try? FileManager.default.removeItem(at: target)
                    try? FileManager.default.copyItem(at: url, to: target)
                } else if let text = await plainText(provider) {
                    try? text.data(using: .utf8)?.write(to: inbox.appendingPathComponent("\(n)-shared.txt"))
                }
            }
        }
        done(open: n > 0)
    }

    private func fileURL(_ p: NSItemProvider) async -> URL? {
        for type in [UTType.image, .movie, .pdf, .data] where p.hasItemConformingToTypeIdentifier(type.identifier) {
            if let url = try? await p.loadItem(forTypeIdentifier: type.identifier) as? URL, url.isFileURL { return url }
        }
        return nil
    }

    private func plainText(_ p: NSItemProvider) async -> String? {
        if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { return url.absoluteString }
        if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { return text }
        return nil
    }

    /// An extension can't open its app directly; the responder chain's openURL does, as Apple's own extensions do.
    private func done(open: Bool) {
        if open, let url = URL(string: "khole://share") {
            var r: UIResponder? = self
            while let next = r {
                if let app = next as? UIApplication { app.open(url); break }
                r = next.next
            }
        }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
