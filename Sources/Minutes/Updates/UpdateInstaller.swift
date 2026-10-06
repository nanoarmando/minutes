import Foundation
import Security

enum UpdateInstallerError: LocalizedError {
    case mountFailed(String)
    case missingApp
    case notSignedLikeThisCopy
    case wrongVersion(expected: AppVersion, found: String?)
    case stagingFailed(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .mountFailed(let detail): "The disk image could not be opened: \(detail)"
        case .missingApp: "The disk image does not contain Minutes.app."
        case .notSignedLikeThisCopy: "The download is not signed like this copy of Minutes, so it was not installed."
        case .wrongVersion(let expected, let found): "The download is version \(found ?? "unknown"), not the announced \(expected)."
        case .stagingFailed(let detail): "The new version could not be prepared: \(detail)"
        case .launchFailed(let detail): "The installer could not start: \(detail)"
        }
    }
}

/// Turns a downloaded disk image into a verified app outside any mounted volume, then swaps it in.
enum UpdateInstaller {
    static let appName = "Minutes.app"

    /// ~/Library/Caches/Minutes/updates
    static let workspace = URL.cachesDirectory.appendingPathComponent("Minutes/updates", isDirectory: true)

    private static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")

    static var stagedApp: URL {
        workspace.appendingPathComponent("staged", isDirectory: true).appendingPathComponent(appName, isDirectory: true)
    }

    /// Written by the swap script when the replacement failed; read by the restored app at launch.
    static var failureReport: URL { workspace.appendingPathComponent("failure.txt") }

    /// Always deletes the disk image; returns the staged app only when both signature checks passed.
    static func stage(diskImage: URL, version: AppVersion) async throws -> URL {
        defer { try? FileManager.default.removeItem(at: diskImage) }
        let requirement = try runningRequirement()
        let staged = stagedApp
        try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())

        let mountPoint = try await attach(diskImage)
        do {
            let mounted = mountPoint.appendingPathComponent(appName, isDirectory: true)
            guard FileManager.default.fileExists(atPath: mounted.path) else { throw UpdateInstallerError.missingApp }
            try verify(mounted, requirement: requirement, version: version)
            try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copy = await run(ditto, ["--noextattr", "--noqtn", mounted.path, staged.path])
            guard copy.succeeded else { throw UpdateInstallerError.stagingFailed(copy.output) }
        } catch {
            await detach(mountPoint)
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            throw error
        }
        await detach(mountPoint)
        do {
            try verify(staged, requirement: requirement, version: version)
        } catch {
            try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
            throw error
        }
        return staged
    }

    /// Started before quitting; `/bin/sh` is reparented to launchd and outlives Minutes.
    static func launchSwap(staged: URL, target: URL, waitingFor pid: Int32) throws {
        let previous = target.deletingLastPathComponent().appendingPathComponent(".Minutes-previous.app", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", swapScript(pid: pid, staged: staged.path, target: target.path, previous: previous.path, report: failureReport.path)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallerError.launchFailed(error.localizedDescription)
        }
    }

    private static func swapScript(pid: Int32, staged: String, target: String, previous: String, report: String) -> String {
        """
        pid=\(pid)
        staged=\(shellQuoted(staged))
        target=\(shellQuoted(target))
        previous=\(shellQuoted(previous))
        report=\(shellQuoted(report))
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$previous"
        if mv "$target" "$previous" 2>/dev/null; then
            if mv "$staged" "$target" 2>/dev/null; then
                xattr -dr com.apple.quarantine "$target" 2>/dev/null
                open "$target"
                rm -rf "$previous" "$(dirname "$staged")"
                exit 0
            fi
            mv "$previous" "$target"
        fi
        echo "Minutes could not replace its app at $target." > "$report"
        rm -rf "$(dirname "$staged")"
        open "$target"
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Disk image

    private static func attach(_ diskImage: URL) async throws -> URL {
        let mounts = workspace.appendingPathComponent("mounts", isDirectory: true)
        try FileManager.default.createDirectory(at: mounts, withIntermediateDirectories: true)
        let result = await run(hdiutil, ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountrandom", mounts.path, "-plist", diskImage.path])
        guard result.succeeded else { throw UpdateInstallerError.mountFailed(result.output) }
        guard let mountPoint = mountPoint(fromPlist: result.output) else {
            throw UpdateInstallerError.mountFailed("hdiutil reported no mount point.")
        }
        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    private static func mountPoint(fromPlist output: String) -> String? {
        // hdiutil may print notices before the plist, so parse from its opening tag.
        guard let start = output.range(of: "<?xml"),
              let plist = try? PropertyListSerialization.propertyList(from: Data(output[start.lowerBound...].utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else { return nil }
        return entities.lazy.compactMap { $0["mount-point"] as? String }.first
    }

    private static func detach(_ mountPoint: URL) async {
        _ = await run(hdiutil, ["detach", mountPoint.path, "-force"])
    }

    /// Runs a tool to completion and returns its exit status and combined output.
    private static func run(_ executable: URL, _ arguments: [String]) async -> (succeeded: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (finished.terminationStatus == 0, output.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }

    // MARK: - Signature

    /// The running app's designated requirement; for "Minutes Self-Signed" it pins the certificate's leaf hash.
    private static func runningRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateInstallerError.notSignedLikeThisCopy }
        return requirement
    }

    private static func verify(_ app: URL, requirement: SecRequirement, version: AppVersion) throws {
        var staticCode: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
        else { throw UpdateInstallerError.notSignedLikeThisCopy }

        let declared = (try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
            .flatMap { ($0 as? [String: Any])?["CFBundleShortVersionString"] as? String }
        guard declared.flatMap(AppVersion.init) == version else {
            throw UpdateInstallerError.wrongVersion(expected: version, found: declared)
        }
    }
}
