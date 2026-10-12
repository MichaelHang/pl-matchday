import XCTest
@testable import EPLViewer

// 译名:球队与球员映射 / 调试覆盖层
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
    // MARK: - 球队中英文映射

    /// 中文队名映射：chinese=true 命中返回中文、未命中回退英文；false 恒为英文
    func testTeamDisplayNameChinese() throws {
        let arsenal = Team(id: 1, name: "Arsenal", shortName: "ARS", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(arsenal.displayName(chinese: true), "阿森纳")
        XCTAssertEqual(arsenal.displayName(chinese: false), "Arsenal")

        let city = Team(id: 15, name: "Manchester City", shortName: "MCI", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(city.displayName(chinese: true), "曼城")

        // 未知 short_name：中文模式回退英文原名
        let unknown = Team(id: 999, name: "Nowhere FC", shortName: "NOW", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(unknown.displayName(chinese: true), "Nowhere FC")

        // 缺 short_name：无法匹配中文，回退英文
        let noShort = Team(id: 998, name: "Some Team", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(noShort.displayName(chinese: true), "Some Team")
    }
}

extension EPLViewerTests {
    // MARK: - 球员中英文名映射（PlayerNames）

    /// 中文模式下已知球星返回中文全名；英文模式恒为原名；未知球员回退英文原名（绝不空白/崩溃）。
    /// 用 sentinel id（999999，不在 zhById 中）隔离出 web_name 回退路径，避免与真实 id 碰撞。
    func testPlayerDisplayNameChineseKnownAndFallback() {
        let haaland = PlayerLite(id: 999999, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "Haaland 应命中中文全名（web_name 回退路径）")
        XCTAssertEqual(haaland.displayName(chinese: false), "Haaland",
                       "英文模式恒为 FPL web_name 原名")

        let nobody = PlayerLite(id: 999999, name: "Unknown Player", nationality: nil)
        XCTAssertEqual(nobody.displayName(chinese: true), "Unknown Player",
                       "未知球员中文模式应回退英文原名，不能空白")
    }

    /// 主键路径：FPL element id 命中时直接返回中文全名（id 跨赛季/转会稳定，优先于 web_name）。
    func testPlayerDisplayNameByIdPrimaryKey() {
        // Haaland 的 FPL element id 长期稳定为 411；即便未来 id 漂移，web_name 回退仍给出中文，故不脆弱。
        let haaland = PlayerLite(id: 411, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "按 id 主键应命中中文全名")
    }

    /// 带重音的 web_name（如 Paquetá）应命中中文名。
    func testPlayerNameAccentedWebNameMatches() {
        // Paquetá 已不在 2026/27 阵容（FPL 无此人），故改用同样带重音且确实入表的 Núñez。
        // 目的：带重音的 web_name 仍能命中中文译名，而非退回英文原文。
        let accented = PlayerLite(id: 999998, name: "Núñez", nationality: nil)
        XCTAssertEqual(accented.displayName(chinese: true), "达尔文·努涅斯")
    }

    /// 维护差量工具：missing(from:) 只返回表中没有的 web_name，且已排序去重（已知项被排除）。
    func testPlayerNameMapMissingExcludesKnown() {
        // Haaland / Watkins / Rice 均在数据集中；Salah 本赛季不在阵容，故也不应被当成已知。
        let webNames = ["Haaland", "Watkins", "Rice", "Some New Guy", "Another New Guy", "Haaland"]
        let missing = PlayerNameMap.missing(from: webNames)
        XCTAssertFalse(missing.contains("Haaland"))
        XCTAssertFalse(missing.contains("Watkins"))
        XCTAssertFalse(missing.contains("Rice"))
        XCTAssertEqual(missing, ["Another New Guy", "Some New Guy"],
                       "missing 应排序去重，且不含已知项")
    }

    /// 回归：译名表已外部化为 bundle 资源（`Resources/PlayerNames-zh-Hans.json`），
    /// 加载器必须能在 App bundle 里找到并解码 —— 上面各 displayName 测试若全绿但本用例红，
    /// 说明资源文件没被打进 target（pbxproj 引用丢失）。
    func testTranslationResourcesAreBundledAndLoadable() {
        // byId 维度（资源文件的主键表；1 与 411 是表内锚点值）
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 1), "戴维·拉亚")
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 411), "埃尔林·哈兰德")
        // 表必须是真实加载的完整表，而不是加载失败后的空表兜底：1..20 全命中
        XCTAssertEqual(PlayerNameMap.missing(ids: Array(1...20)), [],
                       "id 1..20 应全部在译名表中（资源未加载时这里会全量 missing）")
        // 球队表
        let arsenal = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                           venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(TeamNameMap.zh(for: arsenal), "阿森纳")
    }

    /// 加载器健壮性：locale 不存在（或文件损坏）→ nil，由调用方回退空表显示英文。
    func testTranslationStoreMissingLocaleReturnsNil() {
        struct Payload: Decodable {}
        XCTAssertNil(TranslationStore.load("PlayerNames", locale: "xx-Nope") as Payload?,
                     "不存在的 locale 资源应返回 nil，而不是抛错或崩溃")
    }

    // MARK: - 调试期球员中文名覆盖层（PlayerNameOverrides）

    /// 覆盖层按 id 维度优先：覆盖 426 后返回覆盖名；复位后回退内置「布鲁诺·费尔南德斯」。
    /// 每个测试都 defer 复位 `PlayerNameOverrides.current`，避免污染其它测试。
    func testPlayerNameOverrideByIdPrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [426: "测试覆盖名"], byName: [:])
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "测试覆盖名",
            "id 维度覆盖应优先于内置中文名"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "布鲁诺·费尔南德斯",
            "复位覆盖后应回退到内置中文名"
        )
    }

    /// 覆盖层按 name 维度：覆盖 byName["Saka"] 后返回覆盖名；复位后回退内置「布卡约·萨卡」。
    /// 注意：id 维度优先于 name 维度，故必须用「不在 zhById 中的 id」才能落到 name 分支
    /// （若 id 命中内置表，name 覆盖根本不会被走到）。沿用本文件既有的合成 id 约定（999998/999999）。
    func testPlayerNameOverrideByNamePrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [:], byName: ["Saka": "测试名"])
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "测试名",
            "name 维度覆盖应优先于内置中文名"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "布卡约·萨卡",
            "复位覆盖后应回退到内置中文名"
        )
    }

    /// 守卫内置默认值不被回归：无覆盖时 id 1 → 「戴维·拉亚」。
    func testPlayerNameOverrideDefaultsUnchanged() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 1, name: "Raya", nationality: nil).displayName(chinese: true),
            "戴维·拉亚",
            "无覆盖时应返回内置中文名"
        )
    }

    /// 直接覆盖 `PlayerNameStore.commit(_:)`：替换内存覆盖层 + 同步静态快照；
    /// 提交空值应清空两者。落盘失败被 `save()` 吞掉，不影响内存断言。
    func testPlayerNameStoreCommit() {
        defer {
            PlayerNameStore.shared.commit(.init())
            PlayerNameStore.current = .init()
        }
        let store = PlayerNameStore.shared
        let sample = PlayerNameOverrides(byId: [426: "提交覆盖名"], byName: [:])

        store.commit(sample)
        XCTAssertEqual(store.overrides, sample, "commit 后内存覆盖层应等于提交值")
        XCTAssertEqual(PlayerNameStore.current, sample, "commit 后静态快照应同步")

        store.commit(.init())
        XCTAssertEqual(store.overrides, .init(), "commit 空值应清空内存覆盖层")
        XCTAssertEqual(PlayerNameStore.current, .init(), "commit 空值应清空静态快照")
    }
}
