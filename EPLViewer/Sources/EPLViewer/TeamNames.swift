import Foundation

// MARK: - 球队中英文映射

/// 中文队名映射表。
/// - 按 FPL `short_name`（3 字母俱乐部代码）匹配，与 app 当前数据源对齐。
/// - 纯本地展示用，不依赖网络；以后新增/调整球队只需在此追加一行。
/// - 无匹配时返回 nil，调用方自动回退英文原名。
enum TeamNameMap {
    /// FPL short_name → 中文名
    private static let zhByShort: [String: String] = [
        "ARS": "阿森纳",
        "AVL": "阿斯顿维拉",
        "BOU": "伯恩茅斯",
        "BRE": "布伦特福德",
        "BHA": "布莱顿",
        "CHE": "切尔西",
        "COV": "考文垂城",
        "CRY": "水晶宫",
        "EVE": "埃弗顿",
        "FUL": "富勒姆",
        "HUL": "赫尔城",
        "IPS": "伊普斯维奇",
        "LEE": "利兹联",
        "LIV": "利物浦",
        "MCI": "曼城",
        "MUN": "曼联",
        "NEW": "纽卡斯尔联",
        "NFO": "诺丁汉森林",
        "TOT": "托特纳姆热刺",
        "SUN": "桑德兰",
        // 真实 2026-27 PL 候选：FPL 当前为 provisional 名单（含 Coventry/Hull/Ipswich），
        // 若后续调整为真实升班马，补齐映射即可，未命中会自动回退英文。
        "BUR": "伯恩利"
    ]

    /// 取中文名；无匹配返回 nil
    static func zh(for team: Team) -> String? {
        guard let sn = team.shortName else { return nil }
        return zhByShort[sn]
    }
}

extension Team {
    /// 中文队名（无匹配为 nil）
    var nameZh: String? { TeamNameMap.zh(for: self) }

    /// 按语言偏好返回显示名
    /// - Parameter chinese: true 优先中文（无中文则回退英文）；false 恒为英文原名
    func displayName(chinese: Bool) -> String {
        chinese ? (nameZh ?? name) : name
    }
}
