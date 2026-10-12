import XCTest
@testable import EPLViewer

// 自动刷新:持久化 / 调度器 / 缓存失效
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
    // MARK: - autoRefresh 持久化（UserDefaults）

    /// `autoRefresh` 应持久化到 UserDefaults（key `epl_autorefresh`）：写入后重读一致。
    @MainActor
    func testAutoRefreshPersistsToUserDefaults() throws {
        let key = "epl_autorefresh"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            // 还原，避免污染本机 App 默认值 / 其它测试
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        let state = AppState()
        XCTAssertFalse(state.autoRefresh, "未写入时默认应为 false")

        state.autoRefresh = true
        XCTAssertTrue(defaults.bool(forKey: key), "打开后应写回 UserDefaults")
        XCTAssertTrue(AppState().autoRefresh, "新实例应从 UserDefaults 恢复 true")

        state.autoRefresh = false
        XCTAssertFalse(defaults.bool(forKey: key), "关闭后应写回 false")
        XCTAssertFalse(AppState().autoRefresh, "新实例应恢复 false")
    }

    /// 未写入 key 时默认关闭（`UserDefaults.bool` 缺省即 false）。
    @MainActor
    func testAutoRefreshDefaultsToFalseWhenKeyAbsent() throws {
        let key = "epl_autorefresh"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertFalse(AppState().autoRefresh, "未写入 key 时默认 false")
    }

    /// 从 UserDefaults 恢复 `autoRefresh == true` 时，Toggle 的 `.onChange` 不会触发，
    /// 必须在根视图出现时补配置一次定时器，否则「UI 显示开启但 timer 没建」。
    func testRootViewConfiguresAutoRefreshOnAppear() throws {
        let code = codeOnly(try sourceFile("ContentView.swift"))
        XCTAssertTrue(code.contains(".task { appState.configureAutoRefresh() }"),
                      "ContentView 应在出现时调用 configureAutoRefresh()，以恢复持久化的开启状态")
    }

    /// `autoRefresh` 声明应从 UserDefaults 读（Bool 直接读）、`didSet` 写回，key 与既有命名一致。
    func testAutoRefreshDeclarationUsesUserDefaults() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "var autoRefresh: Bool", to: "var isLoading"),
            "找不到 autoRefresh 声明"
        )
        XCTAssertTrue(decl.contains("UserDefaults.standard.bool(forKey: \"epl_autorefresh\")"),
                      "autoRefresh 应从 UserDefaults 读取（Bool 直接读，不套 rawValue）")
        XCTAssertTrue(decl.contains("UserDefaults.standard.set(autoRefresh, forKey: \"epl_autorefresh\")"),
                      "didSet 应把 autoRefresh 写回 UserDefaults")
        XCTAssertFalse(decl.contains(".rawValue"), "Bool 读写不需要 rawValue")
    }

    // MARK: - 「比赛期间自动刷新」调度器（AutoRefreshScheduler 纯函数）

    /// 调度常量锁定（改动需同步契约表）。
    func testAutoRefreshSchedulerConstants() throws {
        XCTAssertEqual(AutoRefreshScheduler.liveInterval, 60, "有比赛时 60s")
        XCTAssertEqual(AutoRefreshScheduler.kickoffLeadTime, 15 * 60, "开球前 15 分钟提前醒")
        XCTAssertEqual(AutoRefreshScheduler.maxIdleSleep, 6 * 60 * 60, "空闲最长休眠 6h")
        XCTAssertEqual(AutoRefreshScheduler.matchWindow, 3 * 60 * 60, "单场最大跨度 3h")
    }

    /// `refreshInterval` 决策表 —— 逐行覆盖（行为契约，唯一间隔入口）。
    func testRefreshIntervalDecisionTable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:00:00Z"))

        // 行 1：全局 autoRefresh=true → 始终 60（与 duringMatches / schedule 无关）
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "全局开 → 60s")
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "全局开 → 60s（与其它无关）")

        // 行 2：全局关 + 比赛期间关 → nil（不设定时器）
        XCTAssertNil(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: now.addingTimeInterval(600)), now: now),
            "两项都关 → 不设定时器")

        // 行 3：全局关 + 比赛期间开 + 有比赛进行中 → 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "有比赛进行中 → 60s")

        // 行 4：无比赛，下一场 +2h → 睡到开球前 15 分钟 = 2h - 15min = 6300s
        //   ⚠️ 团队需求表里此处写作 6900；但 6900 = 2h − 5min，与 kickoffLeadTime(=15min) 不自洽。
        //   按常量语义（开球前 15 分钟醒）应为 6300，本测试锁 6300。
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(2 * 3600)), now: now),
            2 * 3600 - 15 * 60, "睡到下一场开球前 15 分钟（6300s）")

        // 行 5：下一场 +10min（已进入开球前 15 分钟窗口）→ 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(10 * 60)), now: now),
            AutoRefreshScheduler.liveInterval, "已进入开球前窗口 → 60s")

        // 行 6：下一场 +3 天 → clamp 到 maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(3 * 24 * 3600)), now: now),
            AutoRefreshScheduler.maxIdleSleep, "太久远 → clamp 到 6h")

        // 行 7：无下一场 → maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.maxIdleSleep, "无赛程 → 6h 兜底")
    }

    /// 开球 30 分钟前、未结束 → 时间窗判定为进行中；无未来比赛 → nextKickoff = nil。
    func testScheduleDetectsLiveMatchByKickoffWindow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let live = makeMatchTeams(id: 1, home: 1, away: 2,
                                  kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY")
        let s = AutoRefreshScheduler.schedule(matches: [live], now: now)
        XCTAssertTrue(s.hasLiveMatch, "开球 30 分钟前、未结束 → 进行中")
        XCTAssertNil(s.nextKickoff, "没有晚于 now 的比赛")
    }

    /// 数据源状态还没翻（status 仍是 SCHEDULED），但 kickoff 已过且未超窗 → 仍算进行中
    /// （本项目有前科：FPL 开球后约 8 分钟状态/比分未更新）。
    func testScheduleKickoffWindowIgnoresStaleStatus() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:55:00Z", status: "SCHEDULED")
        XCTAssertTrue(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                      "刚开球、状态未翻 → 用时间窗判定为进行中")
    }

    /// 回归：延期 / 取消的比赛即使原开球时间落进时间窗，也不得触发 60s 直播轮询
    /// （否则一场延期的比赛会让调度器空转轮询整整 3 小时）。
    func testScheduleIgnoresPostponedAndCanceledMatches() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let postponed = makeMatchTeams(id: 1, home: 1, away: 2,
                                       kickoff: "2026-09-12T13:55:00Z", status: "POSTPONED")
        let canceled = makeMatchTeams(id: 2, home: 3, away: 4,
                                      kickoff: "2026-09-12T13:55:00Z", status: "CANCELED")
        let s = AutoRefreshScheduler.schedule(matches: [postponed, canceled], now: now)
        XCTAssertFalse(s.hasLiveMatch, "延期 / 取消不算比赛进行中")
    }

    /// 已结束且已超出 3h 时间窗 → 非进行中。
    func testScheduleFinishedOutsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T10:00:00Z", status: "FINISHED")
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "已结束且超窗口 → 非进行中")
    }

    /// ⚠️ 补真实覆盖缺口：已 FINISHED 且**开球仍在 3h 时间窗内** → 必须判为「非进行中」。
    /// 既有的 `testScheduleFinishedOutsideWindowIsNotLive` 用的是 4h 前开球（本就超出窗口），
    /// 因此 `!TodayFilter.isFinished(m)` 这个条件**曾经实际没有被任何用例覆盖**（删掉它也全绿：
    /// 独立 QA 的变异测试 N1 已证实）。本用例专门堵这个洞。
    func testScheduleFinishedInsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:00:00Z", status: "FINISHED") // 1h 前开球，仍在 3h 窗内
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "已结束的比赛即使仍落在时间窗内，也必须判为非进行中")
    }

    /// 结构性守卫：定时器 repeats、视图回报去抖、两处上报点齐全。
    /// （这三条此前均无用例把守 —— 独立 QA 变异 N4 / N6 / N7 删掉后测试仍全绿。）
    func testLiveScheduleWiringGuards() throws {
        let app = codeOnly(try sourceFile("AppState.swift"))

        // N4：定时器必须 repeats —— 「睡到开球前」是先睡一个长间隔、再靠 tick 重算收尾，
        //     改成一次性的话只会醒一次，之后再也无人重建它。
        let cfg = try XCTUnwrap(
            qaSlice(app, from: "func configureAutoRefresh()", to: "func refreshTick"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(cfg.contains("repeats: true"),
                      "定时器必须 repeats:true；改成一次性会导致长睡之后无人再建定时器")

        // N6：去抖 + 记下最新赛程（后者是 refreshTick 能重算 schedule 的前提）
        XCTAssertTrue(app.contains("guard s != liveSchedule else { return }"),
                      "reportLiveSchedule 必须保留去抖，否则每次视图回报都会重建 timer")
        XCTAssertTrue(app.contains("lastKnownMatches = matches"),
                      "reportLiveSchedule 必须记下最新赛程，供 refreshTick 按最新 now 重算 schedule")

        // N7：两个加载赛程的页面都必须上报（漏一个就可能在停在该页时睡过比赛）
        XCTAssertTrue(codeOnly(try sourceFile("TodayView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "TodayView 必须回报赛程")
        XCTAssertTrue(codeOnly(try sourceFile("FixturesView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "FixturesView 必须回报赛程")
    }

    /// 未来比赛不算进行中；`nextKickoff` 取最早的未来开球。
    func testScheduleFutureMatchNotLiveAndReportsNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T16:00:00Z", status: "SCHEDULED"),
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T15:00:00Z", status: "SCHEDULED"), // 最早
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertFalse(s.hasLiveMatch, "未来的比赛不算进行中")
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T15:00:00Z")),
                       "nextKickoff 应是最早的未来开球")
    }

    /// 同时存在进行中与未来比赛 → 两者都要报出来。
    func testScheduleReportsBothLiveAndNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY"),  // 进行中
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T17:00:00Z", status: "SCHEDULED"), // 未来
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertTrue(s.hasLiveMatch)
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T17:00:00Z")))
    }

    /// 空数组 / `utcDate` 不可解析 → 不崩，返回 false/nil。
    func testScheduleEmptyAndUnparseable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let empty = AutoRefreshScheduler.schedule(matches: [], now: now)
        XCTAssertFalse(empty.hasLiveMatch)
        XCTAssertNil(empty.nextKickoff)

        let bad = makeMatchTeams(id: 9, home: 1, away: 2, kickoff: "not-a-date", status: "SCHEDULED")
        let s = AutoRefreshScheduler.schedule(matches: [bad], now: now)
        XCTAssertFalse(s.hasLiveMatch, "不可解析的 utcDate 应被跳过")
        XCTAssertNil(s.nextKickoff)
    }

    /// `configureAutoRefresh` 必须走 `refreshInterval` 决策，不得再硬编码 60s。
    func testConfigureAutoRefreshUsesSchedulerNotHardcoded60() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "func reportLiveSchedule"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(fn.contains("AutoRefreshScheduler.refreshInterval("),
                      "间隔决策必须走 refreshInterval，不得硬编码")
        XCTAssertFalse(fn.contains("withTimeInterval: 60"),
                       "不应再硬编码 60s 间隔")
        XCTAssertTrue(fn.contains("withTimeInterval: interval"),
                      "应把 refreshInterval 的结果传给定时器")
    }

    /// 🚨 守护栏：定时器唤醒后必须**重算间隔**，否则会睡过整场比赛。
    /// 场景：睡到「开球前 15 分钟」醒来时，`schedule` 内容与睡眠前完全相同（`hasLiveMatch` 仍 false、
    /// `nextKickoff` 仍是同一场）→ `reportLiveSchedule` 会早退不重建；只有 tick 自己重算才能把
    /// 间隔切到 60s。删掉 `refreshTick` 里的 `configureAutoRefresh()` 本测试必须变红。
    func testRefreshTickRecomputesIntervalOnEveryWake() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))

        // 1) refreshTick 体内必须「先刷新、再重算间隔」
        let tick = try XCTUnwrap(
            qaSlice(code, from: "func refreshTick", to: "func reportLiveSchedule"),
            "找不到 refreshTick"
        )
        XCTAssertTrue(tick.contains("await refresh(scoresOnly: true)"),
                      "refreshTick 必须先刷新数据，且比赛期间轮询只失效赛程（scoresOnly），不清整份 bootstrap")
        XCTAssertTrue(tick.contains("configureAutoRefresh()"),
                      "refreshTick 必须重算间隔（configureAutoRefresh），否则会睡过整场比赛")
        // ⚠️ 关键：必须用**最新 now 重新算 schedule**，不能只拿存下来的 liveSchedule 算间隔。
        // `hasLiveMatch` 只是存储 Bool、不会自己翻转；只有在 tick 里按开球时间窗重算，
        // 时间越过比赛结束后才会变成 false。否则停在不上报赛程的 tab（积分榜/设置/球员榜/伤停）
        // 时 liveSchedule 被冻结 → 比赛全结束仍永久 60s 轮询。
        XCTAssertTrue(tick.contains("AutoRefreshScheduler.schedule("),
                      "refreshTick 必须用最新 now 重算 schedule，否则停在不上报的 tab 时会永久 60s 轮询")

        // 2) 定时器 fire 闭包必须指向 refreshTick()，而不是只调 refresh()
        let cfg = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "func refreshTick"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(cfg.contains("await self?.refreshTick()"),
                      "定时器 fire 闭包应调用 refreshTick()，在每次唤醒后重算间隔")
        XCTAssertFalse(cfg.contains("await self?.refresh()"),
                       "fire 闭包不应再直接调 refresh()（应调 refreshTick()）")

        // 3) 不得残留「绝不在 tick 里重新 configure」的反向说明（防后人照抄改回去）
        let raw = try sourceFile("AppState.swift")
        XCTAssertFalse(raw.contains("绝不在 tick 里重新 configure"),
                       "错误理由的注释必须删除，避免后人当契约改回去")
    }

    // MARK: - 「比赛期间自动刷新」持久化 + 文案

    @MainActor
    func testAutoRefreshDuringMatchesPersistsToUserDefaults() throws {
        let key = "epl_autorefresh_matches"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        let state = AppState()
        XCTAssertTrue(state.autoRefreshDuringMatches, "未写入（新装 / 从未动过这项）→ 默认开启")

        state.autoRefreshDuringMatches = true
        XCTAssertTrue(defaults.bool(forKey: key), "打开后应写回 UserDefaults")
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "新实例应从 UserDefaults 恢复 true")

        state.autoRefreshDuringMatches = false
        XCTAssertFalse(defaults.bool(forKey: key), "关闭后应写回 false")
        // ⚠️ 关键回归：用户显式关掉后，新实例必须仍是 false，不能被「默认开」顶回 true。
        // 这条守的是三态判定（object(forKey:) == nil）—— 若退化成 bool(forKey:)，
        // 默认值 true 就没法实现，或者关掉后一重启又变开。
        XCTAssertFalse(AppState().autoRefreshDuringMatches,
                       "用户显式关掉后，新实例必须仍是 false（不能被默认值顶回 true）")
    }

    /// 缺 key（新装 / 从未动过这项设置）→ **默认 true**（用户要求「装好就勾上」）。
    @MainActor
    func testAutoRefreshDuringMatchesDefaultsTrueWhenKeyAbsent() throws {
        let key = "epl_autorefresh_matches"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "缺 key → 默认开启")
    }

    /// 文案必须中英双语，禁止写死中文。
    func testAutoRefreshDuringMatchesStringsBilingual() throws {
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.chinese), "比赛期间自动刷新")
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.english), "Auto-refresh during matches")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.chinese), "已开启全局自动刷新，此项无需设置")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.english),
                       "Global auto-refresh is on; this setting is not needed")
    }

    /// 全局自动刷新开启时，「比赛期间自动刷新」Toggle 应被 disable，并显示脚注说明。
    func testSettingsDisablesDuringMatchesToggleWhenGlobalOn() throws {
        let code = codeOnly(try sourceFile("SettingsView.swift"))
        XCTAssertTrue(code.contains(".disabled(appState.autoRefresh)"),
                      "全局自动刷新开启时，「比赛期间自动刷新」应被 disable")
        XCTAssertTrue(code.contains("UIString.autoRefreshDuringMatchesHint.text(appState.language)"),
                      "应显示「无需设置」的脚注")
    }

    /// 每列最多 4 场：确认只作用于两列，且「查看全部 →」入口完好。
    func testColumnCardCapsAtFourAndViewAllIntact() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        // columnCard 只有两处调用（左右两列），没有别的调用点被顺带截断
        XCTAssertEqual(count(of: "columnCard(", in: code), 3,
                       "期望 columnCard 定义 1 处 + 调用 2 处；出现新的调用点需确认是否该被截断")
        XCTAssertEqual(count(of: "ForEach(Array(matches.prefix(4)))", in: code), 1,
                       "截断只应发生在 columnCard 内部一处")

        // 「查看全部 →」仍在，且仍跳赛程页 —— 被截断的比赛要有去处
        XCTAssertEqual(count(of: "UIString.viewAll", in: code), 1,
                       "列卡片右上角的「查看全部 →」不能丢")
        XCTAssertTrue(code.contains("appState.selected = .fixtures"),
                      "「查看全部 →」必须仍跳转到赛程页")

        // 截断不应影响 ViewModel 数据本身（列里超过 4 场时数据仍在，只是不渲染）
        XCTAssertTrue(code.contains("ForEach(Array(matches.prefix(4))) { match in"),
                      "应保留 ForEach 的 match 绑定")
    }

    /// 卡片强制 `.dark` 后 `.primary` 是纯白（对比度过 bar）。
    /// 但 `.secondary` 在 macOS 深色下是**半透明**的 secondaryLabelColor（≈60% 白），
    /// 会**跟着背景一起变暗**；写死的深紫红→亮粉渐变上实测仅 2.31~2.51:1（< 3.0 大字号下限），肉眼发灰。
    /// 量化证明见 companion 测试 `testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient`（不透明白 ≥ bar）。
    /// 因此修法：推荐卡上的小字一律用不透明白 `.white`。
    /// 这里守住「FeaturedMatchCard 内不得再用 `.secondary`」—— 一旦有人回退成 `.secondary`，对比度会塌回发灰。
    func testFeaturedCardSecondaryTextMeetsReadabilityBar() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(
            qaSlice(code, from: "struct FeaturedMatchCard"),
            "找不到 FeaturedMatchCard 定义"
        )
        XCTAssertEqual(count(of: ".secondary", in: card), 0,
            "推荐卡（FeaturedMatchCard）上的小字必须改用不透明白 .white，不能用 .secondary —— " +
            "深紫红→亮粉渐变上 .secondary 对比度仅 2.31:1，达不到 3.0:1，肉眼发灰。")
    }

    /// 参照组：证明「不透明的白字」这个修法确实够用（给工程师一个明确的改法方向）。
    func testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient() throws {
        let src = try sourceFile("TodayView.swift")
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
        XCTAssertEqual(stops.count, 2)

        func luminance(_ c: (Double, Double, Double)) -> Double {
            func chan(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * chan(c.0) + 0.7152 * chan(c.1) + 0.0722 * chan(c.2)
        }
        let white: Double = 1.0
        for (i, s) in stops.enumerated() {
            let bg = (s.0 * 0.88, s.1 * 0.88, s.2 * 0.88)
            let lb = luminance(bg)
            let ratio = (max(white, lb) + 0.05) / (min(white, lb) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                        "不透明白字在端点 \(i) 的对比度应达标")
        }
    }
}

extension EPLViewerTests {
    /// 比赛期间 60s 轮询必须只清「赛程」缓存，不能走 full clearCache()（那会把整份
    /// FPL bootstrap / 积分榜一起清掉，导致每 60s 重下大文件）。
    /// 护栏：invalidateFixtures() 后，内存里的 fixtures 被清、bootstrap 保留。
    func testInvalidateFixturesClearsFixturesKeepsBootstrap() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "夹具 matchesJSON 应可解码出赛程")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        await DataRepository.invalidateFixtures()

        // 赛程被失效
        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "invalidateFixtures 必须清掉内存赛程缓存")
        // bootstrap 保留 —— 若误用 full clearCache()，这里会是 nil
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "invalidateFixtures 不能清掉 bootstrap（否则每 60s 重下整份 bootstrap）")
    }

    /// 端到端护栏：AppState.refresh(scoresOnly:) 的定时器路径不清整份缓存。
    /// 预填内存 fixtures + bootstrap，调用 scoresOnly 刷新后，
    /// fixtures 被清、bootstrap 仍在（证明没走 full clearCache，否则 bootstrap 也会被清）。
    /// 注：CacheStore 磁盘 IO 在本沙箱被拦截，这里用内存缓存层做等价断言。
    @MainActor
    func testRefreshScoresOnlyDoesNotWipeAllCaches() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "夹具 matchesJSON 应可解码出赛程")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        let appState = AppState()
        await appState.refresh(scoresOnly: true)

        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "scoresOnly 刷新必须失效赛程缓存")
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "scoresOnly 刷新不能清掉 bootstrap（否则每 60s 重下整份 bootstrap）")
    }
}
