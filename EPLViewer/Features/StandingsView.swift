import Foundation
import SwiftUI

// MARK: - 视图模式

/// 积分榜 4 个 tab：总 / 主场 / 客场 / 状态
enum StandingsTab: String, CaseIterable, Identifiable {
    case overall, home, away, form
    var id: String { rawValue }
}

// MARK: - ViewModel

/// 积分榜视图模型（@Observable）
@Observable
final class StandingsViewModel {
    var rows: [StandingRow] = []
    var tab: StandingsTab = .overall       // 当前 tab，@Observable 触发视图自动重绘
    var source: DataSource = .sample
    var error: AppError?

    /// 用于「主场/客场/状态」tab 本地补全的赛程数据。tab=overall 时不读。
    private var cachedMatches: [Match] = []

    /// 按当前 tab 重新排序后的行。
    /// 总榜保持数据源顺序；主/客场榜按该维度积分重排并重新编号；
    /// 状态 tab 沿用主积分榜顺序（不做二次排序）。
    func ranked(tab: StandingsTab) -> [RankedStanding] {
        StandingsSorter.rankedStandings(rows: rows, for: tab)
    }

    @MainActor
    func load() async {
        // ⚠️ standings 内部有多级 fallback（ESPN 直连 → 从赛程聚合 → 过期缓存），
        // 每级在慢网络上都可能耗掉大量时间，最坏情况能拖到一分钟。
        // 这里给整体加 25 秒预算：超时显示空状态，绝不让 UI 无限等待。
        let result = await withTimeBudget(seconds: 25) { () -> ([StandingRow], DataSource)? in
            try? await DataRepository.standings()
        }
        let base: [StandingRow]
        let src: DataSource
        if let (data, s) = result {
            base = data
            src = s
        } else {
            // 超预算 → 空数据（不抛错、不转圈；内部 stale 兜底失败才会走到这里）
            base = []
            src = .sample
        }

        // 拉赛程数据用于 home/away enrichment（已有 MemoryStore 缓存，秒回）
        let matchesResult = await withTimeBudget(seconds: 5) { () -> ([Match], DataSource)? in
            try? await DataRepository.matches()
        }
        cachedMatches = matchesResult?.0 ?? []

        // enrichment：保留 ESPN 给的 home/away，没给的用本地聚合补
        rows = StandingsEnricher.enrich(rows: base, with: cachedMatches)
        source = src
        error = nil
    }
}

// MARK: - 行展示形态

/// 一行「行数据 + 当前 tab 下的名次」。
///
/// `rank` 可空：主/客场榜中尚未在该维度踢过球的球队不给名次，名次编号也不占位
/// （显示破折号）。总榜/状态 tab 直接沿用原 position。
struct RankedStanding: Identifiable {
    let row: StandingRow
    let rank: Int?

    /// ⚠️ 必须把 rank 编进 id：同一支球队在总榜第 3、主场榜第 1 时 id 不同。
    /// 若只用 team.id，切 tab 会让 ForEach 把两行的 diff 错配（动画/滚动位置都会乱）。
    var id: String { "\(rank.map(String.init) ?? "x")-\(row.team.id)" }
}

/// 积分榜排序：总榜不动，主/客场按该维度独立排名，状态 tab 沿用主榜顺序。
enum StandingsSorter {
    /// 按「积分 → 净胜球 → 进球」降序；该维度无数据的行沉底且不给名次。
    static func rankedStandings(rows: [StandingRow], for tab: StandingsTab) -> [RankedStanding] {
        guard tab == .home || tab == .away else {
            return rows.map { RankedStanding(row: $0, rank: $0.position) }
        }
        let isHome = (tab == .home)
        let venue: (StandingRow) -> VenueStats? = { isHome ? $0.home : $0.away }
        let sorted = rows.sorted { a, b in
            switch (venue(a), venue(b)) {
            case let (sa?, sb?):
                return (sa.points, sa.goalsFor - sa.goalsAgainst, sa.goalsFor)
                     > (sb.points, sb.goalsFor - sb.goalsAgainst, sb.goalsFor)
            case (nil, nil):
                return false                 // 保持原相对顺序
            case (nil, _):
                return false                 // 无数据沉底
            default:
                return true                  // 有数据的排前面
            }
        }
        var next = 0
        return sorted.map { row in
            guard venue(row) != nil else { return RankedStanding(row: row, rank: nil) }
            next += 1
            return RankedStanding(row: row, rank: next)
        }
    }
}

// MARK: - 视图

/// 积分榜：4 tab（总 / 主场 / 客场 / 状态），整张表格是带圆角的"卡片"
struct StandingsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = StandingsViewModel()

    /// 表格卡片圆角，与 TodayView 的 FeaturedMatchCard / Sidebar 保持一致
    private let cardCornerRadius: CGFloat = 12

    var body: some View {
        @Bindable var appState = appState
        let lang = appState.language
        VStack(spacing: 10) {
            tabBar(lang: lang)
            standingsCard(lang: lang)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 详情页顶部标题统一显示 "xxxx-xxxx 英超联赛"（取自 appTitle + SeasonStore.seasonLabel），
        // 与侧边栏标题保持一致 —— 用户对全 app 顶部标题的预期是「这是哪个赛季的英超应用」，
        // 至于具体在看哪个页面，已经由侧边栏选中项指示。
        .navigationTitle(String(format: UIString.appTitle.text(lang),
                                SeasonStore.seasonLabel))
        .task(id: appState.refreshNonce) {
            // 后台自动轮询静默刷新：不亮全屏遮罩（否则比赛日每 60s 闪一次，非常干扰）；
            // 首载 / 手动刷新照常。isLoading 仍无条件复位，避免极端时序下遮罩卡死。
            if appState.lastRefreshSource != .background { appState.isLoading = true }
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: tab bar（紧凑，减少垂直空间占用）

    @ViewBuilder
    private func tabBar(lang: AppLanguage) -> some View {
        HStack(spacing: 6) {
            ForEach(StandingsTab.allCases) { t in
                standingsTabPill(tab: t, active: vm.tab == t, lang: lang) {
                    vm.tab = t
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func standingsTabPill(tab: StandingsTab, active: Bool, lang: AppLanguage,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(standingsTabTitle(tab, lang: lang))
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : .secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background {
                    Capsule().fill(active
                        ? Color.primary.opacity(0.12)
                        : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    private func standingsTabTitle(_ t: StandingsTab, lang: AppLanguage) -> String {
        switch t {
        case .overall: return UIString.standingsTabOverall.text(lang)
        case .home:    return UIString.standingsTabHome.text(lang)
        case .away:    return UIString.standingsTabAway.text(lang)
        case .form:    return UIString.standingsTabForm.text(lang)
        }
    }

    // MARK: 表格卡片（圆角 + 细边框，内嵌 ScrollView 让窗口小时可滚）

    @ViewBuilder
    private func standingsCard(lang: AppLanguage) -> some View {
        VStack(spacing: 0) {
            content(lang: lang)
        }
        .frame(maxWidth: .infinity)
        // 卡片改为填满详情区（与今日/赛程一致）：去掉 fixedSize(vertical:true) 后，
        // standingsCard 接受父级（body VStack 的 maxHeight:.infinity）给的高度，
        // 圆角背景也跟着铺满整个详情区。
        // 最后一行被拉伸的 bug 由 detailedTable/formTable 内层 VStack 的
        // .fixedSize(vertical:true)（StandingsView.swift:192、326）兜底，不在此处处理。
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    private func content(lang: AppLanguage) -> some View {
        if vm.error != nil {
            ErrorView(message: vm.error?.localizedDescription ?? "加载失败")
        } else if vm.rows.isEmpty {
            EmptyStateView(label: UIString.noStandings.text(lang))
        } else {
            switch vm.tab {
            case .overall, .home, .away:
                detailedTable(lang: lang)
            case .form:
                formTable(lang: lang)
            }
        }
    }

    // MARK: 总/主/客 表格

    @ViewBuilder
    private func detailedTable(lang: AppLanguage) -> some View {
        // 顶层 ScrollView（非嵌在另一个纵向 ScrollView 内），让窗口小时可滚
        ScrollView {
            VStack(spacing: 0) {
                detailedHeader(lang: lang)
                ForEach(Array(vm.ranked(tab: vm.tab).enumerated()), id: \.element.id) { idx, item in
                    detailedRow(row: item.row, rank: item.rank ?? item.row.position,
                                tab: vm.tab, lang: lang)
                    if idx < vm.rows.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            // 关键：VStack 默认会拉伸最后一个 child 填满可用空间。
            // 窗口越大，剩余空间越多，最后一行（第 20 行）就被拉得越高，
            // 视觉上"只有最后一行特别高"。
            // .fixedSize(horizontal:false, vertical:true) 强制 VStack 高度 = 内容之和，
            // 不让最后一行被拉伸；剩余空间由 ScrollView 自然留白（或内容超出时滚动）。
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func detailedHeader(lang: AppLanguage) -> some View {
        HStack(spacing: 0) {
            headerCell(UIString.pos.text(lang), width: 56)
            headerCell(UIString.team.text(lang), width: nil, alignment: .leading)
            headerCell(UIString.played.text(lang), width: 66)
            headerCell(UIString.won.text(lang), width: 66)
            headerCell(UIString.drawn.text(lang), width: 66)
            headerCell(UIString.lost.text(lang), width: 66)
            headerCell(UIString.goalsFor.text(lang), width: 66)
            headerCell(UIString.goalsAg.text(lang), width: 66)
            headerCell(UIString.goalDiff.text(lang), width: 70)
            headerCell(UIString.points.text(lang), width: 80)
        }
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    /// 表头单元格：略大字体（subheadline），名次列用 56pt 宽度。
    private func headerCell(_ text: String, width: CGFloat?, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    /// 依名次计算分区底色（按 2026-27 英超真实赛制）：
    /// 1-5 欧冠、6 欧联、7 协会联赛、18-20 降级；其余无色。
    /// 用名次硬算而非数据源 status，保证示例 / 赛季初数据下也稳定有底色。
    /// ⚠️ 契约：入参必须是「总榜名次」。主/客场榜是独立名次，喂进来会得到错色（见 detailedRow）。
    private func zoneColor(for position: Int) -> Color {
        switch position {
        case 1...5:   return Color.blue.opacity(0.12)    // 欧冠区
        case 6:       return Color.orange.opacity(0.12)  // 欧联区
        case 7:       return Color.green.opacity(0.12)   // 协会联赛区
        case 18...20: return Color.red.opacity(0.12)     // 降级区
        default:      return .clear
        }
    }

    @ViewBuilder
    private func detailedRow(row: StandingRow, rank: Int, tab: StandingsTab, lang: AppLanguage) -> some View {
        let stats = statsForRow(row, tab: tab)
        return HStack(spacing: 0) {
            Text("\(rank)")
                .frame(width: 56)
                .bold()
            HStack(spacing: 12) {
                CrestImage(urlString: row.team.crest)
                    .frame(width: 20, height: 20)
                Text(row.team.displayName(chinese: lang == .chinese))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cellText("\(stats.played)", width: 66)
            cellText("\(stats.won)", width: 66)
            cellText("\(stats.draw)", width: 66)
            cellText("\(stats.lost)", width: 66)
            cellText("\(stats.goalsFor)", width: 66)
            cellText("\(stats.goalsAgainst)", width: 66)
            cellText("\(stats.gdText)", width: 70)
            Text("\(stats.points)")
                .frame(width: 80)
                .bold()
        }
        .padding(.vertical, 4)
        // 分区底色只在「展示名次 = 总榜名次」的 tab 上成立。
        // 主场/客场榜是各自独立的名次（如某队主场第 1 但总榜第 8），
        // 用总榜 position 算出来的欧冠/降级底色在那两页是错的，必须置空。
        .background((tab == .overall) ? zoneColor(for: row.position) : .clear)
    }

    /// 4 tab 各自的数据源
    private func statsForRow(_ row: StandingRow, tab: StandingsTab) -> RowStatsView {
        switch tab {
        case .overall:
            return RowStatsView(
                played: row.playedGames, won: row.won, draw: row.draw, lost: row.lost,
                goalsFor: row.goalsFor, goalsAgainst: row.goalsAgainst,
                gdText: row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)",
                points: row.points
            )
        case .home:
            if let h = row.home {
                let gd = h.goalsFor - h.goalsAgainst
                return RowStatsView(
                    played: h.played, won: h.won, draw: h.draw, lost: h.lost,
                    goalsFor: h.goalsFor, goalsAgainst: h.goalsAgainst,
                    gdText: gd > 0 ? "+\(gd)" : "\(gd)",
                    points: h.points
                )
            }
            return .empty
        case .away:
            if let a = row.away {
                let gd = a.goalsFor - a.goalsAgainst
                return RowStatsView(
                    played: a.played, won: a.won, draw: a.draw, lost: a.lost,
                    goalsFor: a.goalsFor, goalsAgainst: a.goalsAgainst,
                    gdText: gd > 0 ? "+\(gd)" : "\(gd)",
                    points: a.points
                )
            }
            return .empty
        case .form:
            return .empty
        }
    }

    private func cellText(_ s: String, width: CGFloat = 36) -> some View {
        Text(s)
            .frame(width: width)
            .monospacedDigit()
    }

    // MARK: 状态 tab 表格（简化：排名 + 球队 + 近 5 场）

    @ViewBuilder
    private func formTable(lang: AppLanguage) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                formHeader(lang: lang)
                ForEach(Array(vm.rows.enumerated()), id: \.element.id) { idx, row in
                    formRow(row: row, lang: lang)
                    if idx < vm.rows.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            // 与 detailedTable 同理：避免最后一行被 ScrollView 拉伸
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func formHeader(lang: AppLanguage) -> some View {
        HStack(spacing: 0) {
            headerCell(UIString.pos.text(lang), width: 56)
            headerCell(UIString.team.text(lang), width: nil, alignment: .leading)
            headerCell(UIString.standingsTabForm.text(lang), width: 160)
        }
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.05))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    @ViewBuilder
    private func formRow(row: StandingRow, lang: AppLanguage) -> some View {
        HStack(spacing: 0) {
            Text("\(row.position)")
                .frame(width: 56)
                .bold()
            HStack(spacing: 12) {
                CrestImage(urlString: row.team.crest)
                    .frame(width: 20, height: 20)
                Text(row.team.displayName(chinese: lang == .chinese))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FormChipsView(form: row.form)
                .frame(width: 160, alignment: .center)
        }
        .padding(.vertical, 4)
        // 状态 tab 沿用主积分榜顺序 → 展示名次就是总榜名次，分区底色成立。
        .background(zoneColor(for: row.position))
    }
}

// MARK: - 行内统计的扁平结构（避免 SwiftUI body 中重复解 Optional）

private struct RowStatsView {
    let played: Int
    let won: Int
    let draw: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let gdText: String
    let points: Int

    static let empty = RowStatsView(
        played: 0, won: 0, draw: 0, lost: 0,
        goalsFor: 0, goalsAgainst: 0, gdText: UIString.standingsDash.text(.chinese),
        points: 0
    )
}

// MARK: - 状态 tab 行

/// 状态 tab 单行：排名 + 球队 + 近 5 场 W/D/L 序列（彩色小胶囊）
///
/// 胶囊尺寸故意与 detailedRow 文字行（`.body` 17pt + padding 6pt = 23pt）对齐：
/// 18×18 胶囊 + padding 6pt = 24pt，避免状态 tab 卡片比总/主/客三 tab 高一截。
struct FormChipsView: View {
    let form: String?

    var body: some View {
        let chars = Array((form ?? "—————").prefix(5).padding(toLength: 5, withPad: "—", startingAt: 0))
        HStack(spacing: 3) {
            ForEach(0..<chars.count, id: \.self) { i in
                Text(String(chars[i]))
                    .font(.caption2.weight(.semibold))
                    .frame(width: 18, height: 18)
                    .background(Capsule().fill(chipColor(chars[i]).opacity(0.18)))
                    .foregroundStyle(chipColor(chars[i]))
            }
        }
    }

    private func chipColor(_ c: Character) -> Color {
        switch c {
        case "W": return .green
        case "D": return .blue
        case "L": return .gray
        default:  return .secondary
        }
    }
}

// MARK: - 行内球队小单元（队徽 + 简称）— 保留以便其它视图复用

struct TeamCell: View {
    @Environment(AppState.self) private var appState
    let team: Team
    var body: some View {
        HStack(spacing: 6) {
            CrestImage(urlString: team.crest)
                .frame(width: 20, height: 20)
            Text(team.displayName(chinese: appState.language == .chinese))
        }
    }
}
