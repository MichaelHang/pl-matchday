import XCTest
@testable import EPLViewer

// Standings: aggregation / sorting / enrichment.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    /// Build a team (free-form id/name).
    func makeTeam2(_ id: Int, _ name: String) -> Team {
        Team(id: id, name: name, shortName: name, crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// Build a finished match with both teams and a full-time score.
    func makeFinishedMatch(id: Int, kickoff: String,
                                       home: Team, away: Team,
                                       homeGoals: Int, awayGoals: Int) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away,
              score: Score(fullTime: FullTime(home: homeGoals, away: awayGoals)))
    }

    /// Build a finished match without a score (the aggregator should ignore it).
    func makeUnscoredMatch(id: Int, kickoff: String,
                                       home: Team, away: Team) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away, score: nil)
    }

    /// venueStats home: team 100 hosts 3 matches (2W 1D 0L, GF 5 GA 2, 7 pts).
    func testVenueStatsHomeCountsCorrectly() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 3, awayGoals: 1),  // win
            makeFinishedMatch(id: 2, kickoff: "2026-08-25T12:00:00Z",
                              home: a, away: c, homeGoals: 1, awayGoals: 1),  // draw
            makeFinishedMatch(id: 3, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 0),  // win
        ]
        let s = try! XCTUnwrap(StandingsEnricher.venueStats(for: 100, matches: matches, isHome: true))
        XCTAssertEqual(s.played, 3)
        XCTAssertEqual(s.won, 2)
        XCTAssertEqual(s.draw, 1)
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.goalsFor, 5)
        XCTAssertEqual(s.goalsAgainst, 2)
        XCTAssertEqual(s.points, 7)
    }

    /// venueStats away: team 100 travels twice (1W 1L, GF 3 GA 3, 3 pts). Verifies
    /// the home/away flip when counting from the away team's perspective.
    func testVenueStatsAwayFlipsHomeAway() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            // Away win: Alpha is the away team, away goals 2 > home 1
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 1, awayGoals: 2),
            // Away loss: Alpha is the away team, away goals 1 < home 2
            makeFinishedMatch(id: 2, kickoff: "2026-08-25T12:00:00Z",
                              home: c, away: a, homeGoals: 2, awayGoals: 1),
        ]
        let s = try! XCTUnwrap(StandingsEnricher.venueStats(for: 100, matches: matches, isHome: false))
        XCTAssertEqual(s.played, 2)
        XCTAssertEqual(s.won, 1)
        XCTAssertEqual(s.draw, 0)
        XCTAssertEqual(s.lost, 1)
        XCTAssertEqual(s.goalsFor, 3)     // 2 + 1
        XCTAssertEqual(s.goalsAgainst, 3) // 1 + 2
        XCTAssertEqual(s.points, 3)
    }

    /// venueStats: no matches or no scores → nil (distinguishing "no data" from
    /// "played but lost everything").
    func testVenueStatsNoMatchesReturnsNil() {
        let a = makeTeam2(100, "Alpha")
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [], isHome: true),
                     "empty matches → nil")
        // SCHEDULED matches should be ignored
        let scheduled = Match(id: 9, matchday: 1, utcDate: "2026-08-22T12:00:00Z",
                              status: "SCHEDULED", stage: nil, homeTeam: a, awayTeam: a, score: nil)
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [scheduled], isHome: true),
                     "matches that haven't kicked off must not count")
    }

    /// formString: team 100's last 5 in chronological order → "WWDLW".
    func testFormStringReturnsMostRecentFiveChronological() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        // 5 matches: W W D L W (oldest → newest) — Alpha home and away mixed
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-01T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),  // W (home)
            makeFinishedMatch(id: 2, kickoff: "2026-08-08T12:00:00Z",
                              home: b, away: a, homeGoals: 0, awayGoals: 1),  // W (away)
            makeFinishedMatch(id: 3, kickoff: "2026-08-15T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 1),  // D (home)
            makeFinishedMatch(id: 4, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 3, awayGoals: 0),  // L (away)
            makeFinishedMatch(id: 5, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 4, awayGoals: 2),  // W (home)
            // A 6th match, older than #5: with only the last 5 kept it must be dropped
            makeFinishedMatch(id: 0, kickoff: "2026-07-25T12:00:00Z",
                              home: a, away: b, homeGoals: 5, awayGoals: 0),  // should be dropped
        ]
        XCTAssertEqual(StandingsEnricher.formString(for: 100, matches: matches, last: 5),
                       "WWDLW")
    }

    /// formString: no matches at all → nil.
    func testFormStringNoMatchesReturnsNil() {
        let s = StandingsEnricher.formString(for: 100, matches: [], last: 5)
        XCTAssertNil(s)
    }

    /// enrich: rows with nil home/away → filled locally.
    func testEnrichFillsNilHomeAwayFromLocalAggregate() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 1, won: 1, draw: 0, lost: 0,
            points: 3, goalsFor: 2, goalsAgainst: 0, goalDifference: 2,
            form: "W", status: nil,
            home: nil, away: nil
        )
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),
        ]
        let enriched = StandingsEnricher.enrich(rows: [row], with: matches)
        XCTAssertNotNil(enriched[0].home, "home record should be filled")
        XCTAssertEqual(enriched[0].home?.played, 1)
        XCTAssertEqual(enriched[0].home?.points, 3)
        XCTAssertNil(enriched[0].away, "no away matches → away stays nil")
    }

    /// enrich: rows with existing home/away → not overwritten (authoritative values kept).
    func testEnrichPreservesExistingHomeAway() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let preexistingHome = VenueStats(played: 99, won: 99, draw: 0, lost: 0,
                                         goalsFor: 99, goalsAgainst: 0, points: 99)
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 0, won: 0, draw: 0, lost: 0,
            points: 0, goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
            form: nil, status: nil,
            home: preexistingHome, away: nil
        )
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),
        ]
        let enriched = StandingsEnricher.enrich(rows: [row], with: matches)
        XCTAssertEqual(enriched[0].home?.played, 99,
                       "the existing home record must not be overwritten by local aggregation")
        XCTAssertNil(enriched[0].away,
                     "with no away matches, away should stay nil (not an all-zero VenueStats)")
    }

    /// enrich: empty rows / empty matches are both safe.
    func testEnrichSafeOnEmptyInputs() {
        let a = makeTeam2(100, "Alpha")
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 0, won: 0, draw: 0, lost: 0,
            points: 0, goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
            form: nil, status: nil,
            home: nil, away: nil
        )
        XCTAssertTrue(StandingsEnricher.enrich(rows: [], with: []).isEmpty)
        XCTAssertEqual(StandingsEnricher.enrich(rows: [row], with: []).count, 1)
        XCTAssertNil(StandingsEnricher.enrich(rows: [row], with: []).first?.home)
    }

    /// StandingRow.with: filling home/away only; every other field carried over.
    func testStandingRowWithPreservesOtherFields() {
        let a = makeTeam2(100, "Alpha")
        let row = StandingRow(
            position: 5, team: a,
            playedGames: 3, won: 2, draw: 1, lost: 0,
            points: 7, goalsFor: 6, goalsAgainst: 2, goalDifference: 4,
            form: "WDW", status: "CHAMPIONS_LEAGUE",
            home: nil, away: nil
        )
        let newHome = VenueStats(played: 1, won: 1, draw: 0, lost: 0,
                                 goalsFor: 2, goalsAgainst: 0, points: 3)
        let updated = row.with(home: newHome)
        XCTAssertEqual(updated.position, 5, "no other field may be lost")
        XCTAssertEqual(updated.points, 7)
        XCTAssertEqual(updated.form, "WDW")
        XCTAssertEqual(updated.status, "CHAMPIONS_LEAGUE")
        XCTAssertEqual(updated.home?.played, 1)
        XCTAssertNil(updated.away)
    }
}

extension EPLViewerTests {
    // MARK: - Standings position aggregation (teamId dedup)

    /// Regression: if the same teamId appears twice in standings (dirty data / stale
    /// home-away split), the old `Dictionary(uniqueKeysWithValues:)` trapped
    /// (fatalError); `uniquingKeysWith:` doesn't crash and keeps the **first** rank.
    func testBuildPositionsKeepsFirstOnDuplicateTeamId() throws {
        let team = Team(
            id: 1, name: "Arsenal", shortName: "ARS",
            crest: nil, venue: nil, founded: nil, coach: nil, squad: nil
        )
        let first = StandingRow(
            position: 3, team: team, playedGames: 1, won: 1, draw: 0, lost: 0,
            points: 3, goalsFor: 2, goalsAgainst: 1, goalDifference: 1,
            form: nil, status: nil, home: nil, away: nil
        )
        let second = StandingRow(
            position: 7, team: team, playedGames: 1, won: 0, draw: 1, lost: 0,
            points: 1, goalsFor: 1, goalsAgainst: 1, goalDifference: 0,
            form: nil, status: nil, home: nil, away: nil
        )

        // No trap; the duplicate teamId keeps the first-seen rank (3).
        let positions = TodayViewModel.buildPositions(from: [first, second])
        XCTAssertEqual(positions.count, 1, "a duplicate teamId yields one entry")
        XCTAssertEqual(positions[1], 3, "duplicate keys keep the first-seen rank")
    }

    // MARK: - Stable IDs & standings sort determinism

    /// Regression: stableID must be stable across launches — the old code used
    /// `String.hashValue` (randomly seeded per launch), so derived team/match ids
    /// differed between launches, breaking cache comparisons and ForEach diffing.
    /// Reference values pin the FNV-1a 64-bit algorithm via an independent
    /// implementation.
    func testStableIDIsDeterministicFNV1a() {
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), 7_430_836_138_530_658_124)
        XCTAssertEqual(
            ESPNTranslator.stableID(from: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/teams/359"),
            6_167_624_713_123_287_027)
        // Same input, same output; the result must be a non-negative Int (safe as an id)
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), ESPNTranslator.stableID(from: "abc"))
        XCTAssertGreaterThanOrEqual(ESPNTranslator.stableID(from: "x"), 0, "the result must be a non-negative Int")
        XCTAssertNotEqual(ESPNTranslator.stableID(from: "a"), ESPNTranslator.stableID(from: "b"))
    }

    /// Regression: the v3 standings tie-break is points → GD → GF → ESPN rank.
    /// Sorting by points alone let tied rows swap between fetches, desyncing the
    /// list order from the displayed positions.
    func testStandingsV3RowsSortTiebreaksByGDThenRank() throws {
        func entry(id: String, rank: Int, pts: Int, gf: Int, ga: Int) -> ESPNStandingEntryV3 {
            func rec(_ name: String, _ v: Int) -> ESPNRecordV3 {
                ESPNRecordV3(name: name, displayName: nil, shortDisplayName: nil,
                             value: Double(v), stats: nil)
            }
            return ESPNStandingEntryV3(
                team: ESPNTeamRefV3(id: id, name: id, shortName: nil, displayName: "Team \(id)",
                                    logos: nil, abbreviation: nil, dollarRef: nil),
                records: [rec("points", pts), rec("pointsFor", gf), rec("pointsAgainst", ga)],
                stats: nil, rank: rank, note: nil)
        }
        let resp = ESPNStandingsCoreResponse(
            name: nil, displayName: nil,
            standings: [
                entry(id: "5", rank: 1, pts: 3, gf: 1, ga: 1),   // tied, GD 0
                entry(id: "6", rank: 2, pts: 3, gf: 2, ga: 0),   // tied, GD +2 → first
                entry(id: "7", rank: 3, pts: 3, gf: 1, ga: 2),   // tied, GD -1 → last
                entry(id: "8", rank: 4, pts: 3, gf: 1, ga: 1),   // fully tied with team5 → after it by rank
            ])
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertFalse(rows.isEmpty, "a response with records must not fall back to empty")
        XCTAssertEqual(rows.map(\.team.id), [6, 5, 8, 7],
                       "ties break by GD, then goals; fully tied rows pin by ESPN rank")
        XCTAssertEqual(rows.map(\.position), [2, 1, 4, 3],
                       "position keeps the ESPN rank; sorting must not rewrite the position labels")
    }

    /// Regression: a v3 team with only a $ref (no numeric id) derives its id from the
    /// FNV hash — consistent across launches.
    func testStandingsV3RefOnlyTeamGetsStableID() throws {
        let ref = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/teams/359"
        let resp = ESPNStandingsCoreResponse(
            name: nil, displayName: nil,
            standings: [
                ESPNStandingEntryV3(
                    team: ESPNTeamRefV3(id: nil, name: nil, shortName: nil, displayName: nil,
                                        logos: nil, abbreviation: nil, dollarRef: ref),
                    records: [ESPNRecordV3(name: "points", displayName: nil, shortDisplayName: nil,
                                           value: 3, stats: nil)],
                    stats: nil, rank: 1, note: nil)
            ])
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertFalse(rows.isEmpty, "a response with records must not fall back to empty")
        XCTAssertEqual(rows.first?.team.id, ESPNTranslator.stableID(from: ref),
                       "a $ref team without a numeric id should get a launch-stable id")
    }

    /// Regression: aggregating standings from results orders fully-tied teams
    /// (points/GD/GF identical) by teamId — `stats` is a dictionary with unspecified
    /// iteration order, so without a final tiebreak row order could differ between runs.
    func testAggregateMatchesFullTieOrdersByTeamId() {
        func finishedMatch(id: Int, home: Int, away: Int, homeScore: Int, awayScore: Int) -> Match {
            let h = Team(id: home, name: "T\(home)", shortName: nil, crest: nil,
                         venue: nil, founded: nil, coach: nil, squad: nil)
            let a = Team(id: away, name: "T\(away)", shortName: nil, crest: nil,
                         venue: nil, founded: nil, coach: nil, squad: nil)
            return Match(id: id, matchday: 1, utcDate: "2026-08-15T14:00:00Z", status: "FINISHED",
                         stage: nil, homeTeam: h, awayTeam: a,
                         score: Score(fullTime: FullTime(home: homeScore, away: awayScore)))
        }
        // Two 1-0 winners: identical points/GD/GF
        let matches = [
            finishedMatch(id: 1, home: 30, away: 40, homeScore: 1, awayScore: 0),   // team 30 wins
            finishedMatch(id: 2, home: 20, away: 50, homeScore: 1, awayScore: 0),   // team 20 wins
        ]
        let rows = StandingsAggregator.aggregate(matches: matches)
        XCTAssertEqual(rows.map(\.team.id), [20, 30, 40, 50],
                       "fully tied winners ascend by teamId; pointless teams likewise by teamId")
        XCTAssertEqual(rows.map(\.position), [1, 2, 3, 4])
        XCTAssertEqual(rows[0].points, 3)
        XCTAssertEqual(rows[1].points, 3)
        XCTAssertEqual(rows[0].goalsFor, 1)
        XCTAssertEqual(rows[1].goalsFor, 1)
    }

    // MARK: - Standings sorting (home/away tabs rank independently)

    func standing(id: Int, position: Int, pts: Int,
                          gf: Int = 0, ga: Int = 0,
                          home: VenueStats? = nil, away: VenueStats? = nil,
                          form: String? = nil) -> StandingRow {
        StandingRow(position: position, team: Team(id: id, name: "T\(id)", shortName: "T\(id)",
                                                   crest: nil, venue: nil, founded: nil,
                                                   coach: nil, squad: nil),
                    playedGames: 0, won: 0, draw: 0, lost: 0,
                    points: pts, goalsFor: gf, goalsAgainst: ga, goalDifference: gf - ga,
                    form: form, status: nil, home: home, away: away)
    }

    func vs(played: Int, won: Int, draw: Int, lost: Int,
                    gf: Int, ga: Int) -> VenueStats {
        VenueStats(played: played, won: won, draw: draw, lost: lost,
                   goalsFor: gf, goalsAgainst: ga, points: won * 3 + draw)
    }

    func scoredMatch(id: Int, home: Int, away: Int, date: String,
                             score: (Int, Int)) -> Match {
        Match(id: id, matchday: 1, utcDate: date, status: "FINISHED", stage: nil,
              homeTeam: Team(id: home, name: "H\(home)", shortName: "H\(home)", crest: nil,
                             venue: nil, founded: nil, coach: nil, squad: nil),
              awayTeam: Team(id: away, name: "A\(away)", shortName: "A\(away)", crest: nil,
                             venue: nil, founded: nil, coach: nil, squad: nil),
              score: Score(fullTime: FullTime(home: score.0, away: score.1)))
    }

    func testVenueTabSortsByVenuePointsAndRenumbers() {
        // B leads overall but must sit last on the home table; A tops the home table.
        // The rank numbers must renumber by the home dimension.
        let rows = [
            standing(id: 1, position: 1, pts: 90,
                     home: vs(played: 10, won: 9, draw: 0, lost: 1, gf: 25, ga: 8)),
            standing(id: 2, position: 2, pts: 80,
                     home: vs(played: 10, won: 1, draw: 0, lost: 9, gf: 5, ga: 30)),
            standing(id: 3, position: 3, pts: 70,
                     home: vs(played: 10, won: 8, draw: 1, lost: 1, gf: 20, ga: 6))
        ]
        let home = StandingsSorter.rankedStandings(rows: rows, for: .home)
        let names = home.map { $0.row.team.name }
        let ranks = home.compactMap { $0.rank }
        XCTAssertEqual(names, ["T1", "T3", "T2"],
                       "the home table should order by home points, not overall order")
        XCTAssertEqual(ranks, [1, 2, 3], "home-table ranks should renumber 1...N")
    }

    func testVenueTabTieBreaksByGoalDifferenceThenGoalsFor() {
        // Equal points: T1's GD -6 sinks; T2/T3 both +8, more goals wins (20 > 12)
        let rows = [
            standing(id: 1, position: 1, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 4, ga: 10)),
            standing(id: 2, position: 2, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 12, ga: 4)),
            standing(id: 3, position: 3, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 20, ga: 12))
        ]
        let away = StandingsSorter.rankedStandings(rows: rows, for: .away)
        XCTAssertEqual(away.map { $0.row.team.id }, [3, 2, 1],
                       "on equal points, break by GD then goals, descending")
    }

    func testVenueTabPushesTeamsWithoutVenueDataToBottomUnranked() {
        // Teams yet to play home/away: sink, get no rank, and occupy no number slot
        let rows = [
            standing(id: 1, position: 1, pts: 50, home: vs(played: 2, won: 2, draw: 0, lost: 0, gf: 6, ga: 1)),
            standing(id: 2, position: 2, pts: 40),
            standing(id: 3, position: 3, pts: 30, home: vs(played: 2, won: 1, draw: 1, lost: 0, gf: 3, ga: 1))
        ]
        let home = StandingsSorter.rankedStandings(rows: rows, for: .home)
        XCTAssertEqual(home.map { $0.row.team.id }, [1, 3, 2])
        XCTAssertEqual(home.map { $0.rank }, [1, 2, nil],
                       "teams without home data get no rank")
        XCTAssertEqual(Set(home.map { $0.id }).count, 3, "row ids must be unique")
    }

    func testOverallAndFormTabKeepSourceOrder() {
        let rows = [
            standing(id: 7, position: 3, pts: 10),
            standing(id: 8, position: 1, pts: 30),
            standing(id: 9, position: 2, pts: 20)
        ]
        for tab in [StandingsTab.overall, .form] {
            let out = StandingsSorter.rankedStandings(rows: rows, for: tab)
            XCTAssertEqual(out.map { $0.row.team.id }, [7, 8, 9],
                           "\(tab.rawValue) tab should keep the source order")
            XCTAssertEqual(out.map { $0.rank }, [3, 1, 2],
                           "\(tab.rawValue) tab ranks should reuse the overall position")
        }
    }

    func testRankedStandingIdDiffersByRank() {
        // Key guard: the same team under different ranks must have different ids, or
        // tab switches mispair ForEach rows
        let row = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(RankedStanding(row: row, rank: 1).id,
                          RankedStanding(row: row, rank: 3).id,
                          "the same team must have different ids under different ranks")
        XCTAssertNotEqual(RankedStanding(row: row, rank: nil).id,
                          RankedStanding(row: row, rank: 1).id)
    }

    func testStandingRowIdIsStableUnderRerank() {
        let a = standing(id: 1, position: 1, pts: 30)
        let b = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(a.id, b.id, "the same team must have different ids at different positions")
        XCTAssertEqual(a.id, "pos1-team1")
    }

    // MARK: - Standings form enrichment

    func testEnrichDerivesFormFromMatchesWhenMissing() {
        // The regression for "the form tab was all dashes forever": enrich must derive
        // form from fixtures
        let rows = [standing(id: 1, position: 1, pts: 6)]
        let matches = [
            scoredMatch(id: 1, home: 1, away: 2, date: "2026-09-01T14:00:00Z", score: (2, 0)),   // W
            scoredMatch(id: 2, home: 1, away: 3, date: "2026-09-08T14:00:00Z", score: (0, 3)),   // L
            scoredMatch(id: 3, home: 4, away: 1, date: "2026-09-15T14:00:00Z", score: (1, 1))    // D
        ]
        let enriched = StandingsEnricher.enrich(rows: rows, with: matches)
        XCTAssertEqual(enriched.first?.form, "WLD",
                       "form should derive from the last 3 matches in chronological order, not stay empty")
        XCTAssertNotNil(enriched.first?.home, "home data should be filled")
        XCTAssertNotNil(enriched.first?.away, "away data should be filled")
    }

    func testEnrichNormalizesCommaSeparatedForm() {
        // The old sample data was "D,W,W,D,W"; the UI renders the first 5 characters —
        // without normalization commas would render as capsules
        let rows = [standing(id: 1, position: 1, pts: 6, form: "D,W,W,D,W")]
        let enriched = StandingsEnricher.enrich(rows: rows, with: [])
        XCTAssertEqual(enriched.first?.form, "DWWDW")
    }

    func testEnrichKeepsGivenFormButDerivesMissingOne() {
        let rows = [
            standing(id: 1, position: 1, pts: 6, form: "D,W,W,D,W"),
            standing(id: 2, position: 2, pts: 4)
        ]
        let matches = [
            scoredMatch(id: 1, home: 1, away: 2, date: "2026-09-01T14:00:00Z", score: (2, 0)),
            scoredMatch(id: 2, home: 2, away: 1, date: "2026-09-08T14:00:00Z", score: (1, 0))
        ]
        let enriched = StandingsEnricher.enrich(rows: rows, with: matches)
        XCTAssertEqual(enriched[0].form, "DWWDW", "an existing form should be kept after normalization")
        XCTAssertEqual(enriched[1].form, "LW",
                       "a missing form should derive from fixtures in time order (away 0:2 loss, then home 1:0 win)")
    }

    func testNormalizeFormEdgeCases() {
        XCTAssertEqual(StandingsEnricher.normalizeForm("W,W,D,L,W"), "WWDLW")
        XCTAssertEqual(StandingsEnricher.normalizeForm("  W L D  "), "WLD")
        XCTAssertEqual(StandingsEnricher.normalizeForm("WWWWWW"), "WWWWW",
                       "should truncate to the most recent 5")
        XCTAssertEqual(StandingsEnricher.normalizeForm("———"), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(""), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(nil), nil)
    }
}
