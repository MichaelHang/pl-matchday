import SwiftUI

// MARK: - App 入口

@main
struct EPLViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                // 最小高度按「积分榜完整显示 20 队」估算：表头 + 20 行 ≈ 600，
                // 加上导航栏 toolbar(~52) 与列表内边距，取 675 留出余量。
                // 不再为 ScrollView 兜底而撑得更大（之前 680 → 240 那次改太极端了）。
                .frame(minWidth: 900, minHeight: 675)
        }
    }
}

// MARK: - 界面语言
/// 全局界面语言定义见 UIStrings.swift（AppLanguage 枚举 + UIString 集中文案表）

// MARK: - 全局应用状态

/// 全局可观察状态（使用 Observation 框架 @Observable）
/// 标 @MainActor 让所有访问在主 actor 内，避免跨 actor 数据竞争；
/// SwiftUI 的 .environment() 与 @Environment 在 macOS 26 SDK 下可正常解析。
@MainActor
@Observable
final class AppState {
    /// 让玩家中文名覆盖层在启动期即 eager 加载（读取磁盘已有覆盖）。可选但稳妥。
    init() { let _ = PlayerNameStore.shared }

    /// 主板块枚举
    enum AppSection: String, CaseIterable, Identifiable {
        // 顺序即侧边栏显示顺序：今日 → 赛程 → 积分榜 → …
        case today, fixtures, standings, leaders, injuries, settings
        var id: String { rawValue }

        func title(_ lang: AppLanguage) -> String {
            switch self {
            case .today:     return UIString.today.text(lang)
            case .standings: return UIString.standings.text(lang)
            case .fixtures:  return UIString.fixtures.text(lang)
            case .leaders:   return UIString.leaders.text(lang)
            case .injuries:  return UIString.injuries.text(lang)
            case .settings:  return UIString.settings.text(lang)
            }
        }

        var systemImage: String {
            switch self {
            case .today:     return "clock.badge.checkmark"
            case .standings: return "tablecells"
            case .fixtures:  return "calendar"
            case .leaders:   return "soccerball"
            case .injuries:  return "bandage"
            case .settings:  return "gearshape"
            }
        }
    }

    /// 默认落地页：今日（当天比赛总览，打开 app 第一眼就看到）
    var selected: AppSection = .today
    /// 当前赛季（写死为 2026-27 赛季；不做赛季切换 UI，避免干扰当前任务）
    var season: String { SeasonStore.currentSeason }
    /// 界面语言（持久化到 UserDefaults；默认中文，切换即时生效，不触发重新拉数据）
    var language: AppLanguage =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "epl_language") ?? "") ?? .chinese {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "epl_language")
        }
    }
    var source: DataSource = .sample
    /// 60s 自动刷新开关（持久化到 UserDefaults；默认关闭）。
    /// `Bool` 直接读写，key 与既有 `epl_language` / `epl_timezone` 命名一致。
    var autoRefresh: Bool =
        UserDefaults.standard.bool(forKey: "epl_autorefresh") {
        didSet {
            UserDefaults.standard.set(autoRefresh, forKey: "epl_autorefresh")
        }
    }
    /// 「比赛期间自动刷新」开关（持久化到 UserDefaults；**默认开启**）。
    /// 与 `autoRefresh` 互相独立：`autoRefresh` 为开时本项在 UI 上被 disable（全局已 60s，无意义）；
    /// `autoRefresh` 为关时本项开 → 只在有比赛进行中时 60s 轮询，没比赛则**睡到下一场开球前**
    /// （见 `AutoRefreshScheduler`）。key 命名与既有 `epl_*` 一致。
    ///
    /// ⚠️ **默认开**：新装、或从未动过这项设置的用户，进来就是勾上状态。
    /// 所以判定必须用 `object(forKey:) == nil` 走三态，不能直接用 `bool(forKey:)` ——
    /// 后者对「key 不存在」和「用户显式关掉（已存 false）」**都返回 false**，无法区分，
    /// 会退化成「永远默认关」或「用户关掉后一重启又被顶回开」。
    /// 一旦用户拨过开关，`didSet` 立刻写入真值，此后按存值走、不再受默认值影响。
    var autoRefreshDuringMatches: Bool =
        AppState.persistedBool(forKey: "epl_autorefresh_matches", defaultWhenAbsent: true) {
        didSet {
            UserDefaults.standard.set(autoRefreshDuringMatches, forKey: "epl_autorefresh_matches")
        }
    }

    /// 读取持久化的 Bool，并把「key 不存在」与「存了 false」区分开（见 `autoRefreshDuringMatches`）。
    /// 静态成员不参与 `@Observable` 的属性观察（只有实例存储属性才会被宏改写），因此这里安全。
    private static func persistedBool(forKey key: String, defaultWhenAbsent: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultWhenAbsent }
        return UserDefaults.standard.bool(forKey: key)
    }
    var isLoading: Bool = false
    /// 赛程展示时区（持久化到 UserDefaults；默认北京时间，切换即时生效）
    var timeZone: DisplayTimeZone =
        DisplayTimeZone(rawValue: UserDefaults.standard.string(forKey: "epl_timezone") ?? "") ?? .shanghai {
        didSet {
            UserDefaults.standard.set(timeZone.rawValue, forKey: "epl_timezone")
        }
    }
    /// 刷新计数：自增即可触发各视图的 .task(id:) 重新拉取
    var refreshNonce: Int = 0
    /// 60s 自动刷新定时器（开启时定期调用 refresh()，用于比赛期间实时比分）
    /// 用 @ObservationIgnored 避免 Observation 框架试图追踪 Timer 引用
    @ObservationIgnored
    private var refreshTimer: Timer?

    /// 最近一次由视图回报的调度状态（是否有比赛进行中 / 下一场开球时间）。
    /// 由 `reportLiveSchedule(from:)` / `refreshTick()` 按当前时刻**现算**，驱动 `configureAutoRefresh()`。
    var liveSchedule = RefreshSchedule(hasLiveMatch: false, nextKickoff: nil)
    /// 最近一次已知的全量赛程。定时器每次唤醒时用它 + 当前时刻**重新**算 schedule ——
    /// 因为 schedule 依赖 `now`，只看存下来的 `liveSchedule` 是不够的（见 `refreshTick`）。
    /// 全量数组是 COW 值语义，这里只是持有引用，不额外占内存。
    var lastKnownMatches: [Match] = []

    /// 主动刷新：默认「全量」—— 清空所有本地缓存后自增 refreshNonce，各视图重拉必走网络，
    /// 不受 CacheTTL「懒刷新」阈值约束（被动取数如切 tab / 启动不清除缓存，遵循 5 分钟窗口）。
    ///
    /// `scoresOnly: true` 供「比赛期间自动刷新」定时器专用：只失效**赛程**缓存（比分来源），
    /// 保留 bootstrap / 积分榜等其它缓存，避免每 60s 重下整份 FPL bootstrap。
    /// UI 实时性不变（比分只来自赛程），但每 60s 网络开销从 3 份降到 1 份。
    func refresh(scoresOnly: Bool = false) async {
        if scoresOnly {
            await DataRepository.invalidateFixtures()
        } else {
            await DataRepository.clearCache()
        }
        refreshNonce &+= 1
    }

    /// 重建自动刷新定时器。间隔由 `AutoRefreshScheduler.refreshInterval(...)` 决定：
    /// - 全局 `autoRefresh == true` → 固定 60s；
    /// - 否则「比赛期间」开且有比赛进行中 → 60s；
    /// - 否则没比赛 → 睡到下一场开球前（提前 15 分钟），无赛程则 `maxIdleSleep` 兜底；
    /// - 「比赛期间」关 → 不设定时器。
    /// 由 SettingsView 的 Toggle `.onChange`、ContentView 的 `.task`、`reportLiveSchedule(from:)` 调用。
    @MainActor
    func configureAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let interval = AutoRefreshScheduler.refreshInterval(
            autoRefresh: autoRefresh,
            duringMatches: autoRefreshDuringMatches,
            schedule: liveSchedule,
            now: Date()
        )
        guard let interval else { return }
        // tick 每次唤醒做两件事：刷新数据 + **按当前时刻重算间隔**（见 `refreshTick()`）。
        // 重算必须发生在 tick 里 —— 原因见 `refreshTick()` 的注释（这是本功能唯一目标场景的命门）。
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// 定时器每次唤醒：刷新数据 → **按当前时刻重算 schedule 与间隔** → 重建定时器。
    ///
    /// ⚠️ 必须**无条件**重算（不能只靠 `reportLiveSchedule` 那种「内容变了才重建」的去抖），
    /// 有两个独立理由，踩过两次：
    ///
    /// 1. **间隔随 `now` 单调不增，但 schedule 内容可能不变**。
    ///    「睡到开球前 15 分钟」醒来时，schedule 内容与睡前**完全相同**（`hasLiveMatch` 仍 false、
    ///    `nextKickoff` 仍是同一场）→ 基于内容比较的去抖会早退 → 继续按旧的 6300s 睡下去，
    ///    **直接睡过整场比赛**（要到开球后 90 分钟才醒）。
    /// 2. **`hasLiveMatch` 是按开球时间窗判定的，必须重算才会随时间演进**。
    ///    `RefreshSchedule.hasLiveMatch` 只是个存储 Bool，**不会自己翻转**。若停在不上报赛程的
    ///    tab（积分榜 / 设置 / 球员榜 / 伤停），`liveSchedule` 会被冻结；不重算的话，
    ///    比赛全部结束后仍会**永久保持 60s 轮询**（清缓存 + 重拉 + 转圈），浪费网络与电量。
    ///
    /// 用「可能过期的 `lastKnownMatches`」重算是安全且**故意**的：
    /// `untilWake = nextKickoff − now − kickoffLeadTime` 随 `now` **单调不增** ⇒
    /// 重算出的间隔**永不比上次更长**（下限被 `liveInterval` 兜住，不会退化成 0 / 负数导致密集触发），
    /// 所以只会「提前醒」不会「睡过头」。
    private func refreshTick() async {
        // 比赛期间轮询：只刷新赛程（比分来源），不清整份 bootstrap / 积分榜（见 refresh(scoresOnly:)）。
        await refresh(scoresOnly: true)
        liveSchedule = AutoRefreshScheduler.schedule(matches: lastKnownMatches, now: Date())
        configureAutoRefresh()
    }

    /// 由视图取数后回报**最新赛程**；AppState 自行按当前时刻算 schedule，内容没变则 no-op（去抖）。
    ///
    /// ⚠️ 传的是 `matches` 而不是现成的 `RefreshSchedule`：因为 schedule 依赖 `now`，
    /// 必须让 AppState 自己现算，才能与 `refreshTick()` 的重算保持同一套逻辑
    /// （否则「睡到开球前」的间隔演进会退化成只在视图回报时才更新）。
    ///
    /// ⚠️ 该去抖只覆盖「视图回报」这条路径；定时器唤醒后的演进由 `refreshTick()` **无条件**重算，
    /// 不受此早退影响（两个独立理由见 `refreshTick` 注释）。
    /// 说明：`AppState` 实为 `@MainActor` 类（类级标注），显式 `@MainActor` 属冗余但无害，保留以示意图。
    /// 调用点都在主线程（视图 `.task`）。
    @MainActor
    func reportLiveSchedule(from matches: [Match]) {
        lastKnownMatches = matches
        let s = AutoRefreshScheduler.schedule(matches: matches, now: Date())
        guard s != liveSchedule else { return }
        liveSchedule = s
        configureAutoRefresh()
    }
}

// MARK: - 主容器（NavigationSplitView）

/// 左侧栏 + 右侧内容的分栏布局
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            Sidebar()
                .navigationTitle(String(format: UIString.appTitle.text(appState.language),
                                        SeasonStore.seasonLabel))
        } detail: {
            DetailView()
                .toolbar { TopBar() }
        }
        .navigationSplitViewStyle(.balanced)
        // ⚠️ 从 UserDefaults 恢复 `autoRefresh == true` 时，SettingsView 里 Toggle 的 `.onChange`
        // 不会触发（值在视图构造前就已是 true），定时器会漏建 → 出现「UI 显示已开启、但没有
        // timer」的不一致。这里在根视图出现时补配置一次：true 就建 timer，false 则安全 no-op。
        .task { appState.configureAutoRefresh() }
    }
}

/// 根据选中板块切换右侧内容
struct DetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Group {
            switch appState.selected {
            case .today:     TodayView()
            case .standings: StandingsView()
            case .fixtures:  FixturesView()
            case .leaders:   LeadersView()
            case .injuries:  InjuriesView()
            case .settings:  SettingsView()
            }
        }
    }
}

// MARK: - 设置面板

/// 设置页面（赛季 / 自动刷新 / 缓存管理），玻璃质感
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var clearing = false
    #if DEBUG
    @State private var showingNameManager = false
    #endif

    var body: some View {
        @Bindable var appState = appState
        Form {
            // 当前 App 只 focus 在 2026-27 赛季，不开放赛季切换；
            // 如未来要支持历史赛季，可恢复以下 Section：
            //   Section("赛季") {
            //       Picker("赛季", selection: $appState.season) { ... }
            //   }
            Section(UIString.currentSeason.text(appState.language)) {
                LabeledContent(UIString.season.text(appState.language), value: "2026-27")
            }

            Section(UIString.interfaceLang.text(appState.language)) {
                Picker(UIString.interfaceLang.text(appState.language), selection: $appState.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(UIString.refresh.text(appState.language)) {
                Toggle(UIString.autoRefresh.text(appState.language), isOn: $appState.autoRefresh)
                    .onChange(of: appState.autoRefresh) { _, _ in
                        appState.configureAutoRefresh()
                    }
                Toggle(UIString.autoRefreshDuringMatches.text(appState.language),
                       isOn: $appState.autoRefreshDuringMatches)
                    // 全局自动刷新已开时本项无意义（已经每 60s），灰掉并给出脚注说明。
                    .disabled(appState.autoRefresh)
                    .onChange(of: appState.autoRefreshDuringMatches) { _, _ in
                        appState.configureAutoRefresh()
                    }
                if appState.autoRefresh {
                    Text(UIString.autoRefreshDuringMatchesHint.text(appState.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label(UIString.refreshNow.text(appState.language), systemImage: "arrow.clockwise")
                }
            }

            Section(UIString.timezone.text(appState.language)) {
                Picker(UIString.timezone.text(appState.language), selection: $appState.timeZone) {
                    ForEach(DisplayTimeZone.allCases) { tz in
                        Text(tz.label(appState.language)).tag(tz)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(UIString.cache.text(appState.language)) {
                Button(role: .destructive) {
                    clearing = true
                    Task {
                        await appState.refresh()
                        clearing = false
                    }
                } label: {
                    if clearing {
                        ProgressView()
                    } else {
                        Label(UIString.clearCache.text(appState.language), systemImage: "trash")
                    }
                }
            }

            #if DEBUG
            Section {
                Button {
                    showingNameManager = true
                } label: {
                    Label(UIString.debugPlayerNamesManage.text(appState.language),
                          systemImage: "person.text.rectangle")
                }
            } header: {
                Text(UIString.debugPlayerNamesTitle.text(appState.language))
            }
            #endif

            Section {
                Text(UIString.dataSourceDesc.text(appState.language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(UIString.settings.text(appState.language))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        .sheet(isPresented: $showingNameManager) {
            PlayerNameManagerView()
        }
        #endif
        // 注意：不要再在 Form 上叠 .glassEffect()。
        //   .formStyle(.grouped) 已有自己的分组材质，叠 .glassEffect() 在 macOS 26 会渲染成
        //   巨大的椭圆玻璃底（曾经因此出现"设置页面背景一个圆圈"的视觉 bug）。
        //   真要玻璃质感，加在某个 Section/Button 局部即可。
    }
}

