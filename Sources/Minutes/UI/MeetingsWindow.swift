import SwiftUI

/// State of the Meetings window: search results and summary regeneration.
@MainActor @Observable
final class MeetingsModel {
    let environment: AppEnvironment
    var query = ""
    private(set) var results: [NoteSummary] = []
    private(set) var regeneratingID: UUID?
    private(set) var regenerateError: String?
    /// Bumped after a regeneration so the detail reloads the note.
    private(set) var revision = 0

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func refreshResults() async {
        results = await environment.noteIndex.search(query)
    }

    /// Writes a new summary of the given type into the note. On failure the previous summary stays.
    func regenerate(_ note: NoteSummary, type: SummaryType) async {
        guard let service = environment.summaryService else { return }
        regeneratingID = note.id
        regenerateError = nil
        defer { regeneratingID = nil }
        let transcript = await environment.noteIndex.content(of: note).transcript
        let outcome = await MeetingProcessor.summarize(transcript: transcript, title: note.title, type: type, with: service)
        if let error = outcome.error {
            regenerateError = error
            return
        }
        do {
            try NoteWriter(folder: note.url.deletingLastPathComponent()).updateSummary(of: note.url, id: note.id, with: outcome)
            environment.noteIndex.rescan()
            revision += 1
        } catch {
            regenerateError = error.localizedDescription
        }
    }
}

/// The Meetings window: the grouped meeting list and the selected meeting.
struct MeetingsWindow: View {
    @Bindable var environment: AppEnvironment
    @State private var model: MeetingsModel

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: MeetingsModel(environment: environment))
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $environment.selectedMeetingID) {
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).lineLimit(1)
                                Text("\(note.date.formatted(date: .omitted, time: .shortened)) · \(note.duration.minutesText)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .tag(note.id)
                        }
                    }
                }
            }
            .overlay {
                if model.results.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "No meetings yet" : "No matching meetings", systemImage: "text.bubble")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 270)
        } detail: {
            if let note = environment.noteIndex.notes.first(where: { $0.id == environment.selectedMeetingID }) {
                MeetingDetailView(environment: environment, model: model, note: note)
                    .id(note.id)
            } else {
                ContentUnavailableView("Select a meeting", systemImage: "doc.text")
            }
        }
        .searchable(text: $model.query, placement: .sidebar, prompt: "Search meetings and tags")
        // Integrated split view like Notes or Mail: no title text in the toolbar (the window keeps its "Meetings"
        // title for the Window menu and the app switcher) and no toolbar background or divider over the detail.
        .modifier(HiddenToolbarTitle())
        .toolbarBackground(.hidden, for: .windowToolbar)
        .task(id: SearchKey(query: model.query, notes: environment.noteIndex.notes)) { await model.refreshResults() }
    }

    private struct SearchKey: Equatable {
        let query: String
        let notes: [NoteSummary]
    }

    /// Results grouped by day (already newest first): Today, Yesterday, the weekday within the last week, else the date.
    private var groups: [(title: String, notes: [NoteSummary])] {
        let calendar = Calendar.current
        var groups: [(title: String, notes: [NoteSummary])] = []
        for note in model.results {
            let title = Self.dayTitle(note.date, calendar: calendar)
            if groups.last?.title == title {
                groups[groups.count - 1].notes.append(note)
            } else {
                groups.append((title, [note]))
            }
        }
        return groups
    }

    private static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(date: .long, time: .omitted)
    }
}

/// Removes the title text from the toolbar where macOS allows it (15+). On macOS 14 the title stays visible, since
/// clearing it with `navigationTitle("")` would also clear the window's name in the Window menu.
private struct HiddenToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
