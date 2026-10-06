import Foundation

/// A `major.minor.patch` marketing version, compared number by number so 0.2.10 follows 0.2.9.
struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    static var running: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }
}

/// Whether this copy of Minutes may replace itself.
enum UpdateEligibility: Equatable, Sendable {
    case eligible
    case developmentBuild
    case notInApplications
    case readOnlyLocation

    static let releaseBundleIdentifier = "com.minutes.app"

    static var current: UpdateEligibility {
        let bundle = Bundle.main.bundleURL
        guard Bundle.main.bundleIdentifier == releaseBundleIdentifier else { return .developmentBuild }
        if bundle.path.hasPrefix("/Volumes/") || bundle.path.contains("/AppTranslocation/") { return .notInApplications }
        return FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) ? .eligible : .readOnlyLocation
    }

    var refusal: String? {
        switch self {
        case .eligible: nil
        case .developmentBuild: "Updates are only available in the release build."
        case .notInApplications: "Move Minutes to the Applications folder to update it."
        case .readOnlyLocation: "Minutes can't update itself because its folder isn't writable."
        }
    }
}

/// The fields Minutes reads from GitHub's "latest release" answer.
struct UpdateRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let downloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }

    static let tagPrefix = "v"

    let tag: String
    let notes: String
    let pageURL: URL
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case notes = "body"
        case pageURL = "html_url"
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decode(String.self, forKey: .tag)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    var version: AppVersion? {
        guard tag.hasPrefix(Self.tagPrefix) else { return nil }
        return AppVersion(String(tag.dropFirst(Self.tagPrefix.count)))
    }

    /// Only the DMG named after the tag's own version; any other asset is not a Minutes build.
    var diskImage: Asset? {
        guard let version else { return nil }
        return assets.first { $0.name == "Minutes-\(version).dmg" }
    }

    func outcome(comparedTo current: AppVersion) -> UpdateCheckOutcome {
        guard let version, let diskImage else { return .unusable }
        guard version > current else { return .upToDate }
        return .available(AvailableUpdate(version: version, notes: notes, pageURL: pageURL, downloadURL: diskImage.downloadURL))
    }
}

struct AvailableUpdate: Equatable, Sendable {
    let version: AppVersion
    let notes: String
    let pageURL: URL
    let downloadURL: URL
}

enum UpdateCheckOutcome: Equatable, Sendable {
    case available(AvailableUpdate)
    case upToDate
    case unusable
}
