import SwiftUI

// MARK: - 今日：时间与筛选逻辑（纯逻辑，可单测）

/// 带解析后开球时间的比赛，便于按时间筛选 / 排序
struct TimedMatch {
    let match: Match
    let kickoff: Date
}

/// 解析出开球时间并按升序排列（无法解析时间的比赛丢弃）
func timedMatches(_ matches: [Match]) -> [TimedMatch] {
    matches
        .compactMap { m -> TimedMatch? in
            guard let d = parseKickoffDate(m.utcDate) else { return nil }
            return TimedMatch(match: m, kickoff: d)
        }
        .sorted { $0.kickoff < $1.kickoff }
}

enum TodayFilter {
    /// 进行中（含中场）—— 双信号：
    /// 1. 状态为 `IN_PLAY` / `HALFTIME`；**或**
    /// 2. 落在「开球 → 开球 + matchWindow」时间窗内且未被判为已结束。
    ///
    /// 用时间窗兜底数据源状态滞后（FPL 开球后约 8 分钟才翻 `status` / 出版比分），
    /// 与 `AutoRefreshScheduler.schedule` 的「是否进行中」口径一致 —— 调度器已认为在直播、
    /// 显示侧却还显示「未开赛」就是这里过去的缺口。
    static func isLive(_ m: Match, now: Date = Date()) -> Bool {
        if m.status == "IN_PLAY" || m.status == "HALFTIME" { return true }
        // 延期 / 取消的比赛没在踢，但原开球时间同样会落进下方时间窗，
        // 必须显式排除 —— 否则这场比赛在开球时间后 3h 内会被当成「进行中」
        // （赛果卡显示 ⚽ 0-0，MatchCard 的「延期/取消」分支也永远走不到）。
        if m.status == "POSTPONED" || m.status == "CANCELED" || m.status == "CANCELLED" { return false }
        guard let kickoff = parseKickoffDate(m.utcDate) else { return false }
        return kickoff <= now
            && now < kickoff.addingTimeInterval(AutoRefreshScheduler.matchWindow)
            && !isFinished(m)
    }
    /// 已结束
    static func isFinished(_ m: Match) -> Bool { m.status == "FINISHED" }
    /// 未开赛（含延期 / 取消等非进行中、非已结束状态）
    static func isUpcoming(_ m: Match, now: Date = Date()) -> Bool { !isLive(m, now: now) && !isFinished(m) }

    /// date 与 reference 在 tz 时区下是否为同一天
    static func isSameDay(_ date: Date, as reference: Date, in tz: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.isDate(date, inSameDayAs: reference)
    }

    /// 当天（tz 时区）的全部比赛，按开球时间升序
    ///
    /// 判定规则（缺一不可）：
    /// 1. **进行中的比赛一律算「今日」** —— 跨日进行的比赛（如北京时间 23:30 开球、打到次日凌晨）
    ///    开球日期在所选时区里是「昨天」，但它此刻正在踢，必须显示；
    /// 2. 其余比赛按「开球日期 == 今天（所选时区）」筛选。
    static func todayMatches(from matches: [Match], now: Date = Date(), tz: TimeZone) -> [Match] {
        timedMatches(matches)
            .filter { isLive($0.match) || isSameDay($0.kickoff, as: now, in: tz) }
            .map(\.match)
    }

    /// 下一场尚未开球的比赛（严格晚于 now 的第一场）
    static func nextMatch(from matches: [Match], now: Date = Date()) -> Match? {
        timedMatches(matches).first { $0.kickoff > now }?.match
    }
}

// MARK: - 自动刷新调度（纯逻辑，可单测）

/// 自动刷新的调度状态（纯数据，便于单测与等值比较）
struct RefreshSchedule: Equatable {
    /// 是否有比赛正在进行中（时间窗判定，见 `AutoRefreshScheduler.schedule`）
    var hasLiveMatch: Bool
    /// 下一个尚未开球的比赛开球时间；nil = 已知赛程里没有了
    var nextKickoff: Date?
}

/// 「比赛期间自动刷新」的定时器调度器 —— 纯函数，不联网、不读 `Date()`（`now` 显式传入）。
///
/// 设计目标：没比赛进行中时不再固定轮询，而是**睡到下一场开球前**（提前 `kickoffLeadTime` 醒），
/// 空闲时几乎零轮询；同时用 `maxIdleSleep` 兜底，避免赛程空档期「睡死」永远醒不过来。
enum AutoRefreshScheduler {
    /// 有比赛进行中时的刷新间隔
    static let liveInterval: TimeInterval = 60
    /// 开球前多久提前醒来（避免刚好错过开球）
    static let kickoffLeadTime: TimeInterval = 15 * 60
    /// 空闲最长休眠：没有可推算的开球时间时，最多睡这么久就自查一次
    static let maxIdleSleep: TimeInterval = 6 * 60 * 60
    /// 一场比赛从开球算起的最大跨度（用于「是否仍在进行中」的时间窗判定）
    static let matchWindow: TimeInterval = 3 * 60 * 60

    /// 从赛程 + `now` 算出调度状态。
    ///
    /// - `hasLiveMatch`：存在一场 `TodayFilter.isLive` 为真的比赛 —— 状态信号（IN_PLAY / HALFTIME）
    ///   或「`kickoff <= now < kickoff + matchWindow` 时间窗兜底」，延期 / 取消被显式排除。
    ///   用时间窗兜底而非只信 `status`：刚开球时数据源状态可能还没翻
    ///   （FPL 开球后约 8 分钟比分仍为 null，本项目有前科）。
    ///   判定直接复用 `TodayFilter.isLive`，保证显示侧与调度侧永远同一套口径。
    /// - `nextKickoff`：所有 `kickoff > now` 里最早的那个；都没有则 nil。
    /// - `utcDate` 解析不出来的比赛直接跳过，不崩。
    nonisolated static func schedule(matches: [Match], now: Date) -> RefreshSchedule {
        var hasLiveMatch = false
        var nextKickoff: Date?

        for m in matches {
            guard let kickoff = parseKickoffDate(m.utcDate) else { continue }

            // 进行中：口径与 `TodayFilter.isLive` 完全一致（状态优先 + 时间窗兜底）。
            // 直接复用 isLive 而非重复写窗口条件：延期 / 取消的比赛原开球时间也落窗内，
            // 若只排除 FINISHED，调度器会把它们当直播，空转 60s 轮询整整 3 小时。
            if TodayFilter.isLive(m, now: now) {
                hasLiveMatch = true
            }

            // 下一场：严格晚于 now 的最早开球时间
            if kickoff > now, kickoff < (nextKickoff ?? .distantFuture) {
                nextKickoff = kickoff
            }
        }
        return RefreshSchedule(hasLiveMatch: hasLiveMatch, nextKickoff: nextKickoff)
    }

    /// 返回定时器间隔（秒）；nil = 不设定时器。**这是间隔决策的唯一入口。**
    ///
    /// 决策表：
    /// - `autoRefresh == true` → 固定 `liveInterval`（全局已每 60s，本项无意义）；
    /// - `duringMatches == false` → nil（不设定时器）；
    /// - 有比赛进行中 → `liveInterval`；
    /// - 否则睡到下一场开球前 `kickoffLeadTime` 醒；已进入开球前窗口（或更近）→ `liveInterval`；
    ///   无下一场 / 太久远 → `maxIdleSleep` 兜底。
    nonisolated static func refreshInterval(autoRefresh: Bool,
                                            duringMatches: Bool,
                                            schedule: RefreshSchedule,
                                            now: Date) -> TimeInterval? {
        if autoRefresh { return liveInterval }
        guard duringMatches else { return nil }
        if schedule.hasLiveMatch { return liveInterval }

        guard let next = schedule.nextKickoff else { return maxIdleSleep }
        let untilWake = next.timeIntervalSince(now) - kickoffLeadTime
        if untilWake <= liveInterval { return liveInterval }
        return min(untilWake, maxIdleSleep)
    }
}

// MARK: - 推荐比赛（featured 卡片）选取

/// 「推荐比赛」大卡片的选取逻辑 —— 今日页的视觉焦点。
/// 按以下优先级取第一场命中（优先级 2 / 4 / 5 均为「先取最早开球时刻那一批，
/// 同刻多场再按名次和最小选强强对话」的两级排序）：
/// 1. 正在进行中的比赛；
/// 2. 3.5 小时内开球的比赛 —— 取最早开球时刻，同刻多场按名次选强强对话；
/// 3. 今日已结束的比赛（取时间最近的一场）；
/// 4. 今日下一场未开赛 —— 取最早开球时刻，同刻多场按名次选强强对话；
/// 5. 当前轮下一场未开赛（可跨日，如明天）—— 同优先级 2 / 4 的两级排序；
/// 6. 走到这里说明本轮已结束 —— 在本轮全部比赛里选「强强对话」（名次和最小）的赛果；
///    名次缺失时退回本轮最早开球那场。
enum TodayFeatured {
    /// 距开球多久之内算「即将开赛」
    static let upcomingWindow: TimeInterval = 3.5 * 60 * 60

    static func pick(from matches: [Match],
                     currentRound: Int,
                     now: Date = Date(),
                     tz: TimeZone,
                     positions: [Int: Int] = [:]) -> Match? {
        let timed = timedMatches(matches)

        // 1) 进行中（多场时取最早开球的，保证结果稳定）
        if let live = timed.first(where: { TodayFilter.isLive($0.match, now: now) }) { return live.match }

        // 2) 3.5 小时内开球 → 先取最早开球时刻那一批，同刻多场才按「名次和最小」选强强对话。
        //    ⚠️ 前提：`timed` 已按开球时间**升序**（见 `timedMatches`），且 `filter` 保持顺序，
        //    故 `chooseByRanking` 内部取 `candidates.first?.kickoff` 即「窗口内最早时刻」——
        //    与旧的 `first(where:)`（取第一个命中）语义一致。
        //    名次缺失时（positions 为空）rankKey 全部相等 → `min(by:)` 稳定返回最早那一场，
        //    行为与改动前完全一致。
        let soonCandidates = timed.filter {
            $0.kickoff > now && $0.kickoff.timeIntervalSince(now) <= upcomingWindow
        }
        if let chosen = chooseByRanking(soonCandidates, positions: positions) { return chosen.match }

        // 3) 今日已结束 → 取时间最近的一场
        let finishedToday = timed.filter {
            TodayFilter.isFinished($0.match) && TodayFilter.isSameDay($0.kickoff, as: now, in: tz)
        }
        if let last = finishedToday.last { return last.match }

        // 4) 今日下一场未开赛 → 同样先取最早开球时刻那一批，同刻多场按名次和最小选强强对话。
        //    （候选集与旧实现逐字一致，仅把「取第一个」换成 `chooseByRanking`。）
        let todayUpcoming = timed.filter {
            TodayFilter.isUpcoming($0.match, now: now) && TodayFilter.isSameDay($0.kickoff, as: now, in: tz)
        }
        if let chosen = chooseByRanking(todayUpcoming, positions: positions) { return chosen.match }

        // 5) 当前轮下一场未开赛（可跨日）→ 先取最早开球时刻，同时刻多场才按「名次和最小」选强强对话
        let roundUpcoming = timed.filter {
            $0.match.matchday == currentRound && TodayFilter.isUpcoming($0.match, now: now)
        }
        if let chosen = chooseByRanking(roundUpcoming, positions: positions) {
            return chosen.match
        }

        // 6) 本轮已结束 → 在本轮全部比赛里选「强强对话」（两队名次和最小）的赛果。
        //
        // ⚠️ 不能复用 chooseByRanking：它先把候选收敛到「最早开球那一批」再比排名，
        // 对本轮已全部结束的场景会退化成「取最早开球」—— 正是本次要修的行为
        // （第 3 轮踢完后显示利物浦早场，而用户想看阿森纳 vs 切尔西）。
        // 本轮比赛都已结束，开球早晚对展示没有意义，所以这里跨时段直接比名次。
        //
        // 名次缺失时 rankKey 全部相等，`min(by:)` 稳定返回第一个 → 仍是最早开球那场，向后兼容。
        let roundMatches = timed.filter { $0.match.matchday == currentRound }
        return roundMatches.min(by: {
            rankKey($0.match, positions: positions) < rankKey($1.match, positions: positions)
        })?.match
    }

    /// 在若干候选比赛里挑「推荐卡」（供优先级 2 / 4 / 5 复用）。
    /// 两级排序：
    /// 1. 先按开球时间 —— 只取「最早那一批」同时刻开球的比赛；时间不同的比赛最早优先，
    ///    不跨时段比排名（即使最早时刻只有一场，也直接取它，不会为「更强强对话」去推后更晚的比赛）。
    /// 2. 同一时刻有多场时，按「两队名次和最小」选强强对话；和相同再比两队最高名次（更小者）。
    /// 名次来自 `positions`（teamId → 名次），取不到按 `Int.max / 2` 沉底；`timed` 已按开球升序且 `min(by:)` 稳定。
    private static func chooseByRanking(_ candidates: [TimedMatch], positions: [Int: Int]) -> TimedMatch? {
        guard let earliest = candidates.first?.kickoff else { return nil }
        // 时间相同才比较排名：只保留最早开球时刻的那一批
        let sameSlot = candidates.filter { $0.kickoff == earliest }
        return sameSlot.min(by: { rankKey($0.match, positions: positions) < rankKey($1.match, positions: positions) })
    }

    private static func rankKey(_ m: Match, positions: [Int: Int]) -> (sum: Int, best: Int) {
        // ⚠️ 哨兵用 `Int.max / 2` 而非 `Int.max`：两队都取不到名次时
        // `hp + ap` 会是 `Int.max + Int.max`，debug 构建下整数溢出会直接 trap（SIGTRAP / signal 5），
        // 表现就是测试进程崩溃。用一半的上界，和最大也只到 `Int.max`，不会溢出。
        let unknown = Int.max / 2
        let hp = positions[m.homeTeam.id] ?? unknown
        let ap = positions[m.awayTeam.id] ?? unknown
        return (hp + ap, min(hp, ap))
    }
}

/// 今日比赛按状态分组后的结果
struct TodayGroups {
    let live: [Match]
    /// 未开赛（含延期 / 取消等非进行中、非已结束状态）
    let upcoming: [Match]
    let finished: [Match]

    var total: Int { live.count + upcoming.count + finished.count }
    var isEmpty: Bool { total == 0 }
}

/// 第一列内容的来源（决定列标题）
///
/// 第一列是「正在进行中 & 近期」的合流：直播的排前面，今日已结束的接在后面，
/// 不再二选一 —— 用户既想一眼看到正在踢的，也想顺手看到刚踢完的结果。
enum TodayLiveSource: Equatable {
    /// 有直播（列表里同时含直播与今日已结束）
    case liveAndRecent
    /// 没有直播，只剩今日已结束
    case recent
}

/// 第四行两列的内容
struct TodayColumns {
    /// 第一列：正在进行中 & 近期（直播在前，今日已结束在后，均剔除推荐卡那场）
    let live: [Match]
    let liveSource: TodayLiveSource
    /// 第二列：今日开赛（剔除推荐卡那场）
    ///
    /// 这里刻意**不做任何轮次回退**（本轮下一场 / 下一轮）——
    /// 当前轮还是第 2 轮时，跑去把第 3 轮的赛程铺出来会让人以为轮次已经翻页。
    /// 轮次怎么展示还没定，先只做「今日」，空就显示「暂无数据」。
    let upcoming: [Match]
}

// MARK: - ViewModel

/// 今日视图模型（@Observable）
@Observable
final class TodayViewModel {
    var matches: [Match] = []
    var source: DataSource = .sample
    var error: AppError?
    /// 当前轮次
    var currentRound: Int = 1
    /// 当前积分榜名次（teamId → 名次），供推荐卡「本轮下一场」按强强对话优先选取。
    /// 取数走 DataRepository.standings()（带缓存 + 三级兜底，内部已有 per-level 超时），
    /// 不再套外层预算，避免 Tier1 慢时把毫秒级 Tier2 聚合也一起中止。
    var positions: [Int: Int] = [:]

    @MainActor
    func load() async {
        // 并发取数：赛程（首屏必需）、当前轮、积分榜名次三者互不依赖取数，
        // 一起发起能缩短「推荐卡先显示最早开球、再跳到强强对话」的闪烁窗口。
        // （standings 内部会复用已缓存的赛程，不会重复打网络。）
        async let matchesResult: ([Match], DataSource) = DataRepository.matches()
        async let roundResult: Int? = withTimeBudget(seconds: 8) {
            await DataRepository.currentGameweek()
        }
        // ⚠️ 这里**不再**套外层 8s 预算：
        // standings() 内部已有 per-level 超时（Tier1 网络 15s/30s、Tier2 复用已缓存赛程），
        // 自行在三级兜底间切换。若外层再卡 8s，Tier1 慢时会把整个调用中止，
        // 导致毫秒级的 Tier2 聚合永远没机会跑 —— 名次变空、推荐卡退化成「最早开球」。
        async let standingsResult: ([StandingRow], DataSource)? = try? await DataRepository.standings()

        // 首屏渲染点：赛程一到立刻展示，后续数据异步补上。
        let (data, src) = await matchesResult
        matches = data
        source = src
        error = nil

        // currentRound 只用于挑「推荐比赛」，锦上添花：超 8s 就退回从赛程推断当前轮，
        // 不会阻塞上面已经渲染好的首屏。
        let round = await roundResult
        currentRound = round ?? CurrentRoundInference.infer(from: matches) ?? 1

        // 名次缺失（取数超时 / 示例数据）时 FeaturedMatchCard 的公式会自然回退成「开球最早」，不报错。
        if let rows = (await standingsResult)?.0, !rows.isEmpty {
            positions = Self.buildPositions(from: rows)
        }
    }

    /// 把积分榜行聚合成「teamId → 名次」字典。
    ///
    /// 用 `uniquingKeysWith:` 而非 `uniqueKeysWithValues:`，因为同一支球队可能因
    /// 脏数据 / 主客场拆分残留而在聚合结果里出现两次，后者在碰到重复 key 时会直接 trap。
    /// 重复的 key 保留**先出现**的那条（名次以第一次出现的为准）。
    static func buildPositions(from rows: [StandingRow]) -> [Int: Int] {
        Dictionary(rows.map { ($0.team.id, $0.position) }, uniquingKeysWith: { first, _ in first })
    }

    /// 按状态分组的今日比赛（用于头部计数与状态分布）
    func grouped(tz: TimeZone, now: Date = Date()) -> TodayGroups {
        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        return TodayGroups(
            live: today.filter { TodayFilter.isLive($0, now: now) },
            upcoming: today.filter { TodayFilter.isUpcoming($0, now: now) },
            finished: today.filter(TodayFilter.isFinished)
        )
    }

    /// 推荐比赛（featured 大卡片）
    func featured(tz: TimeZone, now: Date = Date()) -> Match? {
        TodayFeatured.pick(from: matches, currentRound: currentRound, now: now, tz: tz, positions: positions)
    }

    /// 第四行两列
    ///
    /// 两列都会**剔除推荐卡那场**，避免同一场比赛在页面上重复出现两次
    /// （推荐卡已把它作为视觉焦点展示，列里再列一次是纯冗余）。
    ///
    /// 第一列是「直播 + 今日已结束」的合流（直播在前，已结束按最近在前）；
    /// 第二列只取**今日未开赛**，不做轮次回退（理由见 `TodayColumns.upcoming`）。
    func columns(tz: TimeZone, now: Date = Date()) -> TodayColumns {
        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        let featuredID = featured(tz: tz, now: now)?.id
        let notFeatured: (Match) -> Bool = { $0.id != featuredID }

        // MARK: 第一列：直播在前（早开球的在前）+ 今日已结束在后（最近结束的在前）
        let liveOnly = today.filter { TodayFilter.isLive($0, now: now) }.filter(notFeatured)
        let finishedToday = today.filter(TodayFilter.isFinished)
            .filter(notFeatured)
            .reversed() // 「近期」：刚踢完的排最前
        let first = liveOnly + finishedToday
        let firstSource: TodayLiveSource = liveOnly.isEmpty ? .recent : .liveAndRecent

        // MARK: 第二列：今日开赛（timedMatches 已按开球时间升序）
        let second = today.filter { TodayFilter.isUpcoming($0, now: now) }.filter(notFeatured)

        return TodayColumns(live: first, liveSource: firstSource, upcoming: second)
    }
}

// MARK: - 视图

/// 今日页结构（自上而下四行）：
/// 1. 大标题「今日 · 8月31日」；
/// 2. 副标题「第 2 轮 · 共 10 场 · 0 场进行中」；
/// 3. 推荐比赛大卡片（整页视觉焦点）；
/// 4. 平均分两列：
///    - 第一列：正在进行中 & 近期（直播在前，今日已结束在后；无直播时标题降级为「近期」）；
///    - 第二列：今日开赛（不做轮次回退，没比赛就显示「暂无数据」）；
///    两列都剔除推荐卡那场，空则整列不显示。
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = TodayViewModel()

    private var timeZone: TimeZone {
        TimeZone(identifier: appState.timeZone.identifier) ?? .current
    }

    var body: some View {
        let lang = appState.language

        Group {
            if vm.matches.isEmpty {
                EmptyStateView(label: UIString.noFixtures.text(lang))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let featured = vm.featured(tz: timeZone) {
                            FeaturedMatchCard(match: featured)
                        }
                        columnsView(vm.columns(tz: timeZone))
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(UIString.today.text(lang))
        .task(id: appState.refreshNonce) {
            // 后台自动轮询静默刷新：不亮全屏遮罩（否则比赛日每 60s 闪一次，非常干扰）；
            // 首载 / 手动刷新照常。isLoading 仍无条件复位，避免极端时序下遮罩卡死。
            if appState.lastRefreshSource != .background { appState.isLoading = true }
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
            // 取数完把「是否有比赛进行中 / 下一场开球时间」回报给 AppState，
            // 驱动自动刷新定时器在「60s 轮询」与「睡到下一场开球前」之间切换。
            appState.reportLiveSchedule(from: vm.matches)
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: 第 1、2 行：大标题 + 副标题

    private var header: some View {
        let lang = appState.language
        let groups = vm.grouped(tz: timeZone)
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: UIString.todayTitleFormat.text(lang), todayDateText))
                .font(.largeTitle)
                .bold()
            Text(String(format: UIString.todaySubtitleFormat.text(lang),
                        vm.currentRound, groups.total, groups.live.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 仅日期：中文「8月31日」/ 英文「Aug 31」
    private var todayDateText: String {
        let lang = appState.language
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = lang == .english ? "MMM d" : "M月d日"
        return df.string(from: Date())
    }

    // MARK: 第 4 行：平均分两列

    /// 第四行：固定两张小卡片（左右各一张），无论有无数据都显示。
    /// 空内容时显示「暂无数据」占位，避免页面在轮次间隙只剩一张孤零零的大卡。
    /// 卡片右上角的「查看全部 →」会跳到赛程板块看完整列表。
    private func columnsView(_ cols: TodayColumns) -> some View {
        let lang = appState.language
        return HStack(alignment: .top, spacing: 16) {
            columnCard(
                title: cols.liveSource == .liveAndRecent
                    ? UIString.colLiveAndRecent.text(lang)
                    : UIString.colRecent.text(lang),
                matches: cols.live
            )
            columnCard(
                title: UIString.colTodayUpcoming.text(lang),
                matches: cols.upcoming
            )
        }
    }

    /// 单列小卡片：标题 + 「查看全部」链接 + 比赛列表或「暂无数据」占位
    private func columnCard(title: String, matches: [Match]) -> some View {
        let lang = appState.language
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    appState.selected = .fixtures
                } label: {
                    HStack(spacing: 4) {
                        Text(UIString.viewAll.text(lang))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if matches.isEmpty {
                Text(UIString.noData.text(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    // 每列最多 4 场：两列共用 columnCard，改一次两列都生效。
                    // 超出 4 场的部分走卡片右上角「查看全部 →」跳赛程页，
                    // 不在卡片里堆长列表（两列都堆满会把今日页撑得需要滚很久）。
                    ForEach(Array(matches.prefix(4))) { match in
                        // 今日页：球队靠两边（主队贴左、客队贴右），与赛程页的"贴中间比分"区分
                        MatchCard(match: match, teamsFlankSides: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 推荐比赛大卡片

/// 推荐卡圆角。
///
/// `.glassEffect()` 不指定形状时，macOS 26 会按容器自动取一个很大的圆角（视觉上 26pt 往上），
/// 用在内容卡片上过于圆钝、抢戏。这里显式指定：
/// - Apple 的圆角随容器尺寸递增，但「内容型卡片」不需要 sheet / modal 那种大圆角；
/// - 12pt 与 macOS 窗口圆角（约 10pt）同一量级，读作「卡片」而不喧宾夺主；
/// - 刻意写死而非吃默认值 —— 每个数值都该是可辩护的选择（Craft）。
private let featuredCardCornerRadius: CGFloat = 12

/// 卡片内「球队块」距卡片左右边缘的额外留白。
/// 卡片本身已有 22pt 内边距，但球队块是 `maxWidth: .infinity` 撑满的，
/// 队徽/队名会顶到离边缘只剩 22pt 的位置，视觉上「贴边」。
/// 再补 40pt，让内容区与玻璃边缘之间留出一口气（Apple 的 breathing room），
/// 同时比分/时间仍稳稳居中，球队块不至于被挤到中间。
private let featuredCardSideInset: CGFloat = 40

/// 推荐卡写死的渐变背景（深紫红 → 亮粉，左→右），不随 macOS 系统强调色变。
/// 用户看了「系统强调色 × Liquid Glass」渲染出的紫红渐变觉得炫酷，
/// 明确选择把这张卡的颜色固定下来 —— 所以这里是常量、不读 AppState.accent。
private let featuredCardGradient = LinearGradient(
    colors: [
        Color(red: 0.45, green: 0.05, blue: 0.35),   // 深紫红（左）
        Color(red: 0.92, green: 0.20, blue: 0.55),   // 亮粉（右）
    ],
    startPoint: .leading,
    endPoint: .trailing
)

/// 今日页第三行：整页视觉焦点的推荐比赛卡片
struct FeaturedMatchCard: View {
    @Environment(AppState.self) private var appState
    let match: Match

    private var timeZone: TimeZone {
        TimeZone(identifier: appState.timeZone.identifier) ?? .current
    }

    private var kickoff: Date? { parseKickoffDate(match.utcDate) }

    /// 开球至今已踢的分钟数（向下取整）—— **纯函数**，`now` 由调用方显式传入。
    ///
    /// 下限 clamp 到 0 —— 赛前状态已置 IN_PLAY、或本机时钟与服务端有偏差时避免出负数。
    /// 拿不到开球时间返回 nil。
    ///
    /// ⚠️ 刻意**不再**在计算属性里偷偷读 `Date()`：实时路径由 `centerBlock` 里的
    /// `TimelineView(.periodic(by: 1))` 每秒把 `context.date` 传进来。这样既让「时间 → 文本」
    /// 整条链路可单测，也避免 SwiftUI 在 `match` 未变时跳过本卡 body 求值导致分钟数冻结。
    nonisolated static func elapsedMinutes(kickoff: Date?, now: Date) -> Int? {
        guard let kickoff else { return nil }
        return max(0, Int(floor(now.timeIntervalSince(kickoff) / 60)))
    }

    /// 把「已踢分钟数」渲染成足球惯用记法（19' / 45' / 90+'）。
    ///
    /// 抽成不依赖 `Date()` 的纯函数，便于单测覆盖各分支。规则：
    /// - 中场休息（HALFTIME）→ 固定 45'
    /// - 上半场（≤45）→ 实际分钟
    /// - 中场休息区间（46–60，状态还没翻成 HALFTIME 的情况）→ 钳到 45'
    /// - 下半场（61–105）→ 实际分钟扣掉中场的 15 分钟
    /// - 补时 / 超长（>105）→ 钳到 90+'
    ///
    /// - Parameters:
    ///   - elapsed: 开球后已过分钟数（调用方保证 ≥ 0）
    ///   - isHalftime: 是否处于中场休息
    nonisolated static func formatLiveClock(elapsed: Int, isHalftime: Bool) -> String {
        if isHalftime { return "45'" }
        if elapsed <= 45 { return "\(elapsed)'" }
        if elapsed <= 60 { return "45'" }
        if elapsed <= 105 { return "\(elapsed - 15)'" }
        return "90+'"
    }

    /// 卡片中间大槽该显示什么 —— 抽成纯函数（不依赖网络 / 时钟），便于单测覆盖每个分支。
    ///
    /// 判定顺序（**顺序不能变**）：
    /// 1. 有比分（`score?.fullTime?.home` 与 `.away` 均非 nil）→ `.score`；
    /// 2. 否则若进行中（`TodayFilter.isLive`）→ `.pendingLiveScore` —— FPL `fixtures` 在开球后
    ///    约 8 分钟内不返回比分，此时按 `0 - 0` 显示，**不能再退化成显示开球时间**；
    /// 3. 否则能解析出开球时间 → `.kickoff`；
    /// 4. 全都不满足 → `.tbd`。
    ///
    /// ⚠️ 顺序必须严格是「有比分 → live → kickoff」：若把 live 判断提到最前，
    /// 「进行中且已有比分」会被错误地当成 `.pendingLiveScore` 而显示 0-0。
    enum CenterContent: Equatable {
        /// 有比分；`isLive` 决定是否在大比分前加 ⚽（进行中）
        case score(home: Int, away: Int, isLive: Bool)
        /// 进行中但数据源尚未返回比分（FPL 开球后约 8 分钟滞后）→ UI 按 0 - 0 显示
        case pendingLiveScore
        /// 未开赛 → 显示开球时间
        case kickoff(Date)
        /// 拿不到比分也拿不到开球时间 → 显示「待定」
        case tbd
    }

    /// 见 `CenterContent` 的判定顺序说明。
    /// `nonisolated` 与 `formatLiveClock` 一致，便于在单测里直接调用。
    nonisolated static func centerContent(for match: Match, now: Date = Date()) -> CenterContent {
        if let home = match.score?.fullTime?.home, let away = match.score?.fullTime?.away {
            return .score(home: home, away: away, isLive: TodayFilter.isLive(match, now: now))
        }
        if TodayFilter.isLive(match, now: now) { return .pendingLiveScore }
        if let kickoff = parseKickoffDate(match.utcDate) { return .kickoff(kickoff) }
        return .tbd
    }

    var body: some View {
        let lang = appState.language
        VStack(spacing: 18) {
            // 顶部：轮次 + 状态徽标（靠左），Spacer 撑开右侧留白
            HStack(spacing: 8) {
                if let md = match.matchday {
                    Text(String(format: UIString.roundN.text(lang), md))
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                statusBadge(lang: lang)
                Spacer()
            }

            // 中部：主队（贴左） | 比分 / 时间（居中） | 客队（贴右）
            // 两侧球队块各占一半、内容分别靠外缘，避免队徽队名全挤在比分旁边、卡片左右留白。
            // （注：列表行的 MatchCard 用的是相反方向 —— 那里刻意让队名贴着比分，保证比分列竖直对齐。）
            HStack(spacing: 0) {
                teamBlock(match.homeTeam, lang: lang, alignment: .leading)
                Spacer(minLength: 24)
                centerBlock(lang: lang)
                Spacer(minLength: 24)
                teamBlock(match.awayTeam, lang: lang, alignment: .trailing)
            }
            .padding(.horizontal, featuredCardSideInset)
        }
        .padding(22)
        // 卡片子树强制深色语义：让 .primary/.secondary 解析成白/浅灰。
        // 否则浅色模式下文字会解析成黑字，压在写死的深紫红渐变上几乎不可读（WCAG 对比度仅 1.71:1）。
        .environment(\.colorScheme, .dark)
        // 写死的渐变背景（不随系统强调色变）；圆角与渐变共用 featuredCardCornerRadius。
        // 渐变之上再叠一层极淡的黑色做柔和暗化，保证亮粉端的白字（44pt 比分 / 顶部轮次与状态小字）
        // 在两端都清晰可读，同时不损失「炫酷」观感。
        .background(
            RoundedRectangle(cornerRadius: featuredCardCornerRadius)
                .fill(featuredCardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: featuredCardCornerRadius)
                        .fill(Color.black.opacity(0.12))
                )
        )
    }

    private func teamBlock(_ team: Team, lang: AppLanguage, alignment: HorizontalAlignment) -> some View {
        VStack(spacing: 10) {
            // 推荐卡是视觉焦点：队徽按 56pt 渲染（CrestImage 默认 20pt 是给列表行用的）
            CrestImage(urlString: team.crest, size: 56)
            Text(team.displayName(chinese: lang == .chinese))
                .font(.title3)
                .bold()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    /// 中部：有比分显示大比分（进行中加 ⚽），未开赛显示大时间。
    /// 「进行中但比分缺失」（数据源滞后）按 0 - 0 显示，避免自相矛盾地退化成显示开球时间。
    private func centerBlock(lang: AppLanguage) -> some View {
        let now = Date()
        return VStack(spacing: 6) {
            switch Self.centerContent(for: match, now: now) {
            case let .score(home, away, isLive):
                scoreRow(home: home, away: away, isLive: isLive)
            case .pendingLiveScore:
                // 进行中但数据源还没给比分 → 按 0 - 0 显示，样式与 live 比分完全一致
                scoreRow(home: 0, away: 0, isLive: true)
            case let .kickoff(date):
                Text(timeText(date, lang: lang))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            case .tbd:
                Text(UIString.tbd.text(lang))
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            // 进行中的分钟数（如 19'）是用户实时关注的信息，用大一号 + 粗体 + 纯白突出；
            // 已结束 / 未开赛那两行只是辅助说明，保持 footnote + .white，不抢视觉。
            if TodayFilter.isLive(match, now: now) {
                // ⚠️ 用 `TimelineView(.periodic(by: 1))` 给分钟数一个**独立于数据刷新的重绘源**：
                // 未进球（比分不变）期间 `match` 不变，SwiftUI 会跳过本卡 body 求值，过去「按
                // `Date()` 现算」的分钟数因此冻结在最后一分钟；TimelineView 的子闭包按时间线自动
                // 重新求值，跨分钟必然刷新。只包这一个 `Text`，不包整张卡（其余内容无需每秒重绘）。
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(statusLine(lang: lang, now: context.date))
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } else {
                Text(statusLine(lang: lang, now: Date()))
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
        }
    }

    /// 大比分一行（进行中前面带 ⚽）。`.score` 与 `.pendingLiveScore` 共用，保证两者样式逐字一致。
    private func scoreRow(home: Int, away: Int, isLive: Bool) -> some View {
        HStack(spacing: 8) {
            if isLive {
                Image(systemName: "soccerball")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            Text("\(home) - \(away)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    /// 比分 / 时间下方的小字：进行中 → 已踢分钟数（如 19'）；已结束 → 已结束；未开赛 → 日期。
    ///
    /// `now` 由调用方显式传入 —— 实时路径来自 `TimelineView` 的 `context.date`，非实时路径传 `Date()`。
    private func statusLine(lang: AppLanguage, now: Date) -> String {
        if TodayFilter.isLive(match, now: now) {
            // 拿不到开球时间就算不出分钟数，回退到「进行中」文案
            guard let elapsed = Self.elapsedMinutes(kickoff: kickoff, now: now) else { return UIString.live.text(lang) }
            return Self.formatLiveClock(elapsed: elapsed,
                                        isHalftime: match.status == "HALFTIME")
        }
        if TodayFilter.isFinished(match) { return UIString.statusFinished.text(lang) }
        guard let kickoff else { return UIString.tbd.text(lang) }
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = lang == .english ? "MMM d" : "M月d日"
        return df.string(from: kickoff)
    }

    private func statusBadge(lang: AppLanguage) -> some View {
        let text: String
        let color: Color
        if TodayFilter.isLive(match, now: Date()) {
            text = UIString.live.text(lang)
            color = .red
        } else if TodayFilter.isFinished(match) {
            text = UIString.statusFinished.text(lang)
            color = .white
        } else if match.status == "POSTPONED"
                    || match.status == "CANCELED"
                    || match.status == "CANCELLED" {
            text = match.status == "POSTPONED" ? UIString.postponed.text(lang) : UIString.canceled.text(lang)
            color = .white
        } else {
            text = UIString.statusUpcoming.text(lang)
            color = .white
        }
        return Text(text)
            .font(.caption)
            .bold()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func timeText(_ date: Date, lang: AppLanguage) -> String {
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}
