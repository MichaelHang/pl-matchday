import Foundation

// MARK: - 聚合 / enrichment / 翻译器（wire 模型 → 内部 domain）

/// 已结束赛事聚合得到的"准实时积分榜"
/// 关键能力：当 v3 standings records 字段尚未生成时，从已踢完的赛事实时算 W/D/L/Pts/GF/GA。
struct StandingsAggregator {
    /// 内部条目：teamId + 比分
    struct RowStat {
        var played: Int = 0
        var won: Int = 0
        var draw: Int = 0
        var lost: Int = 0
        var gf: Int = 0
        var ga: Int = 0
        func points() -> Int { won * 3 + draw }
        func gd() -> Int { gf - ga }
    }

    /// 拉过去 N 天已结束赛事，统计 W/D/L/Pts/GF/GA，按积分降序
    /// - 实现：拉 events 列表 → follow 每个赛事（status.state == "post"）→ 统计
    /// - 缓存：单赛事详情缓存 5 分钟（赛事比分很少变），汇总结果缓存 60 秒（与 standings TTL 对齐）
    static func aggregate(daysBack: Int = 14) async throws -> [StandingRow] {
        // 1. 计算日期范围
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"; df.timeZone = TimeZone(identifier: "UTC")
        let dates = "\(df.string(from: start))-\(df.string(from: now))"

        // 2. 拉赛事 ID
        let eventIds = try await ESPNEventsProvider.fetchEventIds(dates: dates)
        guard !eventIds.isEmpty else { return [] }

        // 3. 并发 follow 单场赛事详情（8 并发足够，避免过度请求）
        let details: [ESPNEventDetailV3] = await withTaskGroup(of: ESPNEventDetailV3?.self) { group in
            var results: [ESPNEventDetailV3] = []
            let semaphore = AsyncSemaphore(value: 8)
            for id in eventIds {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    return (try? await ESPNEventsProvider.fetchEventDetail(eventId: id))
                }
            }
            for await detail in group {
                if let d = detail { results.append(d) }
            }
            return results
        }

        // 4. 筛选已结束赛事 + 解析 W/D/L（GF/GA 等比分并发拉完后再统一累加）
        var stats: [Int: RowStat] = [:]   // key = ESPN team.id (Int)
        var teamMeta: [Int: ESPNTeamRefV3] = [:]   // 用于赛后回填 team 详情
        var finishedPairs: [(eventId: String, homeId: Int, awayId: Int)] = []   // 待补比分的已结束赛事

        for detail in details {
            guard let comp = detail.competitions?.first else { continue }
            // 仅处理已结束赛事：
            //   v3 单场赛事里 status 字段是 $ref 需要再 follow；这里用更直接的方式：
            //   任一 competitor.winner 字段不是 nil → 该场已出胜负（draw 时两队 winner 都为 false）
            //   进行中 / 未开始赛事的 winner 字段均为 nil
            guard let competitors = comp.competitors, competitors.count >= 2 else { continue }
            let hasResult = competitors.contains { $0.winner != nil }
            guard hasResult else { continue }

            // 拿主客（v3 单场赛事里 team 是 $ref；用 competitor.id 即为 team id）
            let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
            let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
            guard let homeId = Int(home.id ?? ""),
                  let awayId = Int(away.id ?? "") else { continue }

            // team ref 用于赛后回填（可选）
            if let h = home.team { teamMeta[homeId] = h }
            if let a = away.team { teamMeta[awayId] = a }

            // 拿 score：competitors.score 经常是 $ref，需要 follow —— 记下本场主客，稍后并发拉取
            finishedPairs.append((eventId: detail.id ?? "", homeId: homeId, awayId: awayId))

            // 即时统计：先按 winner 算 W/D/L，GF/GA 后续补
            let homeWin = home.winner == true
            let awayWin = away.winner == true
            let draw = (home.winner == false && away.winner == false && home.winner != nil)

            // 拿到 team 后再聚合：每个赛事算主客的两条统计
            var hst = stats[homeId] ?? RowStat()
            var ast = stats[awayId] ?? RowStat()
            hst.played += 1
            ast.played += 1
            if homeWin {
                hst.won += 1
                ast.lost += 1
            } else if awayWin {
                ast.won += 1
                hst.lost += 1
            } else if draw {
                hst.draw += 1
                ast.draw += 1
            }
            stats[homeId] = hst
            stats[awayId] = ast
        }

        // 5. 并发 follow 每场已结束赛事双方的比分（score 在 v3 里是 $ref）。
        //    原实现在主循环里逐场串行 await —— 一轮 10 场要串行发 20 个请求，慢得离谱。
        var scores: [String: Int] = [:]   // key = "eventId-teamId"
        await withTaskGroup(of: (String, Int).self) { group in
            let semaphore = AsyncSemaphore(value: 8)
            for pair in finishedPairs {
                for teamId in [pair.homeId, pair.awayId] {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }
                        let value = (try? await ESPNEventsProvider.fetchCompetitorScore(
                            eventId: pair.eventId, competitorId: String(teamId))) ?? 0
                        return ("\(pair.eventId)-\(teamId)", value)
                    }
                }
            }
            for await (key, value) in group {
                scores[key] = value
            }
        }

        // 6. 用真实比分**累加** GF/GA（一支球队打了多场，GF/GA 是总和；
        //    旧实现在这里用 `=` 覆盖，导致 GF/GA 永远只剩最后一场的数字）
        for pair in finishedPairs {
            let hg = scores["\(pair.eventId)-\(pair.homeId)"] ?? 0
            let ag = scores["\(pair.eventId)-\(pair.awayId)"] ?? 0
            var hst = stats[pair.homeId] ?? RowStat()
            var ast = stats[pair.awayId] ?? RowStat()
            hst.gf += hg; hst.ga += ag
            ast.gf += ag; ast.ga += hg
            stats[pair.homeId] = hst
            stats[pair.awayId] = ast
        }

        // 7. follow team 详情拿 name/crest（去重，并发）
        let teamIds = Array(teamMeta.keys)
        var resolvedTeams: [Int: ESPNTeamRefV3] = [:]
        await withTaskGroup(of: (Int, ESPNTeamRefV3?).self) { group in
            for id in teamIds {
                group.addTask {
                    if let t = try? await ESPNEventsProvider.fetchTeam(teamId: String(id)) {
                        return (id, t)
                    }
                    return (id, nil)
                }
            }
            for await (id, t) in group {
                if let t = t { resolvedTeams[id] = t }
            }
        }

        // 8. 装配 StandingRow
        let rows: [StandingRow] = stats.map { (teamId, st) in
            let name = resolvedTeams[teamId]?.displayName ?? resolvedTeams[teamId]?.name ?? "Team #\(teamId)"
            let crest = resolvedTeams[teamId]?.logos?.first?.href
            let team = Team(
                id: teamId, name: name, shortName: resolvedTeams[teamId]?.abbreviation,
                crest: crest, venue: nil, founded: nil, coach: nil, squad: nil
            )
            return StandingRow(
                position: 0,   // 排序后再赋
                team: team,
                playedGames: st.played, won: st.won, draw: st.draw, lost: st.lost,
                points: st.points(), goalsFor: st.gf, goalsAgainst: st.ga,
                goalDifference: st.gd(),
                form: nil, status: nil, home: nil, away: nil
            )
        }
        // 完全同分同净胜球同进球时按 teamId 稳定排序 —— stats 是字典、遍历顺序不定，
        // 不加最终 tiebreak 的话，两次渲染的行序可能不同
        let sorted = rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.team.id < $1.team.id
        }
        return sorted.enumerated().map { (idx, r) in
            StandingRow(position: idx + 1, team: r.team,
                       playedGames: r.playedGames, won: r.won, draw: r.draw, lost: r.lost,
                       points: r.points, goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst,
                       goalDifference: r.goalDifference, form: r.form, status: r.status, home: nil, away: nil)
        }
    }

    /// 从已拉取的赛果（含比分）实时聚合积分榜。
    /// 复用赛程数据源（scoreboard），避免再走 core/events 的 $ref 链；
    /// 只统计 status == FINISHED 且含比分的比赛，未参赛球队不会出现、也不会得到积分。
    static func aggregate(matches: [Match]) -> [StandingRow] {
        var stats: [Int: RowStat] = [:]
        var teamMeta: [Int: Team] = [:]
        for m in matches where m.status == "FINISHED" {
            guard let ft = m.score?.fullTime, let h = ft.home, let a = ft.away else { continue }
            let hid = m.homeTeam.id, aid = m.awayTeam.id
            teamMeta[hid] = m.homeTeam
            teamMeta[aid] = m.awayTeam
            var hs = stats[hid] ?? RowStat()
            var as_ = stats[aid] ?? RowStat()
            hs.played += 1; as_.played += 1
            if h > a      { hs.won += 1; as_.lost += 1 }
            else if a > h { as_.won += 1; hs.lost += 1 }
            else          { hs.draw += 1; as_.draw += 1 }
            hs.gf += h; hs.ga += a
            as_.gf += a; as_.ga += h
            stats[hid] = hs; stats[aid] = as_
        }
        let rows: [StandingRow] = stats.map { (teamId, st) in
            let team = teamMeta[teamId] ?? Team(
                id: teamId, name: "Team #\(teamId)", shortName: nil, crest: nil,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            return StandingRow(
                position: 0, team: team,
                playedGames: st.played, won: st.won, draw: st.draw, lost: st.lost,
                points: st.points(), goalsFor: st.gf, goalsAgainst: st.ga,
                goalDifference: st.gd(), form: nil, status: nil, home: nil, away: nil
            )
        }
        // 完全同分同净胜球同进球时按 teamId 稳定排序 —— stats 是字典、遍历顺序不定，
        // 不加最终 tiebreak 的话，两次渲染的行序可能不同
        let sorted = rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.team.id < $1.team.id
        }
        return sorted.enumerated().map { (idx, r) in
            StandingRow(position: idx + 1, team: r.team,
                       playedGames: r.playedGames, won: r.won, draw: r.draw, lost: r.lost,
                       points: r.points, goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst,
                       goalDifference: r.goalDifference, form: r.form, status: r.status, home: nil, away: nil)
        }
    }
}

// MARK: - 积分榜 enrichment（home/away 拆分 + form）

/// ESPN 现行的 standings API 不直接返回「主场战绩 / 客场战绩」拆分。
/// 这个模块从已结束的赛程本地聚合：
/// - `venueStats(for:matches:isHome:)`：算某队主场或客场的 W/D/L/GF/GA/Pts
/// - `formString(for:matches:last:)`：从最近 N 场完赛推导 W/D/L 序列
/// - `enrich(rows:with:matches:)`：给一行 StandingRow 补 home/away（仅当原来没值时）
///
/// 是纯函数（不依赖环境），便于单元测试。
struct StandingsEnricher {

    /// 某队在「主场」或「客场」维度下的战绩。
    /// - Parameters:
    ///   - teamId: 球队 id
    ///   - matches: 全部比赛（含未开赛、进行中、已结束；本函数只取已结束 + 有比分的）
    ///   - isHome: true=仅算主场比赛，false=仅算客场比赛
    /// - Returns: `nil` 表示「该队在指定维度下没有任何已结束比赛」（UI 区分"无数据"与"踢了但全输"）
    static func venueStats(for teamId: Int, matches: [Match], isHome: Bool) -> VenueStats? {
        let relevant = matches.filter { m in
            guard m.status == "FINISHED",
                  let _ = m.score?.fullTime?.home,
                  let _ = m.score?.fullTime?.away
            else { return false }
            return isHome ? (m.homeTeam.id == teamId) : (m.awayTeam.id == teamId)
        }
        guard !relevant.isEmpty else { return nil }

        var played = 0, won = 0, draw = 0, lost = 0
        var gf = 0, ga = 0
        for m in relevant {
            let hs = m.score?.fullTime?.home ?? 0
            let as_ = m.score?.fullTime?.away ?? 0
            let myScore = isHome ? hs : as_
            let oppScore = isHome ? as_ : hs
            played += 1
            gf += myScore
            ga += oppScore
            if myScore > oppScore { won += 1 }
            else if myScore == oppScore { draw += 1 }
            else { lost += 1 }
        }
        return VenueStats(played: played, won: won, draw: draw, lost: lost,
                          goalsFor: gf, goalsAgainst: ga, points: won * 3 + draw)
    }

    /// 从某队最近 N 场已结束比赛推导胜负序列（如 "WWDLW"）。
    /// - 顺序：从早到晚
    /// - 没有可统计的比赛 → 返回 nil（不是空串，方便 UI 区分「无数据」与「全胜」）
    static func formString(for teamId: Int, matches: [Match], last: Int = 5) -> String? {
        let finished = matches
            .filter { $0.status == "FINISHED"
                && ($0.homeTeam.id == teamId || $0.awayTeam.id == teamId)
                && $0.score?.fullTime?.home != nil
                && $0.score?.fullTime?.away != nil }
            .sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }   // 升序：最早在前
            .suffix(last)                                          // 取最近 N 场（仍升序）
        guard !finished.isEmpty else { return nil }
        return finished.map { m -> String in
            let isHome = m.homeTeam.id == teamId
            let hs = m.score?.fullTime?.home ?? 0
            let as_ = m.score?.fullTime?.away ?? 0
            let myScore = isHome ? hs : as_
            let oppScore = isHome ? as_ : hs
            if myScore > oppScore { return "W" }
            if myScore == oppScore { return "D" }
            return "L"
        }.joined()
    }

    /// 把外部数据源给的 form 归一成紧凑的 "WWDLW"。
    ///
    /// 各数据源写法不统一（有的带分隔符 "W,W,D,L,W"、有的带空格或无 D），
    /// 而 UI 按「前 5 个字符」渲染 —— 不归一会把分隔符当成场次画进胶囊，
    /// 视觉上就像"状态没有更新"。只保留 W/D/L，去掉其它字符后取最近 5 场。
    static func normalizeForm(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let letters = String(raw.filter { $0 == "W" || $0 == "D" || $0 == "L" })
        return letters.isEmpty ? nil : String(letters.suffix(5))
    }

    /// 用 matches 给 standings 行补全 home/away/form。
    /// 行为：原有值不覆盖（可能更权威）；没填的用本地聚合补。
    /// 纯函数；空 rows/空 matches 直接返回原 rows。
    static func enrich(rows: [StandingRow], with matches: [Match]) -> [StandingRow] {
        guard !rows.isEmpty else { return rows }
        return rows.map { row in
            let home = row.home ?? venueStats(for: row.team.id, matches: matches, isHome: true)
            let away = row.away ?? venueStats(for: row.team.id, matches: matches, isHome: false)
            // ⚠️ 必须在这里算 form：ESPN standings 端点不给近 5 场，而 enrich() 原本只补 home/away，
            // 导致「状态」tab 长期全破折号。已有值先归一化（去分隔符），没有才从赛程推导。
            let form = normalizeForm(row.form) ?? formString(for: row.team.id, matches: matches)
            return row.with(home: home, away: away, form: form)
        }
    }
}

/// 简易信号量（控制并发数）
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(value: Int) { self.value = value }
    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
    }
    func signal() {
        if let w = waiters.first {
            waiters.removeFirst(); w.resume()
        } else {
            value += 1
        }
    }
}

// MARK: - 内部模型翻译器（ESPN/FPL native → 内部 domain）

/// ESPN 状态名 → 内部统一状态字符串
enum StatusTranslator {
    static func translate(_ espnName: String?) -> String {
        switch espnName {
        case "STATUS_FINAL":        return "FINISHED"
        case "STATUS_SCHEDULED":    return "SCHEDULED"
        case "STATUS_IN_PROGRESS":  return "IN_PLAY"
        case "STATUS_HALFTIME":     return "HALFTIME"
        case "STATUS_POSTPONED":    return "POSTPONED"
        case "STATUS_CANCELED",
             "STATUS_CANCELLED":    return "CANCELED"
        default:                     return espnName ?? "SCHEDULED"
        }
    }
}

/// FPL bootstrap → 内部 Team / Player / Scorer / Assist / Injury 的派生
enum FPLTranslator {
    /// FPL 球队 id → 内部 Team（含从 elements 派生的 squad）
    static func teams(from bootstrap: FPLBootstrap) -> [Team] {
        let positionMap = Dictionary(
            uniqueKeysWithValues: bootstrap.element_types.map { ($0.id, $0.singular_name) }
        )
        let playersByTeam = Dictionary(grouping: bootstrap.elements) { $0.team }

        return bootstrap.teams.map { fplTeam in
            let players = (playersByTeam[fplTeam.id] ?? []).map { fplPlayer in
                Player(
                    id: fplPlayer.id,
                    name: fplPlayer.web_name,
                    position: positionMap[fplPlayer.element_type],
                    shirtNumber: nil,                 // FPL 无号码
                    nationality: nil                  // FPL 无国籍（需另调 element-summary，留待 v2）
                )
            }
            return Team(
                id: fplTeam.id,
                name: fplTeam.name,
                shortName: fplTeam.short_name,
                crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fplTeam.code).png",
                venue: nil,                          // FPL 无球场
                founded: nil,
                coach: nil,                          // FPL 无教练
                squad: players
            )
        }
    }

    /// 球队 id 查找（含 squad）
    static func team(id: Int, from bootstrap: FPLBootstrap) -> Team? {
        teams(from: bootstrap).first { $0.id == id }
    }

    /// 射手榜（按 goals_scored 降序，展示所有进球球员）
    /// 射手榜（按 goals_scored 降序；limit>0 时截前 N 名）
    static func scorers(from bootstrap: FPLBootstrap, limit: Int = 0) -> [Scorer] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let all = bootstrap.elements
            .filter { $0.goals_scored > 0 }
            .sorted { $0.goals_scored > $1.goals_scored }
            .compactMap { p -> Scorer? in
                guard let fpl = teamById[p.team] else { return nil }
                return Scorer(
                    player: PlayerLite(id: p.id, name: p.web_name, nationality: nil),
                    team: Team(
                        id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                        crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                        venue: nil, founded: nil, coach: nil, squad: nil
                    ),
                    goals: p.goals_scored,
                    assists: p.assists,
                    playedMatches: nil
                )
            }
        return limit > 0 ? Array(all.prefix(limit)) : all
    }

    /// 助攻榜（按 assists 降序；limit>0 时截前 N 名）
    static func assists(from bootstrap: FPLBootstrap, limit: Int = 0) -> [Assist] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let all = bootstrap.elements
            .filter { $0.assists > 0 }
            .sorted { $0.assists > $1.assists }
            .compactMap { p -> Assist? in
                guard let fpl = teamById[p.team] else { return nil }
                let lite = PlayerLite(id: p.id, name: p.web_name, nationality: nil)
                let team = Team(
                    id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                    crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                    venue: nil, founded: nil, coach: nil, squad: nil
                )
                return Assist(from: Scorer(
                    player: lite, team: team, goals: p.goals_scored,
                    assists: p.assists, playedMatches: nil
                ))
            }
        return limit > 0 ? Array(all.prefix(limit)) : all
    }

    /// 伤停榜（status != "a"）
    static func injuries(from bootstrap: FPLBootstrap) -> [Injury] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let positionMap = Dictionary(
            uniqueKeysWithValues: bootstrap.element_types.map { ($0.id, $0.singular_name) }
        )
        return bootstrap.elements
            .filter { $0.status != "a" }
            .compactMap { p -> Injury? in
                guard let fpl = teamById[p.team] else { return nil }
                return Injury(
                    player: PlayerLite(id: p.id, name: p.web_name, nationality: nil),
                    team: Team(
                        id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                        crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                        venue: nil, founded: nil, coach: nil, squad: nil
                    ),
                    status: p.status,
                    news: p.news?.isEmpty == false ? p.news : nil,
                    chanceOfPlayingNextRound: p.chance_of_playing_next_round,
                    position: positionMap[p.element_type]
                )
            }
    }

    /// 赛程（从 FPL fixtures 派生，自带轮次 event、真实比分、官方队徽）
    static func matches(from fixtures: [FPLFixture], teams: [FPLTeam]) -> [Match] {
        let teamById = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        return fixtures.compactMap { f in
            guard let h = teamById[f.team_h], let a = teamById[f.team_a] else { return nil }
            let home = Team(id: h.id, name: h.name, shortName: h.short_name,
                            crest: fplCrest(h.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let away = Team(id: a.id, name: a.name, shortName: a.short_name,
                            crest: fplCrest(a.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let hasScore = f.team_h_score != nil && f.team_a_score != nil
            // 「已结束」的权威判定，三选一即可，避免 FPL 翻转 finished 前的滞后
            // 把已结束比赛误判为进行中（导致 ⚽ 误显示）：
            //   1) finished 真正置位；
            //   2) finished_provisional：FPL 终场即置，且不会在中场/进行中误触发（最可靠）；
            //   3) minutes >= 90：分钟数兜底。
            // 仅当「未结束且已开球且未满 90 分钟」才保持 IN_PLAY，由 UI 加 ⚽ 标识区分进行中 / 已结束。
            let over = f.finished
                    || f.finished_provisional == true
                    || (f.minutes ?? 0) >= 90
            let status: String = over ? "FINISHED"
                            : (f.started == true ? "IN_PLAY" : "SCHEDULED")
            // 有比分就填充（不仅限于已结束）：进行中也能显示实时比分，
            // 由 FixturesView 通过 status == IN_PLAY 加 ⚽ 标识区分「进行中 / 已结束」
            let score: Score? = hasScore
                ? Score(fullTime: FullTime(home: f.team_h_score!, away: f.team_a_score!))
                : nil
            let id = (f.event ?? 0) * 1_000_000 + f.team_h * 1_000 + f.team_a
            return Match(id: id, matchday: f.event, utcDate: f.kickoff_time,
                         status: status, stage: nil, homeTeam: home, awayTeam: away, score: score)
        }
    }

    /// FPL 球队 code → 官方队徽 URL
    private static func fplCrest(_ code: Int) -> String {
        "https://resources.premierleague.com/premierleague/badges/50/t\(code).png"
    }
}

/// ESPN standings → 内部 StandingRow 列表
/// 适配 v3 core API：顶层 standings 数组，每项含 records 与 stats；
/// 赛季初（8 月底）records 可能为空，调用方对空 result 做兜底。
enum ESPNTranslator {
    /// 老 v2 模型（保留为兼容 fallback）
    static func standingRows(from resp: ESPNStandingsResponse) -> [StandingRow] {
        let entries = resp.children?.first?.standings.entries ?? []
        return translateStandingsV2(entries: entries)
    }

    /// 新 v3 core 模型
    static func standingRows(from resp: ESPNStandingsCoreResponse) -> [StandingRow] {
        guard resp.standings.count > 0 else { return [] }
        // 赛季初 records 为空时，把 entries 按 rank/appearance 渲染成 zero-data rows
        // ——Repository 看到空 rows 会再回退本地 JSON；如果用户愿意看"20队已列出但当前积分暂未填"，可以保留。
        let hasAnyRecords = resp.standings.contains { ($0.records?.isEmpty == false) }
        if !hasAnyRecords { return [] }   // 真空 → 触发 Repository 回退本地

        return resp.standings.enumerated().map { (idx, entry) in
            translateV3Entry(idx: idx, entry: entry)
        }
        // 积分 → 净胜球 → 进球 降序；完全同分时按 ESPN rank 稳定住顺序 ——
        // 否则两次取数之间同分行可能互换，列表顺序与显示的名次对不上。
        .sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.position < $1.position
        }
    }

    /// v2 entries 翻译（沿用原逻辑）
    private static func translateStandingsV2(entries: [ESPNStandingEntry]) -> [StandingRow] {
        let rows: [StandingRow] = entries.enumerated().map { (idx, entry) in
            let team = Team(
                id: Int(entry.team.id) ?? idx,
                name: entry.team.name,
                shortName: entry.team.shortName,
                crest: entry.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            var played = 0, won = 0, draw = 0, lost = 0
            var points = 0, gf = 0, ga = 0, gd = 0
            for s in entry.stats {
                let v = Int(s.value ?? 0)
                switch s.name {
                case "gamesPlayed":      played = v
                case "wins":             won = v
                case "ties", "draws":    draw = v
                case "losses":           lost = v
                case "points":           points = v
                case "pointsFor", "goalsFor":      gf = v
                case "pointsAgainst", "goalsAgainst": ga = v
                case "pointDifferential", "goalDifference": gd = v
                default: break
                }
            }
            return StandingRow(
                position: idx + 1,
                team: team,
                playedGames: played, won: won, draw: draw, lost: lost,
                points: points, goalsFor: gf, goalsAgainst: ga, goalDifference: gd,
                form: nil, status: nil, home: nil, away: nil
            )
        }
        return rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.position < $1.position
        }
    }

    /// 稳定的字符串 → 正整数散列（FNV-1a 64bit，对 Int.max 取模）。
    ///
    /// Swift 的 `String.hashValue` 带随机种子，**每次进程启动都不同** —— 用它派生实体 id，
    /// 同一球队/比赛两次启动 id 就会变，缓存比对、SwiftUI ForEach diff 全部错乱。
    /// ESPN 的 id / $ref URL 字符串本身是稳定的，用 FNV 散列得到跨启动一致的替代 id。
    static func stableID(from string: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(Int.max))
    }

    /// 单条 v3 entry → StandingRow
    private static func translateV3Entry(idx: Int, entry: ESPNStandingEntryV3) -> StandingRow {
        let teamRef = entry.team
        let team = Team(
            id: Int(teamRef.id ?? "") ?? teamRef.dollarRef.map(Self.stableID(from:)) ?? idx,
            name: teamRef.displayName ?? teamRef.name ?? "Unknown",
            shortName: teamRef.abbreviation ?? teamRef.shortName,
            crest: teamRef.logos?.first?.href,
            venue: nil, founded: nil, coach: nil, squad: nil
        )
        // 解析 records（按 name 取数）+ 顶层 stats
        var played = 0, won = 0, draw = 0, lost = 0
        var points = 0, gf = 0, ga = 0
        let allRecords = entry.records ?? []
        for rec in allRecords {
            let v = Int(rec.value ?? 0)
            switch rec.name ?? "" {
            case "gamesPlayed", "played":     played = v
            case "wins":                       won = v
            case "ties", "draws", "tiesCount": draw = v
            case "losses", "lossesCount":     lost = v
            case "points":                     points = v
            case "pointsFor", "goalsFor":      gf = v
            case "pointsAgainst", "goalsAgainst": ga = v
            default: break
            }
        }
        let gd = gf - ga
        let status = entry.note?.description.map { mapZone($0) }
        return StandingRow(
            position: entry.rank ?? (idx + 1),
            team: team,
            playedGames: played, won: won, draw: draw, lost: lost,
            points: points, goalsFor: gf, goalsAgainst: ga, goalDifference: gd,
            form: nil, status: status, home: nil, away: nil
        )
    }

    /// 把 ESPN note description 映射成 PRD 约定的 status
    private static func mapZone(_ desc: String) -> String {
        let d = desc.uppercased()
        if d.contains("CHAMPIONS") { return "CHAMPIONS_LEAGUE" }
        if d.contains("EUROPA")    { return "EUROPA_LEAGUE" }
        if d.contains("RELEGAT")   { return "RELEGATION" }
        return desc
    }


    /// ESPN scoreboard/schedule → 内部 Match 列表
    static func matches(from resp: ESPNScoreboardResponse) -> [Match] {
        let events = resp.events ?? []
        return events.compactMap { event -> Match? in
            guard let comps = event.competitions?.first,
                  let competitors = comps.competitors else { return nil }
            let home = competitors.first { $0.homeAway == "home" }
            let away = competitors.first { $0.homeAway == "away" }
            guard let h = home, let a = away else { return nil }

            let homeTeam = Team(
                id: Int(h.team.id) ?? 0,
                name: h.team.name,
                shortName: h.team.shortName,
                crest: h.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            let awayTeam = Team(
                id: Int(a.team.id) ?? 0,
                name: a.team.name,
                shortName: a.team.shortName,
                crest: a.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            let status = StatusTranslator.translate(comps.status?.type?.name)
            let score: Score? = {
                guard status == "FINISHED",
                      let hs = h.score?.value,
                      let as_ = a.score?.value
                else { return nil }
                return Score(fullTime: FullTime(home: Int(hs), away: Int(as_)))
            }()
            return Match(
                id: Int(event.id) ?? Self.stableID(from: event.id) % 1_000_000,
                matchday: event.week?.number,
                utcDate: event.date,
                status: status,
                stage: nil,
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                score: score
            )
        }
    }

    /// v3 events 单场详情 → 内部 Match
    /// 注意：v3 单场赛事里 competitors[].team 只有 id + $ref，没有 name/crest
    ///   → 这里只用 id + 一个 placeholder name，UI 列表里不展开详情即可
    static func match(from detail: ESPNEventDetailV3) -> Match? {
        guard let comp = detail.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2 else { return nil }
        let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
        // v3 单场赛事里 competitor.id 即为 team id
        let homeId = Int(home.id ?? "0") ?? 0
        let awayId = Int(away.id ?? "0") ?? 0
        let homeTeam = Team(id: homeId, name: "Team #\(homeId)", shortName: nil, crest: nil,
                            venue: nil, founded: nil, coach: nil, squad: nil)
        let awayTeam = Team(id: awayId, name: "Team #\(awayId)", shortName: nil, crest: nil,
                            venue: nil, founded: nil, coach: nil, squad: nil)

        let statusName = comp.status?.type?.name
        let state = comp.status?.type?.state
        let status: String?
        if state == "post" || statusName == "STATUS_FULL_TIME" {
            status = "FINISHED"
        } else if state == "in" || statusName == "STATUS_IN_PROGRESS" {
            status = "IN_PLAY"
        } else if let n = statusName, n.contains("POSTPONED") {
            status = "POSTPONED"
        } else {
            status = "SCHEDULED"
        }

        // score 在 v3 单场赛事里仍是 $ref，这里 score 先给 nil；
        // 已结束赛事的 UI 需要详细比分时会触发 follow score——这里 MVP 暂不展开
        let score: Score? = nil

        return Match(
            id: Int(detail.id ?? "0") ?? 0,
            matchday: nil,
            utcDate: detail.date ?? comp.date,
            status: status,
            stage: nil,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            score: score
        )
    }
}
