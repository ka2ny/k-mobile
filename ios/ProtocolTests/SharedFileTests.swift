import Testing
@testable import KMobileProtocol

struct SharedFileTests {
    private let files = [
        SharedFile(name: "Photo 10.HEIC", size: 100, at: 2, type: nil),
        SharedFile(name: "Photo 2.jpg", size: 500, at: 2, type: "image/jpeg"),
        SharedFile(name: "Brief.pdf", size: 300, at: 4, type: "application/pdf"),
        SharedFile(name: "clip.mov", size: 900, at: 1, type: nil)
    ]

    @Test func filtersCombineTypeAndTrimmedSearch() {
        var query = SharedFileQuery()
        query.kind = .images; query.search = " photo "
        #expect(query.apply(to: files).map(\.name) == ["Photo 2.jpg", "Photo 10.HEIC"])
        query.kind = .documents
        #expect(query.apply(to: files).isEmpty)
    }
    @Test func orderingIsDeterministicAndNatural() {
        var query = SharedFileQuery()
        #expect(query.apply(to: files).first?.name == "Brief.pdf")
        query.sort = .largest
        #expect(query.apply(to: files).first?.name == "clip.mov")
        query.sort = .name
        #expect(query.apply(to: files).suffix(2).map(\.name) == ["Photo 2.jpg", "Photo 10.HEIC"])
    }
    @Test func extensionFallbackHandlesMissingMIME() {
        #expect(files.first?.kind == .images)
        #expect(files.last?.kind == .video)
    }
    @Test func updatedFilesDoNotReuseOldPreview() {
        let before = SharedFile(name: "Brief.pdf", size: 300, at: 4, type: nil)
        let after = SharedFile(name: "Brief.pdf", size: 300, at: 5, type: nil)
        #expect(before.id == after.id)
        #expect(before.downloadKey != after.downloadKey)
    }
}
