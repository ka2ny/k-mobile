import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// k-beam, native: send words and files to the computer, take what it sent, and the shared folder.
/// Every result is said under the control that asked for it.
struct BeamView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mobileAccent) private var accent
    @State private var beam: BeamModel?
    @State private var words = ""
    @State private var toFolder = false
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var pickNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.gap) {
                PageHeading(
                    title: "k-beam", detail: "Send words and files to your computer, and take what it sends you.")
                if let beam {
                    content(beam)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .quietPage().quietEntrance()
        }
        .background(Design.background)
        .navigationTitle("k-beam")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await beam?.refresh() }
        .task(id: model.connectionGeneration) {
            let current = beam ?? BeamModel(app: model)
            beam = current
            while !Task.isCancelled {
                await current.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): sendFiles(urls)
            case .failure(let error): pickNote = "Couldn't open those files: \(error.localizedDescription)"
            }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task { await sendPhotos(items) }
        }
    }

    @ViewBuilder private func content(_ beam: BeamModel) -> some View {
        if let error = beam.meError {
            QuietEmptyState(title: "k-beam isn't reachable", detail: error, icon: .beam)
        }
        sendCard(beam)
        inboxCard(beam)
        if beam.folderOn { folderCard(beam) }
        clipboardCard(beam)
    }

    // MARK: Send

    private func sendCard(_ beam: BeamModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("Send to \(beam.me?.name ?? "your computer")", icon: .beam).font(.headline)
            TextField("Words, a link, a code…", text: $words, axis: .vertical)
                .lineLimit(1...6)
                .padding(12)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                .disabled(beam.sending)
            HStack(spacing: 12) {
                Button("Send text") {
                    beam.send(text: words)
                    words = ""
                }
                .buttonStyle(QuietProminentStyle())
                .disabled(beam.sending || words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                PhotosPicker(selection: $photos, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    Text("Photos")
                }
                .buttonStyle(QuietSecondaryStyle()).disabled(beam.sending)
                Button("Files") { pickNote = nil; picking = true }
                    .buttonStyle(QuietSecondaryStyle()).disabled(beam.sending)
            }
            if beam.folderOn {
                Toggle("Into the shared folder “\(beam.folderName)”", isOn: $toFolder).disabled(beam.sending)
            }
            if beam.trusted {
                Text("This phone is trusted: what you send arrives without a question.")
                    .font(.footnote).foregroundStyle(Design.muted)
            } else {
                Text("The computer asks before anything from this phone lands.")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            sendLine(beam)
            if let pickNote { note(pickNote, failed: true) }
        }.quietCard()
    }

    @ViewBuilder private func sendLine(_ beam: BeamModel) -> some View {
        switch beam.sendState {
        case .idle: EmptyView()
        case .asking(let seconds):
            HStack {
                ProgressView()
                Text("Waiting for the computer to accept (\(seconds) s)").font(.callout)
                Spacer()
                Button("Stop") { beam.stopSending() }.buttonStyle(QuietSecondaryStyle())
            }
        case .sending(let done, let total):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                    .tint(accent)
                HStack {
                    Text("\(BeamView.size(done)) of \(BeamView.size(total))")
                        .font(.callout.monospacedDigit())
                    Spacer()
                    Button("Stop") { beam.stopSending() }.buttonStyle(QuietSecondaryStyle())
                }
            }
        case .sent(let words):
            HStack { note(words, failed: false); Spacer(); dismissButton(beam) }
        case .failed(let words):
            HStack { note(words, failed: true); Spacer(); dismissButton(beam) }
        }
    }

    private func dismissButton(_ beam: BeamModel) -> some View {
        Button { beam.clearSendState() } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain).foregroundStyle(Design.muted)
            .accessibilityLabel("Dismiss")
    }

    // MARK: Inbox

    private func inboxCard(_ beam: BeamModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("From your computer").font(.headline).accessibilityAddTraits(.isHeader)
            if let error = beam.inboxError { note(error, failed: true) }
            if beam.inbox.isEmpty && beam.inboxError == nil {
                Text("Nothing waiting. Use Share… or Beam to a phone on the computer.")
                    .font(.callout).foregroundStyle(Design.muted)
            }
            ForEach(beam.inbox) { item in
                VStack(alignment: .leading, spacing: 10) {
                    if let text = item.text, !text.isEmpty {
                        Text(text).textSelection(.enabled).lineLimit(8)
                        Button("Copy") {
                            UIPasteboard.general.string = text
                            UIAccessibility.post(notification: .announcement, argument: "Copied")
                        }.buttonStyle(QuietSecondaryStyle())
                    }
                    ForEach(item.files) { file in fileRow(beam, file: file, item: item) }
                    HStack {
                        Text(Date(timeIntervalSince1970: TimeInterval(item.at)), style: .relative)
                            .font(.footnote).foregroundStyle(Design.muted)
                        Spacer()
                        Button("Dismiss") { Task { await beam.dismiss(item) } }
                            .buttonStyle(QuietSecondaryStyle()).disabled(beam.busyRows.contains(item.id))
                    }
                    if let line = beam.rowNote[item.id] { note(line, failed: true) }
                }
                .padding(.vertical, 6)
                Divider()
            }
        }.quietCard()
    }

    private func fileRow(_ beam: BeamModel, file: BeamModel.InboxFile, item: BeamModel.InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "doc").foregroundStyle(accent).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(file.name).lineLimit(2)
                    Text(BeamView.size(file.size)).font(.footnote).foregroundStyle(Design.muted)
                }
                Spacer(minLength: 0)
                if beam.busyRows.contains(file.id) {
                    ProgressView()
                } else if let url = beam.saved[file.id] {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Share \(file.name)")
                } else {
                    Button("Save") { Task { await beam.save(file, of: item) } }
                        .buttonStyle(QuietSecondaryStyle())
                }
            }
            if let line = beam.rowNote[file.id] { note(line, failed: beam.saved[file.id] == nil) }
        }
    }

    // MARK: Folder

    private func folderCard(_ beam: BeamModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("Shared folder “\(beam.folderName)”").font(.headline).accessibilityAddTraits(.isHeader)
            if let error = beam.folderError { note(error, failed: true) }
            if beam.folder.isEmpty && beam.folderError == nil {
                Text("Empty. Files you put in it on the computer show here.")
                    .font(.callout).foregroundStyle(Design.muted)
            }
            ForEach(beam.folder) { file in
                let key = "folder:" + file.name
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Image(systemName: "folder").foregroundStyle(accent).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(file.name).lineLimit(2)
                            Text(BeamView.size(file.size)).font(.footnote).foregroundStyle(Design.muted)
                        }
                        Spacer(minLength: 0)
                        if beam.busyRows.contains(key) {
                            ProgressView()
                        } else if let url = beam.saved[key] {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("Share \(file.name)")
                        } else {
                            Button("Save") { Task { await beam.save(file) } }.buttonStyle(QuietSecondaryStyle())
                        }
                    }
                    if let line = beam.rowNote[key] { note(line, failed: beam.saved[key] == nil) }
                }
            }
        }.quietCard()
    }

    // MARK: Clipboard

    private func clipboardCard(_ beam: BeamModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            Text("The computer's clipboard").font(.headline).accessibilityAddTraits(.isHeader)
            Button("Get what's copied") { Task { await beam.readClipboard() } }
                .buttonStyle(QuietSecondaryStyle())
            if let text = beam.clipText {
                Text(text).textSelection(.enabled).lineLimit(10)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                HStack {
                    Button("Copy here") {
                        UIPasteboard.general.string = text
                        UIAccessibility.post(notification: .announcement, argument: "Copied")
                    }.buttonStyle(QuietProminentStyle())
                    Button("Clear") { beam.clearClipboardResult() }.buttonStyle(QuietSecondaryStyle())
                }
            }
            if let line = beam.clipNote { note(line, failed: beam.clipText == nil) }
        }.quietCard()
    }

    // MARK: Helpers

    private func note(_ text: String, failed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(failed ? Design.caution : Design.success).frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(text).font(.callout).foregroundStyle(Design.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func sendFiles(_ urls: [URL]) {
        guard let beam else { return }
        var outgoing: [BeamModel.Outgoing] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let copy = try BeamView.copyToTemporary(url, name: url.lastPathComponent)
                outgoing.append(copy)
            } catch {
                pickNote = "Couldn't read “\(url.lastPathComponent)”: \(error.localizedDescription)"
                return
            }
        }
        guard !outgoing.isEmpty else { return }
        pickNote = nil
        beam.send(files: outgoing, toFolder: toFolder)
    }

    private func sendPhotos(_ items: [PhotosPickerItem]) async {
        defer { photos = [] }
        guard let beam else { return }
        var outgoing: [BeamModel.Outgoing] = []
        for (n, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    pickNote = "One of those photos couldn't be read."
                    return
                }
                let type = item.supportedContentTypes.first
                let ext = type?.preferredFilenameExtension ?? "jpg"
                let name = "Photo \(n + 1).\(ext)"
                let url = FileManager.default.temporaryDirectory.appending(path: "beam-" + UUID().uuidString + "." + ext)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                outgoing.append(.init(
                    name: name, url: url, size: Int64(data.count),
                    type: type?.preferredMIMEType ?? "application/octet-stream"))
            } catch {
                pickNote = "Couldn't read a photo: \(error.localizedDescription)"
                return
            }
        }
        pickNote = nil
        beam.send(files: outgoing, toFolder: toFolder)
    }

    /// The picker's URL lives only while it is open: copy the file out first.
    nonisolated static func copyToTemporary(_ url: URL, name: String) throws -> BeamModel.Outgoing {
        let target = FileManager.default.temporaryDirectory.appending(path: "beam-" + UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: target)
        let size = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return .init(name: name, url: target, size: size, type: type)
    }

    nonisolated static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
