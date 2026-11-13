import Foundation

enum AssistantAttachment {
    nonisolated static func read(_ url: URL, limit: Int) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: max(0, limit) + 1) ?? Data()
        guard data.count <= limit else { throw ImportError.tooLarge }
        return data
    }
    enum ImportError: LocalizedError {
        case tooLarge
        var errorDescription: String? { "Attachments can total up to 20 MB. Choose a smaller file or remove an attachment." }
    }
}
