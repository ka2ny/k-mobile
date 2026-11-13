import QuickLook
import SwiftUI

struct BeamFilesView: View {
    let beam: BeamModel
    @State private var query = SharedFileQuery()
    @State private var filtered: [SharedFile] = []
    @State private var limit = 60
    @State private var grid = false
    @State private var selected: SharedFile?
    @Environment(\.mobileAccent) private var accent
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Design.gap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(beam.folderName).font(.title2.weight(.semibold))
                    Text("\(filtered.count) files").font(.subheadline).foregroundStyle(Design.muted)
                }
                Spacer()
                Button(grid ? "Show list" : "Show grid", systemImage: grid ? "list.bullet" : "square.grid.2x2") { grid.toggle() }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            TextField("Search files", text: $query.search).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("files.search")
            ViewThatFits(in: .horizontal) {
                HStack { filters; Spacer(); sortMenu }
                VStack(alignment: .leading) { filters; sortMenu }
            }
            if let error = beam.folderError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Design.caution)
            }
            if filtered.isEmpty {
                ContentUnavailableView(beam.folder.isEmpty ? "Your folder is empty" : "No matching files",
                    systemImage: "folder", description: Text(beam.folder.isEmpty ? "Add files on your computer, or send them to this folder from Beam." : "Try another name or file type."))
            }
            LazyVGrid(columns: grid && !textSize.isAccessibilitySize ? [GridItem(.adaptive(minimum: 145), spacing: 12)] : [GridItem(.flexible())], spacing: 12) {
                ForEach(filtered.prefix(limit)) { file in
                    Button { selected = file } label: { fileTile(file) }.buttonStyle(.plain)
                }
            }
            if filtered.count > limit {
                Button("Show next \(min(60, filtered.count - limit)) files") { limit += 60 }
                    .buttonStyle(QuietSecondaryStyle())
            }
        }
        .onChange(of: query, initial: true) { update() }
        .onChange(of: beam.folder) { update() }
        .sheet(item: $selected) { file in BeamFileDetail(beam: beam, file: file) }
        .quietStateAnimation(value: grid)
    }

    private var filters: some View {
        Picker("File type", selection: $query.kind) {
            ForEach(FileKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
        }.pickerStyle(.menu)
    }
    private var sortMenu: some View {
        Picker("Sort", selection: $query.sort) {
            ForEach(SharedFileQuery.Sort.allCases) { sort in Text(sort.rawValue).tag(sort) }
        }.pickerStyle(.menu)
    }
    private func update() { filtered = query.apply(to: beam.folder); limit = 60 }

    private func fileTile(_ file: SharedFile) -> some View {
        let compact = grid && !textSize.isAccessibilitySize
        let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Image(systemName: file.kind.symbol).font(compact ? .largeTitle : .title2)
                .foregroundStyle(accent).frame(width: 38, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.body.weight(.medium)).lineLimit(2).truncationMode(.middle)
                Text(BeamView.size(file.size)).font(.footnote).foregroundStyle(Design.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Image(systemName: "chevron.right").foregroundStyle(Design.muted).accessibilityHidden(true) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.surface, in: .rect(cornerRadius: Design.controlRadius))
        .accessibilityElement(children: .combine)
    }
}
