import Foundation

// MARK: - 球队中英文映射（译名资源驱动）

/// 译名资源文件结构（`TeamNames-zh-Hans.json`，见 `TranslationStore`）
private struct TeamNamesResource: Decodable {
    /// FPL short_name（3 字母俱乐部代码）→ 中文名
    let byShort: [String: String]
}

/// 球队中文译名映射。
///
/// - 译名表本体在 `Sources/EPLViewer/Resources/TeamNames-zh-Hans.json`（21 条），
///   按 FPL `short_name` 匹配，与 app 当前数据源对齐；新增/调整球队只改 JSON。
/// - 无匹配时返回 nil，调用方自动回退英文原名；加载失败同理（表为空）。
enum TeamNameMap {
    private static let resource: TeamNamesResource? =
        TranslationStore.load("TeamNames", locale: "zh-Hans")

    private static let zhByShort: [String: String] = resource?.byShort ?? [:]

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
