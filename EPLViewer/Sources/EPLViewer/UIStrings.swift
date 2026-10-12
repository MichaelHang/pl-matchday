import Foundation

// MARK: - 界面语言

/// 全局界面语言（设置页可切换中英文；默认中文）
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "中文"
    case english = "英文"
    var id: String { rawValue }
    /// 选择器展示标签：用自身语言书写（中文 / English），而非直译
    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

// MARK: - 显示时区

/// 可选择的显示时区（设置页切换；赛程时间按所选时区换算展示）
/// 默认北京时间，符合国内用户习惯；伦敦为当地开球时间，UTC 为原始数据。
enum DisplayTimeZone: String, CaseIterable, Identifiable {
    case shanghai = "Asia/Shanghai"
    case london   = "Europe/London"
    case utc      = "UTC"
    case newyork  = "America/New_York"
    var id: String { rawValue }
    /// 底层 IANA 时区标识符，交给 TimeZone(identifier:) 使用
    var identifier: String { rawValue }
    /// 选择器展示标签（中英跟随界面语言）
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .shanghai: return lang == .english ? "Beijing (GMT+8)" : "北京时间"
        case .london:   return lang == .english ? "London" : "伦敦"
        case .utc:      return "UTC"
        case .newyork:  return lang == .english ? "New York (ET)" : "纽约（美东）"
        }
    }
}

// MARK: - 集中文案（中英对照）

/// 所有 UI 可见文案集中在此，便于中英切换与审阅。
/// 用法：`UIString.standings.text(appState.language)`
struct UIString {
    let zh: String
    let en: String
    func text(_ lang: AppLanguage) -> String {
        lang == .english ? en : zh
    }
}

extension UIString {
    // 侧边栏板块
    static let standings = UIString(zh: "积分榜", en: "Standings")
    static let today     = UIString(zh: "今日", en: "Today")
    static let fixtures  = UIString(zh: "赛程", en: "Fixtures")
    /// 侧边栏 tab + 页面标题。原名「射手 · 助攻榜」，用户要求改叫「球员榜」（内容仍是射手/助攻两块）。
    static let leaders   = UIString(zh: "球员榜", en: "Players")
    static let injuries  = UIString(zh: "伤停榜", en: "Injuries")
    static let settings  = UIString(zh: "设置", en: "Settings")
    /// 应用主标题（侧边栏 / 详情页），用 `%@` 占位符填赛季标签（如 "2026-2027"）。
    /// 例：zh 渲染 → "2026-2027 英超联赛"；en 渲染 → "EPL 2026-2027"
    static let appTitle  = UIString(zh: "%@ 英超联赛", en: "EPL %@")

    // 设置页
    static let currentSeason = UIString(zh: "当前赛季", en: "Current Season")
    static let season        = UIString(zh: "赛季", en: "Season")
    static let interfaceLang = UIString(zh: "界面语言", en: "Interface Language")
    static let timezone      = UIString(zh: "时区", en: "Time Zone")
    static let refresh       = UIString(zh: "刷新", en: "Refresh")
    static let autoRefresh   = UIString(zh: "自动刷新（60s 节流）", en: "Auto-refresh (60s)")
    static let autoRefreshDuringMatches     = UIString(zh: "比赛期间自动刷新", en: "Auto-refresh during matches")
    static let autoRefreshDuringMatchesHint = UIString(zh: "已开启全局自动刷新，此项无需设置", en: "Global auto-refresh is on; this setting is not needed")
    static let refreshNow    = UIString(zh: "立即刷新所有", en: "Refresh All Now")
    static let cache         = UIString(zh: "缓存", en: "Cache")
    static let clearCache    = UIString(zh: "清空本地缓存", en: "Clear Local Cache")
    static let dataSourceDesc = UIString(
        zh: "数据来源：ESPN 公开接口（积分榜/赛程/赛果）+ FPL 公开接口（球员/射手/助攻/伤停）。无需 API Key；断网时自动回退上次缓存的数据，无缓存则显示空状态。",
        en: "Data source: ESPN public API (standings / fixtures / results) + FPL public API (players / scorers / assists / injuries). No API Key required; offline falls back to the last cached data, or an empty state if no cache exists."
    )

    // 积分榜表头
    static let pos      = UIString(zh: "名次", en: "Pos")
    static let team     = UIString(zh: "球队", en: "Team")
    static let played   = UIString(zh: "场", en: "P")
    static let won      = UIString(zh: "胜", en: "W")
    static let drawn    = UIString(zh: "平", en: "D")
    static let lost     = UIString(zh: "负", en: "L")
    static let goalsFor = UIString(zh: "进", en: "GF")
    static let goalsAg  = UIString(zh: "失", en: "GA")
    static let goalDiff = UIString(zh: "净", en: "GD")
    static let points   = UIString(zh: "积分", en: "Pts")
    static let noStandings = UIString(zh: "暂无积分榜数据", en: "No standings data")

    // 积分榜 tab 切换
    static let standingsTabOverall = UIString(zh: "总览",   en: "Overall")
    static let standingsTabHome    = UIString(zh: "主场", en: "Home")
    static let standingsTabAway    = UIString(zh: "客场", en: "Away")
    static let standingsTabForm    = UIString(zh: "状态", en: "Form")
    /// 主场/客场数据暂不可用时显示的占位
    static let standingsDash       = UIString(zh: "—",     en: "—")

    // 赛程
    static let roundN         = UIString(zh: "第 %d 轮", en: "Round %d")
    static let noFixtures     = UIString(zh: "暂无赛程", en: "No fixtures")
    static let noRoundMatches = UIString(zh: "该轮次暂无比赛", en: "No matches in this round")
    static let tbd            = UIString(zh: "待定", en: "TBD")
    // 比赛状态标签（进行中 / 中场 / 延期 / 取消）
    static let live           = UIString(zh: "进行中", en: "LIVE")
    static let halftime       = UIString(zh: "中场", en: "HT")
    static let postponed      = UIString(zh: "延期", en: "Postponed")
    static let canceled       = UIString(zh: "取消", en: "Canceled")

    // 赛程页（按截图布局：第 N 轮 · 赛程 大标题 + 日期范围副标题 + 本轮/赛季总览 模式 + 轮次 chip）
    /// 大标题「第 32 轮 · 赛程」（%d 为轮次号）
    static let fixturesHeader       = UIString(zh: "第 %d 轮 · 赛程", en: "Matchday %d · Fixtures")
    /// 模式切换：本轮
    static let modeThisRound        = UIString(zh: "本轮", en: "This Round")
    /// 模式切换：赛季总览
    static let modeSeason           = UIString(zh: "赛季总览", en: "Season Overview")
    /// 轮次 chip 文本：中文「第 1 轮 · 8月21」，英文沿用英超惯例缩写「MD 1 · 8月21」
    static let roundChipFormat      = UIString(zh: "第 %d 轮 · %@", en: "MD %d · %@")
    /// chip bar 翻页按钮的无障碍提示。
    /// 纯动作描述、不带参数 —— 翻页的目标轮次由当前窗口决定，写死数字反而误导。
    static let prevRoundsPage       = UIString(zh: "上一组轮次", en: "Previous rounds")
    static let nextRoundsPage       = UIString(zh: "下一组轮次", en: "Next rounds")
    /// 「主队赛事」右上角小标识
    static let homeBadge            = UIString(zh: "主", en: "H")

    // 赛季总览页
    /// 「2026 赛季」标题（%d 为开赛年份）
    static let seasonHeader        = UIString(zh: "%d 赛季", en: "%d Season")
    /// 「VS」
    static let seasonPreviewVs     = UIString(zh: "VS", en: "VS")

    // 今日
    static let statusUpcoming = UIString(zh: "未开赛", en: "Upcoming")
    static let statusFinished = UIString(zh: "已结束", en: "Finished")
    /// 大标题「今日 · 8月31日」（%@ 为日期）
    static let todayTitleFormat = UIString(zh: "今日 · %@", en: "Today · %@")
    /// 副标题「第 2 轮 · 共 10 场 · 0 场进行中」（三个 %d 依次为 轮次 / 今日场次 / 进行中）
    static let todaySubtitleFormat = UIString(
        zh: "第 %d 轮 · 共 %d 场 · %d 场进行中",
        en: "Round %d · %d matches · %d live"
    )
    /// 第四行两列标题
    static let colLiveAndRecent = UIString(zh: "正在进行中 & 近期", en: "Live & Recent")
    /// 没有直播时，第一列只显示今日已结束
    static let colRecent      = UIString(zh: "近期", en: "Recent")
    /// 第四行小卡片右上角的「查看全部」链接，点击跳到赛程板块
    static let viewAll        = UIString(zh: "查看全部", en: "View All")
    /// 第四行小卡片空内容占位
    static let noData         = UIString(zh: "暂无数据", en: "No data")
    static let colTodayUpcoming = UIString(zh: "今日开赛", en: "Today's Fixtures")

    // 射手 / 助攻
    static let goals     = UIString(zh: "进球", en: "Goals")
    static let assists   = UIString(zh: "助攻", en: "Assists")
    static let goalUnit  = UIString(zh: "球", en: "G")
    static let assistUnit = UIString(zh: "助", en: "A")
    static let noScorers = UIString(zh: "暂无射手榜", en: "No top scorers")
    static let noAssists = UIString(zh: "暂无助攻榜", en: "No assists list")

    // 伤停
    static let noInjuries  = UIString(zh: "暂无伤停", en: "No injuries")
    static let nextRound   = UIString(zh: "下轮", en: "Next")
    static let playChance  = UIString(zh: "出战概率 %d%%", en: "Chance to play %d%%")
    static let stInjured   = UIString(zh: "伤", en: "Inj")
    static let stDoubtful  = UIString(zh: "存疑", en: "Doubt")
    static let stOut       = UIString(zh: "缺阵", en: "Out")
    static let stSuspended = UIString(zh: "停赛", en: "Susp")
    static let stUnreg     = UIString(zh: "未注册", en: "Unreg")

    // 通用
    static let loading    = UIString(zh: "加载中…", en: "Loading…")
    static let loadFailed = UIString(zh: "加载失败", en: "Failed to load")

    // MARK: - 调试面板（仅 DEBUG 编译进设置页；文案集中此处，便于中英切换）
    /// 设置页 DEBUG 区块标题
    static let debugPlayerNamesTitle        = UIString(zh: "球员中文名覆盖（调试）", en: "Player Name Overrides (DEBUG)")
    /// 设置页入口按钮文案
    static let debugPlayerNamesManage        = UIString(zh: "管理球员译名…", en: "Manage Player Names…")
    /// 管理器标题（sheet / 分栏导航标题）
    static let debugPlayerNamesManagerTitle  = UIString(zh: "球员中文名", en: "Player Names")
    /// 放弃修改按钮
    static let debugPlayerNamesDiscard       = UIString(zh: "放弃修改", en: "Discard Changes")
    /// 关闭按钮（sheet 取消/关闭）
    static let debugPlayerNamesClose         = UIString(zh: "关闭", en: "Close")
    /// 已保存提示（点保存后短暂显示）
    static let debugPlayerNamesSaved         = UIString(zh: "已保存", en: "Saved")
    /// 有未保存修改提示
    static let debugPlayerNamesUnsaved       = UIString(zh: "有未保存的修改", en: "Unsaved changes")
    /// 未选球队时的占位提示
    static let debugPlayerNamesSelectTeam    = UIString(zh: "从左侧选择一支球队查看球员", en: "Select a team to view its players")
    /// 覆盖徽标
    static let debugPlayerNamesOverrideBadge = UIString(zh: "覆盖", en: "Override")
    /// 保存按钮
    static let debugPlayerNamesSave          = UIString(zh: "保存", en: "Save")
}
