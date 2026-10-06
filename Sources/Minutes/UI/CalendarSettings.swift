import SwiftUI

/// Settings › Calendar: access, start suggestions and followed calendars. Turning the switch on is the only
/// moment Minutes asks for calendar access.
struct CalendarSettings: View {
    let environment: AppEnvironment

    private var calendar: CalendarService { environment.calendar }
    private var useCalendar: Bool { environment.preferences.useCalendar }

    var body: some View {
        Form {
            Section {
                Toggle("Use calendar events", isOn: Binding(get: { useCalendar }, set: { enabled in
                    environment.updatePreferences { $0.useCalendar = enabled }
                    if enabled { Task { await calendar.enable() } }
                }))
                Toggle("Suggest recording when a meeting starts", isOn: environment.binding(\.suggestRecording))
                    .disabled(!useCalendar)
            } footer: {
                Text("The event in progress when a recording starts gives the note its title, attendees and meeting link. Suggestions appear for events with a meeting link or attendees.")
            }
            if useCalendar {
                if calendar.isAuthorized {
                    ForEach(calendar.calendarsByAccount, id: \.account) { group in
                        Section(group.account) {
                            ForEach(group.calendars, id: \.calendarIdentifier) { item in
                                Toggle(item.title, isOn: followBinding(item.calendarIdentifier)).toggleStyle(.checkbox)
                            }
                        }
                    }
                } else if calendar.authorization == .notDetermined {
                    Button("Allow calendar access") { Task { await calendar.enable() } }
                } else {
                    Section {
                        Label("Calendar access is off. Recordings use the generated or default title.", systemImage: "calendar.badge.exclamationmark")
                        Button("Open System Settings") { Permission.calendar.openSettings() }
                    }
                }
            }
        }
    }

    private func followBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !environment.preferences.unfollowedCalendars.contains(id) },
            set: { followed in
                environment.updatePreferences {
                    if followed { $0.unfollowedCalendars.remove(id) } else { $0.unfollowedCalendars.insert(id) }
                }
            }
        )
    }
}
