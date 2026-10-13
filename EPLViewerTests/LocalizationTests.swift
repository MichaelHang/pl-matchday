import XCTest
@testable import EPLViewer

// Translations: team & player mappings / DEBUG override layer.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    // MARK: - Team name mapping

    /// Chinese team names: chinese=true hits the table or falls back to English;
    /// false always returns English.
    func testTeamDisplayNameChinese() throws {
        let arsenal = Team(id: 1, name: "Arsenal", shortName: "ARS", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(arsenal.displayName(chinese: true), "阿森纳")
        XCTAssertEqual(arsenal.displayName(chinese: false), "Arsenal")

        let city = Team(id: 15, name: "Manchester City", shortName: "MCI", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(city.displayName(chinese: true), "曼城")

        // Unknown short_name: Chinese mode falls back to the English name
        let unknown = Team(id: 999, name: "Nowhere FC", shortName: "NOW", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(unknown.displayName(chinese: true), "Nowhere FC")

        // Missing short_name: no Chinese match possible; falls back to English
        let noShort = Team(id: 998, name: "Some Team", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(noShort.displayName(chinese: true), "Some Team")
    }
}

extension EPLViewerTests {
    // MARK: - Player name mapping (PlayerNames)

    /// Chinese mode returns the full Chinese name for known stars; English mode
    /// always the original; unknown players fall back to English (never blank/crash).
    /// Uses sentinel ids (999999, absent from zhById) to isolate the web_name
    /// fallback path, avoiding collisions with real ids.
    func testPlayerDisplayNameChineseKnownAndFallback() {
        let haaland = PlayerLite(id: 999999, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "Haaland should hit the full Chinese name (web_name fallback path)")
        XCTAssertEqual(haaland.displayName(chinese: false), "Haaland",
                       "English mode always shows the FPL web_name")

        let nobody = PlayerLite(id: 999999, name: "Unknown Player", nationality: nil)
        XCTAssertEqual(nobody.displayName(chinese: true), "Unknown Player",
                       "unknown players in Chinese mode fall back to the English name, never blank")
    }

    /// Primary-key path: an FPL element id hit returns the Chinese name directly
    /// (ids are stable across seasons/transfers, taking precedence over web_name).
    func testPlayerDisplayNameByIdPrimaryKey() {
        // Haaland's FPL element id has long been 411; even if ids drift, the web_name
        // fallback still yields Chinese, so this isn't brittle.
        let haaland = PlayerLite(id: 411, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "the id primary key should hit the full Chinese name")
    }

    /// Accented web_names (like Paquetá) must still hit the Chinese table.
    func testPlayerNameAccentedWebNameMatches() {
        // Paquetá is no longer in the 2026/27 squad (absent from FPL), so this uses
        // the equally accented and definitely-tabulated Núñez. Goal: accented
        // web_names still hit the Chinese name rather than reverting to English.
        let accented = PlayerLite(id: 999998, name: "Núñez", nationality: nil)
        XCTAssertEqual(accented.displayName(chinese: true), "达尔文·努涅斯")
    }

    /// Maintenance diff tool: missing(from:) returns only web_names absent from the
    /// table, sorted and deduplicated (known items excluded).
    func testPlayerNameMapMissingExcludesKnown() {
        // Haaland / Watkins / Rice are all in the dataset; Salah isn't in this
        // season's squad, so he must not count as known either.
        let webNames = ["Haaland", "Watkins", "Rice", "Some New Guy", "Another New Guy", "Haaland"]
        let missing = PlayerNameMap.missing(from: webNames)
        XCTAssertFalse(missing.contains("Haaland"))
        XCTAssertFalse(missing.contains("Watkins"))
        XCTAssertFalse(missing.contains("Rice"))
        XCTAssertEqual(missing, ["Another New Guy", "Some New Guy"],
                       "missing should sort, dedupe, and exclude known items")
    }

    /// Regression: the name tables are externalized as bundle resources
    /// (`Resources/PlayerNames-zh-Hans.json`); the loader must find and decode them
    /// from the app bundle — if every displayName test above is green but this one
    /// is red, the resource isn't in the target (a lost pbxproj reference).
    func testTranslationResourcesAreBundledAndLoadable() {
        // byId dimension (the resource's primary table; 1 and 411 are anchor values)
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 1), "戴维·拉亚")
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 411), "埃尔林·哈兰德")
        // The table must be the real fully-loaded table, not the empty fallback:
        // ids 1..20 all hit
        XCTAssertEqual(PlayerNameMap.missing(ids: Array(1...20)), [],
                       "ids 1..20 should all be in the table (an unloaded resource would make these all missing)")
        // Team table
        let arsenal = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                           venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(TeamNameMap.zh(for: arsenal), "阿森纳")
    }

    /// Loader robustness: a missing locale (or corrupt file) → nil; the caller falls
    /// back to an empty table and shows English.
    func testTranslationStoreMissingLocaleReturnsNil() {
        struct Payload: Decodable {}
        XCTAssertNil(TranslationStore.load("PlayerNames", locale: "xx-Nope") as Payload?,
                     "a nonexistent locale resource should return nil, not throw or crash")
    }

    // MARK: - DEBUG player-name override layer (PlayerNameOverrides)

    /// Overrides take precedence by id: overriding 426 returns the override; after
    /// reset it falls back to the built-in name. Every test resets
    /// `PlayerNameOverrides.current` via defer to avoid polluting other tests.
    func testPlayerNameOverrideByIdPrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [426: "测试覆盖名"], byName: [:])
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "测试覆盖名",
            "an id-dimension override takes precedence over the built-in Chinese name"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "布鲁诺·费尔南德斯",
            "after resetting, the built-in Chinese name returns"
        )
    }

    /// Overrides by name dimension: overriding byName["Saka"] returns the override;
    /// after reset it falls back to the built-in name. Note id precedes name, so the
    /// test must use an id **absent from zhById** to reach the name branch (an id hit
    /// would short-circuit before the name lookup). Follows this file's synthetic-id
    /// convention (999998/999999).
    func testPlayerNameOverrideByNamePrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [:], byName: ["Saka": "测试名"])
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "测试名",
            "a name-dimension override takes precedence over the built-in Chinese name"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "布卡约·萨卡",
            "after resetting, the built-in Chinese name returns"
        )
    }

    /// Guards the built-in defaults against regressions: with no overrides,
    /// id 1 → the built-in Chinese name.
    func testPlayerNameOverrideDefaultsUnchanged() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 1, name: "Raya", nationality: nil).displayName(chinese: true),
            "戴维·拉亚",
            "with no overrides the built-in Chinese name returns"
        )
    }

    /// Covers `PlayerNameStore.commit(_:)` directly: replaces the in-memory layer +
    /// syncs the static snapshot; committing empty clears both. Disk failures are
    /// swallowed by save() and don't affect the memory assertions.
    func testPlayerNameStoreCommit() {
        defer {
            PlayerNameStore.shared.commit(.init())
            PlayerNameStore.current = .init()
        }
        let store = PlayerNameStore.shared
        let sample = PlayerNameOverrides(byId: [426: "提交覆盖名"], byName: [:])

        store.commit(sample)
        XCTAssertEqual(store.overrides, sample, "after commit, the in-memory layer equals the committed value")
        XCTAssertEqual(PlayerNameStore.current, sample, "after commit, the static snapshot syncs")

        store.commit(.init())
        XCTAssertEqual(store.overrides, .init(), "committing empty clears the in-memory layer")
        XCTAssertEqual(PlayerNameStore.current, .init(), "committing empty clears the static snapshot")
    }
}
