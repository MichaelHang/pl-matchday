import XCTest
@testable import EPLViewer

// 今日页:筛选 / 推荐卡 / 实时分钟数
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
    // MARK: - 今日筛选

    /// matchday 用可选：`nil` 表示 FPL 里尚未分配轮次的比赛（真实数据里确实存在），
    /// 用于覆盖「未分配比赛不应影响当前轮推断」这类场景。
    func makeMatch(id: Int, kickoff: String, status: String?, matchday: Int? = 1) -> Match {
        let team = Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
                        venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: team, awayTeam: team, score: nil)
    }

    /// 与 makeMatch 类似，但主客队可不同（用于需要「两队名次」的推荐卡选取测试）
    func makeMatchTeams(id: Int, home: Int, away: Int, kickoff: String,
                                status: String?, matchday: Int? = 1) -> Match {
        let h = Team(id: home, name: "H\(home)", shortName: "H\(home)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        let a = Team(id: away, name: "A\(away)", shortName: "A\(away)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: h, awayTeam: a, score: nil)
    }

    /// 只保留「所选时区的当天」比赛，且按开球时间升序
    func testTodayFilterKeepsSameDaySorted() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 参考时刻：北京时间 2026-08-31 20:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "IN_PLAY"),   // 北京 21:00 同一天
            makeMatch(id: 2, kickoff: "2026-08-31T04:00:00Z", status: "FINISHED"),  // 北京 12:00 同一天
            makeMatch(id: 3, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // 北京 次日 00:00
            makeMatch(id: 4, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),  // 前一天
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertEqual(today.map(\.id), [2, 1], "只保留当天比赛，且按开球时间升序")
    }

    /// 「今日」必须按所选时区判断：同一时刻在北京已进入次日、在伦敦仍是当天
    func testTodayFilterRespectsSelectedTimeZone() throws {
        let beijing = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let london  = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // UTC 18:00 → 北京 次日 02:00；伦敦（BST UTC+1）当天 19:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T18:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T18:00:00Z", status: "IN_PLAY"),   // 次日(北京) / 当天(伦敦)
            makeMatch(id: 2, kickoff: "2026-08-31T02:00:00Z", status: "FINISHED"),  // 当天(两地)
        ]

        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: beijing).map(\.id), [1])
        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: london).map(\.id), [2, 1])
    }

    /// 今日比赛按状态分组：进行中 / 未开赛 / 已结束
    func testTodayGroupsByStatus() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T04:00:00Z", status: "IN_PLAY"),
            makeMatch(id: 2, kickoff: "2026-08-31T05:00:00Z", status: "FINISHED"),
            makeMatch(id: 3, kickoff: "2026-08-31T06:00:00Z", status: "SCHEDULED"),
        ]

        let vm = TodayViewModel()
        vm.matches = matches
        let g = vm.grouped(tz: tz, now: now)
        XCTAssertEqual(g.live.map(\.id), [1])
        XCTAssertEqual(g.finished.map(\.id), [2])
        XCTAssertEqual(g.upcoming.map(\.id), [3])
        XCTAssertEqual(g.total, 3)
        XCTAssertFalse(g.isEmpty)
    }

    /// 回归：跨日进行中的比赛（北京 23:30 开球、打到次日凌晨）开球日期算「昨天」，
    /// 但此刻正在踢，必须出现在「今日」——否则进行中的比赛会凭空消失。
    func testTodayFilterIncludesLiveMatchStartedYesterday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 当前：北京时间 2026-08-31 00:23（UTC 16:23 跨日 +8h）
        // 曼联那场北京时间 8月30日 23:30 开球 → 开球日期在所选时区里是「昨天」
        let now = try XCTUnwrap(parseKickoffDate("2026-08-30T16:23:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T15:30:00Z", status: "IN_PLAY"),   // 北京 23:30 开球，跨日进行中
            makeMatch(id: 2, kickoff: "2026-08-30T13:00:00Z", status: "FINISHED"),  // 北京 21:00，昨天已结束 → 不算今日
            makeMatch(id: 3, kickoff: "2026-08-31T11:00:00Z", status: "SCHEDULED"), // 北京 19:00，今天
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertTrue(today.contains { $0.id == 1 }, "进行中的比赛必须出现在今日，即使开球日期是昨天")
        XCTAssertFalse(today.contains { $0.id == 2 }, "昨天已结束的比赛不应出现在今日")
        XCTAssertTrue(today.contains { $0.id == 3 })
        XCTAssertEqual(today.map(\.id), [1, 3], "按开球时间升序")
    }

    /// 「下一场」取严格晚于当前时刻的第一场（等于 now 的不算）
    func testTodayNextMatchIsStrictlyAfterNow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),   // 过去
            makeMatch(id: 2, kickoff: "2026-08-31T12:00:00Z", status: "IN_PLAY"),    // == now
            makeMatch(id: 3, kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED"),
            makeMatch(id: 4, kickoff: "2026-09-05T12:00:00Z", status: "SCHEDULED"),
        ]
        XCTAssertEqual(TodayFilter.nextMatch(from: matches, now: now)?.id, 3)
    }

    // MARK: - 推荐比赛（featured 大卡片）选取

    /// 优先级 1：进行中优先于「即将开赛」
    func testFeaturedPrefersLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // 1 小时后开球
            makeMatch(id: 2, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY"),   // 进行中
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 2：无进行中 → 取 3.5 小时内开球的（超窗的不算）
    func testFeaturedFallsBackToKickoffWithinThreeAndHalfHours() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // +1h  → 命中
            makeMatch(id: 2, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // +4h  → 超窗
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// 优先级 3：无进行中、无即将开赛 → 今日已结束中「时间最近」的一场
    func testFeaturedFallsBackToMostRecentFinishedToday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED"),  // 北京 18:00
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED"),  // 北京 19:00 → 更近
            makeMatch(id: 3, kickoff: "2026-08-31T18:00:00Z", status: "SCHEDULED"), // +6h，超窗
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 5：今日无可推荐 → 取本轮下一场（可跨日，如明天）
    func testFeaturedFallsBackToNextMatchOfCurrentRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T10:00:00Z", status: "FINISHED", matchday: 5),  // 昨天
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 本轮下一场
            makeMatch(id: 3, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 6), // 下一轮
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 5：时间不同的比赛，取开球最早的一场（不因排名更好去推后更晚的强强对话）。
    func testFeaturedRoundNextPicksEarliestKickoffWhenTimesDiffer() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 10, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17，时间中
            makeMatchTeams(id: 11, home: 3, away: 4,  kickoff: "2026-09-04T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 7（排名最好），但最晚
            makeMatchTeams(id: 12, home: 8, away: 9,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17，但最早 → 命中
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4, 8: 8, 9: 9]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 12,
                       "时间不同时取最早开球的一场（#8 vs #9），不因后面有更强强对话而推后")
    }

    /// 优先级 5：同一时刻开球且多场 → 按名次和最小选强强对话。
    func testFeaturedRoundNextSameKickoffChosenByRankingSum() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 20, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17
            makeMatchTeams(id: 21, home: 3, away: 4,  kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 同时刻，和 7 → 命中
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 21,
                       "同一时刻开球时按名次和最小选：#3 vs #4（和 7）优于 #2 vs #15（和 17）")
    }

    /// 优先级 5：同一时刻且名次和相同 → 比较两队里排名最高的（更小者）胜出。
    func testFeaturedRoundNextSameKickoffRankingTieBreakByBestTeam() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 7, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 9，最佳 #2
            makeMatchTeams(id: 31, home: 1, away: 8, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 9，最佳 #1 → 命中
        ]
        let positions = [1: 1, 8: 8, 2: 2, 7: 7]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 31,
                       "同时刻且和相同（都是 9）时取榜首更靠前的那场：#1 vs #8 优于 #2 vs #7")
    }

    /// 优先级 5：最早开球时刻只有一场 → 直接取它，不因后面有更强强对话而推后。
    func testFeaturedRoundNextEarliestSlotSingleMatchPickedDirectly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 40, home: 10, away: 11, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 最早且唯一 → 命中
            makeMatchTeams(id: 41, home: 1,  away: 2,  kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED", matchday: 5), // 更晚（排名更好也不考虑）
        ]
        let positions = [10: 10, 11: 11, 1: 1, 2: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 40,
                       "最早时刻只有一场时直接取它，不跨时段为更强强对话推后")
    }

    /// 名次缺失时（取数超时 / 示例数据）必须优雅回退成「开球最早的一场」，不能崩。
    func testFeaturedRoundNextFallsBackToKickoffWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 15, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatchTeams(id: 31, home: 3, away: 4,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // 开球最早 → 命中
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: [:])?.id, 31,
                       "名次缺失时必须回退到开球最早的一场，而不是报错或选错")
    }

    /// 优先级 6：本轮已结束 → 显示本轮第一场（最早开球）的赛果
    func testFeaturedFallsBackToFirstMatchOfFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5), // 本轮最早
            makeMatch(id: 2, kickoff: "2026-08-29T14:00:00Z", status: "FINISHED", matchday: 5),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// 本轮已**全部结束** → 推荐卡应显示本轮的「强强对话」，而不是开球最早那场。
    ///
    /// 回归场景（用户报的 Bug）：第 3 轮已全部结束，卡片显示利物浦的早场，
    /// 期望显示阿森纳 vs 切尔西（名次和最小的强强对话）。
    ///
    /// 路由说明：`currentRound = 3` 时，优先级 5（本轮**未开赛**）的候选为空，
    /// 且 now 不在比赛日（跳过优先级 3/4），所以落到**优先级 6**。
    func testFeaturedFinishedRoundPicksMarqueeNotEarliestKickoff() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // now = 第 3 轮结束两天后，非比赛日 → 优先级 3（今日已结束）/ 4（今日未开赛）都不命中
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))

        let ars = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let che = Team(id: 61, name: "Chelsea", shortName: "CHE", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let liv = Team(id: 64, name: "Liverpool", shortName: "LIV", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let bha = Team(id: 397, name: "Brighton", shortName: "BHA", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        func m(_ id: Int, _ home: Team, _ away: Team, _ kickoff: String,
               _ md: Int, _ status: String) -> Match {
            Match(id: id, matchday: md, utcDate: kickoff, status: status,
                  stage: nil, homeTeam: home, awayTeam: away, score: nil)
        }

        let matches = [
            // 第 3 轮：全部已结束。id 1 开球最早（北京 11:00），id 2 最晚但名次和最小
            m(1, liv, bha, "2026-08-30T03:00:00Z", 3, "FINISHED"),   // 利物浦早场
            m(2, ars, che, "2026-08-30T06:00:00Z", 3, "FINISHED"),   // 阿森纳 vs 切尔西（强强对话）
            m(3, bha, liv, "2026-08-30T09:00:00Z", 3, "FINISHED"),
            // 第 4 轮已排期但未开赛 —— currentRound 仍是 3，所以不会走优先级 5
            m(4, ars, bha, "2026-09-05T11:00:00Z", 4, "SCHEDULED"),
        ]
        // 名次：阿森纳 1 / 切尔西 3（和 4）；利物浦 8 / 布莱顿 15（和 23）
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "本轮已结束时应显示强强对话（阿森纳 vs 切尔西），" +
                       "而不是开球最早的利物浦那场")
    }

    /// 控制组：证明优先级 5（本轮**下一场未开赛**）仍然是「时间优先」——
    /// 同一轮里时间不同的比赛取最早，不会因为排名更「强强」而推到更晚的场次。
    /// 这条同时锁住「优先级 6 的改动没有误伤优先级 5」。
    func testFeaturedUpcomingRoundStillPrefersEarliestKickoffOverMarquee() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))

        let ars = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let che = Team(id: 61, name: "Chelsea", shortName: "CHE", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let liv = Team(id: 64, name: "Liverpool", shortName: "LIV", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let bha = Team(id: 397, name: "Brighton", shortName: "BHA", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        func m(_ id: Int, _ home: Team, _ away: Team, _ kickoff: String,
               _ md: Int, _ status: String) -> Match {
            Match(id: id, matchday: md, utcDate: kickoff, status: status,
                  stage: nil, homeTeam: home, awayTeam: away, score: nil)
        }

        let matches = [
            m(1, ars, che, "2026-08-30T03:00:00Z", 3, "FINISHED"),
            // 第 3 轮还有未开赛的场次 → 命中优先级 5：取最早开球（id 2），而非名次的 id 3
            m(2, liv, bha, "2026-09-05T11:00:00Z", 3, "SCHEDULED"),  // 最早
            m(3, ars, che, "2026-09-05T14:00:00Z", 3, "SCHEDULED"),  // 更晚但更强强
        ]
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "优先级 5 仍应是时间优先：本轮未开赛场次里取最早，不因排名推到更晚")
    }

    // MARK: - QA 独立复审：优先级 6 的边界与错误路径

    /// 本轮已结束 + `positions` 完全缺失（积分榜取数超时 / 失败）→
    /// 必须退回「本轮最早开球」，不能崩、不能返回 nil。
    ///
    /// 这条同时是**哨兵溢出**的回归测试：两队都取不到名次时
    /// `rankKey` 会算 `Int.max / 2 + Int.max / 2`，debug 构建下若溢出会直接 trap（signal 5），
    /// 表现是测试进程整体崩溃而不是单条失败 —— 能跑到这里就说明没溢出。
    func testFeaturedFinishedRoundFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3),
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 最早
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: [:])
        XCTAssertNotNil(picked, "名次全缺时不能返回 nil —— 必须回退到本轮最早开球那场")
        XCTAssertEqual(picked?.id, 2, "名次全缺时回退到本轮最早开球（id 2）")
    }

    /// 两队名次都取不到的比赛应**沉底**，让位给名次已知的比赛（哨兵 Int.max/2 的语义）。
    func testFeaturedFinishedRoundRanksUnknownTeamsLast() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // 两队都无名次 → 沉底（即使开球最早）
            makeMatchTeams(id: 1, home: 91, away: 92, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // 名次已知且最小 → 命中（开球更晚也不影响，本轮已结束）
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [23: 5, 24: 7]   // 91 / 92 缺失
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2, "名次未知的比赛应沉底，让位给名次已知且和最小的那场")
    }

    /// `positions` 部分缺失（只有一支球队有名次）→ 该场会被哨兵拉高而落选。
    /// 这里锁住当前行为，便于后续讨论是否要改（见 QA 报告）。
    func testFeaturedFinishedRoundPartialPositionsSinkTheMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // 榜首(#1) vs 无名次球队 → 和 ≈ Int.max/2 + 1，会被拉高
            makeMatchTeams(id: 1, home: 1, away: 99, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // 中游对中游，两队名次都已知 → 和 21
            makeMatchTeams(id: 2, home: 10, away: 11, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 10: 10, 11: 11]   // 99 缺失
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "部分缺失时：两队名次都已知的比赛（和 21）应胜出，" +
                       "榜首 + 未知队（和 ≈ Int.max/2）被哨兵拉高 —— 当前行为，非崩溃")
    }

    /// 名次和**完全相同**时（`min(by:)` 的语义）应稳定返回开球最早的那场，不能随机跳。
    func testFeaturedFinishedRoundTieReturnsEarliestStable() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // 两场 rankKey 完全相同：(1+8, min(1,8)) == (8+1, min(8,1)) == (9, 1)
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 8, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 最早
            makeMatchTeams(id: 2, home: 8, away: 1, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 8: 8]
        // 跑多次确认稳定，不是偶然
        for _ in 0..<20 {
            let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                            now: now, tz: tz, positions: positions)
            XCTAssertEqual(picked?.id, 1, "名次和完全相同且最佳名次也相同时，应稳定返回开球最早那场")
        }
    }

    /// 真正的全局最小值：最小值不在首/尾，且轮次里还有更晚的下一轮比赛干扰。
    func testFeaturedFinishedRoundPicksTrueMinimumAmongMany() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 和 30
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T04:00:00Z", status: "FINISHED", matchday: 3), // 和 12
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // 和 25
            makeMatchTeams(id: 4, home: 27, away: 28, kickoff: "2026-08-30T06:00:00Z", status: "FINISHED", matchday: 3), // 和  8 ← 最小，位置在中间
            makeMatchTeams(id: 5, home: 29, away: 30, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // 和 40
            // 下一轮已排期：currentRound 仍是 3，不应被选
            makeMatchTeams(id: 6, home: 31, away: 32, kickoff: "2026-09-05T11:00:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 25: 12, 26: 13,
                         27: 3, 28: 5, 29: 20, 30: 20, 31: 1, 32: 2]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 4,
                       "应选出名次和最小（8）的那场；最小值既不在首位也不在末位，" +
                       "且不能选到下一轮（id 6，和 3 更小但属于第 4 轮）")
    }

    /// 本轮在 matches 里没有任何比赛 → 返回 nil，不能崩。
    func testFeaturedFinishedRoundReturnsNilWhenRoundHasNoMatches() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [21: 1, 22: 2, 23: 3, 24: 4]
        XCTAssertNil(TodayFeatured.pick(from: matches, currentRound: 99,
                                        now: now, tz: tz, positions: positions),
                     "currentRound 没有对应比赛时应返回 nil")
        XCTAssertNil(TodayFeatured.pick(from: [], currentRound: 3,
                                        now: now, tz: tz, positions: positions),
                     "matches 为空时应返回 nil")
    }

    /// 工程师刻意不复用 `chooseByRanking` 的理由必须成立：
    /// 它会先把候选收敛到「最早开球那一批」，所以对本轮各场开球时间不同的场景
    /// 会退化成「取最早开球」—— 正是被修掉的 Bug。
    /// 这里用纯数据证明二者在优先级 6 的场景下结果不同。
    func testChooseByRankingWouldCollapseToEarliestForFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // 本轮已全部结束，三场开球时间各不相同
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 和 30，最早
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // 和 12
            makeMatchTeams(id: 3, home: 27, away: 28, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // 和  8 ← 最小
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 27: 3, 28: 5]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 3, "优先级 6 应跨时段选名次和最小的那场")

        // 若退化成「取最早开球」，结果就会是 id 1 —— 正是用户报的 Bug
        let earliest = matches.min(by: { $0.utcDate ?? "" < $1.utcDate ?? "" })
        XCTAssertEqual(earliest?.id, 1, "最早开球的是 id 1（利物浦早场式的错误结果）")
        XCTAssertNotEqual(picked?.id, earliest?.id,
                          "修复后不应再等于最早开球那场 —— 证明确实跨时段比了名次")
    }

    // MARK: - QA：优先级 2 / 4 同刻多场按名次（本次缺陷修复的回归）

    /// 优先级 2（3.5 小时内开球）同刻多场 → 按名次和最小选强强对话，
    /// 而不是退化成「取原始数组顺序第一个」。
    ///
    /// 场景还原（2026-09-12 真实缺陷）：伦敦 13:57，15:00 BST（14:00Z）有若干场同刻开球，
    /// 距 now 63 分钟落在 3.5h 窗口内。FPL fixtures 里排在最前的是名次最差那场（名次和 34），
    /// 修复前会被它偷走推荐位；按名次应选中名次和最小的那场。
    ///
    /// 命中场 id 3 刻意放在数组**第三位**，确保测的是「按名次」而非「碰巧第一个」。
    func testFeaturedSoonWindowSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 伦敦 2026-09-12 13:57（BST）= 12:57Z；15:00 BST = 14:00Z，距 now 63 分钟
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // 数组里排第一，但名次最差（18 + 16 = 34）—— 修复前会被这个偷走
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 和 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 和 7 → 命中
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "同刻开球时应按名次和最小选强强对话（和 7），" +
                       "而不是数组顺序第一个（和 34）")
    }

    /// 控制组：优先级 2 仍「时间优先」—— 最早时刻只有一场（名次很差）时直接取它，
    /// 不能为了「更强强对话」把推荐推到更晚的场次。
    func testFeaturedSoonWindowPicksEarliestSlotNotMarquee() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // 最早时刻唯一（14:00Z），名次最差（和 34）→ 必须选它
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            // 更晚（14:15Z），名次很好（和 3）→ 不能因为「更强强」而推后
            makeMatchTeams(id: 2, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [2: 18, 7: 16, 4: 1, 5: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 1,
                       "最早时刻只有一场时直接取它，不跨时段为更强强对话推后")
    }

    /// 向后兼容：`positions` 为空（名次取不到）→ 优先级 2 仍返回「最早开球那一场」，
    /// 与改动前 `first(where:)` 完全一致，且不崩。
    func testFeaturedSoonWindowFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:30:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 最早 → 命中
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: [:])?.id, 2,
                       "名次缺失时必须回退到开球最早的一场（id 2），行为与改动前一致")
    }

    /// 优先级 4（今日下一场未开赛）同刻多场 → 同样按名次和最小选强强对话。
    /// 开球距 now 超过 3.5h（跳过优先级 2），但仍是伦敦当日 → 落到优先级 4。
    func testFeaturedTodayUpcomingSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        // 18:00Z = 19:00 BST（伦敦同日），距 now 5h3m > 3.5h → 优先级 2 不命中
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // 和 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // 和 7 → 命中
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "今日未开赛同刻多场时也应按名次和最小选强强对话")
    }

    // MARK: - 第四行第二列（今日开赛）

    /// 第二列只取今日未开赛，并剔除推荐卡那场
    func testTodayColumnsExcludesFeaturedMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5

        // ① 今日多场未开赛 → 推荐卡占最早那场，第二列保留其余
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5), // +1h → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5), // 北京 23:00
        ]
        let c1 = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(c1.upcoming.map(\.id), [2], "推荐卡那场不应重复出现在第二列")

        // ② 今日仅剩推荐卡那场未开赛 → 第二列为空（不做轮次回退）
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5), // 推荐卡
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 本轮后续，但不算今日
        ]
        let c2 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c2.upcoming.isEmpty, "第二列只看今日，不回退到本轮下一场")

        // ③ 今日没有未开赛（只有已结束的）→ 第二列为空
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let c3 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c3.upcoming.isEmpty)
    }

    /// 本轮已全部结束 → 第二列**不**跳到下一轮，保持为空（显示「暂无数据」）
    func testTodayColumnsDoesNotFallBackToNextEvent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 北京 2026-08-31 20:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // 今日已结束 → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-09-05T10:00:00Z", status: "SCHEDULED", matchday: 6), // 下一轮
            makeMatch(id: 4, kickoff: "2026-09-05T14:00:00Z", status: "SCHEDULED", matchday: 7),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertTrue(cols.upcoming.isEmpty, "轮次还是第 5 轮，不该把第 6/7 轮的赛程铺到今日页")
    }

    /// 第一列是「正在进行中 & 近期」的合流：直播在前，今日已结束在后（最近的在前）
    func testTodayColumnsFirstColumnShowsLiveAndRecent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "IN_PLAY", matchday: 5),      // 直播最早 → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),      // 直播
            makeMatch(id: 3, kickoff: "2026-08-31T08:00:00Z", status: "FINISHED", matchday: 5),     // 今日已结束（较晚）
            makeMatch(id: 4, kickoff: "2026-08-31T07:00:00Z", status: "FINISHED", matchday: 5),     // 今日已结束（较早）
            makeMatch(id: 5, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5),     // 昨天，不算今日
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2, 3, 4], "直播在前（按开球升序），已结束在后（最近的在前）")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// 没有直播时，第一列只列今日已结束，标题降级为「近期」
    func testTodayColumnsFirstColumnRecentOnly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // 今日已结束
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED", matchday: 5), // 今日最晚一场 → 推荐卡
            makeMatch(id: 3, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5), // 昨天，不算今日
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 2, "推荐卡取今日最近结束的一场")
        XCTAssertEqual(cols.live.map(\.id), [1], "第一列只列今日已结束的其余比赛")
        XCTAssertEqual(cols.liveSource, .recent)
    }

    /// 有直播时，第一列不再重复推荐卡那场
    func testTodayColumnsFirstColumnExcludesFeaturedLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),     // 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),     // 另一场直播
            makeMatch(id: 3, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2], "直播时第一列也不该重复推荐卡那场")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// 无论哪种情形，推荐卡那场都不会出现在第二列
    func testTodayColumnsNeverDuplicatesFeatured() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),    // 进行中
            makeMatch(id: 2, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let featured = try XCTUnwrap(vm.featured(tz: tz, now: now))
        XCTAssertEqual(featured.id, 1, "进行中的比赛优先成为推荐卡")
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertFalse(cols.upcoming.contains { $0.id == featured.id })
        XCTAssertEqual(cols.upcoming.map(\.id), [2, 3])
    }

    // MARK: - QA 独立复审：改动 1 / 2 / 3

    /// 从 `from` 起截到 `to`（不含 `to`）；`to` 为 nil 时截到末尾。
    func qaSlice(_ s: String, from: String, to: String? = nil) -> String? {
        guard let lo = s.range(of: from) else { return nil }
        let rest = s[lo.lowerBound...]
        guard let to, let hi = rest.range(of: to) else { return String(rest) }
        return String(rest[rest.startIndex..<hi.lowerBound])
    }

    // ── 改动 1：推荐卡改成写死渐变背景 ──

    /// 渐变必须是写死的 `Color` 字面量，不得读系统强调色 / AppState。
    func testFeaturedCardGradientIsHardcodedNotAccentDriven() throws {
        let src = try sourceFile("TodayView.swift")
        let block = try XCTUnwrap(
            qaSlice(src, from: "let featuredCardGradient", to: "\n)"),
            "找不到 featuredCardGradient 常量声明"
        )
        XCTAssertTrue(block.contains("LinearGradient"), "推荐卡背景应是 LinearGradient")
        XCTAssertEqual(count(of: "Color(red:", in: block), 2, "渐变两端各一个写死的 Color")
        XCTAssertTrue(block.contains("startPoint: .leading"), "渐变方向应为左→右")
        XCTAssertTrue(block.contains("endPoint: .trailing"), "渐变方向应为左→右")
        for forbidden in ["AppState", "accent", "Accent", "NSColor", "@Environment", ".tint"] {
            XCTAssertEqual(count(of: forbidden, in: block), 0,
                           "渐变里出现 \(forbidden) —— 那就又变回随系统强调色变了")
        }
    }

    /// `FeaturedMatchCard` 里已无 `.glassEffect`；但 `columnCard` 那处 Liquid Glass 必须保留。
    func testFeaturedCardDroppedGlassEffectButColumnCardKeptIt() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "找不到 FeaturedMatchCard")
        XCTAssertEqual(count(of: "glassEffect", in: card), 0,
                       "FeaturedMatchCard 里仍有 .glassEffect 残留 —— 背景没换干净")

        let columnCard = try XCTUnwrap(
            qaSlice(code, from: "func columnCard", to: "struct FeaturedMatchCard"),
            "找不到 columnCard"
        )
        XCTAssertEqual(count(of: "glassEffect", in: columnCard), 1,
                       "columnCard 的 Liquid Glass 属于改动范围外，必须原样保留")
        XCTAssertTrue(columnCard.contains("RoundedRectangle(cornerRadius: 12)"),
                      "columnCard 的圆角应保持 12")
    }

    /// 暗化层的圆角必须与外层一致，否则边缘会露出毛边。
    func testFeaturedCardOverlaySharesCornerRadiusWithGradient() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let bg = try XCTUnwrap(qaSlice(card, from: ".background("), "找不到推荐卡的 .background(")

        XCTAssertEqual(count(of: "cornerRadius:", in: bg), 2,
                       "背景块里应恰好两处圆角：渐变一层 + 暗化 overlay 一层")
        XCTAssertEqual(count(of: "RoundedRectangle(cornerRadius: featuredCardCornerRadius)", in: bg), 2,
                       "两处圆角必须都用同一个 featuredCardCornerRadius 常量，不能写死数字")
        XCTAssertTrue(bg.contains(".fill(featuredCardGradient)"), "渐变没被填进背景")
        XCTAssertTrue(bg.contains(".fill(Color.black.opacity(0.12))"), "缺少暗化 overlay")
    }

    /// 只许动背景：圆角 / 内边距 / 队徽尺寸 / 比分字号 / 球队块留白一律不得变。
    func testFeaturedCardLayoutConstantsUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        XCTAssertTrue(code.contains("let featuredCardCornerRadius: CGFloat = 12"),
                      "推荐卡圆角应保持 12")
        XCTAssertTrue(code.contains("let featuredCardSideInset: CGFloat = 40"),
                      "球队块额外留白应保持 40")

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        XCTAssertTrue(card.contains("CrestImage(urlString: team.crest, size: 56)"),
                      "队徽应按 56×56 渲染（CrestImage.size，外层 .frame 放不大固定尺寸的子视图）")
        XCTAssertTrue(card.contains(".system(size: 44, weight: .bold, design: .rounded)"),
                      "比分字号应保持 44")
        XCTAssertTrue(card.contains(".padding(22)"), "卡片内边距应保持 22")
        XCTAssertTrue(card.contains("padding(.horizontal, featuredCardSideInset)"),
                      "中部球队块应仍用 featuredCardSideInset 留白")
        XCTAssertTrue(card.contains("VStack(spacing: 18)"), "卡片纵向间距应保持 18")
        XCTAssertTrue(card.contains("Spacer(minLength: 24)"), "比分两侧最小间距应保持 24")
    }

    /// 渐变换成写死的深紫红→亮粉后，卡上文字在**浅色模式**下还读得清吗？
    ///
    /// 修复方案：卡片子树强制深色语义（`.environment(\.colorScheme, .dark)`），
    /// 让 `.primary` / `.secondary` / 默认前景色在浅色模式下也解析成**白/浅灰**，
    /// 而不是黑字压深紫红（那样 WCAG 对比度只有 1.71:1）。
    /// 这里按 WCAG 相对亮度验证「白字 vs 渐变两端」的对比度都 ≥ AA 大字号门槛 3.0。
    func testFeaturedCardGradientKeepsTextReadableInLightMode() throws {
        let src = try sourceFile("TodayView.swift")

        // 修复的核心：卡片子树必须强制深色语义，否则浅色模式下文字解析成黑字
        XCTAssertTrue(src.contains(".environment(\\.colorScheme, .dark)"),
                      "推荐卡必须强制深色语义（.environment(\\.colorScheme, .dark)），否则浅色模式下黑字压深紫红几乎不可读")

        let block = try XCTUnwrap(qaSlice(src, from: "let featuredCardGradient", to: "\n)"))

        let re = try NSRegularExpression(
            pattern: #"Color\(\s*red:\s*([\d.]+)\s*,\s*green:\s*([\d.]+)\s*,\s*blue:\s*([\d.]+)\s*\)"#
        )
        var stops: [(Double, Double, Double)] = []
        for m in re.matches(in: block, range: NSRange(location: 0, length: (block as NSString).length)) {
            guard let rr = Range(m.range(at: 1), in: block),
                  let gg = Range(m.range(at: 2), in: block),
                  let bb = Range(m.range(at: 3), in: block),
                  let r = Double(block[rr]), let g = Double(block[gg]), let b = Double(block[bb])
            else { continue }
            stops.append((r, g, b))
        }
        XCTAssertEqual(stops.count, 2, "应解析出渐变的两个端点")

        // 暗化层：0.12 的黑叠在渐变之上
        let dim = 0.12
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func chan(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * chan(c.0) + 0.7152 * chan(c.1) + 0.0722 * chan(c.2)
        }
        func contrast(_ a: Double, _ b: Double) -> Double {
            let (hi, lo) = a > b ? (a, b) : (b, a)
            return (hi + 0.05) / (lo + 0.05)
        }

        // 深色语义下 .primary / 默认前景色 == 白（亮度 1）
        let white: Double = 1.0
        // WCAG AA 大字号（≥24pt）最低 3.0 —— 取最宽松的一档，避免误报
        let bar = 3.0
        for (i, s) in stops.enumerated() {
            let eff = (s.0 * (1 - dim), s.1 * (1 - dim), s.2 * (1 - dim))
            let ratio = contrast(luminance(eff), white)
            XCTAssertGreaterThanOrEqual(
                ratio, bar,
                "渐变端点 \(i)（rgb \(s)）叠上 0.12 暗化层后，与深色语义下的白字对比度只有 " +
                String(format: "%.2f", ratio) + ":1，低于 \(bar):1"
            )
        }
    }

    // ── 改动 2：状态徽标移左 + 删除「推荐比赛」字样 ──

    /// `UIString.featured` 必须零残留；同时确认删的不是 `vm.featured(...)` 选比赛的方法。
    func testFeaturedUIStringIsFullyRemovedButPickerSurvives() throws {
        for f in try allSourceFiles() {
            XCTAssertEqual(count(of: "UIString.featured", in: f.text), 0,
                           "\(f.name) 里仍有 UIString.featured —— 已删的「推荐比赛」字样回来了")
        }
        let strings = try sourceFile("UIStrings.swift")
        XCTAssertEqual(count(of: "featured", in: strings), 0,
                       "UIStrings.swift 里不该再有任何 featured 条目")

        // ⚠️ 反例护栏：选推荐比赛的**方法**必须完好，不能被误删
        let today = try sourceFile("TodayView.swift")
        XCTAssertTrue(today.contains("func featured(tz: TimeZone, now: Date = Date()) -> Match?"),
                      "TodayViewModel.featured(tz:now:) 被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("enum TodayFeatured"),
                      "TodayFeatured 枚举被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("func pick(from matches: [Match]"),
                      "TodayFeatured.pick 被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("if let featured = vm.featured(tz: timeZone)"),
                      "今日页仍在用 vm.featured(...) 取推荐比赛")
    }

    /// 行为层面确认选推荐比赛的逻辑没被删改（不只是「源码里还有这个符号」）。
    func testFeaturedPickerStillWorksAfterStringRemoval() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T04:00:00Z", status: "FINISHED",  matchday: 5),
            makeMatch(id: 2, kickoff: "2026-08-31T11:30:00Z", status: "IN_PLAY",   matchday: 5),
            makeMatch(id: 3, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 2,
                       "进行中的比赛优先成为推荐卡 —— featured(tz:now:) 仍然有效")
    }

    /// 顶部一行：轮次 → 状态徽标（靠左）→ Spacer 撑开右侧；且不再有「推荐比赛」文案。
    func testFeaturedCardTopRowIsRoundBadgeThenSpacer() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let top = try XCTUnwrap(qaSlice(card, from: "HStack(spacing: 8) {", to: "\n            }"),
                                "找不到推荐卡顶部的 HStack")

        XCTAssertFalse(top.contains("UIString.featured"), "顶部不该再有「推荐比赛」文案")
        XCTAssertTrue(top.contains("UIString.roundN.text(lang)"), "轮次要走 UIString.roundN")
        XCTAssertTrue(top.contains("statusBadge(lang: lang)"), "状态徽标应紧跟轮次")
        XCTAssertTrue(top.contains("Spacer()"), "末尾要有 Spacer 撑开右侧留白")

        // 顺序：轮次 < 徽标 < Spacer（徽标靠左、Spacer 收尾）
        let rRound = try XCTUnwrap(top.range(of: "UIString.roundN"))
        let rBadge = try XCTUnwrap(top.range(of: "statusBadge(lang: lang)"))
        let rSpacer = try XCTUnwrap(top.range(of: "Spacer()"))
        XCTAssertLessThan(rRound.lowerBound, rBadge.lowerBound, "轮次应在徽标之前")
        XCTAssertLessThan(rBadge.lowerBound, rSpacer.lowerBound, "徽标应靠左，Spacer 收尾")
    }

    /// `UIString.roundN` 必须保留，且今日页 / 赛程页两处调用都还在。
    func testRoundNStringStillServesTwoCallSites() throws {
        XCTAssertEqual(UIString.roundN.text(.chinese), "第 %d 轮")
        XCTAssertEqual(UIString.roundN.text(.english), "Round %d")
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.chinese)), 1)
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.english)), 1,
                       "中英占位符数量不一致会让 String(format:) 读脏参数")

        let today = codeOnly(try sourceFile("TodayView.swift"))
        let fixtures = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.roundN", in: today), 1,
                       "今日页推荐卡顶部仍应显示轮次")
        XCTAssertEqual(count(of: "UIString.roundN", in: fixtures), 1,
                       "赛程页赛季总览卡片仍应显示轮次")
    }

    // ── 改动 3：翻页只移窗口、不动 focusedRound ──

    /// 翻页函数体里不许出现 `focusedRound` —— 从源头锁住「翻页改焦点」。
    func testPagingFunctionsNeverTouchFocusedRound() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        let paging = try XCTUnwrap(
            qaSlice(code, from: "func pageRoundsBackward", to: "func groupedSections"),
            "找不到两个翻页函数"
        )
        XCTAssertEqual(count(of: "focusedRound", in: paging), 0,
                       "翻页函数不得改写 focusedRound —— 翻页只是移动 chip 的取景框")
        XCTAssertTrue(paging.contains("clampWindowStart()"),
                      "两个翻页函数都要夹回合法区间")
    }

    /// 大标题读的是 `vm.focusedRound`，不是窗口首轮 —— 翻页时标题必须稳定。
    func testFixturesHeaderReadsFocusedRoundNotWindow() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.fixturesHeader", in: code), 1,
                       "大标题只应出现一次")
        let section = try XCTUnwrap(
            qaSlice(code, from: "func thisRoundSection", to: "func seasonOverviewSection"),
            "找不到 thisRoundSection"
        )
        XCTAssertTrue(section.contains("UIString.fixturesHeader.text(lang), vm.focusedRound"),
                      "大标题必须读 vm.focusedRound，窗口移动时标题才不会跳变")
        XCTAssertFalse(section.contains("visibleRounds.first"),
                       "大标题不该跟着窗口首轮变")
    }

    /// 翻页对称往返：右翻 3 次再左翻 3 次，窗口与高亮都回到原处，focusedRound 全程恒定。
    ///
    /// ⚠️ 步数刻意选 3 —— 从起点 17 右翻 4 次会撞上界 33（clamp），
    /// 那时左翻 4 次回不到 17（非对称是 clamp 的正常结果，不是 bug）。
    func testPagingRoundTripKeepsFocusedRoundAndRestoresWindow() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "初始居中：MD20 居中 → 起点 17")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22])

        let originalStart = vm.roundWindowStart
        let shownMDs = vm.displayed.map(\.matchday)

        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 32, "右翻 3 次：17 → 22 → 27 → 32")
        XCTAssertEqual(vm.visibleRounds, [33, 34, 35, 36, 37])
        XCTAssertEqual(vm.focusedRound, 20, "翻页绝不改 focusedRound")
        XCTAssertEqual(vm.displayed.map(\.matchday), shownMDs, "内容区应始终显示 MD20")

        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "左翻 3 次窗口回到原处")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "回到原窗口后 MD20 重新高亮")
        XCTAssertEqual(vm.focusedRound, 20, "来回翻页后高亮仍是 MD20")
        XCTAssertTrue(vm.visibleRounds.contains(vm.focusedRound))
    }

    /// 单步右翻：窗口应正好从 MD18–22 挪到 MD23–27（窗口大小 5 的整页位移）。
    func testSingleForwardPageShiftsWindowByExactlyFive() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20

        vm.pageRoundsForward()
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27], "右翻一页 → MD23–MD27")
        XCTAssertEqual(vm.focusedRound, 20, "focusedRound 不动")

        vm.pageRoundsBackward()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "左翻一页 → 回到 MD18–MD22")
    }

    /// 初始居中仍成立：中间 / 靠左 / 靠右三种位置分别居中 / 左对齐 / 右对齐，且不越界。
    func testWindowAlignmentCoversMiddleLeftRightEdges() {
        // 中间：MD20 → 前 2 后 2
        let mid = FixturesViewModel()
        mid.matches = makeRounds(38)
        mid.roundWindowStart = 0
        mid.focusedRound = 20
        XCTAssertEqual(mid.visibleRounds, [18, 19, 20, 21, 22], "MD20 → 居中")

        // 靠左：MD1 / MD2 / MD3 → 起点夹到 0，不会变负
        for r in [1, 2, 3] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 30
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 0, "MD\(r) 靠左 → 起点夹到 0")
            XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        }

        // 靠右：MD36 / MD37 / MD38 → 起点夹到上界 33
        for r in [36, 37, 38] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 0
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 33, "MD\(r) 靠右 → 起点夹到上界 33")
            XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        }

        // 恰好比一屏多一轮（6 轮）→ 上界 1，右翻两格仍停在上界
        let six = FixturesViewModel()
        six.matches = makeRounds(6)
        six.focusedRound = 3
        XCTAssertEqual(six.roundWindowMaxStart, 1)
        six.pageRoundsForward()
        XCTAssertEqual(six.visibleRounds, [2, 3, 4, 5, 6])
        six.pageRoundsForward()
        XCTAssertEqual(six.roundWindowStart, 1, "再右翻仍停在上界")
    }

    /// 窗口不变量全量遍历：count × focusedRound × 翻页步数，逐一验三条不变量。
    func testWindowInvariantsHoldForAllCountsFocusedAndSteps() {
        let size = FixturesViewModel.roundWindowSize
        let counts = [0, 1, 3, 5, 6, 12, 38, 200]

        for count in counts {
            let vm = FixturesViewModel()
            vm.matches = count == 0 ? [] : makeRounds(count)

            var focusedCandidates = [1, 2, 3, 5, max(1, count / 2 + 1), count - 1, count, 999]
            focusedCandidates.append(contentsOf: [-5, 0])

            for focused in focusedCandidates {
                vm.focusedRound = focused
                let alignedStart = vm.roundWindowStart

                for step in 0...4 {
                    for _ in 0..<step { vm.pageRoundsForward() }

                    XCTAssertLessThanOrEqual(vm.visibleRounds.count, size,
                                             "count=\(count) focused=\(focused) fwd=\(step)：窗口超过 5")
                    XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                                "count=\(count) focused=\(focused) fwd=\(step)：起点为负")
                    XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                             "count=\(count) focused=\(focused) fwd=\(step)：起点越过上界")
                    XCTAssertEqual(vm.visibleRounds.count,
                                   min(size, max(0, count - vm.roundWindowStart)),
                                   "count=\(count) focused=\(focused) fwd=\(step)：窗口切片长度不对")
                    XCTAssertEqual(vm.focusedRound, focused,
                                   "count=\(count) fwd=\(step)：翻页改了 focusedRound")

                    // 再原路翻回去。⭐ 起点不是 0，而是上面 focusedRound 对齐后的位置。
                    // 往返的精确预期值：
                    //   - 右翻没撞上界（alignedStart + 5·step <= maxStart）→ 必须精确回到 alignedStart；
                    //   - 撞了上界 → 回程落点是 max(maxStart - 5·step, 0)（clamp 的正常结果，不是 bug）。
                    for _ in 0..<step { vm.pageRoundsBackward() }
                    let hitClamp = alignedStart + step * size > vm.roundWindowMaxStart
                    let expected = hitClamp
                        ? max(vm.roundWindowMaxStart - step * size, 0)
                        : alignedStart
                    XCTAssertEqual(vm.roundWindowStart, expected,
                                   "count=\(count) focused=\(focused) step=\(step)：" +
                                   "往返落点不符合预期（起点 \(alignedStart)，上界 \(vm.roundWindowMaxStart)）")
                }
            }
        }
    }

    /// `roundChipBar` 的文档注释曾写着「翻到的新窗口首轮自动成为新的聚焦轮次」——
    /// 那正是本次改动**删掉**的行为。注释与代码不符比没有注释更害人。
    func testRoundChipBarDocCommentDoesNotClaimPagingChangesFocus() throws {
        let src = try sourceFile("FixturesView.swift")
        let doc = try XCTUnwrap(
            qaSlice(src, from: "/// 「本轮」模式下的横向轮次切换", to: "func roundChipBar"),
            "找不到 roundChipBar 的文档注释"
        )
        for stale in ["自动成为新的聚焦轮次", "翻到的新窗口首轮", "自动成为新的"] {
            XCTAssertEqual(count(of: stale, in: doc), 0,
                           "roundChipBar 的文档注释仍在描述已被删除的「翻页即改焦点」行为：" + stale)
        }
    }

    // MARK: - QA 独立复审：今日页两处改动（每列 4 场 / 直播分钟数）

    /// `formatLiveClock` 全分支表驱动覆盖（纯函数，直接单测）。
    func testFormatLiveClockCoversAllBranches() {
        let cases: [(elapsed: Int, halftime: Bool, expected: String)] = [
            // 上半场（≤45）：直接用实际分钟
            (0, false, "0'"), (1, false, "1'"), (19, false, "19'"),
            (44, false, "44'"), (45, false, "45'"),
            // 中场休息区间 46–60（状态还没翻成 HALFTIME）→ 钳到 45'
            (46, false, "45'"), (50, false, "45'"), (60, false, "45'"),
            // 下半场 61–105：扣掉中场的 15 分钟
            (61, false, "46'"), (75, false, "60'"), (90, false, "75'"), (105, false, "90'"),
            // 补时 / 超长 → 钳到 90+'
            (106, false, "90+'"), (200, false, "90+'"),
            // 中场休息：无论已过多少分钟都固定 45'
            (0, true, "45'"), (45, true, "45'"), (46, true, "45'"),
            (80, true, "45'"), (200, true, "45'"),
        ]
        for c in cases {
            XCTAssertEqual(
                FeaturedMatchCard.formatLiveClock(elapsed: c.elapsed, isHalftime: c.halftime),
                c.expected,
                "elapsed=\(c.elapsed) isHalftime=\(c.halftime)"
            )
        }
    }

    /// 分段边界的 off-by-one：每一对相邻输入都必须落在正确的段里。
    func testFormatLiveClockSegmentBoundariesAreExact() {
        let boundaries: [(elapsed: Int, expected: String, note: String)] = [
            (45,  "45'",  "上半场末"),
            (46,  "45'",  "进入中场区间 → 钳位"),
            (60,  "45'",  "中场区间末"),
            (61,  "46'",  "下半场开始 → 扣 15"),
            (105, "90'",  "下半场末"),
            (106, "90+'", "进入补时 → 钳位"),
        ]
        for b in boundaries {
            XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: b.elapsed, isHalftime: false),
                           b.expected, "边界 \(b.elapsed)（\(b.note)）")
        }
    }

    /// 时钟偏差 / 状态提前置 IN_PLAY 时，已踢分钟数不得为负。
    /// `elapsedMinutes` 现已改为接收 `now` 的**纯函数**（可真正单测，见 `testElapsedMinutesPureFunction`），
    /// 这里守住声明本身的结构契约，确保它不会退化成「内部偷读 Date()」。
    func testElapsedMinutesClampsFutureKickoffToZero() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "找不到 elapsedMinutes"
        )
        XCTAssertTrue(decl.contains("max(0,"),
                      "elapsedMinutes 必须把负值夹到 0（时钟偏差时不能出负数）")
        XCTAssertTrue(decl.contains("guard let kickoff else { return nil }") ||
                      decl.contains("guard let kickoff else {return nil}"),
                      "拿不到开球时间必须返回 nil，供 statusLine 回退")
        XCTAssertTrue(decl.contains("floor("), "分钟数应向下取整")
    }

    /// 开球时间解析失败时，`statusLine` 的 live 分支要回退到「进行中」文案，不能崩或显示空串。
    func testStatusLineFallsBackToLiveTextWhenKickoffMissing() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func statusLine", to: "func statusBadge"),
            "找不到 statusLine"
        )
        XCTAssertTrue(fn.contains("guard let elapsed = Self.elapsedMinutes(kickoff: kickoff, now: now) else { return UIString.live.text(lang) }"),
                      "拿不到已踢分钟数时，live 分支必须回退到「进行中」文案")
        XCTAssertTrue(fn.contains("Self.formatLiveClock(elapsed: elapsed"),
                      "live 分支应调用纯函数 formatLiveClock")
        XCTAssertTrue(fn.contains("isHalftime: match.status == \"HALFTIME\""),
                      "中场状态要传给 formatLiveClock")
        XCTAssertFalse(fn.contains("formatLiveClock(elapsed: elapsedMinutes!"),
                      "不得对 elapsedMinutes 强制解包")
    }

    /// 非 live 分支（已结束 / 未开赛）不能被这次改动误伤。
    func testStatusLineNonLiveBranchesUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func statusLine", to: "func statusBadge"),
            "找不到 statusLine"
        )
        XCTAssertTrue(fn.contains("if TodayFilter.isFinished(match) { return UIString.statusFinished.text(lang) }"),
                      "已结束仍应返回「已结束」")
        XCTAssertTrue(fn.contains("guard let kickoff else { return UIString.tbd.text(lang) }"),
                      "未开赛且无开球时间仍应回退「待定」")
        XCTAssertTrue(fn.contains("df.dateFormat = lang == .english ? \"MMM d\" : \"M月d日\""),
                      "未开赛仍有开球时间时应返回日期")
        // 顺序：live → finished → upcoming，live 判断必须在最前
        guard let live = fn.range(of: "TodayFilter.isLive(match, now: now)"),
              let finished = fn.range(of: "TodayFilter.isFinished(match)") else {
            return XCTFail("statusLine 缺少状态分支")
        }
        XCTAssertLessThan(live.lowerBound, finished.lowerBound, "live 分支必须在最前面")
    }

    // MARK: - 实时分钟数：纯函数 + TimelineView 解耦（修复「分钟数冻结」）

    /// `elapsedMinutes(kickoff:now:)` 全分支：把 `now` 显式传入后，时间 → 分钟数完全可单测
    /// （旧实现偷偷读 `Date()`，只能靠源码扫描）。
    func testElapsedMinutesPureFunction() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func mins(_ seconds: TimeInterval) throws -> Int {
            try XCTUnwrap(FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                           now: kickoff.addingTimeInterval(seconds)),
                          "elapsedMinutes 不应为 nil")
        }

        XCTAssertNil(FeaturedMatchCard.elapsedMinutes(kickoff: nil, now: kickoff),
                     "拿不到开球时间 → nil")

        XCTAssertEqual(try mins(0), 0, "恰好开球 → 0'")
        XCTAssertEqual(try mins(-30), 0, "now 早于 kickoff → clamp 到 0，不得为负")
        XCTAssertEqual(try mins(-3600), 0, "时钟偏差 1 小时 → 仍 clamp 到 0")
        XCTAssertEqual(try mins(59.9), 0, "59.9s 尚未跨分钟 → 0'")
        XCTAssertEqual(try mins(60.0), 1, "60.0s 正好跨分钟 → 1'")
        XCTAssertEqual(try mins(60.5), 1, "60.5s 仍取下界 → 1'")
        XCTAssertEqual(try mins(16 * 60), 16, "题目场景：16 分钟 → 16'")
        XCTAssertEqual(try mins(6000), 100, "长时差（100 分钟）→ 100'")
    }

    /// 「时间 → 显示文本」整条链路纯函数化：`elapsedMinutes(now)` 组合 `formatLiveClock` 即可断言文本。
    func testLiveMinuteTextChainIsPure() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func text(atSeconds seconds: TimeInterval, isHalftime: Bool = false) throws -> String {
            let elapsed = try XCTUnwrap(
                FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                 now: kickoff.addingTimeInterval(seconds)))
            return FeaturedMatchCard.formatLiveClock(elapsed: elapsed, isHalftime: isHalftime)
        }
        XCTAssertEqual(try text(atSeconds: 4 * 60), "4'")
        XCTAssertEqual(try text(atSeconds: 16 * 60), "16'", "用户报的卡住场景")
        XCTAssertEqual(try text(atSeconds: 0), "0'")
        XCTAssertEqual(try text(atSeconds: 50 * 60, isHalftime: true), "45'", "中场固定 45'")
    }

    /// 实时分钟数必须挂在 `TimelineView(.periodic(by: 1))` 上（独立于数据刷新的重绘源），
    /// 否则 `match` 未变时 SwiftUI 跳过本卡 body，分钟数冻结。
    func testFeaturedCardLiveMinuteWrappedInTimelineView() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "找不到 FeaturedMatchCard")
        XCTAssertEqual(count(of: "TimelineView(", in: card), 1,
                       "实时分钟数应且只应有一个 TimelineView")
        XCTAssertTrue(card.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "TimelineView 必须是 1 秒周期，才能跨分钟刷新")

        // TimelineView 只包住那一个 Text（在 centerBlock 的实时分支里），不包整张卡
        let center = try XCTUnwrap(qaSlice(card, from: "func centerBlock",
                                           to: "func scoreRow"),
                                   "找不到 centerBlock")
        XCTAssertTrue(center.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "TimelineView 必须只在 centerBlock 的实时分支里")
        XCTAssertTrue(center.contains("context.date"),
                      "TimelineView 闭包应把 context.date 作为 now 传入状态行")
        XCTAssertTrue(center.contains("Text(statusLine(lang: lang, now: Date()))"),
                      "非实时分支仍用 Date() 单次求值，不引入每秒重绘")
    }

    /// `elapsedMinutes` 不得再内部读 `Date()` —— 时间来源必须是显式 `now` 参数（本 bug 的根治点）。
    func testElapsedMinutesHasNoImplicitDateRead() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "找不到 elapsedMinutes"
        )
        XCTAssertFalse(decl.contains("Date()"),
                       "elapsedMinutes 不得内部读 Date() —— 必须由调用方（TimelineView）传入 now")
        XCTAssertTrue(decl.contains("now: Date"), "elapsedMinutes 应显式接收 now")
    }
}

extension EPLViewerTests {
    // MARK: - 推荐卡「进行中分钟数」记法

    /// 守卫 `FeaturedMatchCard.formatLiveClock` 的分支逻辑。
    /// 这是用户明确要的「进行中 → 显示已踢分钟数（如 19'）」的渲染契约，
    /// 工程师特意把它抽成不依赖 `Date()` 的纯函数，便于单测覆盖每一个分支。
    /// 分支规则见 TodayView.swift 中 `formatLiveClock` 的注释。
    func testFormatLiveClockBranches() throws {
        // 中场休息：固定 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 50, isHalftime: true), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: true), "45'")

        // 上半场（≤45）：实际分钟
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: false), "0'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 19, isHalftime: false), "19'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 45, isHalftime: false), "45'")

        // 中场休息区间（46–60，状态还没翻成 HALFTIME）：钳到 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 46, isHalftime: false), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 60, isHalftime: false), "45'")

        // 下半场（61–105）：实际分钟扣掉中场 15 分钟（61→46'，90→75'，105→90'）
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 61, isHalftime: false), "46'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 90, isHalftime: false), "75'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 105, isHalftime: false), "90'")

        // 补时 / 超长（>105）：钳到 90+'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 106, isHalftime: false), "90+'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 120, isHalftime: false), "90+'")
    }

    // MARK: - 推荐卡中间大槽内容（centerContent）

    /// 造一支只靠 id 区分的球队（`makeMatch series` 不够用时自建）
    func ccTeam(_ id: Int) -> Team {
        Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// 造一场比赛；`homeScore` / `awayScore` 均为 nil 表示「无比分」（`score = nil`）。
    /// 注意 `makeMatch` / `makeMatchTeams` 的 score 恒为 nil，测比分相关分支需要这个辅助。
    func ccMatch(id: Int = 1,
                         kickoff: String? = "2026-09-12T14:00:00Z",
                         status: String?,
                         home: Int = 1, away: Int = 2,
                         homeScore: Int? = nil, awayScore: Int? = nil) -> Match {
        let score: Score? = (homeScore != nil || awayScore != nil)
            ? Score(fullTime: FullTime(home: homeScore, away: awayScore))
            : nil
        return Match(id: id, matchday: 4, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: ccTeam(home), awayTeam: ccTeam(away), score: score)
    }

    /// 核心回归：**进行中但无比分** → `.pendingLiveScore`（改动前会错误地退化成 `.kickoff`，
    /// 于是卡片上方显示开球时间、下方显示已踢分钟数，自相矛盾）。
    func testCenterContentLiveWithoutScoreIsPendingLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay), .pendingLiveScore,
                       "IN_PLAY 但数据源还没给比分时，必须按 0-0 展示，不能显示开球时间")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime), .pendingLiveScore,
                       "HALFTIME 但无比分时同样按 0-0 展示")
    }

    /// 进行中**且有比分** → `.score`，且 `isLive == true`（判定顺序里「有比分」优先于 live）。
    func testCenterContentLiveWithScoreReturnsLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: 1, awayScore: 0)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay),
                       .score(home: 1, away: 0, isLive: true),
                       "进行中且有比分时应显示真实比分（绝不能退化成 0-0）")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: 2, awayScore: 1)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime),
                       .score(home: 2, away: 1, isLive: true),
                       "中场休息状态也算 live，应显示真实比分")
    }

    /// 未开赛（`SCHEDULED`）+ 有开球时间 → `.kickoff`（行为与改动前一致）。
    func testCenterContentScheduledReturnsKickoff() throws {
        let m = ccMatch(kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED")
        let expected = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m), .kickoff(expected),
                       "未开赛且有开球时间时应显示开球时间")
    }

    /// 已结束 + 有比分 → `.score`，且 `isLive == false`。
    func testCenterContentFinishedWithScoreReturnsNonLiveScore() throws {
        let m = ccMatch(status: "FINISHED", homeScore: 2, awayScore: 2)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m),
                       .score(home: 2, away: 2, isLive: false),
                       "已结束应显示最终比分，且不带 live 语义")
    }

    /// 非 live、无开球时间、无比分 → `.tbd`。
    func testCenterContentNonLiveNoKickoffNoScoreReturnsTbd() throws {
        let scheduled = ccMatch(kickoff: nil, status: "SCHEDULED")
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: scheduled), .tbd,
                       "拿不到比分也拿不到开球时间 → 待定")

        let noStatus = ccMatch(kickoff: nil, status: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: noStatus), .tbd,
                       "状态缺失且无开球时间 / 比分 → 待定")
    }

    // MARK: - 「未开赛 → 进行中」过渡对齐（显示侧与调度器同一套开球窗口径）

    /// 核心回归：开球后、但数据源 `status` 还没翻（FPL 滞后约 8 分钟）时，
    /// 一场 `SCHEDULED` 且已落在「开球 → 开球+3h」窗内的比赛，显示侧应把它当**进行中**
    /// 处理（卡片显示 0 - 0 + ⚽），而不是退化成「未开赛 / 开球时间」。
    /// 这正是「调度器已在轮询、UI 却还显示未开赛」那个缺口的修复点。
    func testCenterContentScheduledButInKickoffWindowIsPendingLiveScore() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))
        // 开球后 2 分钟、比分尚未出版（数据源滞后）
        let now = kickoff.addingTimeInterval(2 * 60)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m, now: now), .pendingLiveScore,
                       "开球窗内的 SCHEDULED（无比分）应显示 0-0 进行中，而非开球时间")
    }

    /// `TodayFilter.isLive(_:now:)` 双信号等价性：状态 OR 开球窗，与 `AutoRefreshScheduler` 一致。
    func testTodayFilterIsLiveWindowAlignedWithScheduler() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))

        // 1) 状态信号永远为真（不依赖 now）
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "IN_PLAY")), "IN_PLAY 应判为进行中")
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "HALFTIME")), "HALFTIME 应判为进行中")

        // 2) 开球窗信号：窗内为真
        let inWindow = kickoff.addingTimeInterval(2 * 60)
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: inWindow),
                      "开球后落在 3h 窗内应判为进行中")

        // 3) 开球前：尚未进行中
        let beforeKickoff = kickoff.addingTimeInterval(-60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: beforeKickoff),
                       "开球前不应判为进行中")

        // 4) 开球 4 小时后（超出 3h 窗）：不再进行中
        let afterWindow = kickoff.addingTimeInterval(4 * 60 * 60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: afterWindow),
                       "超出 3h 窗不应判为进行中")

        // 5) 已结束优先于时间窗：即使仍在窗内，FINISHED 也非进行中
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "FINISHED"), now: inWindow),
                       "已结束优先于时间窗，不应判为进行中")
    }

    /// 回归：延期 / 取消的比赛虽未结束，但原开球时间同样落进 3h 时间窗 ——
    /// 不得被时间窗兜底判成「进行中」（否则赛果卡显示 ⚽ 0-0，而非「延期 / 取消」）。
    func testIsLiveExcludesPostponedAndCanceledEvenInWindow() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(30 * 60)

        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "POSTPONED"), now: now),
                       "开球窗内的 POSTPONED 不应判为进行中")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELED"), now: now),
                       "开球窗内的 CANCELED 不应判为进行中")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELLED"), now: now),
                       "开球窗内的 CANCELLED 不应判为进行中")

        // 同一时刻、同一开球时间的 SCHEDULED 仍按窗内进行中处理（防止把兜底逻辑改死）
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: now),
                      "状态滞后的正常比赛仍应按时间窗判为进行中")
    }

    /// 分区回归：开球窗内的 SCHEDULED 比赛应进入「进行中」分组，而非「未开赛」分组
    /// （今日页 / 赛程页 header 计数与分栏的对齐依据）。
    func testGroupedScheduledInWindowCountedAsLiveNotUpcoming() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(2 * 60)
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let today = TodayFilter.todayMatches(from: [m], now: now, tz: tz)
        let live = today.filter { TodayFilter.isLive($0, now: now) }
        let upcoming = today.filter { TodayFilter.isUpcoming($0, now: now) }

        XCTAssertEqual(live.count, 1, "开球窗内的 SCHEDULED 应计入进行中")
        XCTAssertEqual(upcoming.count, 0, "开球窗内的 SCHEDULED 不应同时计入未开赛")
    }
}
