import Foundation

// MARK: - Team name mapping (resource-driven)

/// Shape of the translation resource (`TeamNames-zh-Hans.json`, see `TranslationStore`).
private struct TeamNamesResource: Decodable {
    /// FPL short_name (3-letter club code) → Chinese name
    let byShort: [String: String]
}

/// Team Chinese-name mapping.
///
/// - The table lives in
///   `EPLViewer/Localization/Resources/TeamNames-zh-Hans.json` (21 entries),
///   keyed by FPL `short_name` to match the app's data source; adding or adjusting
///   teams only touches the JSON.
/// - No match returns nil and the caller falls back to the English name; a failed
///   load (empty table) behaves the same.
enum TeamNameMap {
    private static let resource: TeamNamesResource? =
        TranslationStore.load("TeamNames", locale: "zh-Hans")

    private static let zhByShort: [String: String] = resource?.byShort ?? [:]

    /// Chinese name for a team; nil when unmatched.
    static func zh(for team: Team) -> String? {
        guard let sn = team.shortName else { return nil }
        return zhByShort[sn]
    }
}

extension Team {
    /// Chinese name (nil when unmatched).
    var nameZh: String? { TeamNameMap.zh(for: self) }

    /// Display name by language preference.
    /// - Parameter chinese: true prefers Chinese (falls back to English); false always English.
    func displayName(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}
