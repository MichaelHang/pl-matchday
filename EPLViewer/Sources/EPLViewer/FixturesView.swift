import SwiftUI

// MARK: - 模式

/// 赛程页的查看模式
/// - `.thisRound` 单轮详情（默认，进入时停留在 `focusedRound`）
/// - `.season` 赛季总览（所有轮次卡片网格，点击进入对应轮次详情）
enum FixturesMode: Equatable {
    case thisRound
    case season
}

/// 轮次在赛季里的进度状态（用于总览卡片角标颜色）
enum RoundProgress {
    /// 已踢完
    case past
    /// 当前轮（正在踢或即将踢）
    case current
    /// 未来轮次
    case future
    /// 该轮暂无数据（不在 availableRounds 内，例如下一轮还没发赛程）
    case unknown
}

// MARK: - 赛季进度 / 轮次快照

/// 赛季进度汇总（顶部进度条用）
struct SeasonProgress: Equatable {
    /// 当前轮次（is_current > is_next > 最近已结束）
    let currentRound: Int
    /// 总轮次（取 FPL events 末位；FPL 拿不到时默认 38）
    let totalRounds: Int
    /// 已踢轮次（bootstrap.events.finished=true 的计数）
    let playedRounds: Int
    /// 剩余轮次
    let remainingRounds: Int
    /// 已踢百分比 0..1
    let fraction: Double
    /// 取第一轮 deadline_time 的年份（不可得则取当前年）
    let seasonYear: Int
}

/// 一个轮次的「快照」—— 赛季总览卡片用
struct RoundSnapshot: Identifiable {
    let round: Int
    let startDate: Date?
    let progress: RoundProgress
    let previews: [Match]
    var id: Int { round }
}

// MARK: - ViewModel

/// 赛程视图模型（@Observable）
@Observable
final class FixturesViewModel {
    /// 比赛全集。赋值即自动重建索引 —— 保证「按轮次分桶 / 每轮最早开球」
    /// 这两个索引永远和数据同步（手动赋值、测试注入也一样）。
    var matches: [Match] = [] {
        didSet {
            rebuildIndexes()
            availableRounds = matchesByRound.keys.sorted()
        }
    }
    var source: DataSource = .sample
    var error: AppError?
    /// 模式：本轮 / 赛季总览
    var mode: FixturesMode = .thisRound
    /// 当前正在查看的轮次 —— 「本轮」模式下展示它，
    /// 「赛季总览」下的卡片点击会改写它后切回 `.thisRound`。
    /// 改值（初始聚焦当前轮、或点总览卡片跳过来）会自动把轮次窗口对齐到它。
    /// 已在窗口内则不动 —— 这样点窗口里某个 chip 不会让窗口跳来跳去。
    /// ⚠️ 翻页**不改** focusedRound，所以翻页不会触发这里，窗口不会被拉回去。
    var focusedRound: Int = 1 {
        didSet { alignWindowToFocusedRound() }
    }
    /// 真正「当前」轮（来自 FPL is_current/is_next），仅用于初始化和进度文案。
    /// 它参与 `roundSnapshots` 的 past/current/future 判定，所以改值要让快照缓存失效。
    var currentRound: Int = 1 {
        didSet { invalidateSnapshotCache() }
    }
    /// 有比赛的轮次列表（升序，来自 FPL fixtures 数据）。
    /// 列表长度一变，窗口起点可能就越界，所以要立刻夹回合法区间。
    var availableRounds: [Int] = [] {
        didSet { clampWindowStart() }
    }
    /// 赛季进度（赛季总览 header 用；首次 load 时填充）。
    /// 它是 `roundSnapshots` 的直接入参之一，改值要让快照缓存失效。
    var seasonProgress: SeasonProgress? {
        didSet { invalidateSnapshotCache() }
    }

    // MARK: 轮次窗口（chip bar 固定窗口分页）
    //
    // chip bar 不再一次列出全部轮次：38 轮尚可，轮次数涨到几百上千会拖垮布局阶段。
    // 改成「固定大小窗口 + 左右翻页」—— 一次最多渲染 `roundWindowSize` 个 chip，
    // 渲染量与总轮次数无关。

    /// 窗口大小：chip bar 一次显示的轮次数量
    static let roundWindowSize = 5
    /// 窗口在 `availableRounds` 里的起始下标。
    /// 放 ViewModel（而不是 View 的 `@State`）是为了可测试；
    /// 它是**参与观察**的普通属性 —— 窗口翻页了 UI 必须重绘。
    var roundWindowStart: Int = 0

    // MARK: 预计算索引
    //
    // ⚠️ 38 个轮次 chip 每个都要「该轮最早开球时间」，如果每次都全表扫描 380 场，
    // 就是 38 × 380 = 14440 次 parse —— 且发生在 SwiftUI body 求值路径上，
    // 任何一次重绘都会重跑，主线程直接卡死。所以 load 时一次遍历建好索引。

    /// 每轮的最早开球时间（UTC Date）—— chip 的「M月d日」后缀与分组都靠它
    private(set) var roundStartUTC: [Int: Date] = [:]
    /// 按轮次分桶的比赛（桶内已按开球时间升序）
    private(set) var matchesByRound: [Int: [Match]] = [:]

    // MARK: 赛季总览快照缓存
    //
    // ⚠️ `roundSnapshots(seasonProgress:)` 直接在 SwiftUI body 求值路径上被调用，
    // 每次重绘都要遍历全部轮次、为每轮生成含 ≤3 场预览的快照 —— O(轮数 × 预览数)。
    // 38 轮无感，轮次数涨到几百上千就是每次重绘几千条，主线程直接被吃满。
    // 所以这里按「输入是否变化」缓存：输入没变就直接返回上一次的结果。

    /// 快照缓存的判定 key —— 覆盖所有能改变快照结果的输入
    private struct SnapshotCacheKey: Equatable {
        /// 索引版本号（`matches` 每次重建索引都会自增）
        let indexGeneration: Int
        /// 当前轮：决定快照的 past / current / future 状态
        let currentRound: Int
        /// 赛季进度：决定总轮数与当前轮（为 nil 时走 `currentRound` 兜底）
        let seasonProgress: SeasonProgress?
    }

    /// 索引版本号。用它替代「对全部比赛做一遍指纹」来判断数据是否变过，O(1)。
    /// `roundStartUTC` / `matchesByRound` / `availableRounds` 三个索引都由 `matches` 派生，
    /// 所以它们同步失效 —— 一个版本号足够覆盖。
    ///
    /// ⚠️ 标 `@ObservationIgnored`：body 从不读它，不该参与 @Observable 的依赖追踪。
    @ObservationIgnored private var indexGeneration: Int = 0
    /// 上一次算出的快照结果
    @ObservationIgnored private var snapshotCache: [RoundSnapshot]?
    /// 生成 `snapshotCache` 时的输入 key
    @ObservationIgnored private var snapshotCacheKey: SnapshotCacheKey?
    /// 缓存**未命中**（真正重算）的次数。仅供测试断言「第二次调用没有重算」，UI 不使用。
    @ObservationIgnored private(set) var roundSnapshotsComputeCount: Int = 0

    /// 作废快照缓存。索引重建 / 当前轮变化 / 赛季进度变化都会走到这里。
    ///
    /// 真正的判定由 `SnapshotCacheKey` 兜底（key 不匹配就自动重算），
    /// 这里显式清空只是多一层保险，成本可忽略。
    private func invalidateSnapshotCache() {
        snapshotCache = nil
        snapshotCacheKey = nil
    }

    @MainActor
    func load() async {
        let (data, src) = await DataRepository.matches()
        matches = data // didSet 会重建索引并刷新 availableRounds
        source = src
        error = nil
        // 只取一次 events，同时用于「当前轮」和「赛季进度」——
        // 之前这里各调一次（currentGameweek + gameweeks），同一份 bootstrap 被解码两遍。
        //
        // ⚠️ 且必须给时间预算：FPL bootstrap-static 实测会慢到几十秒仍不结束，
        // 而「当前轮 / 赛季进度」只是锦上添花。拿不到就用比赛数据本地推断，
        // 绝不能让它拖住首屏 —— 否则表现就是「进了赛程页一直转圈」。
        let events = await withTimeBudget(seconds: 8) { await DataRepository.gameweeks() }
        currentRound = events.flatMap { DataRepository.deriveCurrentRound($0) }
            ?? inferCurrentRoundFromMatches()
            ?? 1
        // 默认聚焦 currentRound；如该轮暂无数据，回退到首个有数据的轮次。
        // 走预计算索引 O(1) 判断，不再 O(n) 扫 380 场。
        if matchesByRound[currentRound] != nil {
            focusedRound = currentRound
        } else if let first = availableRounds.first {
            focusedRound = first
        } else {
            focusedRound = currentRound
        }
        await loadSeasonProgress(events: events)
    }

    /// 从 FPL events 读出赛季进度（已踢轮数 / 总数 / 当前轮 / 年份）。
    /// 失败时按 38 轮 + 0% 兜底，确保 UI 仍有渲染内容。
    /// - Parameter events: 由 `load()` 一次性取好传入，本方法不再重复取数。
    @MainActor
    func loadSeasonProgress(events: [FPLGameweek]? = nil) async {
        let resolvedEvents: [FPLGameweek]?
        if let events {
            resolvedEvents = events
        } else {
            resolvedEvents = await DataRepository.gameweeks()
        }
        guard let events = resolvedEvents else {
            let total = max(38, availableRounds.last ?? 38)
            seasonProgress = SeasonProgress(
                currentRound: currentRound,
                totalRounds: total,
                playedRounds: 0,
                remainingRounds: total,
                fraction: 0,
                seasonYear: Calendar.current.component(.year, from: Date())
            )
            return
        }
        let total = events.map(\.id).max() ?? 38
        let played = events.filter { ($0.finished ?? false) == true }.count
        let current = events.first(where: { ($0.is_current ?? false) == true })?.id
            ?? events.first(where: { ($0.is_next ?? false) == true })?.id
            ?? events.filter({ ($0.finished ?? false) == true }).map(\.id).max()
            ?? total
        let remaining = max(0, total - played)
        let frac = total > 0 ? Double(played) / Double(total) : 0
        let year = events
            .compactMap { $0.deadline_time }
            .compactMap(parseKickoffDate)
            .map { Calendar.current.component(.year, from: $0) }
            .first ?? Calendar.current.component(.year, from: Date())
        seasonProgress = SeasonProgress(
            currentRound: current,
            totalRounds: total,
            playedRounds: played,
            remainingRounds: remaining,
            fraction: frac,
            seasonYear: year
        )
    }

    /// 按模式 + 轮次过滤后的比赛，按开球时间升序。
    /// 直接取预计算桶（桶内已排好序），O(1)；不再对 380 场做 filter + sort。
    var displayed: [Match] {
        matchesByRound[focusedRound] ?? []
    }

    // MARK: - 索引构建

    /// 拿不到 FPL events 时的兜底：用已有的比赛数据本地推断「当前轮」。
    /// 具体规则见 `CurrentRoundInference`（赛程页与今日页共用同一套规则）。
    /// （internal 而非 private：供单元测试覆盖这条兜底路径）
    func inferCurrentRoundFromMatches() -> Int? {
        CurrentRoundInference.infer(from: matches)
    }

    /// 一次遍历建好「按轮次分桶」与「每轮最早开球时间」两个索引。
    /// 之后所有查询都是 O(1) 取桶，不再全表扫描。
    private func rebuildIndexes() {
        // 索引换新 → 派生的快照结果一并作废
        indexGeneration += 1
        invalidateSnapshotCache()
        var byRound: [Int: [Match]] = [:]
        var earliest: [Int: Date] = [:]
        for m in matches {
            guard let r = m.matchday else { continue }
            byRound[r, default: []].append(m)
            if let d = parseKickoffDate(m.utcDate) {
                if let cur = earliest[r] {
                    if d < cur { earliest[r] = d }
                } else {
                    earliest[r] = d
                }
            }
        }
        // 桶内按开球时间升序（ISO8601 字符串字典序 == 时间序）
        for (r, list) in byRound {
            byRound[r] = list.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }
        }
        matchesByRound = byRound
        roundStartUTC = earliest
    }

    // MARK: - 轮次元数据

    /// 某个轮次的最早开球时间（UTC）→ 用于 chip/卡片显示「M月d日」。
    /// 查预计算索引，O(1)；时区换算交给格式化函数，不在这里做。
    func roundStart(_ round: Int) -> Date? {
        roundStartUTC[round]
    }

    // MARK: - 轮次窗口（chip bar 分页）

    /// 窗口起始下标的合法上界。
    /// 轮次数不足一屏时为 0 —— 此时窗口没法挪动，两个翻页箭头都该隐藏。
    var roundWindowMaxStart: Int {
        max(0, availableRounds.count - FixturesViewModel.roundWindowSize)
    }

    /// 窗口内可见的轮次编号（至多 `roundWindowSize` 个）。
    /// 起点先夹回合法区间再切片，保证任何状态下都不越界。
    var visibleRounds: [Int] {
        let start = min(max(roundWindowStart, 0), roundWindowMaxStart)
        guard start < availableRounds.count else { return [] }
        let end = min(start + FixturesViewModel.roundWindowSize, availableRounds.count)
        return Array(availableRounds[start..<end])
    }

    /// 把 `roundWindowStart` 夹回 `[0, roundWindowMaxStart]` 并写回。
    /// 数据刷新导致 `availableRounds` 变短时靠它兜底。
    func clampWindowStart() {
        roundWindowStart = min(max(roundWindowStart, 0), roundWindowMaxStart)
    }

    /// 把窗口重新定位到包含 `focusedRound` 的位置。
    ///
    /// 对齐规则（以 `availableRounds` 为有序数组）：
    /// - 中间：以 `focusedRound` 为中心，前 2 后 2（窗口大小 5 → 偏移 `5 / 2 = 2`）
    /// - 靠左/靠右：起点被夹到 0 / 上界，等价于窗口左对齐 / 右对齐
    /// - 轮次总数 ≤ 窗口大小：直接归零（全部轮次都显示，无需对齐）
    ///
    /// 两种情况下**保持不动**，不动是刻意的：
    /// - `focusedRound` 已经在窗口内（包括翻页后用户只是移动了取景框、没换选中的轮）→ 不重排，保持视窗稳定
    /// - `focusedRound` 不在 `availableRounds` 里（该轮暂无数据）→ 没有可对齐的位置
    func alignWindowToFocusedRound() {
        let size = FixturesViewModel.roundWindowSize
        if availableRounds.count <= size {
            roundWindowStart = 0
            return
        }
        guard !visibleRounds.contains(focusedRound),
              let idx = availableRounds.firstIndex(of: focusedRound)
        else { return }
        // count > size 在这里恒成立，所以 maxStart > 0，夹取结果不会越界
        let maxStart = availableRounds.count - size
        roundWindowStart = min(max(idx - size / 2, 0), maxStart)
    }

    /// 向左翻一页（上一组轮次）。
    /// **只移动窗口，不改 `focusedRound`** —— 当前选中的那一轮保持高亮，
    /// 内容区也继续显示它。窗口纯粹是 chip 的导航取景框，只有点 chip 才切换选中轮。
    func pageRoundsBackward() {
        roundWindowStart = max(roundWindowStart - FixturesViewModel.roundWindowSize, 0)
        clampWindowStart()
    }

    /// 向右翻一页（下一组轮次）。同样只移动窗口，不改 `focusedRound`。
    func pageRoundsForward() {
        roundWindowStart = roundWindowStart + FixturesViewModel.roundWindowSize
        clampWindowStart()
    }

    // MARK: - 按 (轮次, 日期) 分组

    /// 返回按日期分组的数据；每天一节，节内按开球升序
    func groupedSections(tz: TimeZone) -> [FixturesSection] {
        let list = matchesByRound[focusedRound] ?? []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var buckets: [Date: [Match]] = [:]
        for m in list {
            guard let d = parseKickoffDate(m.utcDate) else { continue }
            let local = cal.startOfDay(for: d)
            buckets[local, default: []].append(m)
        }
        return buckets
            .map { (date, items) in
                FixturesSection(date: date,
                                matches: items.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") })
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - 赛季总览快照

    /// 给赛季总览卡片网格用：每个轮次一张快照，
    /// 卡内最多 3 场预览（开球升序前 3 场）。
    /// 全部走预计算索引，不做任何全表扫描。
    ///
    /// 结果按输入缓存：`matches`（经 `indexGeneration`）/ `currentRound` / `seasonProgress`
    /// 三者都没变时直接返回上一次的结果，避免 body 每次重绘都 O(轮数 × 预览数) 重算。
    func roundSnapshots(seasonProgress: SeasonProgress?) -> [RoundSnapshot] {
        let key = SnapshotCacheKey(
            indexGeneration: indexGeneration,
            currentRound: currentRound,
            seasonProgress: seasonProgress
        )
        if let cached = snapshotCache, snapshotCacheKey == key {
            return cached
        }
        let cur = seasonProgress?.currentRound ?? currentRound
        let set = Set(availableRounds)
        let max = seasonProgress?.totalRounds ?? (availableRounds.last ?? 38)
        var result: [RoundSnapshot] = []
        result.reserveCapacity(max)
        for r in 1...max {
            let progress: RoundProgress
            if r < cur {
                progress = .past
            } else if r == cur {
                progress = .current
            } else {
                progress = .future
            }
            // 直接取预计算桶，避免 38 轮 × 380 场的重复全表扫描
            let items = matchesByRound[r] ?? []
            // 哪怕本季暂无该轮数据，也展示空快照（占位）
            result.append(RoundSnapshot(
                round: r,
                startDate: roundStartUTC[r],
                progress: set.contains(r) ? progress : (progress == .future ? .unknown : progress),
                previews: Array(items.prefix(3))
            ))
        }
        roundSnapshotsComputeCount += 1
        snapshotCache = result
        snapshotCacheKey = key
        return result
    }
}

/// 一节 = 某个本地日期下的若干场比赛
struct FixturesSection: Identifiable {
    var date: Date
    var matches: [Match]
    var id: Date { date }
}

// MARK: - 日期工具

// ⚠️ 性能关键区：这些方法都在 SwiftUI body 求值路径上被调用，
// 而赛程页一次要渲染 380 场比赛 + 38 个轮次 chip。
// 每次新建 DateFormatter / ISO8601DateFormatter 会让主线程直接卡死
// （DateFormatter 构造成本极高），所以一律走缓存池。

/// 格式化器缓存池。
///
/// Swift 6 严格并发下全局 `var` 会报 MutableGlobalVariable，所以收进这个单例；
/// 内部用 NSLock 保护，对 Swift 6 标注 `@unchecked Sendable`。
private final class FormatterPool: @unchecked Sendable {
    static let shared = FormatterPool()

    private let lock = NSLock()
    private var cache: [String: DateFormatter] = [:]

    let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 按 时区 + 语言 + 格式 唯一键复用 DateFormatter 实例
    func formatter(tz: TimeZone, localeID: String, format: String) -> DateFormatter {
        let key = "\(tz.identifier)|\(localeID)|\(format)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: localeID)
        f.dateFormat = format
        cache[key] = f
        return f
    }
}

/// 「8月29日 / Aug 29」短日期
private func formatShortDate(_ d: Date, tz: TimeZone, lang: AppLanguage) -> String {
    let df = FormatterPool.shared.formatter(
        tz: tz,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "MMM d" : "M月d日")
    return df.string(from: d)
}

/// 「8月29日 星期六 / Sat, Aug 29」
private func formatDateHeader(_ d: Date, tz: TimeZone, lang: AppLanguage) -> String {
    let df = FormatterPool.shared.formatter(
        tz: tz,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "EEE · MMM d" : "M月d日 EEEE")
    return df.string(from: d)
}

// MARK: - 视图

/// 赛程
/// - `.thisRound` 模式：聚焦当前轮（默认）或用户从总览点入的某一轮，按日期分组展示全部比赛
/// - `.season`    模式：赛季总览卡片网格，点卡片回到 `.thisRound` 看该轮详情
struct FixturesView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = FixturesViewModel()

    /// 品牌粉色 —— 用于赛季总览进度条与「当前轮」角标
    /// （与 TodayView 详情页不使用品牌色保持一致，本色仅用于进度语义）
    private let accentPink = Color(red: 1.00, green: 0.231, blue: 0.498)

    var body: some View {
        @Bindable var appState = appState
        let lang = appState.language
        let tz = TimeZone(identifier: appState.timeZone.identifier) ?? .current

        VStack(spacing: 0) {
            if vm.error != nil {
                ErrorView(message: vm.error?.localizedDescription ?? "加载失败")
            } else if vm.matches.isEmpty {
                EmptyStateView(label: UIString.noFixtures.text(lang))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch vm.mode {
                        case .thisRound:
                            thisRoundSection(lang: lang, tz: tz)
                        case .season:
                            seasonOverviewSection(lang: lang, tz: tz)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("")
        .task(id: appState.refreshNonce) {
            appState.isLoading = true
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
            // 赛程页也展示进行中比赛，一并回报调度状态（与 TodayView 用同一入口）。
            appState.reportLiveSchedule(from: vm.matches)
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: 本轮详情页

    @ViewBuilder
    private func thisRoundSection(lang: AppLanguage, tz: TimeZone) -> some View {
        Text(String(format: UIString.fixturesHeader.text(lang), vm.focusedRound))
            .font(.system(size: 28, weight: .bold))

        modeBar(lang: lang)

        if !vm.availableRounds.isEmpty {
            roundChipBar(lang: lang, tz: tz)
        }

        if vm.displayed.isEmpty {
            EmptyStateView(label: UIString.noRoundMatches.text(lang))
                .padding(.top, 32)
        } else {
            groupsSection(lang: lang, tz: tz)
        }
    }

    // MARK: 赛季总览页

    @ViewBuilder
    private func seasonOverviewSection(lang: AppLanguage, tz: TimeZone) -> some View {
        let progress = vm.seasonProgress

        // 大标题「2026 赛季」
        Text(String(format: UIString.seasonHeader.text(lang),
                     progress?.seasonYear ?? Calendar.current.component(.year, from: Date())))
            .font(.system(size: 28, weight: .bold))

        // 轮次切换 pill（保留入口，与新赛季总览并存）
        modeBar(lang: lang)

        // 卡片网格
        let snapshots = vm.roundSnapshots(seasonProgress: progress)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 260),
                               spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(snapshots) { snap in
                Button {
                    vm.focusedRound = snap.round
                    vm.mode = .thisRound
                } label: {
                    SeasonOverviewCard(
                        snapshot: snap,
                        lang: lang,
                        tz: tz,
                        accent: accentPink
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 模式切换 pill

    @ViewBuilder
    private func modeBar(lang: AppLanguage) -> some View {
        HStack(spacing: 8) {
            modePill(label: UIString.modeThisRound.text(lang),
                     active: vm.mode == .thisRound) {
                vm.mode = .thisRound
            }
            modePill(label: UIString.modeSeason.text(lang),
                     active: vm.mode == .season) {
                vm.mode = .season
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func modePill(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(active
                        ? Color.primary.opacity(0.12)
                        : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 轮次 chip bar

    /// 「本轮」模式下的横向轮次切换：**固定窗口** —— 一次只渲染 `visibleRounds`
    /// （至多 5 个轮次），每个 chip 显示「MD N · M月d日」，聚焦 chip 高亮。
    /// 左右两个箭头按窗口大小（±5）翻页，**只移动窗口、不修改 `focusedRound`** ——
    /// 选中的轮次保持高亮、内容区不变；只有点 chip 才切换选中轮。
    ///
    /// 窗口状态在 ViewModel（`roundWindowStart`）里，这里是纯渲染 + 转发动作。
    @ViewBuilder
    private func roundChipBar(lang: AppLanguage, tz: TimeZone) -> some View {
        let rounds = vm.visibleRounds
        ScrollView(.horizontal, showsIndicators: false) {
            // ⚠️ 保留 LazyHStack 而非普通 HStack：
            // 窗口固定 5 个 chip，眼下 lazy 已不是性能必需项，但它是护栏 ——
            // `testRoundChipBarUsesLazyHStack` 会断言它存在，且万一以后窗口调大
            // 也不会退化成「一次建上百个视图」。
            //
            // 安全性：外层是 ScrollView（不是 lazy 容器），不构成「lazy 套 lazy」；
            // 且下方有 .frame(height: 32) 提供确定高度，横向 lazy 容器能正常算尺寸。
            LazyHStack(spacing: 8) {
                // 上一组轮次（窗口已经在最左时隐藏）
                if vm.roundWindowStart > 0 {
                    roundPageButton(systemName: "chevron.left",
                                    help: UIString.prevRoundsPage.text(lang)) {
                        vm.pageRoundsBackward()
                    }
                }

                ForEach(rounds, id: \.self) { r in
                    roundChip(
                        label: chipLabel(round: r, lang: lang, tz: tz),
                        active: r == vm.focusedRound
                    ) {
                        vm.focusedRound = r
                    }
                }

                // 下一组轮次（窗口已经在最右，或轮次总数不足一屏时隐藏）
                if vm.roundWindowStart < vm.roundWindowMaxStart {
                    roundPageButton(systemName: "chevron.right",
                                    help: UIString.nextRoundsPage.text(lang)) {
                        vm.pageRoundsForward()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        // ⚠️ 必须有明确高度：嵌套在纵向 ScrollView 里的横向 ScrollView，
        // 没有高度约束会和父视图无限协商尺寸，布局阶段直接卡死主线程。
        // （同时它也给上面的 LazyHStack 提供了确定高度 —— 删掉会同时回归卡死 bug
        //  并让 lazy 容器算不出尺寸。）
        .frame(height: 32)
    }

    /// 轮次 chip bar 两端的圆形翻页按钮（`<` / `>`）。
    /// 两个按钮共用同一个实现，保证样式与无障碍文案口径一致。
    @ViewBuilder
    private func roundPageButton(systemName: String,
                                 help: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 单个轮次 chip 的文案：「MD N · M月d日」
    private func chipLabel(round: Int, lang: AppLanguage, tz: TimeZone) -> String {
        let date = vm.roundStart(round)
        let dateStr = date.map { formatShortDate($0, tz: tz, lang: lang) } ?? "—"
        return String(format: UIString.roundChipFormat.text(lang), round, dateStr)
    }

    @ViewBuilder
    private func roundChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(active
                        ? Color.primary.opacity(0.18)
                        : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: 本轮比赛分组（按日期）

    @ViewBuilder
    private func groupsSection(lang: AppLanguage, tz: TimeZone) -> some View {
        let sections = vm.groupedSections(tz: tz)
        // ⚠️ 这里必须是普通 VStack，不能是 LazyVStack：
        // lazy 容器向子视图提议的是「未确定宽度」，而 LazyVGrid 必须拿到确定宽度
        // 才能算出列数 → 行数 → 自身高度。两者叠加会让尺寸协商反复来回，
        // 主线程 100% 打满，表现为「数据加载完了但界面卡在转圈」。
        // 一轮最多 10 场、分组最多 4-5 个，全量渲染毫无压力。
        VStack(alignment: .leading, spacing: 22) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(formatDateHeader(section.date, tz: tz, lang: lang))
                        .font(.headline)
                        .padding(.leading, 2)

                    // ⚠️ maximum 必须是具体数值，不能是 .infinity：
                    // 无界上限同样会让 .adaptive 的列数计算发散。
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 320),
                                           spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(section.matches) { match in
                            MatchGridCard(match: match)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 赛季总览卡片

/// 单个轮次在赛季总览里的预览卡：
/// - 左上「第 N 轮」
/// - 右上 状态点（past=绿 / current=品牌粉 / future=灰 / unknown=灰）
/// - 第二行 起始日期「M月d日」
/// - 第三行起 至多 3 场预览（[crest] vs [crest] — score）
struct SeasonOverviewCard: View {
    @Environment(AppState.self) private var appState
    let snapshot: RoundSnapshot
    let lang: AppLanguage
    let tz: TimeZone
    let accent: Color

    var body: some View {
        let isCurrent = snapshot.progress == .current
        VStack(alignment: .leading, spacing: 6) {
            // 顶行：第 N 轮 + 状态点
            HStack {
                Text(String(format: UIString.roundN.text(lang), snapshot.round))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                statusDot
            }
            // 第二行：起始日期
            if let s = snapshot.startDate {
                Text(formatShortDate(s, tz: tz, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // 预览比赛区（至多 3 场）
            VStack(spacing: 4) {
                if snapshot.previews.isEmpty {
                    Text(UIString.noData.text(lang))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                } else {
                    ForEach(snapshot.previews) { m in
                        previewRow(m)
                        if m.id != snapshot.previews.last?.id {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isCurrent ? accent.opacity(0.6) : Color.primary.opacity(0.08),
                                      lineWidth: isCurrent ? 1.2 : 0.5)
                }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch snapshot.progress {
        case .past:     Circle().fill(Color.green.opacity(0.85)).frame(width: 8, height: 8)
        case .current:  Circle().fill(accent).frame(width: 8, height: 8)
        case .future:   Circle().fill(Color.primary.opacity(0.18)).frame(width: 8, height: 8)
        case .unknown:  Circle().fill(Color.primary.opacity(0.10)).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private func previewRow(_ m: Match) -> some View {
        HStack(spacing: 4) {
            CrestImage(urlString: m.homeTeam.crest)
                .frame(width: 16, height: 16)
            Text(UIString.seasonPreviewVs.text(lang))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            CrestImage(urlString: m.awayTeam.crest)
                .frame(width: 16, height: 16)
            Spacer(minLength: 4)
            if let h = m.score?.fullTime?.home, let a = m.score?.fullTime?.away {
                Text("\(h)-\(a)")
                    .font(.caption.monospacedDigit())
            } else {
                Text(formatKickoffShort(m.utcDate, tz: tz))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 比赛卡（本轮详情页用）

/// 单场比赛卡（截图风格：大字时间 + 主标 + 两行队名/比分）
struct MatchGridCard: View {
    @Environment(AppState.self) private var appState
    let match: Match

    var body: some View {
        let lang = appState.language
        let tz = TimeZone(identifier: appState.timeZone.identifier) ?? .current

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(formatKickoffShort(match.utcDate, tz: tz))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(UIString.homeBadge.text(lang))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            teamRow(
                crest: match.homeTeam.crest,
                name: match.homeTeam.displayName(chinese: appState.language == .chinese),
                score: homeScoreView(),
                isWinner: isHomeWinner
            )

            Divider()
                .padding(.vertical, 4)

            teamRow(
                crest: match.awayTeam.crest,
                name: match.awayTeam.displayName(chinese: appState.language == .chinese),
                score: awayScoreView(),
                isWinner: isAwayWinner
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private func teamRow(crest: String?, name: String, score: Text, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            CrestImage(urlString: crest)
                .frame(width: 20, height: 20)
            Text(name)
                .font(.system(size: 13, weight: isWinner ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            score
                .font(.system(size: 13, weight: isWinner ? .semibold : .regular))
                .monospacedDigit()
        }
    }

    private var isFinished: Bool {
        match.status == "FINISHED" ||
            match.score?.fullTime?.home != nil ||
            match.score?.fullTime?.away != nil
    }
    private var homeScore: Int? { match.score?.fullTime?.home }
    private var awayScore: Int? { match.score?.fullTime?.away }

    private var isHomeWinner: Bool {
        guard let h = homeScore, let a = awayScore, isFinished else { return false }
        return h > a
    }
    private var isAwayWinner: Bool {
        guard let h = homeScore, let a = awayScore, isFinished else { return false }
        return a > h
    }

    @ViewBuilder
    private func homeScoreView() -> Text {
        Text(displayScore(homeScore))
    }
    @ViewBuilder
    private func awayScoreView() -> Text {
        Text(displayScore(awayScore))
    }

    private func displayScore(_ s: Int?) -> String {
        guard let s else { return "" }
        return "\(s)"
    }
}

// MARK: - 旧版比赛卡（今日页与未来可能共用：主队 | 比分 | 客队 三栏）
//   保留不动：今日页与顶部比赛卡共用，旧版设计保留。
struct MatchCard: View {
    @Environment(AppState.self) private var appState
    let match: Match
    /// 球队靠两边（true）还是贴着中间比分（false，默认）。
    /// - `true`  = 主队靠卡片左边缘、客队靠卡片右边缘 —— **今日页**用（用户偏好：两队分开靠边）。
    /// - `false` = 主队靠右贴比分、客队靠左贴比分 —— **赛程页**用（让比分列竖直对齐，多条卡横向扫读更整齐）。
    var teamsFlankSides: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                CrestImage(urlString: match.homeTeam.crest)
                    .frame(width: 24, height: 24)
                Text(match.homeTeam.displayName(chinese: appState.language == .chinese))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: teamsFlankSides ? .leading : .trailing)

            scoreText
                .frame(width: 104, alignment: .center)

            HStack(spacing: 6) {
                Text(match.awayTeam.displayName(chinese: appState.language == .chinese))
                    .lineLimit(1)
                CrestImage(urlString: match.awayTeam.crest)
                    .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: teamsFlankSides ? .trailing : .leading)
        }
        .padding(8)
        .glassEffect()
    }

    private var scoreText: some View {
        let lang = appState.language
        return Group {
            if let home = match.score?.fullTime?.home,
               let away = match.score?.fullTime?.away {
                HStack(spacing: 4) {
                    if TodayFilter.isLive(match, now: Date()) {
                        Image(systemName: "soccerball")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    Text("\(home) - \(away)").bold()
                }
            } else if TodayFilter.isLive(match, now: Date()) {
                HStack(spacing: 4) {
                    Image(systemName: "soccerball")
                        .foregroundStyle(.red)
                        .font(.footnote)
                    Text(match.status == "HALFTIME" ? UIString.halftime.text(lang) : UIString.live.text(lang))
                        .foregroundStyle(.red)
                }
            } else if match.status == "POSTPONED"
                        || match.status == "CANCELED"
                        || match.status == "CANCELLED" {
                Text(match.status == "POSTPONED" ? UIString.postponed.text(lang) : UIString.canceled.text(lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(formatKickoff(match.utcDate, tz: appState.timeZone, lang: lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 把开球时间按所选时区显示为「HH:mm」
private func formatKickoffShort(_ utcDate: String?, tz: TimeZone) -> String {
    guard let d = parseKickoffDate(utcDate) else { return "" }
    let df = FormatterPool.shared.formatter(tz: tz, localeID: "en_US", format: "HH:mm")
    return df.string(from: d)
}

// MARK: - 解析与格式化（共享）

/// 解析 ISO8601 开球时间
func parseKickoffDate(_ utcDate: String?) -> Date? {
    guard let utcDate else { return nil }
    // 走缓存池里的静态解析器：这里在 body 求值路径上每场比赛都会被调用
    let pool = FormatterPool.shared
    return pool.isoBasic.date(from: utcDate) ?? pool.isoFractional.date(from: utcDate)
}

/// 把 ISO8601 开球时间按所选时区换算为「日期 时间」文本
func formatKickoff(_ utcDate: String?, tz: DisplayTimeZone, lang: AppLanguage) -> String {
    guard let d = parseKickoffDate(utcDate) else { return UIString.tbd.text(lang) }
    let df = FormatterPool.shared.formatter(
        tz: TimeZone(identifier: tz.identifier) ?? .current,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "MMM d HH:mm" : "M月d日 HH:mm")
    return df.string(from: d)
}
