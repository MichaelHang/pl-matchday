import Foundation

// MARK: - Player name mapping (resource-driven: JSON table + runtime override layer)

/// Shape of the translation resource (`PlayerNames-zh-Hans.json`, see `TranslationStore`).
private struct PlayerNamesResource: Decodable {
    /// FPL element id (string keys) → Chinese full name
    let byId: [String: String]
    /// web_name → Chinese full name (secondary fallback)
    let byName: [String: String]
}

/// Player Chinese-name mapping.
///
/// Data layers (highest priority first):
/// 1. the override layer `PlayerNameStore.current` (DEBUG panel, persisted at
///    runtime, never committed to the repo);
/// 2. the id-keyed table `zhById` (FPL element id — stable across seasons and
///    transfers, unaffected by name changes);
/// 3. the web_name-keyed table `zhByName` (less reliable under duplicate surnames,
///    hence fallback only);
/// 4. the original English name (final fallback — never blank).
///
/// The table lives in
/// `EPLViewer/Localization/Resources/PlayerNames-zh-Hans.json`
/// (667 id entries + 220 web_name entries). To maintain it: edit the JSON and
/// rebuild; runtime fixes go through the DEBUG override panel.
/// `missing(ids:)` / `missing(from:)` diff out current players still lacking a
/// Chinese name — filling the table is mechanical work.
enum PlayerNameMap {
    /// A failed load (missing/corrupt file) → both tables empty → English names everywhere.
    private static let resource: PlayerNamesResource? =
        TranslationStore.load("PlayerNames", locale: "zh-Hans")

    /// FPL element id → Chinese full name (primary dimension).
    private static let zhById: [Int: String] = {
        guard let byId = resource?.byId else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: byId.compactMap { key, value in Int(key).map { ($0, value) } }
        )
    }()

    /// web_name → Chinese full name (secondary dimension).
    private static let zhByName: [String: String] = resource?.byName ?? [:]

    /// Chinese name for a player; nil when unmatched.
    /// Overrides beat the table; the id dimension still precedes the name dimension.
    static func zh(for player: PlayerLite) -> String? {
        let o = PlayerNameStore.current
        if let pid = player.id, let c = (o.byId[pid] ?? zhById[pid]) { return c }
        if let c = (o.byName[player.name] ?? zhByName[player.name]) { return c }
        return nil
    }

    /// Table-only Chinese name (excludes overrides); the DEBUG panel's baseline for
    /// flagging redundant overrides.
    static func builtInName(forId id: Int) -> String? { zhById[id] }

    /// Maintenance: given current FPL element ids, those missing a Chinese name (sorted).
    static func missing(ids: [Int]) -> [Int] {
        ids.filter { zhById[$0] == nil }.sorted()
    }

    /// Maintenance (web_name dimension): given web_names, those missing a Chinese
    /// name (sorted, deduplicated).
    static func missing(from webNames: [String]) -> [String] {
        Set(webNames).subtracting(zhByName.keys).sorted()
    }
}

extension PlayerLite {
    /// Chinese name (nil when unmatched).
    var nameZh: String? { PlayerNameMap.zh(for: self) }

    /// Display name by language preference: Chinese mode prefers Chinese (falls back
    /// to English); English mode always shows the original name.
    func displayName(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}
