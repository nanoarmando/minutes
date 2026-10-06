import KeyboardShortcuts
import SwiftUI

/// The menu bar menu: idle, recording, processing and finished states.
struct MenuView: View {
    let environment: AppEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch environment.status {
            case .recording: recording
            case .processing(let step): processing(step)
            default: idle
            }
            MenuDivider()
            if !environment.isRecording {
                if let version = environment.updates.availableVersion, !environment.isBusy {
                    MenuRow("Update available (\(version.description))") { environment.showAbout() }
                }
                MenuRow("All meetings…") { environment.showMeetings() }
                MenuRow("Open notes folder") { NSWorkspace.shared.open(environment.preferences.notesFolder) }
                MenuDivider()
            }
            MenuRow("Settings…") { environment.showSettings() }
            MenuRow("About Minutes") { environment.showAbout() }
            MenuRow("Quit") { NSApp.terminate(nil) }
        }
        .padding(5)
        .frame(width: 300)
        // The panel keeps the height of its first layout unless the content reports a fixed ideal height;
        // without this, states with less content (idle after a message) leave empty space at the bottom.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - States

    @ViewBuilder private var idle: some View {
        finishedMessage
        modelStatus
        Text(engineDescription).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 3)
        MenuRow("Start recording", detail: KeyboardShortcuts.getShortcut(for: .toggleRecording)?.description ?? "") {
            environment.startRecording()
        }
    }

    @ViewBuilder private var recording: some View {
        HStack {
            Image(systemName: "circle.fill").foregroundStyle(.red)
            Text("Recording").font(.headline)
            Spacer()
            Text(environment.elapsed.clock).monospacedDigit()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        LevelRow(label: "You", level: environment.micLevel)
        LevelRow(label: "Others", level: environment.systemLevel)
        MenuRow("Stop & summarize", detail: KeyboardShortcuts.getShortcut(for: .toggleRecording)?.description ?? "") {
            environment.stopRecording()
        }
        MenuRow("Discard…") {
            // MenuRow closes the panel first, so this alert is not hidden behind it.
            if confirm("Discard this recording?", "The audio and transcript are deleted and no note is created.", action: "Discard") {
                environment.discardRecording()
            }
        }
    }

    private func processing(_ current: ProcessingStep) -> some View {
        let steps: [ProcessingStep] = [.transcribing, .separatingSpeakers, .summarizing, .saving]
        let currentIndex = steps.firstIndex(of: current) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            Text("Processing meeting").font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 6) {
                    if index < currentIndex {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if index == currentIndex {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "circle").foregroundStyle(.tertiary)
                    }
                    Text(step.rawValue).foregroundStyle(index > currentIndex ? .secondary : .primary)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    @ViewBuilder private var finishedMessage: some View {
        switch environment.status {
        case .finished(.saved(let note)):
            Message(icon: "checkmark.circle.fill", tint: .green, text: "Saved “\(note.title)”"
                + (note.summaryFailed ? ". The summary failed." : "")
                + (note.systemAudioSilent ? " Only the microphone was recorded." : "")) {
                MenuButton("Open") { environment.showMeetings(selecting: note.id) }
            }
        case .finished(.waitingForFolder(let message)):
            Message(icon: "folder.badge.questionmark", tint: .orange, text: message + " The meeting is kept until you choose a writable folder.") {
                MenuButton("Choose folder…") { environment.showSettings(.general) }
            }
        case .finished(.failed(let message)):
            Message(icon: "exclamationmark.triangle.fill", tint: .orange, text: message) {
                MenuButton("Retry") { environment.retryProcessing() }
                MenuButton("Discard") {
                    if confirm("Discard this recording?", "The audio and transcript are deleted.", action: "Discard") { environment.discardRecording() }
                }
            }
        case .startFailed(let message):
            Message(icon: "exclamationmark.triangle.fill", tint: .orange, text: message) {
                MenuButton("Open Settings") { environment.showSettings(.general) }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var modelStatus: some View {
        switch environment.modelState {
        case .downloading(let fraction):
            VStack(alignment: .leading) {
                Text("Downloading the transcription model…").font(.caption)
                ProgressView(value: fraction)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        case .failed(let message) where environment.preferences.engine == .parakeet:
            Message(icon: "exclamationmark.triangle.fill", tint: .orange, text: "Model download failed: \(message)") {
                MenuButton("Retry") { environment.downloadModel() }
            }
        default:
            EmptyView()
        }
    }

    private var engineDescription: String {
        environment.preferences.engine == .parakeet
            ? "Transcribing on this Mac (Parakeet v3)"
            : "Transcribing with \(environment.preferences.transcriptionModel) (API)"
    }
}

/// Closes the MenuBarExtra panel. SwiftUI offers no API for it; the panel is the only window whose class name
/// contains "MenuBarExtra". Matching that is more reliable than `NSApp.keyWindow`, which is nil or another window
/// when the action runs after an alert or while another app is active.
@MainActor
func closeMenuPanel() {
    NSApp.windows.first { String(describing: type(of: $0)).contains("MenuBarExtra") && $0.isVisible }?.close()
}

/// A button inside a menu message (Open, Retry…): closes the panel before running its action, like `MenuRow`.
private struct MenuButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title) {
            closeMenuPanel()
            action()
        }
    }
}

/// A thin divider with menu spacing.
private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 10).padding(.vertical, 5)
    }
}

/// A full-width menu item: fixed height, accent highlight with white text on hover, like a native menu.
/// Every row closes the panel before running its action.
struct MenuRow: View {
    let title: String
    let detail: String
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, detail: String = "", action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button {
            closeMenuPanel()
            action()
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer()
                Text(detail).foregroundStyle(isHovered ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)).lineLimit(1)
            }
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: 22)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct LevelRow: View {
    let label: String
    let level: Float

    var body: some View {
        HStack {
            Text(label).frame(width: 50, alignment: .leading)
            ProgressView(value: Double(level)).animation(.linear(duration: 0.1), value: level)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
    }
}

private struct Message<Actions: View>: View {
    let icon: String
    let tint: Color
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon).foregroundStyle(tint) }
            HStack { actions }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Asks for confirmation with a destructive action; returns true when confirmed.
@MainActor
func confirm(_ title: String, _ message: String, action: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: action).hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")
    NSApp.activate()
    return alert.runModal() == .alertFirstButtonReturn
}

extension TimeInterval {
    /// "12:34" or "1:02:03".
    var clock: String {
        Duration.seconds(self).formatted(.time(pattern: self >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    /// "47 min" or "1 h 5 min".
    var minutesText: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
