import Foundation

// MARK: - Basic submodels

/// Coach info.
struct Coach: Codable, Identifiable {
    let id: Int?
    let name: String
    let nationality: String?
}

/// Player info (used in team squads).
struct Player: Codable, Identifiable {
    let id: Int?
    let name: String
    let position: String?
    let shirtNumber: Int?
    let nationality: String?
}

/// Team info.
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

// MARK: - Scores

/// Full-time score.
struct FullTime: Codable {
    let home: Int?
    let away: Int?
}

/// Score (extensible with halftime etc.).
struct Score: Codable {
    let fullTime: FullTime?
}

// MARK: - Matches

/// A single match.
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

/// Matches list response.
struct MatchesResponse: Decodable {
    let matches: [Match]
}

// MARK: - Teams

/// Teams list response.
struct TeamsResponse: Decodable {
    let teams: [Team]
}

// MARK: - Standings

/// One team's standings row.
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
    let form: String?         // last-5 results, e.g. "WWDLW"
    let status: String?       // zone marker, e.g. "CHAMPIONS_LEAGUE" / "RELEGATION"
    let home: VenueStats?     // home record (ESPN doesn't provide it; aggregated locally from fixtures)
    let away: VenueStats?     // away record (same)

    /// Stable identity: **position alone is not enough**.
    /// Home/away tables re-sort and renumber rows 1...N within that dimension, so the
    /// same team has different positions in different tables; an id of just the
    /// position could collide within one table and misalign cross-table diffing,
    /// triggering SwiftUI ForEach warnings.
    var id: String { "pos\(position)-team\(team.id)" }

    /// Copy with home/away/form replaced; every other field is carried over.
    /// Used by the enrichment path: ESPN only provides totals; home/away/form are
    /// aggregated locally from fixtures.
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

/// A team's record in the home or away dimension.
struct VenueStats: Codable, Equatable {
    let played: Int
    let won: Int
    let draw: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let points: Int
}

/// One standings table (stage/type + rows).
struct StandingTable: Codable {
    let stage: String?
    let type: String?
    let table: [StandingRow]
}

/// Standings response.
struct StandingsResponse: Codable {
    let standings: [StandingTable]
}

// MARK: - Scorers / assists / injuries

/// Minimal player info (shared by leaderboard models).
struct PlayerLite: Decodable, Identifiable {
    let id: Int?
    let name: String
    let nationality: String?
}

/// A scorer.
struct Scorer: Decodable, Identifiable {
    let player: PlayerLite
    let team: Team
    let goals: Int
    let assists: Int?
    let playedMatches: Int?

    /// Stable identity (falls back to the name when player.id is nil).
    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }
}

/// Scorers response.
struct ScorersResponse: Decodable {
    let scorers: [Scorer]
}

/// An assist entry (same shape as Scorer, sorted by assists; named separately for clarity).
struct Assist: Identifiable {
    let player: PlayerLite
    let team: Team
    let assists: Int
    let playedMatches: Int?
    let goals: Int?  // shown alongside

    /// Stable identity.
    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }

    init(from scorer: Scorer) {
        self.player = scorer.player
        self.team = scorer.team
        self.assists = scorer.assists ?? 0
        self.playedMatches = scorer.playedMatches
        self.goals = scorer.goals
    }
}

/// An injured/unavailable player.
struct Injury: Decodable, Identifiable {
    let player: PlayerLite
    let team: Team
    let status: String        // "i" injured / "d" doubtful / "u" unavailable / "s" suspended
    let news: String?
    let chanceOfPlayingNextRound: Int?  // 0-100
    let position: String?

    var id: String { "\(player.id.map(String.init) ?? player.name)-\(team.id)" }
}

/// Injuries response.
struct InjuriesResponse: Decodable {
    let injuries: [Injury]
}

// MARK: - Errors & data source

/// App error type.
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

/// Where the data came from.
enum DataSource: String {
    case live   // from the public APIs (ESPN + FPL)
    /// The last successfully persisted cache, served on network failure —
    /// real content, possibly outdated (stale-if-error).
    case stale
    /// Placeholder: no data at all (e.g. offline on first launch). No bundled samples.
    case sample
}

// MARK: - Current-round inference (network fallback)

/// Infers the "current round" locally from fixtures.
///
/// Used as a fallback when FPL `events` is unavailable (timeout / network failure).
/// Both the fixtures page and the today page need it, so the rule lives here once
/// instead of being written twice.
enum CurrentRoundInference {
    /// - Rule: the first round that still has unfinished matches; if all are finished,
    ///   the last round with any matches.
    /// - Returns: the inferred round; nil when there is no fixture data at all.
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
