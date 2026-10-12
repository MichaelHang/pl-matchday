import XCTest
@testable import EPLViewer

// 积分榜:聚合 / 排序 / enrichment
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
    /// 造一支球队（id/name 自由指定）
    func makeTeam2(_ id: Int, _ name: String) -> Team {
        Team(id: id, name: name, shortName: name, crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// 造一场含主客两队 + 全场比分的已结束比赛
    func makeFinishedMatch(id: Int, kickoff: String,
                                       home: Team, away: Team,
                                       homeGoals: Int, awayGoals: Int) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away,
              score: Score(fullTime: FullTime(home: homeGoals, away: awayGoals)))
    }

    /// 造一场已结束但没比分的（应被聚合器忽略）
    func makeUnscoredMatch(id: Int, kickoff: String,
                                       home: Team, away: Team) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away, score: nil)
    }

    /// venueStats 主场：team 100 主场比赛 3 场（2 胜 1 平 0 负，进 5 失 2，积 7 分）
    func testVenueStatsHomeCountsCorrectly() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 3, awayGoals: 1),  // 胜
            makeFinishedMatch(id: 2, kickoff: "2026-08-25T12:00:00Z",
                              home: a, away: c, homeGoals: 1, awayGoals: 1),  // 平
            makeFinishedMatch(id: 3, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 0),  // 胜
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

    /// venueStats 客场：team 100 客场比赛 2 场（1 胜 1 负，进 3 失 3，积 3 分）
    /// 验证「从客队视角」统计能正确翻转主客。
    func testVenueStatsAwayFlipsHomeAway() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            // 客胜：Alpha 是 away 队，away 进球 2 > home 1
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 1, awayGoals: 2),
            // 客负：Alpha 是 away 队，away 进球 1 < home 2
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

    /// venueStats：没比赛或没比分 → nil（区分"无数据"和"踢了但全输"）
    func testVenueStatsNoMatchesReturnsNil() {
        let a = makeTeam2(100, "Alpha")
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [], isHome: true),
                     "空 matches → nil")
        // SCHEDULED 的比赛应该被忽略
        let scheduled = Match(id: 9, matchday: 1, utcDate: "2026-08-22T12:00:00Z",
                              status: "SCHEDULED", stage: nil, homeTeam: a, awayTeam: a, score: nil)
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [scheduled], isHome: true),
                     "未开赛的不应计入")
    }

    /// formString：team 100 最近 5 场按时间顺序 → "WWDLW"
    func testFormStringReturnsMostRecentFiveChronological() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        // 5 场：W W D L W（按时间从早到晚）—— Alpha 有时主有时客
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-01T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),  // W（主）
            makeFinishedMatch(id: 2, kickoff: "2026-08-08T12:00:00Z",
                              home: b, away: a, homeGoals: 0, awayGoals: 1),  // W（客）
            makeFinishedMatch(id: 3, kickoff: "2026-08-15T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 1),  // D（主）
            makeFinishedMatch(id: 4, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 3, awayGoals: 0),  // L（客）
            makeFinishedMatch(id: 5, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 4, awayGoals: 2),  // W（主）
            // 第 6 场：比第 5 场更早，但假定 6 场只取最近 5，应被丢弃
            makeFinishedMatch(id: 0, kickoff: "2026-07-25T12:00:00Z",
                              home: a, away: b, homeGoals: 5, awayGoals: 0),  // 应被丢弃
        ]
        XCTAssertEqual(StandingsEnricher.formString(for: 100, matches: matches, last: 5),
                       "WWDLW")
    }

    /// formString：没有任何比赛 → nil
    func testFormStringNoMatchesReturnsNil() {
        let s = StandingsEnricher.formString(for: 100, matches: [], last: 5)
        XCTAssertNil(s)
    }

    /// enrich：rows 的 home/away 是 nil → 本地补全
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
        XCTAssertNotNil(enriched[0].home, "主场应被补全")
        XCTAssertEqual(enriched[0].home?.played, 1)
        XCTAssertEqual(enriched[0].home?.points, 3)
        XCTAssertNil(enriched[0].away, "客场无比赛仍为 nil")
    }

    /// enrich：rows 已有 home/away → 不覆盖（保留权威值）
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
                       "原有 home 不应被本地聚合覆盖")
        XCTAssertNil(enriched[0].away,
                     "无客场比赛时 away 应为 nil（不是全 0 VenueStats）")
    }

    /// enrich：空 rows / 空 matches 都安全
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

    /// StandingRow.with：只补 home/away 时，其它字段全部沿用
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
        XCTAssertEqual(updated.position, 5, "其它字段不能丢")
        XCTAssertEqual(updated.points, 7)
        XCTAssertEqual(updated.form, "WDW")
        XCTAssertEqual(updated.status, "CHAMPIONS_LEAGUE")
        XCTAssertEqual(updated.home?.played, 1)
        XCTAssertNil(updated.away)
    }
}

extension EPLViewerTests {
    // MARK: - 积分榜名次聚合（teamId 去重）

    /// 回归测试：积分榜聚合时若同一 teamId 出现两次（脏数据 / 主客场拆分残留），
    /// 旧的 `Dictionary(uniqueKeysWithValues:)` 会直接 trap（fatalError）；
    /// 改用 `uniquingKeysWith:` 后不再崩溃，且保留**先出现**的那条名次。
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

        // 不应 trap；重复的 teamId 保留先出现的名次（3）。
        let positions = TodayViewModel.buildPositions(from: [first, second])
        XCTAssertEqual(positions.count, 1, "重复 teamId 只应产出一条记录")
        XCTAssertEqual(positions[1], 3, "重复 key 应保留先出现的名次")
    }

    // MARK: - 稳定 ID 与积分榜排序确定性

    /// 回归：stableID 必须跨启动稳定 —— 旧实现用 `String.hashValue`（每次启动随机种子），
    /// 派生出的球队/比赛 id 两次启动不一致，缓存比对与 ForEach diff 全乱。
    /// 基准值用独立实现算好的 FNV-1a 64bit 锁死算法。
    func testStableIDIsDeterministicFNV1a() {
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), 7_430_836_138_530_658_124)
        XCTAssertEqual(
            ESPNTranslator.stableID(from: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/teams/359"),
            6_167_624_713_123_287_027)
        // 同输入恒同输出；结果必须是非负 Int（可安全用作 id）
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), ESPNTranslator.stableID(from: "abc"))
        XCTAssertGreaterThanOrEqual(ESPNTranslator.stableID(from: "x"), 0, "结果必须是非负 Int")
        XCTAssertNotEqual(ESPNTranslator.stableID(from: "a"), ESPNTranslator.stableID(from: "b"))
    }

    /// 回归：v3 积分榜同分时按 净胜球 → 进球 → ESPN rank 稳定排序。
    /// 旧实现只按积分排，同分行两次取数间可能互换，列表顺序与显示名次对不上。
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
                entry(id: "5", rank: 1, pts: 3, gf: 1, ga: 1),   // 同分、GD 0
                entry(id: "6", rank: 2, pts: 3, gf: 2, ga: 0),   // 同分、GD +2 → 应排最前
                entry(id: "7", rank: 3, pts: 3, gf: 1, ga: 2),   // 同分、GD -1 → 垫底
                entry(id: "8", rank: 4, pts: 3, gf: 1, ga: 1),   // 与 team5 完全同分 → 按 rank 排在 team5 后
            ])
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertFalse(rows.isEmpty, "有 records 的响应不应回退为空")
        XCTAssertEqual(rows.map(\.team.id), [6, 5, 8, 7],
                       "同分先比净胜球、再比进球，完全同分按 ESPN rank 稳定住")
        XCTAssertEqual(rows.map(\.position), [2, 1, 4, 3],
                       "position 沿用 ESPN rank，排序不应改写名次标签")
    }

    /// 回归：v3 team 只有 $ref（无数字 id）时，id 用 FNV 散列派生 —— 跨启动一致。
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
        XCTAssertFalse(rows.isEmpty, "有 records 的响应不应回退为空")
        XCTAssertEqual(rows.first?.team.id, ESPNTranslator.stableID(from: ref),
                       "无数字 id 的 $ref 球队应得到跨启动稳定的 id")
    }

    /// 回归：从赛果聚合积分榜时，积分/净胜球/进球完全相同的球队按 teamId 稳定排序 ——
    /// stats 是字典、遍历顺序不定，没有最终 tiebreak 时两次聚合的行序可能不同。
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
        // 两队各 1-0 取胜：积分/净胜球/进球完全相同
        let matches = [
            finishedMatch(id: 1, home: 30, away: 40, homeScore: 1, awayScore: 0),   // team 30 胜
            finishedMatch(id: 2, home: 20, away: 50, homeScore: 1, awayScore: 0),   // team 20 胜
        ]
        let rows = StandingsAggregator.aggregate(matches: matches)
        XCTAssertEqual(rows.map(\.team.id), [20, 30, 40, 50],
                       "完全同分的胜者按 teamId 升序，零分球队同样按 teamId 升序")
        XCTAssertEqual(rows.map(\.position), [1, 2, 3, 4])
        XCTAssertEqual(rows[0].points, 3)
        XCTAssertEqual(rows[1].points, 3)
        XCTAssertEqual(rows[0].goalsFor, 1)
        XCTAssertEqual(rows[1].goalsFor, 1)
    }

    // MARK: - 积分榜排序（主场/客场榜按维度独立排名）

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
        // B 总榜第 1 但主场榜应排末位；A 主场榜第一。名次编号必须按主场榜重排。
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
                       "主场榜应按主场积分降序，而不是沿用总榜顺序")
        XCTAssertEqual(ranks, [1, 2, 3], "主场榜名次应重新编号 1...N")
    }

    func testVenueTabTieBreaksByGoalDifferenceThenGoalsFor() {
        // 同积分：T1 净胜球 -6 垫底；T2/T3 同为 +8，进球多者(20>12)靠前
        let rows = [
            standing(id: 1, position: 1, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 4, ga: 10)),
            standing(id: 2, position: 2, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 12, ga: 4)),
            standing(id: 3, position: 3, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 20, ga: 12))
        ]
        let away = StandingsSorter.rankedStandings(rows: rows, for: .away)
        XCTAssertEqual(away.map { $0.row.team.id }, [3, 2, 1],
                       "同分时应按净胜球、再按进球降序")
    }

    func testVenueTabPushesTeamsWithoutVenueDataToBottomUnranked() {
        // 尚未在主/客场踢过球的队伍：沉底、不给名次，且不占用名次编号
        let rows = [
            standing(id: 1, position: 1, pts: 50, home: vs(played: 2, won: 2, draw: 0, lost: 0, gf: 6, ga: 1)),
            standing(id: 2, position: 2, pts: 40),
            standing(id: 3, position: 3, pts: 30, home: vs(played: 2, won: 1, draw: 1, lost: 0, gf: 3, ga: 1))
        ]
        let home = StandingsSorter.rankedStandings(rows: rows, for: .home)
        XCTAssertEqual(home.map { $0.row.team.id }, [1, 3, 2])
        XCTAssertEqual(home.map { $0.rank }, [1, 2, nil],
                       "无主场数据的队伍不给名次")
        XCTAssertEqual(Set(home.map { $0.id }).count, 3, "行 id 必须互不相同")
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
                           "\(tab.rawValue) tab 应保持数据源顺序")
            XCTAssertEqual(out.map { $0.rank }, [3, 1, 2],
                           "\(tab.rawValue) tab 名次应沿用总榜 position")
        }
    }

    func testRankedStandingIdDiffersByRank() {
        // 关键护栏：同一支球队在不同名次下 id 不同，否则切 tab 会让 ForEach 错配
        let row = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(RankedStanding(row: row, rank: 1).id,
                          RankedStanding(row: row, rank: 3).id,
                          "同一球队在不同名次下 id 必须不同")
        XCTAssertNotEqual(RankedStanding(row: row, rank: nil).id,
                          RankedStanding(row: row, rank: 1).id)
    }

    func testStandingRowIdIsStableUnderRerank() {
        let a = standing(id: 1, position: 1, pts: 30)
        let b = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(a.id, b.id, "同一球队在不同 position 下 id 必须不同")
        XCTAssertEqual(a.id, "pos1-team1")
    }

    // MARK: - 积分榜 form（状态）补全

    func testEnrichDerivesFormFromMatchesWhenMissing() {
        // 这是「状态 tab 长期全破折号」的回归用例：enrich 必须从赛程推导 form
        let rows = [standing(id: 1, position: 1, pts: 6)]
        let matches = [
            scoredMatch(id: 1, home: 1, away: 2, date: "2026-09-01T14:00:00Z", score: (2, 0)),   // W
            scoredMatch(id: 2, home: 1, away: 3, date: "2026-09-08T14:00:00Z", score: (0, 3)),   // L
            scoredMatch(id: 3, home: 4, away: 1, date: "2026-09-15T14:00:00Z", score: (1, 1))    // D
        ]
        let enriched = StandingsEnricher.enrich(rows: rows, with: matches)
        XCTAssertEqual(enriched.first?.form, "WLD",
                       "form 应从最近 3 场按时间升序推导，而不是留空")
        XCTAssertNotNil(enriched.first?.home, "主场数据应被补全")
        XCTAssertNotNil(enriched.first?.away, "客场数据应被补全")
    }

    func testEnrichNormalizesCommaSeparatedForm() {
        // 本地示例数据是 "D,W,W,D,W"，UI 按前 5 个字符渲染，不归一会把逗号画成胶囊
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
        XCTAssertEqual(enriched[0].form, "DWWDW", "已有 form 应归一化后保留")
        XCTAssertEqual(enriched[1].form, "LW",
                       "缺失的 form 应从赛程按时间推导（第 1 场客战 0:2 输、第 2 场主场 1:0 赢）")
    }

    func testNormalizeFormEdgeCases() {
        XCTAssertEqual(StandingsEnricher.normalizeForm("W,W,D,L,W"), "WWDLW")
        XCTAssertEqual(StandingsEnricher.normalizeForm("  W L D  "), "WLD")
        XCTAssertEqual(StandingsEnricher.normalizeForm("WWWWWW"), "WWWWW",
                       "应截断到最近 5 场")
        XCTAssertEqual(StandingsEnricher.normalizeForm("———"), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(""), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(nil), nil)
    }
}
