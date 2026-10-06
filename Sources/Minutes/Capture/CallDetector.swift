import AppKit
import CoreAudio

/// Notices calls that are not in the calendar from meeting apps using the microphone (detect-unscheduled-calls D1–D2).
/// Polls Core Audio's per-process objects every 2 s while enabled; needs no permission.
// All state is confined to `queue`; only coarse events leave it.
final class CallDetector: @unchecked Sendable {
    enum Event: Sendable {
        /// A meeting app has used the microphone for 10 continuous seconds.
        case callStarted(appName: String)
        /// During a recording in which a meeting app used the microphone, none has for 10 seconds.
        case callEnded
    }

    /// Matched by prefix, so browser helper processes (com.google.Chrome.helper…) count as their browser.
    static let meetingApps = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "Cisco-Systems.Spark",
        "com.webex.meetingmanager", "com.apple.FaceTime", "com.hnc.Discord", "com.google.Chrome",
        "company.thebrowser.Browser", "com.apple.Safari", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox",
    ]
    private static let pollInterval: DispatchTimeInterval = .seconds(2)
    private static let threshold: TimeInterval = 10

    private let onEvent: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "com.minutes.call-detector", qos: .utility)
    private var timer: DispatchSourceTimer?
    /// Meeting app (list entry) → when it started using the microphone continuously.
    private var inputSince: [String: Date] = [:]
    /// Meeting apps already suggested during their current continuous use.
    private var suggested = Set<String>()
    private var isRecording = false
    private var callSeenWhileRecording = false
    private var lastCallInput = Date.distantPast
    private var endAsked = false

    init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
    }

    func setEnabled(_ enabled: Bool) {
        queue.async { [self] in
            guard enabled != (timer != nil) else { return }
            timer?.cancel()
            timer = nil
            inputSince = [:]
            suggested = []
            guard enabled else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: Self.pollInterval)
            source.setEventHandler { [weak self] in self?.poll() }
            source.resume()
            timer = source
        }
    }

    /// Arms the "did the meeting end?" question for every new recording, also one that starts right after another
    /// without an observed stop.
    func setRecording(_ recording: Bool) {
        queue.async { [self] in
            guard recording || isRecording else { return }
            isRecording = recording
            callSeenWhileRecording = false
            endAsked = false
        }
    }

    private func poll() {
        let now = Date()
        let active = Self.meetingAppsUsingInput()
        inputSince = inputSince.filter { active[$0.key] != nil }
        suggested.formIntersection(active.keys)
        for (app, pid) in active {
            let since = inputSince[app] ?? now
            inputSince[app] = since
            if now.timeIntervalSince(since) >= Self.threshold, suggested.insert(app).inserted {
                onEvent(.callStarted(appName: Self.displayName(app: app, pid: pid)))
            }
        }

        guard isRecording else { return }
        if !active.isEmpty {
            callSeenWhileRecording = true
            lastCallInput = now
            endAsked = false  // the call resumed: ask again when it ends
        } else if callSeenWhileRecording, !endAsked, now.timeIntervalSince(lastCallInput) >= Self.threshold {
            endAsked = true
            onEvent(.callEnded)
        }
    }

    // MARK: - Core Audio

    /// Meeting apps (list entry → one PID) with a process currently capturing audio input, excluding Minutes.
    private static func meetingAppsUsingInput() -> [String: pid_t] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [String: pid_t] = [:]
        for process in processObjects() where read(process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1 {
            guard let pid = read(process, kAudioProcessPropertyPID, as: pid_t.self), pid != ownPID,
                  let bundleID = bundleID(of: process),
                  let app = meetingApps.first(where: { bundleID.lowercased().hasPrefix($0.lowercased()) }) else { continue }
            result[app] = result[app] ?? pid
        }
        return result
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func read<Value>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as type: Value.Type) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Value>.size)
        let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    /// Nil, and the process ignored, when Core Audio reports no bundle ID.
    private static func bundleID(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let bundleID = value?.takeRetainedValue() as String?, !bundleID.isEmpty else { return nil }
        return bundleID
    }

    /// The app's name ("Google Chrome", not its helper), else the process's, else the bundle ID.
    private static func displayName(app: String, pid: pid_t) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: app).first?.localizedName
            ?? NSRunningApplication(processIdentifier: pid)?.localizedName
            ?? app
    }
}
