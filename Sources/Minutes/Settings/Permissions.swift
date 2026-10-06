import AppKit
import AVFoundation
import EventKit

/// The permissions a recording needs, their current state and the System Settings panes that grant them.
enum Permission: String, Sendable {
    case microphone, systemAudio, calendar

    var name: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio Recording"
        case .calendar: "Calendars"
        }
    }

    enum State {
        case granted, denied, notDetermined
        /// System audio: the probe cannot tell "not asked yet" from "denied".
        case notGranted
    }

    var state: State {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notDetermined
            default: .denied
            }
        case .systemAudio:
            SystemAudioTap.hasPermission() ? .granted : .notGranted
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .notDetermined: .notDetermined
            default: .denied
            }
        }
    }

    var isGranted: Bool { state == .granted }

    /// Asks the user when the system still allows asking; returns the resulting state.
    func request() async -> Bool {
        switch self {
        case .microphone: await AVCaptureDevice.requestAccess(for: .audio)
        case .systemAudio: await SystemAudioTap.requestPermission()
        case .calendar: isGranted // Only CalendarService asks, from Settings › Calendar.
        }
    }

    private var settingsURL: URL? {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .systemAudio: "Privacy_ScreenCapture"
        case .calendar: "Privacy_Calendars"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
    }

    @MainActor
    func openSettings() {
        if let settingsURL { NSWorkspace.shared.open(settingsURL) }
    }
}
