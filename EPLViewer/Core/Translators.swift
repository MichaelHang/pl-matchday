import Foundation

// MARK: - Aggregation / enrichment / translators (wire models → internal domain)

/// A "near-live" standings table aggregated from finished events.
/// Key capability: while ESPN's v3 `records` field is still empty, W/D/L/Pts/GF/GA
/// are computed live from played matches.
struct StandingsAggregator {
    /// Internal per-team accumulator.
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

    /// Pull finished events from the last N days, tally W/D/L/Pts/GF/GA, sort by points.
    /// - Implementation: fetch event list → follow each event (status.state == "post") → tally
    /// - Caching: per-event details cached 5 min (scores rarely change), summary 60 s (aligned with standings TTL)
    static func aggregate(daysBack: Int = 14) async throws -> [StandingRow] {
        // 1. Compute the date range
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"; df.timeZone = TimeZone(identifier: "UTC")
        let dates = "\(df.string(from: start))-\(df.string(from: now))"

        // 2. Fetch event IDs
        let eventIds = try await ESPNEventsProvider.fetchEventIds(dates: dates)
        guard !eventIds.isEmpty else { return [] }

        // 3. Follow per-event details concurrently (8 lanes is plenty; avoids excessive requests)
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

        // 4. Filter finished events + parse W/D/L (GF/GA are added after scores arrive)
        var stats: [Int: RowStat] = [:]   // key = ESPN team.id (Int)
        var teamMeta: [Int: ESPNTeamRefV3] = [:]   // for backfilling team details afterwards
        var finishedPairs: [(eventId: String, homeId: Int, awayId: Int)] = []   // finished events awaiting scores

        for detail in details {
            guard let comp = detail.competitions?.first else { continue }
            // Only finished events:
            //   in a v3 event the status field is a $ref that would need another follow;
            //   a more direct test: any competitor.winner != nil → the match has a result
            //   (on a draw both winners are false; live/upcoming events leave winner nil).
            guard let competitors = comp.competitors, competitors.count >= 2 else { continue }
            let hasResult = competitors.contains { $0.winner != nil }
            guard hasResult else { continue }

            // Home/away (in a v3 event `team` is a $ref; competitor.id is the team id)
            let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
            let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
            guard let homeId = Int(home.id ?? ""),
                  let awayId = Int(away.id ?? "") else { continue }

            // Team refs are kept for the later backfill (optional)
            if let h = home.team { teamMeta[homeId] = h }
            if let a = away.team { teamMeta[awayId] = a }

            // Scores: competitors.score is usually a $ref — record this fixture, fetch later
            finishedPairs.append((eventId: detail.id ?? "", homeId: homeId, awayId: awayId))

            // Tally W/D/L from winner now; GF/GA are added once scores arrive
            let homeWin = home.winner == true
            let awayWin = away.winner == true
            let draw = (home.winner == false && away.winner == false && home.winner != nil)

            // Two rows per event: home and away
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

        // 5. Follow both competitors' scores for every finished event concurrently
        //    (score is a $ref in v3). The old implementation awaited serially inside
        //    the main loop — a 10-match round meant 20 sequential requests, painfully slow.
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

        // 6. **Add** GF/GA from the real scores (a team plays multiple matches; GF/GA
        //    are totals. The old implementation overwrote with `=`, leaving GF/GA at
        //    the last match's numbers only.)
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

        // 7. Follow team details for name/crest (deduplicated, concurrent)
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

        // 8. Assemble StandingRows
        let rows: [StandingRow] = stats.map { (teamId, st) in
            let name = resolvedTeams[teamId]?.displayName ?? resolvedTeams[teamId]?.name ?? "Team #\(teamId)"
            let crest = resolvedTeams[teamId]?.logos?.first?.href
            let team = Team(
                id: teamId, name: name, shortName: resolvedTeams[teamId]?.abbreviation,
                crest: crest, venue: nil, founded: nil, coach: nil, squad: nil
            )
            return StandingRow(
                position: 0,   // assigned after sorting
                team: team,
                playedGames: st.played, won: st.won, draw: st.draw, lost: st.lost,
                points: st.points(), goalsFor: st.gf, goalsAgainst: st.ga,
                goalDifference: st.gd(),
                form: nil, status: nil, home: nil, away: nil
            )
        }
        // Fully tied on points/GD/GF → order by teamId: `stats` is a dictionary with
        // unspecified iteration order, so without a final tiebreak two renders could
        // list rows in different orders.
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

    /// Aggregate a standings table from already-fetched results (with scores).
    /// Reuses the fixtures source (scoreboard) instead of the core/events $ref chain;
    /// only FINISHED matches with scores count — teams yet to play don't appear and
    /// don't earn points.
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
        // Fully tied on points/GD/GF → order by teamId: `stats` is a dictionary with
        // unspecified iteration order, so without a final tiebreak two renders could
        // list rows in different orders.
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

// MARK: - Standings enrichment (home/away split + form)

/// ESPN's current standings API doesn't return home/away splits. This module
/// aggregates them locally from finished fixtures:
/// - `venueStats(for:matches:isHome:)`: a team's home or away W/D/L/GF/GA/Pts
/// - `formString(for:matches:last:)`: W/D/L sequence over the last N finished matches
/// - `enrich(rows:with:matches:)`: fills home/away (+form) on a row (only when absent)
///
/// Pure functions (no environment dependencies), easy to unit test.
struct StandingsEnricher {

    /// A team's record in the "home" or "away" dimension.
    /// - Parameters:
    ///   - teamId: team id
    ///   - matches: all matches (upcoming, live, finished; only finished + scored count here)
    ///   - isHome: true = home matches only, false = away matches only
    /// - Returns: nil means "no finished matches in this dimension" (lets the UI
    ///   distinguish "no data" from "played but lost everything")
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

    /// Derive the W/D/L sequence (e.g. "WWDLW") over a team's last N finished matches.
    /// - Order: oldest → newest
    /// - No countable matches → nil (not an empty string, so the UI can tell
    ///   "no data" apart from "all wins")
    static func formString(for teamId: Int, matches: [Match], last: Int = 5) -> String? {
        let finished = matches
            .filter { $0.status == "FINISHED"
                && ($0.homeTeam.id == teamId || $0.awayTeam.id == teamId)
                && $0.score?.fullTime?.home != nil
                && $0.score?.fullTime?.away != nil }
            .sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }   // ascending: earliest first
            .suffix(last)                                          // last N (still ascending)
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

    /// Normalize a source-provided form string into a compact "WWDLW".
    ///
    /// Sources write forms differently (some "W,W,D,L,W" with separators, some with
    /// spaces, some without D), while the UI renders the first 5 characters — without
    /// normalization separators get drawn as match capsules and the form looks
    /// "stuck". Keep only W/D/L, drop everything else, keep the last 5.
    static func normalizeForm(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let letters = String(raw.filter { $0 == "W" || $0 == "D" || $0 == "L" })
        return letters.isEmpty ? nil : String(letters.suffix(5))
    }

    /// Fill home/away/form on standings rows from matches.
    /// Existing values are kept (they may be more authoritative); missing values are
    /// aggregated locally. Pure function; empty rows/matches return rows unchanged.
    static func enrich(rows: [StandingRow], with matches: [Match]) -> [StandingRow] {
        guard !rows.isEmpty else { return rows }
        return rows.map { row in
            let home = row.home ?? venueStats(for: row.team.id, matches: matches, isHome: true)
            let away = row.away ?? venueStats(for: row.team.id, matches: matches, isHome: false)
            // ⚠️ form must be computed here: ESPN's standings endpoint never provides
            // the last-5 form, and enrich() originally only filled home/away, leaving
            // the Form tab all dashes forever. Normalize existing values (strip
            // separators) first; derive from fixtures only when absent.
            let form = normalizeForm(row.form) ?? formString(for: row.team.id, matches: matches)
            return row.with(home: home, away: away, form: form)
        }
    }
}

/// Minimal counting semaphore (bounds concurrency).
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

// MARK: - Internal model translators (ESPN/FPL wire → internal domain)

/// ESPN status name → internal status string.
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

/// FPL bootstrap → internal Team / Player / Scorer / Assist / Injury.
enum FPLTranslator {
    /// FPL team ids → internal Teams (with squads derived from elements).
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
                    shirtNumber: nil,                 // FPL has no shirt numbers
                    nationality: nil                  // FPL has no nationality (needs element-summary; deferred)
                )
            }
            return Team(
                id: fplTeam.id,
                name: fplTeam.name,
                shortName: fplTeam.short_name,
                crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fplTeam.code).png",
                venue: nil,                          // FPL has no venue data
                founded: nil,
                coach: nil,                          // FPL has no coach data
                squad: players
            )
        }
    }

    /// Team lookup by id (with squad).
    static func team(id: Int, from bootstrap: FPLBootstrap) -> Team? {
        teams(from: bootstrap).first { $0.id == id }
    }

    /// Top scorers (goals_scored descending; top N when limit > 0).
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

    /// Top assists (assists descending; top N when limit > 0).
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

    /// Transfer/departure notices masquerading as unavailability: FPL marks players
    /// who left the club as status "u" with a transfer news line ("Has joined X
    /// permanently", "on loan", "departed as a free agent"). They don't belong on an
    /// injury board — left in, they bury real injuries under transfer noise.
    static func isTransferDeparture(news: String?) -> Bool {
        guard let news, !news.isEmpty else { return false }
        let lowered = news.lowercased()
        return lowered.contains("joined")
            || lowered.contains("departed")
            || lowered.contains("free agent")
            || lowered.contains("on loan")
    }

    /// Injuries (status != "a", excluding transfer departures).
    static func injuries(from bootstrap: FPLBootstrap) -> [Injury] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let positionMap = Dictionary(
            uniqueKeysWithValues: bootstrap.element_types.map { ($0.id, $0.singular_name) }
        )
        return bootstrap.elements
            .filter { $0.status != "a" }
            .filter { !isTransferDeparture(news: $0.news) }
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

    /// Fixtures derived from FPL fixtures (gameweek, real scores, official crests).
    static func matches(from fixtures: [FPLFixture], teams: [FPLTeam]) -> [Match] {
        let teamById = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        return fixtures.compactMap { f in
            guard let h = teamById[f.team_h], let a = teamById[f.team_a] else { return nil }
            let home = Team(id: h.id, name: h.name, shortName: h.short_name,
                            crest: fplCrest(h.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let away = Team(id: a.id, name: a.name, shortName: a.short_name,
                            crest: fplCrest(a.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let hasScore = f.team_h_score != nil && f.team_a_score != nil
            // Authoritative "finished" test — any one of three signals, guarding against
            // FPL's lag in flipping `finished` (which would show ⚽ on finished matches):
            //   1) finished actually set;
            //   2) finished_provisional: set at full time, never fires mid-match (most reliable);
            //   3) minutes >= 90: minutes-based fallback.
            // Only "not finished + started + under 90 minutes" stays IN_PLAY; the UI adds
            // ⚽ to distinguish live from finished.
            let over = f.finished
                    || f.finished_provisional == true
                    || (f.minutes ?? 0) >= 90
            let status: String = over ? "FINISHED"
                            : (f.started == true ? "IN_PLAY" : "SCHEDULED")
            // Fill the score whenever present (not only when finished): live matches
            // show real-time scores too; FixturesView uses status == IN_PLAY + ⚽ to
            // distinguish live from finished.
            let score: Score? = hasScore
                ? Score(fullTime: FullTime(home: f.team_h_score!, away: f.team_a_score!))
                : nil
            let id = (f.event ?? 0) * 1_000_000 + f.team_h * 1_000 + f.team_a
            return Match(id: id, matchday: f.event, utcDate: f.kickoff_time,
                         status: status, stage: nil, homeTeam: home, awayTeam: away, score: score)
        }
    }

    /// FPL team code → official crest URL.
    private static func fplCrest(_ code: Int) -> String {
        "https://resources.premierleague.com/premierleague/badges/50/t\(code).png"
    }
}

/// ESPN standings → internal StandingRows.
/// Adapts the v3 core API: a top-level standings array whose entries carry records
/// and stats; early in the season `records` may be empty — callers fall back on
/// empty results.
enum ESPNTranslator {
    /// Legacy v2 model (kept as a compatibility fallback).
    static func standingRows(from resp: ESPNStandingsResponse) -> [StandingRow] {
        let entries = resp.children?.first?.standings.entries ?? []
        return translateStandingsV2(entries: entries)
    }

    /// New v3 core model.
    static func standingRows(from resp: ESPNStandingsCoreResponse) -> [StandingRow] {
        guard resp.standings.count > 0 else { return [] }
        // When records are empty early in the season we could render zero-data rows
        // by rank; returning [] instead lets the repository fall back (fixture
        // aggregation / stale cache), which is more useful than an empty table.
        let hasAnyRecords = resp.standings.contains { ($0.records?.isEmpty == false) }
        if !hasAnyRecords { return [] }   // truly empty → trigger the repository fallback

        return resp.standings.enumerated().map { (idx, entry) in
            translateV3Entry(idx: idx, entry: entry)
        }
        // Points → GD → GF descending; fully tied rows are pinned by ESPN rank —
        // otherwise tied rows could swap between fetches and disagree with the
        // displayed position.
        .sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.position < $1.position
        }
    }

    /// v2 entries translation (original logic).
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

    /// Stable string → positive integer hash (FNV-1a 64-bit, modulo Int.max).
    ///
    /// Swift's `String.hashValue` is seeded per process and **differs on every
    /// launch** — deriving entity ids from it would change ids across launches and
    /// break cache comparisons and SwiftUI ForEach diffing. ESPN's ids / $ref URLs
    /// are stable strings, so FNV yields a launch-stable substitute id.
    static func stableID(from string: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(Int.max))
    }

    /// One v3 entry → StandingRow.
    private static func translateV3Entry(idx: Int, entry: ESPNStandingEntryV3) -> StandingRow {
        let teamRef = entry.team
        let team = Team(
            id: Int(teamRef.id ?? "") ?? teamRef.dollarRef.map(Self.stableID(from:)) ?? idx,
            name: teamRef.displayName ?? teamRef.name ?? "Unknown",
            shortName: teamRef.abbreviation ?? teamRef.shortName,
            crest: teamRef.logos?.first?.href,
            venue: nil, founded: nil, coach: nil, squad: nil
        )
        // Parse records (by name) + top-level stats
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

    /// Map an ESPN zone note description onto the app's status vocabulary.
    private static func mapZone(_ desc: String) -> String {
        let d = desc.uppercased()
        if d.contains("CHAMPIONS") { return "CHAMPIONS_LEAGUE" }
        if d.contains("EUROPA")    { return "EUROPA_LEAGUE" }
        if d.contains("RELEGAT")   { return "RELEGATION" }
        return desc
    }


    /// ESPN scoreboard/schedule → internal Matches.
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

    /// A v3 event detail → internal Match.
    /// Note: in a v3 event, competitors[].team carries only id + $ref — no name/crest
    /// → only id + a placeholder name here; list UIs don't expand details.
    static func match(from detail: ESPNEventDetailV3) -> Match? {
        guard let comp = detail.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2 else { return nil }
        let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
        // In a v3 event, competitor.id is the team id
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

        // score is still a $ref inside a v3 event, so it stays nil here; UIs that need
        // detailed scores would trigger a score follow — out of scope for now.
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
