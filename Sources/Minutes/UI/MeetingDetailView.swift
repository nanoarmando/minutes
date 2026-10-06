import SwiftUI

/// One meeting as a reading layout (design D14): header with actions, tag chips, and the Summary or Transcript.
struct MeetingDetailView: View {
    let environment: AppEnvironment
    let model: MeetingsModel
    let note: NoteSummary
    @State private var content: NoteContent?
    @State private var showsTranscript = false
    @State private var isAddingTag = false
    @State private var newTag = ""
    @State private var tagError: String?
    /// The last automatic tagging error recorded in the sidecar.
    @State private var taggingFailure: String?
    /// The instructions saved for this meeting (sidecar), used to pre-fill "Correct with instructions…".
    @State private var instructions: String?
    @State private var isCorrecting = false
    @State private var isRetagging = false
    /// The summary language stored in the sidecar ("en", "es"); nil for Auto.
    @State private var language: String?
    @State private var editedTitle: String?
    @State private var titleError: String?
    @FocusState private var isTitleFocused: Bool

    private static let languageChoices: [(code: String?, name: String)] = [(nil, "Auto"), ("en", "English"), ("es", "Español")]

    private static let readingWidth: CGFloat = 720

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                tags
                Picker("View", selection: $showsTranscript) {
                    Text("Summary").tag(false)
                    Text("Transcript").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if showsTranscript {
                    TranscriptView(transcript: content?.transcript ?? "")
                } else {
                    summaryTypes
                    summary
                }
            }
            .frame(maxWidth: Self.readingWidth, alignment: .leading)
            // No top padding: the hidden toolbar already reserves that space, so the title lines up with the sidebar search.
            .padding([.horizontal, .bottom], 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: "\(note.modified)-\(model.revision)") {
            content = await environment.noteIndex.content(of: note)
            let sidecar = NoteWriter(folder: note.url.deletingLastPathComponent()).readSidecar(id: note.id)
            taggingFailure = sidecar?.tagging?.lastError
            instructions = sidecar?.instructions
            language = sidecar?.language
        }
        .sheet(isPresented: $isCorrecting) {
            CorrectionSheet(environment: environment, model: model, note: note, instructions: instructions ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                title
                Text(meta).foregroundStyle(.secondary)
                if note.recovered {
                    Label("Recovered after Minutes quit unexpectedly", systemImage: "exclamationmark.arrow.circlepath")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            // Borderless buttons have no pressed state that can stick. The actions that switch to another app run on
            // the next turn of the run loop, after the click has been fully handled.
            HStack(spacing: 14) {
                ActionButton("Correct with instructions…", systemImage: "wand.and.stars") { isCorrecting = true }
                ActionButton("Open in editor", systemImage: "square.and.pencil") { NSWorkspace.shared.open(note.url) }
                ActionButton("Copy summary", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content?.summary ?? "", forType: .string)
                }
                ActionButton("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
            }
            .padding(.top, 10)
        }
    }

    private var isBusy: Bool { model.regeneratingID == note.id || isRetagging }

    /// Click to edit; Enter saves, Escape or leaving the field cancels.
    @ViewBuilder private var title: some View {
        if let editedTitle {
            TextField("Title", text: Binding(get: { editedTitle }, set: { self.editedTitle = $0 }))
                .font(.largeTitle.weight(.semibold))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit(saveTitle)
                .onExitCommand { self.editedTitle = nil }
                .onChange(of: isTitleFocused) { _, focused in if !focused { self.editedTitle = nil } }
                .onAppear { isTitleFocused = true }
        } else {
            Text(note.title).font(.largeTitle.weight(.semibold))
                .onTapGesture {
                    guard !isBusy else { return }
                    titleError = nil
                    editedTitle = note.title
                }
        }
        if let titleError { Text(titleError).font(.caption).foregroundStyle(.red) }
    }

    private func saveTitle() {
        let title = editedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        editedTitle = nil
        guard !title.isEmpty, title != note.title, !isBusy else { return }
        let writer = NoteWriter(folder: note.url.deletingLastPathComponent(), fileNamePattern: environment.preferences.fileNamePattern)
        do {
            _ = try writer.updateTitle(of: note.url, date: note.date, to: title)
        } catch {
            titleError = error.localizedDescription
        }
        environment.noteIndex.rescan()
    }

    /// "Mon, Oct 5, 2026 · 09:30 · 11 min · You + 4 speakers"
    private var meta: String {
        var parts = [note.date.formatted(date: .abbreviated, time: .omitted), note.date.formatted(date: .omitted, time: .shortened), note.duration.minutesText]
        let others = note.speakers.filter { $0 != TranscriptAssembler.you }.count
        if note.speakers.contains(TranscriptAssembler.you) {
            parts.append(others == 0 ? "You" : "You + \(others) speaker\(others == 1 ? "" : "s")")
        } else if others > 0 {
            parts.append("\(others) speaker\(others == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tags

    private var tags: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(note.tags, id: \.self) { tag in
                    let isClient = tag.hasPrefix("client/")
                    HStack(spacing: 4) {
                        Text(tag)
                        Button("Remove \(tag)", systemImage: "xmark") { setTag(tag, present: false) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).imageScale(.small)
                    }
                    .foregroundStyle(isClient ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .chip()
                    .background(isClient ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary), in: Capsule())
                }
                Button("+ Add tag") { isAddingTag = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .chip()
                    .overlay(Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3])))
                    .popover(isPresented: $isAddingTag, arrowEdge: .bottom) { addTagPopover }
                Button(isRetagging ? "Re-tagging…" : "Re-tag") { retag() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .chip()
                    .disabled(isRetagging)
            }
            if let tagError { Text(tagError).font(.caption).foregroundStyle(.red) }
            if let taggingFailure, !isRetagging {
                HStack {
                    Label("Tagging failed: \(taggingFailure)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Re-tag") { retag() }
                }
            }
        }
    }

    private var addTagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("New tag", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addTag(newTag) }
            ForEach(suggestions.prefix(8), id: \.self) { tag in
                Button(tag) { addTag(tag) }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    /// Tags used in other notes that this note does not have yet, filtered by what is typed.
    private var suggestions: [String] {
        Set(environment.existingTags).subtracting(note.tags).sorted()
            .filter { newTag.isEmpty || $0.localizedCaseInsensitiveContains(newTag) }
    }

    private func addTag(_ tag: String) {
        let cleaned = tag.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        guard !cleaned.isEmpty else { return }
        setTag(cleaned, present: true)
        newTag = ""
        isAddingTag = false
    }

    private func setTag(_ tag: String, present: Bool) {
        do { try environment.setTag(tag, present: present, on: note) } catch { tagError = error.localizedDescription }
    }

    private func retag() {
        isRetagging = true
        Task {
            taggingFailure = await environment.retag(note)
            isRetagging = false
        }
    }

    // MARK: - Summary

    @ViewBuilder private var summaryTypes: some View {
        let isRegenerating = model.regeneratingID == note.id
        HStack(spacing: 6) {
            FlowLayout(spacing: 6) {
                ForEach(environment.summaryTypes.types) { type in
                    let isCurrent = type.id == note.summaryType
                    Button(type.name) { regenerate(type) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
                }
            }
            Spacer()
            Menu("Language: \(Self.languageChoices.first { $0.code == language }?.name ?? "Auto")") {
                ForEach(Self.languageChoices, id: \.name) { choice in
                    Button(choice.name) { setLanguage(choice.code) }
                }
            }
            .fixedSize()
            .disabled(isRetagging)
            Button("Regenerate", systemImage: "arrow.clockwise") {
                regenerate(currentType)
            }
            .buttonStyle(.borderedProminent)
        }
        .disabled(isRegenerating)
        if isRegenerating {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Regenerating with \(environment.preferences.summaryModel)…").foregroundStyle(.secondary)
            }
        } else if let error = model.regenerateError {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    @ViewBuilder private var summary: some View {
        let text = content?.summary ?? ""
        // A note without a summary holds a one-line italic placeholder (see SummaryOutcome.sectionBody).
        if text.hasPrefix("_"), text.hasSuffix("_"), !text.contains("\n") {
            Label(String(text.dropFirst().dropLast()), systemImage: "text.badge.star")
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        } else {
            MarkdownText(text)
        }
    }

    /// Stores the choice first, so it is kept for the next attempt when the summary or tagging fails.
    private func setLanguage(_ code: String?) {
        guard environment.summaryService != nil else { return regenerate(currentType) }
        do {
            try NoteWriter(folder: note.url.deletingLastPathComponent()).updateSidecar(id: note.id) { $0.language = code }
        } catch {
            tagError = error.localizedDescription
            return
        }
        language = code
        Task {
            await model.regenerate(note, type: currentType)
            if model.regenerateError == nil { retag() }
        }
    }

    private var currentType: SummaryType {
        environment.summaryTypes.type(id: note.summaryType ?? "") ?? environment.summaryTypes.defaultType
    }

    private func regenerate(_ type: SummaryType) {
        guard environment.summaryService != nil else {
            if confirm("A summary provider is needed", "Configure a provider in Settings › Summaries to generate summaries.", action: "Open Summaries Settings") {
                environment.showSettings(.summaries)
            }
            return
        }
        Task { await model.regenerate(note, type: type) }
    }
}

private extension View {
    /// The shared size of everything in the tag row, so chips and buttons line up: same font, height and centering.
    func chip() -> some View {
        font(.callout).padding(.horizontal, 10).frame(height: 26)
    }
}

/// A borderless icon button with a tooltip; its action runs after the click is fully handled.
private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: @MainActor () -> Void

    init(_ title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage) {
            Task { @MainActor in action() }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .imageScale(.large)
        .help(title)
    }
}

/// Transcript lines "[HH:MM:SS] Speaker: text": monospaced time, the speaker in a stable color, then the text.
private struct TranscriptView: View {
    let transcript: String
    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    private struct Line: Identifiable {
        let id: Int
        let time: String
        let speaker: String
        let text: String
    }

    var body: some View {
        let lines = Self.parse(transcript)
        let colors = Self.colors(for: lines)
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(line.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if !line.speaker.isEmpty {
                            Text(line.speaker).font(.callout.weight(.semibold)).foregroundStyle(colors[line.speaker] ?? .primary)
                        }
                        Text(line.text).lineSpacing(2)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private static func parse(_ transcript: String) -> [Line] {
        transcript.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.enumerated().map { index, raw in
            if let match = raw.firstMatch(of: /^\[(\d{2}:\d{2}:\d{2})\] ([^:]+): (.*)$/) {
                return Line(id: index, time: String(match.1), speaker: String(match.2), text: String(match.3))
            }
            return Line(id: index, time: "", speaker: "", text: raw)
        }
    }

    /// Colors assigned in order of first appearance, so each speaker keeps one color throughout.
    private static func colors(for lines: [Line]) -> [String: Color] {
        var colors: [String: Color] = [:]
        for line in lines where !line.speaker.isEmpty && colors[line.speaker] == nil {
            colors[line.speaker] = palette[colors.count % palette.count]
        }
        return colors
    }
}

/// Renders summary Markdown block by block: headings, bullet and numbered lists (nested by indentation),
/// `- [ ]` / `- [x]` tasks as checkboxes, and inline bold, italic, code and links.
struct MarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func row(_ raw: String) -> some View {
        let indent = CGFloat(raw.prefix { $0 == " " }.count / 2) * 18
        let line = raw.trimmingCharacters(in: .whitespaces)
        if let heading = line.firstMatch(of: /^(#{1,6})\s+(.*)/) {
            inline(String(heading.2))
                .font(heading.1.count <= 1 ? .title2.weight(.semibold) : heading.1.count == 2 ? .title3.weight(.semibold) : .headline)
                .padding(.top, 10)
        } else if let task = line.firstMatch(of: /^[-*] \[( |x|X)\] (.*)/) {
            item(marker: Image(systemName: task.1 == " " ? "square" : "checkmark.square"), text: String(task.2), indent: indent)
        } else if let bullet = line.firstMatch(of: /^[-*] (.*)/) {
            item(marker: Image(systemName: "circle.fill").resizable().frame(width: 5, height: 5), text: String(bullet.1), indent: indent)
        } else if let numbered = line.firstMatch(of: /^(\d+)\. (.*)/) {
            item(marker: Text("\(String(numbered.1))."), text: String(numbered.2), indent: indent)
        } else if !line.isEmpty {
            inline(line).lineSpacing(3)
        }
    }

    private func item<Marker: View>(marker: Marker, text: String, indent: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker.foregroundStyle(.secondary).frame(minWidth: 14)
            inline(text).lineSpacing(3)
        }
        .padding(.leading, indent)
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }
}

/// Lays out views left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrange(subviews, width: bounds.width).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + lineHeight), origins)
    }
}
