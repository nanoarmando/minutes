import Foundation

/// Deterministic client rules from email domains (tag-clients-from-meeting-context D2): every attendee domain that
/// is neither the user's organization nor a personal email provider is a client of the meeting.
enum ClientDomains {
    static let personal: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "icloud.com", "me.com", "mac.com",
        "yahoo.com", "proton.me", "protonmail.com",
    ]
    static let maxClients = 2

    static func domain(of email: String) -> String? {
        let parts = email.lowercased().trimmingCharacters(in: .whitespaces).split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") ? String(parts[1]) : nil
    }

    /// The last two labels, so `mail.drgreenlife.com` and `drgreenlife.com` compare equal.
    static func registrable(_ domain: String) -> String {
        domain.split(separator: ".").suffix(2).joined(separator: ".")
    }

    /// The user's organization: the domain they joined with, else every domain of "Your email addresses".
    static func ownDomains(ownDomain: String?, userEmails: [String]) -> [String] {
        let domains = ownDomain.map { [$0] } ?? userEmails.compactMap(domain)
        return unique(domains.map(registrable))
    }

    /// Client domains ordered by number of attendees, at most two.
    static func clientDomains(attendeeEmails: [String], ownDomains: [String]) -> [String] {
        let excluded = Set(ownDomains).union(personal)
        let counts = Dictionary(attendeeEmails.compactMap(domain).map { (registrable($0), 1) }, uniquingKeysWith: +)
            .filter { !excluded.contains($0.key) }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(maxClients).map(\.key)
    }

    /// The client tag derived from a domain alone: `drgreenlife.com` → `client/drgreenlife`.
    static func fallbackTag(for domain: String) -> String {
        "client/" + TagService.slug(String(domain.split(separator: ".").first ?? ""))
    }

    /// True when a client slug names one of the user's own domains ("vnstudios" or "vn-studios" for vnstudios.com).
    static func isOwn(_ clientSlug: String, ownDomains: [String]) -> Bool {
        let compact = clientSlug.replacingOccurrences(of: "-", with: "")
        return ownDomains.contains { compact == TagService.slug(String($0.split(separator: ".").first ?? "")).replacingOccurrences(of: "-", with: "") }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
