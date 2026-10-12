import XCTest
@testable import EPLViewer

// 赛程页:布局 / 轮次窗口 / 快照缓存
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
    // MARK: - 赛程页（截图风格布局）

    /// focusedRound 决定 displayed 该展示哪一轮，无论 mode 是什么
    func testFixturesFocusedRoundDrivesDisplayed() throws {
        let vm = FixturesViewModel()
        vm.focusedRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2025-09-12T11:00:00Z", status: "FINISHED", matchday: 12),
        ]
        XCTAssertEqual(vm.displayed.map(\.id), [1])

        // 用户从「赛季总览」点击「第 N 轮」 → focusedRound 被改写
        vm.focusedRound = 12
        XCTAssertEqual(vm.displayed.map(\.id), [2])
    }

    /// 按日期分组的赛程页布局：每节包含该日所有比赛，按开球时间升序
    func testFixturesGroupedSectionsByLocalDate() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let vm = FixturesViewModel()
        vm.focusedRound = 1
        vm.matches = [
            // 北京 8月29 日三场
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-29T14:00:00Z", status: "FINISHED", matchday: 1),
            // 北京 9月1 日一场
            makeMatch(id: 3, kickoff: "2025-09-01T03:00:00Z", status: "FINISHED", matchday: 1),
        ]
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].matches.map(\.id), [1, 2], "同日内按开球升序")
        XCTAssertEqual(sections[1].matches.map(\.id), [3])
    }

    /// 赛季总览快照：每轮一张，至多 3 场预览，状态由 currentRound 决定
    func testFixturesRoundSnapshotsBySeasonProgress() throws {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 4, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 5, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let progress = SeasonProgress(
            currentRound: 2, totalRounds: 3,
            playedRounds: 1, remainingRounds: 2,
            fraction: 1.0 / 3.0, seasonYear: 2025
        )
        let snaps = vm.roundSnapshots(seasonProgress: progress)
        XCTAssertEqual(snaps.count, 3)
        XCTAssertEqual(snaps[0].progress, .past)
        XCTAssertEqual(snaps[1].progress, .current)
        XCTAssertEqual(snaps[2].progress, .future)
        XCTAssertEqual(snaps[0].previews.count, 2, "第 1 轮 2 场")
        XCTAssertEqual(snaps[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(snaps[2].previews.map(\.id), [5])
    }

    /// 赛季总览快照：超过 3 场的轮次只预览前 3 场
    func testFixturesRoundSnapshotsPreviewLimitIsThree() throws {
        let vm = FixturesViewModel()
        vm.matches = (1...8).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T1\(i):00:00Z", status: "FINISHED", matchday: 1)
        }
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 1, totalRounds: 38, playedRounds: 0, remainingRounds: 38,
            fraction: 0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps[0].previews.count, 3, "每张总览卡片上限 3 场")
    }

    /// 赛季总览：未来轮次数据未发 → 显示 unknown 状态
    func testFixturesRoundSnapshotsFutureWithoutDataIsUnknown() throws {
        let vm = FixturesViewModel()
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 5, totalRounds: 38, playedRounds: 4, remainingRounds: 34,
            fraction: 4.0 / 38.0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps.count, 38)
        // 第 5 轮 = current；第 6-38 = future 数据未发 → unknown
        XCTAssertEqual(snaps[4].progress, .current)
        XCTAssertEqual(snaps[5].progress, .unknown)
        XCTAssertTrue(snaps[5].previews.isEmpty, "未知轮次无预览")
    }

    /// 索引随 matches 赋值自动重建：availableRounds 同步、roundStart 取该轮最早开球
    ///
    /// 这条是性能回归的护栏 —— 38 个轮次 chip 每个都要 roundStart，
    /// 一旦有人改回「每次全表扫描 matches」，本测试仍会过，但界面会卡死。
    /// 所以 roundStart 必须只查预计算字典（O(1)）。
    func testFixturesIndexesRebuiltOnMatchesAssignment() throws {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1), // 最早
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(vm.availableRounds, [1, 2], "赋值即同步轮次列表")

        let earliest = try XCTUnwrap(parseKickoffDate("2025-08-21T11:00:00Z"))
        XCTAssertEqual(vm.roundStart(1), earliest, "roundStart 取该轮最早开球")
        XCTAssertNil(vm.roundStart(9), "无数据轮次返回 nil")

        // 分组直接读预计算桶，同样按开球升序
        vm.focusedRound = 1
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].matches.map(\.id), [2, 1])
    }

    /// `displayed` 必须走预计算桶，不能回到 380 场全表 filter
    func testFixturesDisplayedReadsPrebuiltBucket() {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        vm.focusedRound = 1
        XCTAssertEqual(vm.displayed.map(\.id), [2, 1], "桶内已按开球升序")
        vm.focusedRound = 2
        XCTAssertEqual(vm.displayed.map(\.id), [3])
        vm.focusedRound = 99
        XCTAssertTrue(vm.displayed.isEmpty, "无数据轮次返回空，不崩溃")
    }

    // MARK: - 布局陷阱回归护栏

    /// 赛程页踩过的两个坑都会让 SwiftUI 布局阶段打满主线程（表现为「一直转圈 + 界面卡死」）：
    ///   1. LazyVStack 内嵌 LazyVGrid —— lazy 容器提议的宽度不确定，网格算不出列数
    ///   2. GridItem(.adaptive(maximum: .infinity)) —— 列宽无上界，列数计算发散
    /// 这里直接扫源码兜底，防止以后改版又把陷阱写回来。
    func testFixturesViewHasNoLayoutDeadlockTraps() throws {
        let src = try sourceFile("FixturesView.swift")
        // 只扫代码：先剥掉 // 注释，否则解释「为什么不能用 LazyVStack」的注释会误报
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertFalse(codeOnly.contains("LazyVStack"),
                       "赛程页禁止 LazyVStack：嵌套 lazy 容器会让 LazyVGrid 尺寸协商死循环")
        XCTAssertFalse(codeOnly.contains("maximum: .infinity"),
                       "GridItem 的 maximum 必须是具体数值，不能是 .infinity")
    }

    /// 轮次 chip bar 的两个护栏必须同时成立：
    ///   1. 用 LazyHStack —— 普通 HStack 会为每一个轮次都建视图，
    ///      轮次数涨到几百上千时布局阶段会一次性算上千个 chip 的尺寸，主线程打满。
    ///   2. 保留 .frame(height: 32) —— 这是修「嵌在纵向 ScrollView 里的横向
    ///      ScrollView 无限协商尺寸导致卡死」的护栏，删掉会回归；
    ///      同时它也是 LazyHStack 能算出尺寸的前提。
    /// 同样先剥掉 // 注释再匹配，否则解释性注释会误报。
    func testRoundChipBarUsesLazyHStack() throws {
        let src = try sourceFile("FixturesView.swift")
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertTrue(codeOnly.contains("LazyHStack"),
                      "轮次 chip bar 必须用 LazyHStack，否则轮次一多就会全量渲染卡住主线程")
        XCTAssertTrue(codeOnly.contains(".frame(height: 32)"),
                      "横向 chip bar 的固定高度约束不能删：删了会回归布局死循环")
    }

    /// `roundSnapshots` 在 SwiftUI body 求值路径上被调用，必须缓存：
    /// 输入没变时直接返回上次结果（不重算），输入变了必须重新算。
    func testRoundSnapshotsAreCached() {
        let vm = FixturesViewModel()
        vm.matches = (1...6).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T1\(i):00:00Z", status: "FINISHED", matchday: i % 3 + 1)
        }
        let progress = SeasonProgress(
            currentRound: 2, totalRounds: 3,
            playedRounds: 1, remainingRounds: 2,
            fraction: 1.0 / 3.0, seasonYear: 2025
        )

        // 第一次调用：缓存为空 → 必然重算
        let first = vm.roundSnapshots(seasonProgress: progress)
        let computesAfterFirst = vm.roundSnapshotsComputeCount
        XCTAssertEqual(computesAfterFirst, 1, "首次调用应真正计算一次")

        // 第二次调用：输入完全没变 → 命中缓存，不再重算
        let second = vm.roundSnapshots(seasonProgress: progress)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst,
                       "输入未变时应命中缓存，不应重算")
        XCTAssertEqual(fingerprint(second), fingerprint(first), "缓存命中的结果与首次一致")

        // 换个 seasonProgress（关键输入变了）→ 必须重算且结果随之更新
        let moved = SeasonProgress(
            currentRound: 3, totalRounds: 3,
            playedRounds: 2, remainingRounds: 1,
            fraction: 2.0 / 3.0, seasonYear: 2025
        )
        let third = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 1,
                       "seasonProgress 变化后必须重算")
        XCTAssertEqual(third[1].progress, .past, "当前轮推进后，第 2 轮由 current 变 past")
        XCTAssertEqual(third[2].progress, .current)

        // 再改 matches（走 didSet 重建索引）→ 缓存必须失效，结果跟着数据更新
        vm.matches = [makeMatch(id: 99, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3)]
        let afterRematch = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 2,
                       "matches 变化后必须重算")
        XCTAssertEqual(afterRematch[2].previews.map(\.id), [99], "快照内容应反映新的比赛数据")
        XCTAssertTrue(afterRematch[0].previews.isEmpty, "旧的第 1 轮数据已不在")
    }

    // MARK: - 轮次窗口（chip bar 固定窗口分页）

    /// 造 `count` 个轮次（每轮 1 场），只为撑出 availableRounds，内容不重要
    func makeRounds(_ count: Int) -> [Match] {
        (1...count).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: i)
        }
    }

    // MARK: - 首次聚焦轮次（load() 仅在首次拿数据时聚焦；刷新不得重置浏览位置）

    /// 把 makeRounds 的结果按轮次分桶（matchesByRound 的形状）
    func roundsByRound(_ count: Int) -> (byRound: [Int: [Match]], rounds: [Int]) {
        var byRound: [Int: [Match]] = [:]
        for m in makeRounds(count) { byRound[m.matchday ?? 0, default: []].append(m) }
        return (byRound, Array(1...count))
    }

    /// 当前轮有数据 → 聚焦当前轮
    func testInitialFocusRoundPrefersCurrentRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 7,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            7, "当前轮有数据 → 聚焦当前轮")
    }

    /// 当前轮暂无赛程（如 FPL 已推进到下一轮但赛程未发）→ 回退第一个有数据的轮次
    func testInitialFocusRoundFallsBackToFirstAvailableRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 11,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            1, "当前轮无数据 → 聚焦首个有数据的轮次")
    }

    /// 完全没有赛程 → 维持传入的 currentRound（load() 侧此时根本不会调用本函数）
    func testInitialFocusRoundWithNoDataKeepsCurrentRound() {
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 5,
                                                availableRounds: [],
                                                matchesByRound: [:]),
            5, "无任何轮次数据 → 维持当前轮")
    }

    /// 聚焦中间轮 → 窗口以它为**中心**（前 2 后 2）
    func testRoundWindowCentersOnFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.roundWindowStart = 0            // 手动把窗口推回最左，真正考验对齐逻辑
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "MD20 居中 → MD18–MD22")
        XCTAssertEqual(vm.roundWindowStart, 17)
    }

    /// 聚焦靠左的轮次（第 1 / 第 2 轮）→ 窗口**左对齐**，起点不会变负
    func testRoundWindowAlignsLeftNearStart() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // 第 1 轮：idx 0 - 2 = -2 → 夹到 0
        vm.roundWindowStart = 20
        vm.focusedRound = 1
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0, "起点不能为负")

        // 第 2 轮：idx 1 - 2 = -1 → 同样夹到 0
        vm.roundWindowStart = 20
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// 聚焦靠右的轮次（倒数第 2 / 最后 1 轮）→ 窗口**右对齐**，不越过上界
    func testRoundWindowAlignsRightNearEnd() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // 倒数第 2 轮（MD37）：idx 36 - 2 = 34 → 夹到上界 33
        vm.roundWindowStart = 0
        vm.focusedRound = 37
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33, "38 轮时上界是 33")

        // 最后一轮（MD38）：idx 37 - 2 = 35 → 同样夹到 33
        vm.roundWindowStart = 0
        vm.focusedRound = 38
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33)
    }

    /// 轮次总数不足一屏 → 全部显示，上界为 0（两个翻页箭头都该隐藏）
    func testRoundWindowShowsAllWhenFewerThanWindowSize() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(3)
        vm.roundWindowStart = 99            // 越界起点也要能被夹回来
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3], "只有 3 轮 → 全部显示")
        XCTAssertEqual(vm.roundWindowStart, 0)
        XCTAssertEqual(vm.roundWindowMaxStart, 0, "不足一屏 → 上界 0，箭头全隐藏")
    }

    /// 翻页边界：向右翻到底停在上界不再增长，向左翻到头停在 0 不会变负
    func testRoundWindowPagingStopsAtBounds() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1

        // 一路向右翻
        for _ in 0..<20 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 33, "38 轮的上界 = 38 - 5")
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.focusedRound, 1, "翻页只移动窗口，不改选中的轮次")

        // 继续右翻不会越界
        vm.pageRoundsForward()
        XCTAssertEqual(vm.roundWindowStart, 33)
        XCTAssertEqual(vm.roundWindowMaxStart, 33)

        // 一路向左翻
        for _ in 0..<20 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, 0, "起点不会变负")
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.focusedRound, 1, "翻页只移动窗口，选中轮次始终不变")

        // 继续左翻不会变负
        vm.pageRoundsBackward()
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// 右翻后焦点与翻页前完全相同：窗口动了，focusedRound 没动，
    /// 于是新窗口里没有任何 chip 处于高亮态（这正是用户要的"焦点原地不动"）。
    func testPagingPreservesFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "初始居中窗口 MD18–MD22")

        vm.pageRoundsForward()
        XCTAssertEqual(vm.focusedRound, 20, "右翻后焦点仍是 20")
        XCTAssertNotEqual(vm.roundWindowStart, 17, "窗口起点确实移动了")
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27])
        XCTAssertFalse(vm.visibleRounds.contains(20), "新窗口不含 20 → 无高亮 chip")
    }

    /// 连续右翻 N 次再左翻同样 N 次：
    /// 窗口起点回到原值、focusedRound 始终未变、且焦点重新落回 visibleRounds（MD20 重新高亮）。
    func testPagingRoundTripRestoresWindowAndFocus() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        let originalStart = vm.roundWindowStart
        XCTAssertEqual(originalStart, 17)

        // 右翻 3 次（17→22→27→32，未触碰上界 33，保证来回对称）
        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.focusedRound, 20, "右翻过程中焦点恒定")

        // 左翻同样 3 次：窗口回到原处、焦点始终未变、MD20 重新高亮
        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "来回翻页窗口回到原处")
        XCTAssertEqual(vm.focusedRound, 20, "焦点始终没变")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "回到原窗口后 MD20 重新高亮")
        XCTAssertTrue(vm.visibleRounds.contains(20))
    }

    /// 翻页后 visibleRounds 不含 focusedRound：渲染不崩、高亮判定 `r == focusedRound`
    /// 对窗口内每个 chip 都为 false（无高亮，符合预期，不是 bug）。
    func testPagingAwayFromFocusRendersNoSelection() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.pageRoundsForward()                 // 窗口 MD23–MD27，焦点仍在 20
        XCTAssertFalse(vm.visibleRounds.contains(20))

        // 模拟 chip bar 的高亮判定：窗口里没有任何 chip 应被高亮
        let anyHighlighted = vm.visibleRounds.contains { $0 == vm.focusedRound }
        XCTAssertFalse(anyHighlighted, "窗口里无 chip 处于高亮态，符合预期")

        // 不变量：翻到窗口外仍成立
        XCTAssertLessThanOrEqual(vm.visibleRounds.count, FixturesViewModel.roundWindowSize)
        XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart)
    }

    /// 从赛季总览点 MD30 跳过来：窗口原本在最左，必须自动重新对齐并包含 MD30
    func testRoundWindowAlignsToFarAwayFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5], "起点在最左")

        // 模拟「总览页点 MD30 卡片」—— 只改 focusedRound，窗口由 didSet 自动对齐
        vm.focusedRound = 30
        XCTAssertTrue(vm.visibleRounds.contains(30), "对齐后窗口必须包含 focusedRound")
        XCTAssertEqual(vm.visibleRounds, [28, 29, 30, 31, 32])

        // 已经在窗口内时不应该乱动（否则翻页后焦点落回首轮会把窗口重新居中、来回弹）
        let before = vm.roundWindowStart
        vm.focusedRound = 29
        XCTAssertEqual(vm.roundWindowStart, before, "焦点仍在窗内 → 窗口保持不动")
    }

    /// 不变量：任何数据规模 / 任何操作序列下，窗口都不越界、不超长
    func testRoundWindowInvariantsHoldAcrossDataSizes() {
        let size = FixturesViewModel.roundWindowSize
        // 覆盖：空数据 / 1 轮 / 不足一屏 / 刚好一屏 / 多一屏 / 38 轮 / 200 轮
        for count in [0, 1, 3, 5, 6, 12, 38, 200] {
            let vm = FixturesViewModel()
            vm.matches = count == 0 ? [] : makeRounds(count)
            // 覆盖：越界的小值 / 中间值 / 越界的大值
            for focused in [1, 2, 3, 5, count / 2 + 1, count - 1, count, 999] {
                vm.roundWindowStart = 0
                vm.focusedRound = focused
                vm.alignWindowToFocusedRound()

                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size,
                                         "轮次 \(count) 场 / 聚焦 \(focused)：窗口不得超过 \(size) 个")
                XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                            "轮次 \(count) 场 / 聚焦 \(focused)：起点不能为负")
                XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                         "轮次 \(count) 场 / 聚焦 \(focused)：起点不能越过上界")

                // 翻到最右，再验一遍不变量
                for _ in 0..<(count + 1) { vm.pageRoundsForward() }
                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size)
                XCTAssertEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                               "一直右翻后应停在上界")
                XCTAssertEqual(vm.visibleRounds,
                               Array(vm.availableRounds.suffix(min(size, count))),
                               "最右窗口应是最后 \(min(size, count)) 个轮次")
            }
        }
    }

    /// 把快照压成可比较的指纹：轮次 + 状态 + 预览场次 id
    /// （元组数组不能直接 XCTAssertEqual，所以压成字符串）
    func fingerprint(_ snaps: [RoundSnapshot]) -> String {
        snaps.map { snap -> String in
            let progress: String
            switch snap.progress {
            case .past:    progress = "past"
            case .current: progress = "current"
            case .future:  progress = "future"
            case .unknown: progress = "unknown"
            }
            let ids = snap.previews.map { String($0.id) }.joined(separator: ",")
            return "\(snap.round):\(progress):[\(ids)]"
        }.joined(separator: "|")
    }

    // MARK: - QA 独立验证：快照缓存正确性

    // 为什么不用工程师自己加的 `roundSnapshotsComputeCount`：
    // 那个计数器只能证明「有没有重算」—— 计数器没涨说明命中了缓存，
    // 但**命中时返回的内容对不对，它一个字也证明不了**。
    // 真正的风险是「该失效却没失效」返回陈旧快照，那才是用户能看到的数据错误。
    // 所以下面一律用一个独立 oracle 对拍：直接从 `vm.matches` 原始数据重算期望结果，
    // 每次调 `roundSnapshots` 都和它对齐。任何一次失效漏判都会在这里暴露。

    /// 独立 oracle：不读 VM 的任何缓存/索引，直接从 `vm.matches` 原始数据重算期望快照。
    /// 输出格式与 `fingerprint(_:)` 完全一致，便于直接比对。
    func oracleSnapshots(for vm: FixturesViewModel, progress: SeasonProgress?) -> String {
        let cur = progress?.currentRound ?? vm.currentRound
        let maxRound = progress?.totalRounds ?? (vm.availableRounds.sorted().last ?? 38)
        // 生产实现在 maxRound < 1 时会因 `1...maxRound` 直接 trap。
        // oracle 不重演这个 crash，返回哨兵值，让断言给出可读的失败信息。
        guard maxRound >= 1 else { return "<INVALID maxRound=\(maxRound)>" }

        var byRound: [Int: [Match]] = [:]
        for m in vm.matches {
            guard let r = m.matchday else { continue }
            byRound[r, default: []].append(m)
        }
        for (r, list) in byRound {
            byRound[r] = list.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }
        }

        let known = Set(vm.availableRounds)
        var out: [String] = []
        for r in 1...maxRound {
            let base: RoundProgress = r < cur ? .past : (r == cur ? .current : .future)
            let effective = known.contains(r) ? base : (base == .future ? .unknown : base)
            let ids = (byRound[r] ?? []).prefix(3).map { String($0.id) }.joined(separator: ",")
            out.append("\(r):\(progressName(effective)):[\(ids)]")
        }
        return out.joined(separator: "|")
    }

    func progressName(_ p: RoundProgress) -> String {
        switch p {
        case .past:    return "past"
        case .current: return "current"
        case .future:  return "future"
        case .unknown: return "unknown"
        }
    }

    /// 五场样例：第 1 轮 2 场、第 2 轮 2 场、第 3 轮 1 场
    func sampleMatches() -> [Match] {
        [
            makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 4, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 5, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3),
        ]
    }

    /// 内容相等但分别构造的两个 `SeasonProgress`：缓存 key 靠 Equatable 比对，
    /// 必须认「值相等」而不是认「同一个对象」（结构体本来也没有引用身份，
    /// 这里覆盖的是「key 里存了 Optional<SeasonProgress> 却没正确解包比较」这类写法）。
    func testRoundSnapshotsCacheTreatsEqualSeasonProgressValuesAsSameInput() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let a = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        let b = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        XCTAssertEqual(a, b, "前置条件：两个 seasonProgress 必须值相等")

        let r1 = vm.roundSnapshots(seasonProgress: a)
        let r2 = vm.roundSnapshots(seasonProgress: b)
        XCTAssertEqual(fingerprint(r1), oracleSnapshots(for: vm, progress: a))
        XCTAssertEqual(fingerprint(r2), fingerprint(r1),
                       "内容相等的不同 seasonProgress 必须得出同一份快照")
        XCTAssertEqual(fingerprint(r2), oracleSnapshots(for: vm, progress: b))

        // 只有与快照无关的字段（playedRounds / fraction）变化 → key 不等 → 重算，
        // 但内容不该变（currentRound 与 totalRounds 都没动）
        let c = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 2,
                               remainingRounds: 1, fraction: 2.0 / 3.0, seasonYear: 2025)
        XCTAssertNotEqual(a, c, "前置条件：两个 seasonProgress 必须值不等")
        let r3 = vm.roundSnapshots(seasonProgress: c)
        XCTAssertEqual(fingerprint(r3), oracleSnapshots(for: vm, progress: c))
        XCTAssertEqual(fingerprint(r3), fingerprint(r1),
                       "currentRound / totalRounds 没变，快照内容就不该变")
    }

    /// `seasonProgress` 在 nil ↔ 非 nil 之间来回切，是 key 比对最容易写错的分支
    /// （Optional 参与 == 时，nil 与 nil 必须判等、nil 与 .some 必须判不等）。
    func testRoundSnapshotsNilProgressToggleNeverReturnsStaleSnapshot() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()                 // availableRounds = [1, 2, 3]

        let nilFirst = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(nilFirst.count, 3, "nil 时 totalRounds 兜底为 availableRounds.last")
        XCTAssertEqual(fingerprint(nilFirst), oracleSnapshots(for: vm, progress: nil))
        let nilSecond = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(nilSecond), fingerprint(nilFirst), "连续两次 nil 结果必须一致")

        let p = SeasonProgress(currentRound: 3, totalRounds: 5, playedRounds: 2,
                               remainingRounds: 3, fraction: 0.4, seasonYear: 2025)
        let nonNil = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(nonNil.count, 5)
        XCTAssertEqual(fingerprint(nonNil), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(nonNil), fingerprint(nilFirst),
                          "前置条件：nil 与非 nil 的结果必须不同，否则这条测不出陈旧缓存")

        // 切回 nil —— 不能残留上一次非 nil 的缓存
        let backToNil = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(backToNil), fingerprint(nilFirst),
                       "切回 nil 必须回到 nil 的结果，不能残留上一次非 nil 的缓存")
        XCTAssertEqual(fingerprint(backToNil), oracleSnapshots(for: vm, progress: nil))

        // 再切回非 nil —— 反过来也不能残留 nil 那一份
        let again = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(again), fingerprint(nonNil),
                       "切回非 nil 也不能残留 nil 的缓存")
        XCTAssertEqual(fingerprint(again), oracleSnapshots(for: vm, progress: p))
    }

    /// 只改 `currentRound`（matches 与 seasonProgress 都不动），缓存必须失效。
    /// 注意必须传 `seasonProgress: nil`：非 nil 时 cur 取 seasonProgress.currentRound，
    /// vm.currentRound 根本不参与输出，那样测不出这条失效路径。
    func testRoundSnapshotsInvalidatesWhenOnlyCurrentRoundChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        vm.currentRound = 1

        let before = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(before[0].progress, .current, "前置条件：当前轮是第 1 轮")
        XCTAssertEqual(fingerprint(before), oracleSnapshots(for: vm, progress: nil))

        vm.currentRound = 3                          // 只动这一个输入
        let after = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(after), oracleSnapshots(for: vm, progress: nil))
        XCTAssertNotEqual(fingerprint(after), fingerprint(before))
        XCTAssertEqual(after[0].progress, .past, "currentRound 变了缓存必须失效：第 1 轮应变 past")
        XCTAssertEqual(after[1].progress, .past)
        XCTAssertEqual(after[2].progress, .current)

        // 改回原值也要回到原结果，不能是「只失效一次」的一次性开关
        vm.currentRound = 1
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)), fingerprint(before),
                       "currentRound 还原后应回到第一次的结果")
    }

    /// 轮次集合的退化形态：1 轮 / 0 轮（matches 为空）/ 乱序不连续 [7, 3, 19] / 极多（1000 轮）
    func testRoundSnapshotsHandlesDegenerateRoundSets() {
        // 1) 只有 1 轮
        let one = FixturesViewModel()
        one.matches = [makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1)]
        let oneSnaps = one.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(oneSnaps.count, 1)
        XCTAssertEqual(fingerprint(oneSnaps), oracleSnapshots(for: one, progress: nil))
        XCTAssertEqual(oneSnaps[0].progress, .current)
        XCTAssertEqual(oneSnaps[0].previews.map(\.id), [1])

        // 2) matches 为空 → availableRounds 空 → 走 38 兜底，不崩、不越界
        let empty = FixturesViewModel()
        let emptySnaps = empty.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(emptySnaps.count, 38)
        XCTAssertEqual(fingerprint(emptySnaps), oracleSnapshots(for: empty, progress: nil))
        XCTAssertTrue(emptySnaps.allSatisfy { $0.previews.isEmpty }, "无数据时全部空占位")

        // 3) 轮次编号乱序且不连续
        let sparse = FixturesViewModel()
        sparse.matches = [
            makeMatch(id: 7, kickoff: "2025-10-01T11:00:00Z", status: "SCHEDULED", matchday: 7),
            makeMatch(id: 3, kickoff: "2025-09-01T11:00:00Z", status: "FINISHED", matchday: 3),
            makeMatch(id: 19, kickoff: "2025-12-01T11:00:00Z", status: "SCHEDULED", matchday: 19),
        ]
        XCTAssertEqual(sparse.availableRounds, [3, 7, 19], "轮次号应升序")
        let sparseSnaps = sparse.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(sparseSnaps.count, 19, "总轮数取 availableRounds.last")
        XCTAssertEqual(fingerprint(sparseSnaps), oracleSnapshots(for: sparse, progress: nil))
        XCTAssertEqual(sparseSnaps.map(\.round), Array(1...19),
                       "轮次号必须连续铺满 1...max，不能跟着数据里的洞跳号")
        XCTAssertEqual(sparseSnaps[2].previews.map(\.id), [3])
        XCTAssertEqual(sparseSnaps[6].previews.map(\.id), [7])
        XCTAssertEqual(sparseSnaps[18].previews.map(\.id), [19])
        XCTAssertTrue(sparseSnaps[0].previews.isEmpty, "第 1 轮无数据 → 空占位，不能越界取到别的轮")

        // 4) 轮次极多：这是「一次性渲染全部轮次」质疑的压测口径，1000 轮不许崩
        let many = FixturesViewModel()
        many.matches = (1...1000).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T11:00:00Z", status: "SCHEDULED", matchday: i)
        }
        let manySnaps = many.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(manySnaps.count, 1000)
        XCTAssertEqual(manySnaps.first?.round, 1)
        XCTAssertEqual(manySnaps.last?.round, 1000)
        XCTAssertEqual(fingerprint(manySnaps), oracleSnapshots(for: many, progress: nil))
    }

    /// `matches` 换成不同内容、`seasonProgress` 保持不变 —— 只能靠 `indexGeneration` 失效。
    func testRoundSnapshotsInvalidatesWhenMatchesContentChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let p = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)

        let first = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(first[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(fingerprint(first), oracleSnapshots(for: vm, progress: p))

        // 换一批完全不同的比赛，seasonProgress 一个字没变
        vm.matches = [
            makeMatch(id: 71, kickoff: "2025-08-21T09:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 72, kickoff: "2025-09-04T09:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let second = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(second), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(second), fingerprint(first))
        XCTAssertEqual(second[0].previews.map(\.id), [71], "快照必须跟着新数据走，不能返回旧缓存")
        XCTAssertEqual(second[2].previews.map(\.id), [72])

        // 内容相同但重新赋一次值（indexGeneration 自增）→ 结果仍须与 oracle 一致
        vm.matches = vm.matches
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                       oracleSnapshots(for: vm, progress: p))
    }

    /// 交叉遍历输入组合，每一步都对拍 oracle，兜住「该失效却没失效」。
    ///
    /// ⚠️ 这一条第一版是**假通过**：当时在循环里反复给 `vm.seasonProgress` / `vm.matches` 赋值，
    /// 而这两个属性的 `didSet` 会无条件清空缓存 —— 于是无论 `SnapshotCacheKey` 里
    /// 到底比了什么字段，每次都会重算，测试永远绿。
    /// key 真正成为**唯一防线**的场景只有一个：**函数入参与已存属性不一致**
    /// （此时不触发任何 didSet，只有 key 比对能救命）。所以下面第一轮全程不再写属性。
    func testRoundSnapshotsNeverGoesStaleAcrossInputMutationSweep() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let progresses: [SeasonProgress?] = [
            nil,
            SeasonProgress(currentRound: 1, totalRounds: 3, playedRounds: 0,
                           remainingRounds: 3, fraction: 0, seasonYear: 2025),
            SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                           remainingRounds: 2, fraction: 0.33, seasonYear: 2025),
            SeasonProgress(currentRound: 3, totalRounds: 8, playedRounds: 2,
                           remainingRounds: 6, fraction: 0.25, seasonYear: 2025),
        ]

        // —— 第一轮：key 是唯一防线。此后不再写 vm.seasonProgress / vm.matches ——
        vm.seasonProgress = progresses[1]
        for pass in 0..<2 {
            for (i, p) in progresses.enumerated() {
                for (j, q) in progresses.enumerated() {
                    _ = vm.roundSnapshots(seasonProgress: p)
                    XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: q)),
                                   oracleSnapshots(for: vm, progress: q),
                                   "pass\(pass)：入参由 #\(i) 换成 #\(j) 后返回了陈旧快照 —— " +
                                   "SnapshotCacheKey 漏了 seasonProgress 字段？")
                }
            }
            vm.currentRound = 4
            XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)),
                           oracleSnapshots(for: vm, progress: nil),
                           "pass\(pass)：只改 currentRound 后返回了陈旧快照 —— " +
                           "didSet 与 key 两道保险同时失效")
            vm.currentRound = 2
        }

        // —— 第二轮：改 matches 内容（indexGeneration 路径）——
        for k in 0..<3 {
            vm.matches = sampleMatches() + [
                makeMatch(id: 900 + k, kickoff: "2025-09-11T11:00:00Z",
                          status: "FINISHED", matchday: 2),
            ]
            for (i, p) in progresses.enumerated() {
                XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                               oracleSnapshots(for: vm, progress: p),
                               "第 \(k) 次改 matches / 入参 #\(i) 后返回了陈旧快照")
            }
        }
    }

    // MARK: - QA 独立验证：lazy 化与布局红线

    /// 静态扫源码确认 lazy 化的结构（比「源码里含不含 LazyHStack」更严格）：
    /// LazyHStack 必须是横向 ScrollView 的**第一个直接子视图** ——
    /// 中间夹任何容器都可能是「lazy 套 lazy」，那是布局死循环红线。
    func testRoundChipBarLazyHStackIsDirectChildOfHorizontalScrollView() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "ScrollView(.horizontal", in: code), 1,
                       "期望只有轮次 chip bar 一处横向 ScrollView；结构变了本护栏需同步更新")

        guard let sv = code.range(of: "ScrollView(.horizontal") else {
            return XCTFail("找不到横向 ScrollView")
        }
        guard let brace = code[sv.upperBound...].firstIndex(of: "{") else {
            return XCTFail("横向 ScrollView 后面没有内容块")
        }
        var i = code.index(after: brace)
        while i < code.endIndex, code[i].isWhitespace { i = code.index(after: i) }
        let firstToken = code[i...]
        XCTAssertTrue(firstToken.hasPrefix("LazyHStack"),
                      "横向 ScrollView 的第一个直接子视图必须是 LazyHStack，不能是别的容器（" +
                      "lazy 套 lazy 会布局死循环，退回 HStack 则轮次一多就全量建视图）。" +
                      "实际开头：\(firstToken.prefix(40))")

        guard let fn = code.range(of: "func roundChipBar") else {
            return XCTFail("找不到 roundChipBar")
        }
        // 上面的 hasPrefix("LazyHStack") 已经排除了退回普通 HStack 的情况
        // （不能再用 contains("HStack(spacing: 8)") 反查 —— LazyHStack 本身就含这段子串）
        XCTAssertTrue(code[fn.lowerBound...].contains(".frame(height: 32)"),
                      "roundChipBar 的横向 ScrollView 必须保留 .frame(height: 32)")
        XCTAssertTrue(code[fn.lowerBound...].contains("roundPageButton"),
                      "两个翻页按钮应复用 roundPageButton，保证样式与无障碍文案口径一致")
        // 固定窗口：chip bar 只渲染窗口内的轮次，不能回到「列出全部 availableRounds」
        XCTAssertTrue(code[fn.lowerBound...].contains("vm.visibleRounds"),
                      "chip bar 必须渲染 vm.visibleRounds（固定窗口），" +
                      "直接 ForEach(vm.availableRounds) 会让渲染量随总轮次数线性增长")
    }

    /// 全项目硬红线：lazy 容器互相嵌套 / GridItem 无上界 / URLSession.shared / .help 硬编码
    func testSourcesHaveNoLayoutOrNetworkRedLines() throws {
        let violations = try allSourceFiles().flatMap { f -> [String] in
            let code = codeOnly(f.text)
            var v: [String] = []
            if code.contains("LazyVStack") {
                v.append("\(f.name)：出现 LazyVStack（lazy 容器嵌套会让布局尺寸协商死循环）")
            }
            if code.contains("maximum: .infinity") {
                v.append("\(f.name)：GridItem 的 maximum 不能是 .infinity")
            }
            if code.contains("URLSession.shared") {
                v.append("\(f.name)：禁止使用 URLSession.shared（资源超时 7 天会让 await 永不返回）")
            }
            if code.contains(".help(\"") {
                v.append("\(f.name)：.help( 里出现硬编码字符串字面量，必须走 UIString")
            }
            return v
        }
        XCTAssertEqual(violations, [], "硬约束红线被踩：\n" + violations.joined(separator: "\n"))
    }

    /// 逐字符扫括号深度，检出任何「lazy 容器嵌在 lazy 容器里」。
    /// 比单纯 `contains("LazyVStack")` 强：就算以后换了别的 lazy 容器名也拦得住。
    func testNoLazyContainerNestedInsideAnotherLazyContainer() throws {
        for f in try allSourceFiles() {
            let v = lazyNestingViolations(codeOnly(f.text))
            XCTAssertEqual(v, [], "\(f.name) 出现 lazy 容器嵌套：\(v.joined(separator: "; "))")
        }
    }

    /// 嵌在纵向 ScrollView 里的横向 ScrollView 必须有确定高度，否则无限协商尺寸卡死主线程
    func testHorizontalScrollViewsAreHeightConstrained() throws {
        for f in try allSourceFiles() {
            let code = codeOnly(f.text)
            var search = code.startIndex
            while let r = code.range(of: "ScrollView(.horizontal", range: search..<code.endIndex) {
                // 窗口要够长：横向 ScrollView 的内容块（LazyHStack + 若干 chip）本身就有上千字符
                let windowEnd = code.index(r.upperBound, offsetBy: 3000, limitedBy: code.endIndex)
                    ?? code.endIndex
                XCTAssertTrue(code[r.upperBound..<windowEnd].contains(".frame(height:"),
                              "\(f.name) 的横向 ScrollView 缺少 .frame(height:)：" +
                              "嵌在纵向 ScrollView 里会和父视图无限协商尺寸")
                search = r.upperBound
            }
        }
    }
}
