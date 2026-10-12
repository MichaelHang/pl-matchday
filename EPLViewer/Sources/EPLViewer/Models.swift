import Foundation

// MARK: - 基础子模型

/// 教练信息
struct Coach: Codable, Identifiable {
    let id: Int?
    let name: String
    let nationality: String?
}

/// 球员信息（球队阵容中使用）
struct Player: Codable, Identifiable {
    let id: Int?
    let name: String
    let position: String?
    let shirtNumber: Int?
    let nationality: String?
}

/// 球队信息
struct Team: Codable, Identifiable {
    let id: Int
    let name: String
    let shortName: String?
    let crest: String?
    let venue: String?
    let founded: Int?
    let coach: Coach?
    let squad: [Player]?
}

// MARK: - 比分相关

/// 全场比分
struct FullTime: Codable {
    let home: Int?
    let away: Int?
}

/// 比分（可扩展半场等）
struct Score: Codable {
    let fullTime: FullTime?
}

// MARK: - 比赛

/// 单场比赛
struct Match: Codable, Identifiable {
    let id: Int
    let matchday: Int?
    let utcDate: String?
    let status: String?
    let stage: String?
    let homeTeam: Team
    let awayTeam: Team
    let score: Score?
}

/// 比赛列表响应
struct MatchesResponse: Decodable {
    let matches: [Match]
}

// MARK: - 球队列表

/// 球队列表响应
struct TeamsResponse: Decodable {
    let teams: [Team]
}

// MARK: - 积分榜

/// 单支球队的积分榜行
struct StandingRow: Codable, Identifiable {
    let position: Int
    let team: Team
    let playedGames: Int
    let won: Int
    let draw: Int
    let lost: Int
    let points: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let goalDifference: Int
    let form: String?         // 近 5 场胜负序列，如 "WWDLW"
    let status: String?       // 升降级区标识，如 "CHAMPIONS_LEAGUE" / "RELEGATION"
    let home: VenueStats?     // 主场战绩（ESPN 不直接给，由本地从赛程聚合）
    let away: VenueStats?     // 客场战绩（同上）

    /// 唯一标识：**不能只用 position**。
    /// 主场/客场榜会把行按该维度重排并重新编号 1...N，同一支球队在不同榜里 position 不同；
    /// 若 id 只取 position，同一榜单内可能撞 id、跨榜 diff 也会错配，SwiftUI ForEach 直接警告。
    var id: String { "pos\(position)-team\(team.id)" }

    /// 用 home/away/form 构造副本。其它字段全部沿用。
    /// 用于 enrichment 路径：ESPN 只给总积分，home/away/form 由本地从赛程聚合补全。
    func with(home: VenueStats? = nil, away: VenueStats? = nil, form: String? = nil) -> StandingRow {
        StandingRow(
            position: position, team: team,
            playedGames: playedGames, won: won, draw: draw, lost: lost,
            points: points, goalsFor: goalsFor, goalsAgainst: goalsAgainst, goalDifference: goalDifference,
            form: form ?? self.form, status: status,
            home: home ?? self.home, away: away ?? self.away
        )
    }
}

/// 球队在「主场」或「客场」维度下的战绩
struct VenueStats: Codable, Equatable {
    let played: Int
    let won: Int
    let draw: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let points: Int
}

/// 单个积分榜表格（阶段/类型 + 行）
struct StandingTable: Codable {
    let stage: String?
    let type: String?
    let table: [StandingRow]
}

/// 积分榜响应
struct StandingsResponse: Codable {
    let standings: [StandingTable]
}

// MARK: - 射手榜 / 助攻榜 / 伤停榜

/// 精简球员信息（榜单类通用）
struct PlayerLite: Decodable, Identifiable {
    let id: Int?
    let name: String
    let nationality: String?
}

/// 射手
struct Scorer: Decodable, Identifiable {
    let player: PlayerLite
    let team: Team
    let goals: Int
    let assists: Int?
    let playedMatches: Int?

    /// 稳定的唯一标识（player.id 可能为空时回退到名称）
    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }
}

/// 射手榜响应
struct ScorersResponse: Decodable {
    let scorers: [Scorer]
}

/// 助攻（与射手共用结构，按 assists 排序即可；为语义清晰单独命名）
struct Assist: Identifiable {
    let player: PlayerLite
    let team: Team
    let assists: Int
    let playedMatches: Int?
    let goals: Int?  // 顺带展示进球数

    /// 稳定的唯一标识
    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }

    init(from scorer: Scorer) {
        self.player = scorer.player
        self.team = scorer.team
        self.assists = scorer.assists ?? 0
        self.playedMatches = scorer.playedMatches
        self.goals = scorer.goals
    }
}

/// 伤停球员
struct Injury: Decodable, Identifiable {
    let player: PlayerLite
    let team: Team
    let status: String        // "i" injured / "d" doubtful / "u" unavailable / "s" suspended
    let news: String?
    let chanceOfPlayingNextRound: Int?  // 0-100
    let position: String?

    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }
}

/// 伤停响应
struct InjuriesResponse: Decodable {
    let injuries: [Injury]
}

// MARK: - 错误与数据源枚举

/// 应用错误类型
enum AppError: Error, LocalizedError {
    case noData
    case apiError(Int)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .noData:
            return "暂无数据"
        case .apiError(let code):
            return "接口返回错误（HTTP \(code)）"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .decoding:
            return "数据解析失败"
        }
    }
}

/// 数据来源
enum DataSource: String {
    case live   // 来自公开接口（ESPN + FPL）
    /// 网络失败时回退的「上次成功落盘的缓存」—— 内容真实但可能过期（stale-if-error）
    case stale
    /// 占位：完全无数据（如首次安装且从未成功联网）。不再有内置示例文件。
    case sample
}

// MARK: - 当前轮推断（网络兜底）

/// 从赛程数据本地推断「当前轮」。
///
/// 用途：FPL 的 `events` 拿不到时（接口超时 / 网络失败）的兜底。
/// 赛程页和今日页都要用，所以抽出来共用 —— 避免同一个推断规则写两遍。
enum CurrentRoundInference {
    /// - 规则：取第一个**还有未结束比赛**的轮次；若全部已结束，取最后一个有比赛的轮次。
    /// - Returns: 推断出的轮次；无任何赛程数据时返回 nil
    static func infer(from matches: [Match]) -> Int? {
        var byRound: [Int: [Match]] = [:]
        for m in matches {
            guard let r = m.matchday else { continue }
            byRound[r, default: []].append(m)
        }
        let rounds = byRound.keys.sorted()
        guard !rounds.isEmpty else { return nil }
        for r in rounds where (byRound[r] ?? []).contains(where: { $0.status != "FINISHED" }) {
            return r
        }
        return rounds.last
    }
}
