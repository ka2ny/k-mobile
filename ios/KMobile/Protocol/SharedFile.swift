import Foundation

struct SharedFile: Decodable, Sendable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let size: Int64
    let at: Int
    let type: String?
    /// A replacement with the same name needs a fresh local copy and preview.
    var downloadKey: String { "folder:\(name):\(at):\(size)" }

    var kind: FileKind {
        let mime = type?.lowercased() ?? ""
        let ext = (name as NSString).pathExtension.lowercased()
        if mime.hasPrefix("image/") || ["heic", "jpg", "jpeg", "png", "gif", "webp", "svg"].contains(ext) { return .images }
        if mime.hasPrefix("video/") || ["mov", "mp4", "m4v", "webm"].contains(ext) { return .video }
        if mime.hasPrefix("audio/") || ["mp3", "m4a", "wav", "flac"].contains(ext) { return .audio }
        if ["zip", "gz", "tar", "7z", "rar"].contains(ext) { return .archives }
        if mime.hasPrefix("text/") || ["pdf", "txt", "md", "rtf", "doc", "docx", "csv", "xls", "xlsx", "pages", "key", "pptx"].contains(ext) { return .documents }
        return .other
    }
}

enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case all = "All files", images = "Images", documents = "Documents", video = "Video", audio = "Audio", archives = "Archives", other = "Other"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: "folder"
        case .images: "photo"
        case .documents: "doc.text"
        case .video: "film"
        case .audio: "waveform"
        case .archives: "doc.zipper"
        case .other: "doc"
        }
    }
}

struct SharedFileQuery: Equatable, Sendable {
    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case newest = "Newest first", name = "Name", largest = "Largest first"
        var id: Self { self }
    }
    var search = ""
    var kind = FileKind.all
    var sort = Sort.newest

    func apply(to files: [SharedFile]) -> [SharedFile] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { (kind == .all || $0.kind == kind) && (term.isEmpty || $0.name.localizedStandardContains(term)) }
            .sorted { a, b in
                switch sort {
                case .newest: if a.at != b.at { return a.at > b.at }
                case .largest: if a.size != b.size { return a.size > b.size }
                case .name: break
                }
                let comparison = a.name.localizedStandardCompare(b.name)
                return comparison == .orderedSame ? a.name < b.name : comparison == .orderedAscending
            }
    }
}
