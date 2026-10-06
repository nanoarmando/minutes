import Foundation
import Observation

/// What the meeting list needs from one note, read from its front matter only.
struct NoteSummary: Identifiable, Sendable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let date: Date
    let duration: TimeInterval
    let speakers: [String]
    let tags: [String]
    let summaryType: String?
    let recovered: Bool
    let modified: Date
}

/// The parts of a note's body the Meetings window reads.
struct NoteContent: Sendable {
    let summary: String
    let transcript: String
}

/// The notes in the current notes folder. The folder is the source of truth: the list is rebuilt from front
/// matter (first 2 KB of each file) whenever the folder changes, and full text for search is read lazily on a
/// background task and cached by modification date.
@MainActor @Observable
final class NoteIndex {
    /// Newest first.
    private(set) var notes: [NoteSummary] = []
    private(set) var folder: URL

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingRescan: Task<Void, Never>?
    @ObservationIgnored private let textCache = SearchTextCache()

    init(folder: URL) {
        self.folder = folder
        watch()
        rescan()
    }

    func setFolder(_ url: URL) {
        guard url != folder else { return }
        folder = url
        notes = []
        watch()
        rescan()
    }

    /// Rescans after a short quiet period, so a burst of file events triggers one scan.
    func rescan(after delay: Duration = .zero) {
        if watcher == nil { watch() }  // the folder may have been created since
        pendingRescan?.cancel()
        let folder = folder
        pendingRescan = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let scanned = await Task.detached(priority: .userInitiated) { Self.scan(folder) }.value
            guard !Task.isCancelled, folder == self.folder else { return }
            notes = scanned
        }
    }

    /// Notes whose tags, title, summary or transcript contain every word of the query (case- and
    /// accent-insensitive). Tags are in the front matter, so the full text covers them.
    func search(_ query: String) async -> [NoteSummary] {
        let terms = SearchTextCache.fold(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return notes }
        let matches = await textCache.matching(terms, in: notes)
        return notes.filter { matches.contains($0.id) }
    }

    func content(of note: NoteSummary) async -> NoteContent {
        await textCache.entry(for: note).content
    }

    // MARK: - Watching and scanning

    private func watch() {
        watcher?.cancel()
        watcher = nil
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.rescan(after: .milliseconds(500)) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    nonisolated private static func scan(_ folder: URL) -> [NoteSummary] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { url -> NoteSummary? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let head = String(decoding: (try? handle.read(upToCount: 2048)) ?? Data(), as: UTF8.self)
            guard let frontMatter = NoteFile.frontMatter(of: head),
                  let id = frontMatter.scalars["minutes_id"].flatMap(UUID.init(uuidString:)) else { return nil }
            let values = frontMatter.scalars
            let modified = (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            return NoteSummary(
                id: id, url: url,
                title: values["title"] ?? url.deletingPathExtension().lastPathComponent,
                date: values["date"].flatMap(NoteFile.parseISO8601) ?? modified,
                duration: values["duration"].flatMap(TimeInterval.init) ?? 0,
                speakers: frontMatter.lists["speakers"] ?? [],
                tags: frontMatter.lists["tags"] ?? [],
                summaryType: values["summary_type"],
                recovered: values["recovered"] == "true",
                modified: modified
            )
        }.sorted { $0.date > $1.date }
    }
}

/// Full text of each note, read on demand and kept until the file's modification date changes.
actor SearchTextCache {
    struct Entry {
        let modified: Date
        let folded: String
        let content: NoteContent
    }

    private var entries: [UUID: Entry] = [:]

    func matching(_ terms: [String], in notes: [NoteSummary]) -> Set<UUID> {
        Set(notes.filter { note in terms.allSatisfy(entry(for: note).folded.contains) }.map(\.id))
    }

    func entry(for note: NoteSummary) -> Entry {
        if let entry = entries[note.id], entry.modified == note.modified { return entry }
        let document = (try? String(contentsOf: note.url, encoding: .utf8)) ?? note.title
        let entry = Entry(
            modified: note.modified, folded: Self.fold(document),
            content: NoteContent(summary: NoteFile.summarySection(of: document), transcript: NoteFile.transcriptSection(of: document))
        )
        entries[note.id] = entry
        return entry
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
