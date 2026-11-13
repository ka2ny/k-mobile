import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// k-beam, native: send words and files to the computer, take what it sent, and the shared folder.
/// Every result is said under the control that asked for it.
struct BeamView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.mobileAccent) private var accent
    @State private var beam: BeamModel?
    @Binding var words: String
    @State private var toFolder = false
    @State private var picking = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var pickNote: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var section = Section.send
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    private enum Section: String, CaseIterable, Identifiable {
        case send = "Send", inbox = "Inbox", files = "Files", clipboard = "Clipboard"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Design.gap) {
                PageHeading(
                    title: "Beam", detail: "Move something between your phone and computer.")
                Picker("Beam workspace", selection: $section) {
                    ForEach(Section.allCases) { section in Text(section.rawValue).tag(section) }
                }.pickerStyle(.segmented)
                if let beam {
                    content(beam)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .quietPage().quietEntrance()
        }
        .background(Design.background)
        .navigationTitle("Beam")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await beam?.refresh() }
        .task(id: "\(model.connectionGeneration)-\(scenePhase)") {
            beam?.stop()
            guard scenePhase == .active else { return }
            let current = BeamModel(app: model)
            beam = current
            while !Task.isCancelled {
                await current.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
        .onDisappear { importTask?.cancel(); beam?.stop() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): sendFiles(urls)
            case .failure(let error): pickNote = "Couldn't open those files: \(error.localizedDescription)"
            }
        }
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            importTask?.cancel()
            importTask = Task { await sendPhotos(items) }
        }
    }

    @ViewBuilder private func content(_ beam: BeamModel) -> some View {
        if let error = beam.meError {
            QuietEmptyState(title: "k-beam isn't reachable", detail: error, icon: .beam)
        }
        switch section {
        case .send: sendCard(beam)
        case .inbox: inboxCard(beam)
        case .files:
            if beam.folderOn { folderCard(beam) }
            else {
                QuietEmptyState(title: "Your shared folder", detail: "Enable the shared folder in Settings → k-beam on your computer. Files placed there will appear here.", icon: .files)
            }
        case .clipboard: clipboardCard(beam)
        }
    }

    // MARK: Send

    private func sendCard(_ beam: BeamModel) -> some View {
        VStack(alignment: .leading, spacing: Design.gap) {
            MobileLabel("Send to \(beam.me?.name ?? "your computer")", icon: .beam).font(.headline)
            TextField("Words, a link, a code…", text: $words, axis: .vertical)
                .lineLimit(1...6)
                .padding(12)
                .background(Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius))
                .disabled(beam.sending || importing)
            HStack(spacing: 12) {
                Button("Send text") {
                    let submitted = words
                    beam.send(text: submitted) {
                        if words == submitted { words = "" }
                    }
                }
                .buttonStyle(QuietProminentStyle())
                .disabled(beam.sending || words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                PhotosPicker(selection: $photos, maxSelectionCount: 20, matching: .any(of: [.images, .videos])) {
                    Text("Photos")
                }
                .buttonStyle(QuietSecondaryStyle()).disabled(beam.sending || importing)
                Button("Files") { pickNote = nil; picking = true }
                    .buttonStyle(QuietSecondaryStyle()).disabled(beam.sending || importing)
            }
            if beam.folderOn {
                Toggle("Into the shared folder “\(beam.folderName)”", isOn: $toFolder).disabled(beam.sending || importing)
            }
            if beam.trusted {
                Text("This phone is trusted: what you send arrives without a question.")
                    .font(.footnote).foregroundStyle(Design.muted)
            } else {
                Text("The computer asks before anything from this phone lands.")
                    .font(.footnote).foregroundStyle(Design.muted)
            }
            if importing {
                ProgressView("Preparing files…")
                Button("Cancel import", role: .cancel) { importTask?.cancel() }
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

    private func folderCard(_ beam: BeamModel) -> some View { BeamFilesView(beam: beam) }

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
        guard let beam, !importing, !beam.sending else { return }
        let destination = toFolder
        importTask = Task {
            importing = true
            defer { importing = false }
            do {
                let worker = Task.detached { try BeamImport.copyFiles(urls) }
                let outgoing = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { BeamImport.remove(outgoing); return }
                pickNote = nil
                beam.send(files: outgoing, toFolder: destination)
            } catch { if !Task.isCancelled { pickNote = "Couldn't read those files: \(error.localizedDescription)" } }
        }
    }

    private func sendPhotos(_ items: [PhotosPickerItem]) async {
        guard let beam, !importing, !beam.sending else { return }
        let destination = toFolder
        importing = true
        var outgoing: [BeamModel.Outgoing] = []
        var handedOff = false
        defer {
            importing = false; photos = []
            if !handedOff { BeamImport.remove(outgoing) }
        }
        do {
            for item in items {
                try Task.checkCancellation()
                guard let imported = try await item.loadTransferable(type: BeamImport.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                outgoing.append(imported.file)
                try Task.checkCancellation()
            }
            pickNote = nil
            handedOff = true
            beam.send(files: outgoing, toFolder: destination)
        } catch { if !Task.isCancelled { pickNote = "Couldn't import media: \(error.localizedDescription)" } }
    }

    nonisolated static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
