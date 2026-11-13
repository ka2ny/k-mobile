import QuickLook
import SwiftUI

struct BeamFileDetail: View {
    let beam: BeamModel
    let file: SharedFile
    @Environment(\.dismiss) private var dismiss
    @State private var operation: Task<Void, Never>?
    @State private var preview: URL?
    private var key: String { file.downloadKey }
    private var canPreview: Bool {
        let size = beam.saved[key] == nil ? file.size : (beam.savedSizes[key] ?? Int64.max)
        return size <= 32 * 1024 * 1024
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(file.name, systemImage: file.kind.symbol).font(.headline).textSelection(.enabled)
                    LabeledContent("Size", value: BeamView.size(file.size))
                    LabeledContent("Type", value: file.type ?? file.kind.rawValue)
                    LabeledContent("Modified") { Text(Date(timeIntervalSince1970: Double(file.at)), format: .dateTime.year().month().day().hour().minute()) }
                }
                Section {
                    if let url = beam.saved[key] {
                        if canPreview { Button("Preview", systemImage: "eye") { preview = url } }
                        ShareLink(item: url) { Label("Share or save a copy", systemImage: "square.and.arrow.up") }
                    } else if beam.busyRows.contains(key) {
                        ProgressView("Downloading…")
                        Button("Cancel download", role: .cancel) { operation?.cancel() }
                    } else {
                        Button(canPreview ? "Save & preview" : "Save to Files", systemImage: "arrow.down.circle") {
                            operation = Task {
                                await beam.save(file)
                                guard !Task.isCancelled else { return }
                                if canPreview { preview = beam.saved[key] }
                            }
                        }
                    }
                    if let note = beam.rowNote[key] { Text(note).font(.callout).foregroundStyle(Design.muted) }
                } footer: {
                    if !canPreview { Text("Save this file to open it in another app. In-app previews are limited to 32 MB.") }
                }
            }
            .quietList().navigationTitle("File details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .quickLookPreview($preview)
        }
        .onDisappear { operation?.cancel() }
    }
}
