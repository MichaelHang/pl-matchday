import Foundation

// MARK: - 球员中英文映射（译名资源驱动：JSON 译名表 + 运行期覆盖层）

/// 译名资源文件结构（`PlayerNames-zh-Hans.json`，见 `TranslationStore`）
private struct PlayerNamesResource: Decodable {
    /// FPL element id（字符串键）→ 中文全名
    let byId: [String: String]
    /// web_name → 中文全名（二级回退）
    let byName: [String: String]
}

/// 球员中文译名映射。
///
/// 数据分层（优先级从高到低）：
/// 1. 覆盖层 `PlayerNameStore.current`（调试面板维护，运行期落盘，永不进仓库）；
/// 2. id 维度译名表 `zhById`（FPL element id，稳定、跨赛季/转会不随姓名变化）；
/// 3. web_name 维度译名表 `zhByName`（重姓碰撞时不如 id 可靠，故仅作回退）；
/// 4. 英文原名（最终回退，绝不空白）。
///
/// 译名表本体在 `Sources/EPLViewer/Resources/PlayerNames-zh-Hans.json`（667 条 id + 220 条 web_name），
/// 维护方式：直接编辑 JSON 后重新编译；运行期临时修正走调试面板覆盖层。
/// `missing(ids:)` / `missing(from:)` 可差分出「本赛季还没有中文名」的现役名单，补表是机械活。
enum PlayerNameMap {
    /// 译名资源加载失败（文件缺失/损坏）→ 双表为空，全部回退英文原名
    private static let resource: PlayerNamesResource? =
        TranslationStore.load("PlayerNames", locale: "zh-Hans")

    /// FPL element id → 中文全名（主键维度）
    private static let zhById: [Int: String] = {
        guard let byId = resource?.byId else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: byId.compactMap { key, value in Int(key).map { ($0, value) } }
        )
    }()

    /// web_name → 中文全名（二级回退维度）
    private static let zhByName: [String: String] = resource?.byName ?? [:]

    /// 取中文名；无匹配返回 nil。
    /// 覆盖层优先：覆盖层（调试期开发者自定义）胜出；id 维度仍先于 name 维度。
    static func zh(for player: PlayerLite) -> String? {
        let o = PlayerNameStore.current
        if let pid = player.id, let c = (o.byId[pid] ?? zhById[pid]) { return c }
        if let c = (o.byName[player.name] ?? zhByName[player.name]) { return c }
        return nil
    }

    /// 仅取译名表中文名（不含覆盖层）；供调试面板判断「是否冗余覆盖」做基线。
    static func builtInName(forId id: Int) -> String? { zhById[id] }

    /// 维护用：给定一批 FPL element id（现役球员），返回映射表缺失中文名的那些（已排序）。
    static func missing(ids: [Int]) -> [Int] {
        ids.filter { zhById[$0] == nil }.sorted()
    }

    /// 维护用（兼容 web_name 维度）：给定一批 web_name，返回缺失中文名的那些（已排序去重）。
    static func missing(from webNames: [String]) -> [String] {
        Set(webNames).subtracting(zhByName.keys).sorted()
    }
}

extension PlayerLite {
    /// 中文名（无匹配为 nil）
    var nameZh: String? { PlayerNameMap.zh(for: self) }

    /// 按语言偏好返回显示名：中文模式下优先中文（无则回退英文），英文模式恒为英文原名
    func displayName(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}
