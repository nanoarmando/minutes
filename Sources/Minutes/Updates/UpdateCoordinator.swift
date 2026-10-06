import AppKit
import Observation

/// Checks Minutes' own releases at launch, every 24 hours and when About opens, and installs one on
/// confirmation. Results live in memory only.
@MainActor @Observable
final class UpdateCoordinator {
    enum State: Equatable {
        case idle
        case unavailable(String)
        case checking
        case upToDate
        case available(AvailableUpdate)
        case downloading(AvailableUpdate, Double)
        case verifying(AvailableUpdate)
        case failed(String)
    }

    private static let checkInterval = Duration.seconds(24 * 3600)

    private(set) var state = State.idle
    /// The last install failure (download, verification or swap), shown under the release notes.
    private(set) var installError: String?
    /// Installing is refused while this returns true (a recording in progress or being processed).
    @ObservationIgnored var isAppBusy: () -> Bool = { false }
    @ObservationIgnored private let client = UpdateClient()
    @ObservationIgnored private var dailyCheck: Task<Void, Never>?

    var isWorking: Bool {
        switch state {
        case .checking, .downloading, .verifying: true
        default: false
        }
    }

    /// The newer version, when one is known; drives the menu's update row.
    var availableVersion: AppVersion? {
        if case .available(let update) = state { return update.version }
        return nil
    }

    /// Checks now and then every 24 hours; reports a swap that failed after the last quit.
    func start() {
        if let message = try? String(contentsOf: UpdateInstaller.failureReport, encoding: .utf8) {
            try? FileManager.default.removeItem(at: UpdateInstaller.failureReport)
            installError = message
        }
        dailyCheck = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    func check() {
        guard !isWorking else { return }
        if let refusal = UpdateEligibility.current.refusal, UpdateEligibility.current == .developmentBuild {
            state = .unavailable(refusal)
            return
        }
        guard let current = AppVersion.running else {
            state = .unavailable("This copy of Minutes has no readable version.")
            return
        }
        state = .checking
        Task { [client] in
            do {
                guard let release = try await client.latestRelease() else {
                    state = .upToDate
                    return
                }
                switch release.outcome(comparedTo: current) {
                case .available(let update): state = .available(update)
                case .upToDate: state = .upToDate
                case .unusable: state = .failed("The latest release could not be used.")
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func install(_ update: AvailableUpdate) {
        guard case .available = state, !isAppBusy(), UpdateEligibility.current == .eligible else { return }
        installError = nil
        state = .downloading(update, 0)
        Task { [client] in
            let diskImage = UpdateInstaller.workspace.appendingPathComponent("Minutes-\(update.version).dmg")
            do {
                try FileManager.default.createDirectory(at: UpdateInstaller.workspace, withIntermediateDirectories: true)
                try await client.download(update.downloadURL, to: diskImage) { fraction in
                    Task { @MainActor in
                        if case .downloading(update, _) = self.state { self.state = .downloading(update, fraction) }
                    }
                }
                state = .verifying(update)
                let staged = try await UpdateInstaller.stage(diskImage: diskImage, version: update.version)
                confirmInstall(update, staged: staged)
            } catch {
                try? FileManager.default.removeItem(at: diskImage)
                state = .available(update)
                installError = error.localizedDescription
            }
        }
    }

    private func confirmInstall(_ update: AvailableUpdate, staged: URL) {
        let alert = NSAlert()
        alert.messageText = "Install Minutes \(update.version)?"
        alert.informativeText = "Minutes will quit, replace itself with the new version and reopen."
        alert.addButton(withTitle: "Install and Reopen")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, !isAppBusy() else {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            state = .available(update)
            return
        }
        do {
            try UpdateInstaller.launchSwap(staged: staged, target: Bundle.main.bundleURL, waitingFor: ProcessInfo.processInfo.processIdentifier)
        } catch {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            state = .available(update)
            installError = error.localizedDescription
            return
        }
        NSApp.terminate(nil)
    }
}
