import AppKit
import EventKit
import Observation

/// Calendar data stored with a meeting (session.json, then the note's front matter).
struct EventInfo: Codable, Sendable, Equatable {
    var title: String
    var calendar: String
    var attendees: [String]
    var meetingLink: String?
}

/// Calendar access, followed calendars, the event lookup at recording start and start suggestions (design D9).
/// Access is requested only by `enable()`, called from Settings › Calendar.
@MainActor @Observable
final class CalendarService {
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
    private static let lookAhead: TimeInterval = 7 * 24 * 3600
    private static let wakeGrace: TimeInterval = 5 * 60

    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    /// Calendars grouped by account (`source.title`), for Settings.
    private(set) var calendarsByAccount: [(account: String, calendars: [EKCalendar])] = []

    @ObservationIgnored var preferences: Preferences { didSet { reload() } }
    /// Suggestions are never posted while this returns true.
    @ObservationIgnored var isRecording: () -> Bool = { false }
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Occurrences already suggested, by event identifier and start date.
    @ObservationIgnored private var notified = Set<String>()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(preferences: Preferences) {
        self.preferences = preferences
        observers = [
            NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suggestEvents(startedSince: Date().addingTimeInterval(-Self.wakeGrace))
                    self?.reload()
                }
            },
        ]
        reload()
    }

    var isAuthorized: Bool { authorization == .fullAccess }
    private var isActive: Bool { preferences.useCalendar && isAuthorized }

    /// Asks macOS for full calendar access. The only place Minutes requests it.
    func enable() async {
        _ = try? await store.requestFullAccessToEvents()
        reload()
    }

    /// The event of a followed calendar in progress at `start` with the most overlap with the next 30 minutes,
    /// ignoring all-day events.
    func event(at start: Date) -> EventInfo? {
        let windowEnd = start.addingTimeInterval(30 * 60)
        func overlap(_ event: EKEvent) -> TimeInterval {
            min(event.endDate, windowEnd).timeIntervalSince(max(event.startDate, start))
        }
        return events(from: start.addingTimeInterval(-24 * 3600), to: windowEnd)
            .filter { $0.startDate <= start && $0.endDate > start }
            .max { overlap($0) < overlap($1) }
            .map(Self.info)
    }

    // MARK: - Calendars and planning

    private func reload() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        let calendars = isAuthorized ? store.calendars(for: .event) : []
        calendarsByAccount = Dictionary(grouping: calendars) { $0.source.title }
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.account < $1.account }
        planNextSuggestion()
    }

    private func events(from start: Date, to end: Date) -> [EKEvent] {
        guard isActive else { return [] }
        let followed = store.calendars(for: .event).filter { !preferences.unfollowedCalendars.contains($0.calendarIdentifier) }
        guard !followed.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: followed))
            .filter { !$0.isAllDay }
    }

    /// One timer for the next start of a qualifying event (a meeting link or at least one attendee).
    private func planNextSuggestion() {
        timer?.cancel()
        guard isActive, preferences.suggestRecording else { return }
        let now = Date()
        guard let next = events(from: now, to: now.addingTimeInterval(Self.lookAhead))
            .filter({ $0.startDate > now && Self.qualifies($0) }).map(\.startDate).min() else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.suggestEvents(startedSince: next.addingTimeInterval(-1))
            self?.planNextSuggestion()
        }
    }

    private func suggestEvents(startedSince since: Date) {
        guard isActive, preferences.suggestRecording, !isRecording() else { return }
        let now = Date()
        for event in events(from: since, to: now.addingTimeInterval(1))
        where event.startDate >= since && event.startDate <= now && Self.qualifies(event) {
            let occurrence = "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)"
            guard notified.insert(occurrence).inserted else { continue }
            MeetingNotifications.postEventStarting(Self.info(event), occurrence: occurrence)
        }
    }

    // MARK: - Event data

    private static func qualifies(_ event: EKEvent) -> Bool {
        meetingLink(of: event) != nil || !attendees(of: event).isEmpty
    }

    private static func info(_ event: EKEvent) -> EventInfo {
        EventInfo(title: event.title ?? "", calendar: event.calendar.title, attendees: attendees(of: event), meetingLink: meetingLink(of: event))
    }

    /// Display names, or the email when there is none, excluding the user.
    private static func attendees(of event: EKEvent) -> [String] {
        (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { participant in
            if let name = participant.name, !name.isEmpty { return name }
            let address = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            return address.isEmpty ? nil : address
        }
    }

    /// The event URL, else the first Zoom, Meet, Teams or Webex link in the location or notes.
    private static func meetingLink(of event: EKEvent) -> String? {
        if let url = event.url { return url.absoluteString }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first { url in
            guard let host = url.host()?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }?.absoluteString
    }
}
