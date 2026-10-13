import Foundation

// MARK: - Interface language

/// Global interface language (switchable in Settings; Chinese by default).
enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "中文"
    case english = "英文"
    var id: String { rawValue }
    /// Picker label written in its own language (中文 / English), not translated.
    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

// MARK: - Display time zone

/// Selectable display time zone (Settings; fixture times convert accordingly).
/// Beijing by default for Chinese users; London = local kickoff time, UTC = raw data.
enum DisplayTimeZone: String, CaseIterable, Identifiable {
    case shanghai = "Asia/Shanghai"
    case london   = "Europe/London"
    case utc      = "UTC"
    case newyork  = "America/New_York"
    var id: String { rawValue }
    /// Underlying IANA identifier for TimeZone(identifier:).
    var identifier: String { rawValue }
    /// Picker label (follows the interface language).
    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .shanghai: return lang == .english ? "Beijing (GMT+8)" : "北京时间"
        case .london:   return lang == .english ? "London" : "伦敦"
        case .utc:      return "UTC"
        case .newyork:  return lang == .english ? "New York (ET)" : "纽约（美东）"
        }
    }
}

// MARK: - Centralized copy (zh/en pairs)

/// All UI-visible copy lives here for easy switching and review.
/// Usage: `UIString.standings.text(appState.language)`
struct UIString {
    let zh: String
    let en: String
    func text(_ lang: AppLanguage) -> String {
        lang == .english ? en : zh
    }
}

extension UIString {
    // Sidebar sections
    static let standings = UIString(zh: "积分榜", en: "Standings")
    static let today     = UIString(zh: "今日", en: "Today")
    static let fixtures  = UIString(zh: "赛程", en: "Fixtures")
    /// Sidebar tab + page title. Renamed to "Players" at the user's request
    /// (contents are still the scorer/assist leaderboards).
    static let leaders   = UIString(zh: "球员榜", en: "Players")
    static let injuries  = UIString(zh: "伤停榜", en: "Injuries")
    static let settings  = UIString(zh: "设置", en: "Settings")
    /// App title (sidebar / detail pages); %@ takes the season label ("2026-2027").
    /// zh renders "2026-2027 英超联赛"; en renders "EPL 2026-2027".
    static let appTitle  = UIString(zh: "%@ 英超联赛", en: "EPL %@")

    // Settings
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

    // Standings headers
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

    // Standings tabs
    static let standingsTabOverall = UIString(zh: "总览",   en: "Overall")
    static let standingsTabHome    = UIString(zh: "主场", en: "Home")
    static let standingsTabAway    = UIString(zh: "客场", en: "Away")
    static let standingsTabForm    = UIString(zh: "状态", en: "Form")
    /// Placeholder when home/away data is unavailable.
    static let standingsDash       = UIString(zh: "—",     en: "—")

    // Fixtures
    static let roundN         = UIString(zh: "第 %d 轮", en: "Round %d")
    static let noFixtures     = UIString(zh: "暂无赛程", en: "No fixtures")
    static let noRoundMatches = UIString(zh: "该轮次暂无比赛", en: "No matches in this round")
    static let tbd            = UIString(zh: "待定", en: "TBD")
    // Match status labels (live / halftime / postponed / canceled)
    static let live           = UIString(zh: "进行中", en: "LIVE")
    static let halftime       = UIString(zh: "中场", en: "HT")
    static let postponed      = UIString(zh: "延期", en: "Postponed")
    static let canceled       = UIString(zh: "取消", en: "Canceled")

    // Fixtures page (screenshot layout: big title + mode pills + round chips)
    /// Big title "Round 32 · Fixtures" (%d = round number)
    static let fixturesHeader       = UIString(zh: "第 %d 轮 · 赛程", en: "Matchday %d · Fixtures")
    /// Mode switch: this round
    static let modeThisRound        = UIString(zh: "本轮", en: "This Round")
    /// Mode switch: season overview
    static let modeSeason           = UIString(zh: "赛季总览", en: "Season Overview")
    /// Round chip: zh "第 1 轮 · 8月21", en follows the PL convention "MD 1 · 8月21"
    static let roundChipFormat      = UIString(zh: "第 %d 轮 · %@", en: "MD %d · %@")
    /// Accessibility help for the chip-bar paging buttons.
    /// Pure action descriptions without parameters — the paged-to rounds depend on
    /// the current window; hardcoding numbers would mislead.
    static let prevRoundsPage       = UIString(zh: "上一组轮次", en: "Previous rounds")
    static let nextRoundsPage       = UIString(zh: "下一组轮次", en: "Next rounds")
    /// Small "home" badge on a match card.
    static let homeBadge            = UIString(zh: "主", en: "H")

    // Season overview page
    /// "2026 Season" title (%d = the season's starting year)
    static let seasonHeader        = UIString(zh: "%d 赛季", en: "%d Season")
    /// "VS"
    static let seasonPreviewVs     = UIString(zh: "VS", en: "VS")

    // Today
    static let statusUpcoming = UIString(zh: "未开赛", en: "Upcoming")
    static let statusFinished = UIString(zh: "已结束", en: "Finished")
    /// Large title "Today · Aug 31" (%@ = the date)
    static let todayTitleFormat = UIString(zh: "今日 · %@", en: "Today · %@")
    /// Subtitle "Round 2 · 10 matches · 0 live" (round / total / live)
    static let todaySubtitleFormat = UIString(
        zh: "第 %d 轮 · 共 %d 场 · %d 场进行中",
        en: "Round %d · %d matches · %d live"
    )
    /// Bottom-row column titles
    static let colLiveAndRecent = UIString(zh: "正在进行中 & 近期", en: "Live & Recent")
    /// With no live matches, column 1 shows only today's finished matches.
    static let colRecent      = UIString(zh: "近期", en: "Recent")
    /// "View all" link on the column cards; jumps to the fixtures section.
    static let viewAll        = UIString(zh: "查看全部", en: "View All")
    /// Empty placeholder inside a column card.
    static let noData         = UIString(zh: "暂无数据", en: "No data")
    static let colTodayUpcoming = UIString(zh: "今日开赛", en: "Today's Fixtures")

    // Scorers / assists
    static let goals     = UIString(zh: "进球", en: "Goals")
    static let assists   = UIString(zh: "助攻", en: "Assists")
    static let goalUnit  = UIString(zh: "球", en: "G")
    static let assistUnit = UIString(zh: "助", en: "A")
    static let noScorers = UIString(zh: "暂无射手榜", en: "No top scorers")
    static let noAssists = UIString(zh: "暂无助攻榜", en: "No assists list")

    // Injuries
    static let noInjuries  = UIString(zh: "暂无伤停", en: "No injuries")
    static let nextRound   = UIString(zh: "下轮", en: "Next")
    static let playChance  = UIString(zh: "出战概率 %d%%", en: "Chance to play %d%%")
    static let stInjured   = UIString(zh: "伤", en: "Inj")
    static let stDoubtful  = UIString(zh: "存疑", en: "Doubt")
    static let stOut       = UIString(zh: "缺阵", en: "Out")
    static let stSuspended = UIString(zh: "停赛", en: "Susp")
    static let stUnreg     = UIString(zh: "未注册", en: "Unreg")

    // Common
    static let loading    = UIString(zh: "加载中…", en: "Loading…")
    static let loadFailed = UIString(zh: "加载失败", en: "Failed to load")

    // MARK: - DEBUG panel (DEBUG builds only; copy centralized here for zh/en switching)
    /// DEBUG section title in Settings
    static let debugPlayerNamesTitle        = UIString(zh: "球员中文名覆盖（调试）", en: "Player Name Overrides (DEBUG)")
    /// Settings entry button
    static let debugPlayerNamesManage        = UIString(zh: "管理球员译名…", en: "Manage Player Names…")
    /// Manager title (sheet / split navigation)
    static let debugPlayerNamesManagerTitle  = UIString(zh: "球员中文名", en: "Player Names")
    /// Discard button
    static let debugPlayerNamesDiscard       = UIString(zh: "放弃修改", en: "Discard Changes")
    /// Close button (sheet cancel/close)
    static let debugPlayerNamesClose         = UIString(zh: "关闭", en: "Close")
    /// Saved flash (shown briefly after saving)
    static let debugPlayerNamesSaved         = UIString(zh: "已保存", en: "Saved")
    /// Unsaved-changes hint
    static let debugPlayerNamesUnsaved       = UIString(zh: "有未保存的修改", en: "Unsaved changes")
    /// Placeholder when no team is selected
    static let debugPlayerNamesSelectTeam    = UIString(zh: "从左侧选择一支球队查看球员", en: "Select a team to view its players")
    /// Override badge
    static let debugPlayerNamesOverrideBadge = UIString(zh: "覆盖", en: "Override")
    /// Save button
    static let debugPlayerNamesSave          = UIString(zh: "保存", en: "Save")
}
