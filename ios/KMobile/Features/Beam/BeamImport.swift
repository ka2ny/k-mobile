import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// File-backed import keeps videos out of the main actor and out of a single large Data allocation.
struct BeamImport: Transferable, Sendable {
    let file: BeamModel.Outgoing
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let url = received.file
            return try await Task.detached { BeamImport(file: try copy(url)) }.value
        }
    }

    nonisolated static func copyFiles(_ urls: [URL]) throws -> [BeamModel.Outgoing] {
        var files: [BeamModel.Outgoing] = []
        do {
            for url in urls {
                try Task.checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                files.append(try copy(url))
            }
            return files
        } catch { remove(files); throw error }
    }

    nonisolated private static func copy(_ url: URL) throws -> BeamModel.Outgoing {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let target = FileManager.default.temporaryDirectory.appending(path: "beam-" + UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: target)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            return .init(name: url.lastPathComponent, url: target, size: Int64(values.fileSize ?? 0),
                         type: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
        } catch { try? FileManager.default.removeItem(at: target); throw error }
    }

    nonisolated static func remove(_ files: [BeamModel.Outgoing]) {
        for file in files { try? FileManager.default.removeItem(at: file.url) }
    }
}
