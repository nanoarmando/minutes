import AppKit
import EventKit
import Observation

/// Calendar data stored with a meeting (session.json, then the note's front matter).
struct EventInfo: Codable, Sendable, Equatable {
    var title: String
    var calendar: String
    /// Display names (or emails) of the other attendees, as written in front matter.
    var attendees: [String]
    var meetingLink: String?
    /// Email addresses of the other attendees, for client detection (sidecar only).
    var attendeeEmails: [String] = []
    /// The domain of the address the user joined with, when known.
    var ownDomain: String?

    init(title: String, calendar: String, attendees: [String], meetingLink: String?, attendeeEmails: [String] = [], ownDomain: String? = nil) {
        self.title = title
        self.calendar = calendar
        self.attendees = attendees
        self.meetingLink = meetingLink
        self.attendeeEmails = attendeeEmails
        self.ownDomain = ownDomain
    }

    /// Session files written before `attendeeEmails` existed still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        calendar = try container.decode(String.self, forKey: .calendar)
        attendees = try container.decode([String].self, forKey: .attendees)
        meetingLink = try container.decodeIfPresent(String.self, forKey: .meetingLink)
        attendeeEmails = try container.decodeIfPresent([String].self, forKey: .attendeeEmails) ?? []
        ownDomain = try container.decodeIfPresent(String.self, forKey: .ownDomain)
    }
}

/// Calendar access, followed calendars, the event lookup at recording start and start suggestions (design D9).
/// Access is requested only by `enable()`, called from Settings › Calendar.
@MainActor @Observable
final class CalendarService {
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
    private static let lookAhead: TimeInterval = 7 * 24 * 3600
    private static let wakeGrace: TimeInterval = 5 * 60
    private static let leadTime: TimeInterval = 60

    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)
    /// Calendars grouped by account (`source.title`), for Settings.
    private(set) var calendarsByAccount: [(account: String, calendars: [EKCalendar])] = []

    @ObservationIgnored var preferences: Preferences { didSet { reload() } }
    /// Picks the "Stop & record next" variant of a suggestion while this returns true.
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
                MainActor.assumeIsolated { self?.reload() }
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
            .map(info)
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

    /// Suggests what is already due (launch, late calendar changes, wake), then one timer for the next suggestion
    /// moment: `leadTime` before the start of a qualifying event (a meeting link or at least one attendee).
    private func planNextSuggestion() {
        timer?.cancel()
        guard isActive, preferences.suggestRecording else { return }
        suggestDueEvents()
        let now = Date()
        guard let next = events(from: now, to: now.addingTimeInterval(Self.lookAhead))
            .filter({ $0.startDate.addingTimeInterval(-Self.leadTime) > now && Self.qualifies($0) })
            .map({ $0.startDate.addingTimeInterval(-Self.leadTime) }).min() else { return }
        timer = Task { [weak self] in
            // Re-planning also posts what became due, so an early wake-up of the sleep only re-arms the timer.
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.planNextSuggestion()
        }
    }

    /// Events whose suggestion moment has passed and that started less than `wakeGrace` ago.
    private func suggestDueEvents() {
        guard isActive, preferences.suggestRecording else { return }
        let now = Date()
        let since = now.addingTimeInterval(-Self.wakeGrace)
        for event in events(from: since, to: now.addingTimeInterval(Self.leadTime + 1))
        where event.startDate > since && event.startDate.addingTimeInterval(-Self.leadTime) <= now && Self.qualifies(event) {
            let occurrence = "\(event.eventIdentifier ?? "")@\(event.startDate.timeIntervalSince1970)"
            guard notified.insert(occurrence).inserted else { continue }
            MeetingNotifications.postEventStarting(info(event), occurrence: occurrence, whileRecording: isRecording())
        }
    }

    // MARK: - Event data

    private static func qualifies(_ event: EKEvent) -> Bool {
        meetingLink(of: event) != nil || !attendees(of: event).isEmpty
    }

    /// The user's address is the attendee matching "Your email addresses", else the participant the calendar marks
    /// as the user, else the calendar account when it is an email address. Attendees that are the user are left out.
    private func info(_ event: EKEvent) -> EventInfo {
        let userEmails = Set(preferences.userEmails)
        let participants = event.attendees ?? []
        let isUser = { (participant: EKParticipant) in participant.isCurrentUser || userEmails.contains(Self.email(of: participant) ?? "") }
        // Names and addresses stay aligned per attendee; a missing address is "".
        let others = participants.filter { !isUser($0) && Self.displayName(of: $0) != nil }
        let userAddress = participants.compactMap(Self.email).first(where: userEmails.contains)
            ?? participants.first(where: \.isCurrentUser).flatMap(Self.email)
            ?? Self.emailAccount(event.calendar.source.title)
        return EventInfo(
            title: event.title ?? "", calendar: event.calendar.title,
            attendees: others.compactMap(Self.displayName), meetingLink: Self.meetingLink(of: event),
            attendeeEmails: others.map { Self.email(of: $0) ?? "" }, ownDomain: userAddress.flatMap(ClientDomains.domain)
        )
    }

    private static func emailAccount(_ title: String) -> String? {
        title.contains("@") ? title.lowercased() : nil
    }

    private static func email(of participant: EKParticipant) -> String? {
        let address = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "").lowercased()
        return address.contains("@") ? address : nil
    }

    private static func displayName(of participant: EKParticipant) -> String? {
        if let name = participant.name, !name.isEmpty { return name }
        return email(of: participant)
    }

    private static func attendees(of event: EKEvent) -> [String] {
        (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(displayName)
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
