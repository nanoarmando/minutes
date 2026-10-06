import Foundation
import UserNotifications

/// System notifications: "meeting saved" (clicking opens the meeting) and "event starting" (its "Start recording"
/// action records with that event's data). Responses are handled by `AppDelegate`.
enum MeetingNotifications {
    static let meetingIDKey = "meetingID"
    static let eventKey = "event"
    static let eventCategory = "event-starting"
    static let startRecordingAction = "start-recording"

    /// UserNotifications raises an exception outside an app bundle (a bare `swift build` binary).
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([UNNotificationCategory(
            identifier: eventCategory,
            actions: [
                UNNotificationAction(identifier: startRecordingAction, title: "Start recording", options: [.foreground]),
                UNNotificationAction(identifier: "dismiss", title: "Dismiss"),
            ],
            intentIdentifiers: []
        )])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postSaved(_ note: SavedNote) {
        let content = UNMutableNotificationContent()
        content.title = note.summaryFailed ? "Meeting saved, summary failed" : "Meeting saved"
        var body = note.title
        if note.summaryFailed { body += "\nSummarize it again from the Meetings window." }
        if note.systemAudioSilent { body += "\nOnly the microphone was recorded: check the System Audio Recording permission." }
        content.body = body
        content.userInfo = [meetingIDKey: note.id.uuidString]
        post(content, id: note.id.uuidString)
    }

    static func postEventStarting(_ event: EventInfo, occurrence: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(event.title) is starting"
        content.body = "Record this meeting with Minutes?"
        content.categoryIdentifier = eventCategory
        content.userInfo = [eventKey: (try? JSONEncoder().encode(event)) ?? Data()]
        post(content, id: occurrence)
    }

    static func event(from userInfo: [AnyHashable: Any]) -> EventInfo? {
        (userInfo[eventKey] as? Data).flatMap { try? JSONDecoder().decode(EventInfo.self, from: $0) }
    }

    private static func post(_ content: UNMutableNotificationContent, id: String) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
