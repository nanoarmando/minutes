import SwiftUI
import UserNotifications

@main
struct MinutesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuView(environment: delegate.environment)
        } label: {
            MenuBarLabel(environment: delegate.environment)
        }
        .menuBarExtraStyle(.window)

        Window("Meetings", id: "meetings") {
            MeetingsWindow(environment: delegate.environment)
        }
        .defaultSize(width: 900, height: 620)

        Window("About Minutes", id: "about") {
            AboutView(environment: delegate.environment)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(environment: delegate.environment)
        }
    }
}

/// The menu bar item: an icon when idle, a red dot with the elapsed time while recording. It is always on
/// screen, so it also hands SwiftUI's window actions to the environment for code outside views.
private struct MenuBarLabel: View {
    let environment: AppEnvironment
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if environment.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill").foregroundStyle(.red)
                    Text(environment.elapsed.clock).monospacedDigit()
                }
            } else {
                Image(systemName: "waveform")
            }
        }
        .onAppear {
            environment.openWindow = { openWindow(id: $0) }
            environment.openSettingsWindow = { openSettings() }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let environment = AppEnvironment()

    /// Clicking the Dock icon (shown while a window is open) brings the Meetings window to the front.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.showMeetings()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if MeetingNotifications.isAvailable { UNUserNotificationCenter.current().delegate = self }
    }

    /// While recording, Quit asks whether to save or discard and quits only after that action completes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard environment.isRecording else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A meeting is being recorded"
        alert.informativeText = "Save the meeting before quitting, or discard the recording?"
        alert.addButton(withTitle: "Stop & Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return .terminateCancel }
        Task {
            await environment.endRecordingForQuit(save: response == .alertFirstButtonReturn)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        let meetingID = (userInfo[MeetingNotifications.meetingIDKey] as? String).flatMap(UUID.init(uuidString:))
        let event = MeetingNotifications.event(from: userInfo)
        Task { @MainActor in
            if let event {
                // Only the action starts a recording; clicking the notification body does nothing.
                if action == MeetingNotifications.startRecordingAction { self.environment.startRecording(event: event) }
            } else {
                self.environment.showMeetings(selecting: meetingID)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
