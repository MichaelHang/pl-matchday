import Foundation
import SwiftUI

// MARK: - View mode

/// Standings tabs: overall / home / away / form.
enum StandingsTab: String, CaseIterable, Identifiable {
    case overall, home, away, form
    var id: String { rawValue }
}

// MARK: - ViewModel

/// Standings view model (@Observable).
@Observable
final class StandingsViewModel {
    var rows: [StandingRow] = []
    var tab: StandingsTab = .overall       // current tab; @Observable redraws the view
    var source: DataSource = .sample
    var error: AppError?

    /// Fixtures used to fill the home/away/form tabs locally. Unused on the overall tab.
    private var cachedMatches: [Match] = []

    /// Rows re-ranked for the current tab.
    /// Overall keeps source order; home/away re-rank and renumber within the dimension;
    /// form keeps the main table order (no second sort).
    func ranked(tab: StandingsTab) -> [RankedStanding] {
        StandingsSorter.rankedStandings(rows: rows, for: tab)
    }

    @MainActor
    func load() async {
        // ⚠️ standings() has multiple fallback tiers (ESPN direct → fixture
        // aggregation → stale cache), each of which can burn serious time on a slow
        // network — worst case around a minute. A 25 s overall budget bounds it: on
        // timeout show the empty state, never an endless wait.
        // Seed from the in-process last-known-good first: aggregating the previous
        // fixtures gives an instant table while the (up to 25 s) network budget runs.
        if rows.isEmpty, let last = await MemoryStore.shared.lastGoodFixturesSnapshot(), !last.isEmpty {
            rows = StandingsEnricher.enrich(rows: StandingsAggregator.aggregate(matches: last), with: last)
            source = .stale
        }

        let result = await withTimeBudget(seconds: 25) { () -> ([StandingRow], DataSource)? in
            try? await DataRepository.standings()
        }
        let base: [StandingRow]
        let src: DataSource
        if let (data, s) = result {
            base = data
            src = s
        } else {
            // Over budget → empty (no throw, no spinner; only reached if the internal
            // stale fallback failed too)
            base = []
            src = .sample
        }

        // Fetch fixtures for home/away enrichment (MemoryStore hit, instant when warm)
        let matchesResult = await withTimeBudget(seconds: 5) { () -> ([Match], DataSource)? in
            try? await DataRepository.matches()
        }
        cachedMatches = matchesResult?.0 ?? []

        // Enrichment: keep ESPN-provided home/away; fill the rest by local aggregation
        rows = StandingsEnricher.enrich(rows: base, with: cachedMatches)
        source = src
        error = nil
    }
}

// MARK: - Row display shape

/// One row: "row data + rank in the current tab".
///
/// `rank` is optional: in home/away tables a team yet to play in that dimension gets
/// no rank (and no number slot — a dash is shown). Overall/form reuse the original
/// position.
struct RankedStanding: Identifiable {
    let row: StandingRow
    let rank: Int?

    /// ⚠️ The rank must be part of the id: the same team is #3 overall but #1 at home
    /// — different ids. Using team.id alone would make ForEach mispair rows across
    /// tab switches (animations and scroll positions go haywire).
    var id: String { "\(rank.map(String.init) ?? "x")-\(row.team.id)" }
}

/// Standings sorting: overall unchanged; home/away ranked independently within their
/// dimension; form keeps the main order.
enum StandingsSorter {
    /// Points → GD → GF descending; rows without data in the dimension sink unranked.
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
                return false                 // keep original relative order
            case (nil, _):
                return false                 // no data sinks
            default:
                return true                  // teams with data first
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

// MARK: - View

/// Standings: 4 tabs (overall / home / away / form); the whole table is one rounded card.
struct StandingsView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = StandingsViewModel()

    /// Table card corner radius, consistent with TodayView's FeaturedMatchCard / Sidebar.
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
        // Detail pages all show "xxxx-xxxx Premier League" (appTitle + season label),
        // matching the sidebar — the top title answers "which season's app is this",
        // while the sidebar already indicates which page you're on.
        .navigationTitle(String(format: UIString.appTitle.text(lang),
                                SeasonStore.seasonLabel))
        .task(id: appState.refreshNonce) {
            // Background polling refreshes silently: no full-screen overlay (a flash
            // every 60 s on matchdays is very disruptive); first load / manual refresh
            // keep it. isLoading still resets unconditionally so the overlay can never
            // stick under odd timings.
            if appState.lastRefreshSource != .background { appState.isLoading = true }
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: Tab bar (compact, to save vertical space)

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
                    Capsule().fill(active ? Color.eplSurfaceStrong : Color.eplSurface)
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

    // MARK: Table card (rounded + hairline border; embedded ScrollView for small windows)

    @ViewBuilder
    private func standingsCard(lang: AppLanguage) -> some View {
        VStack(spacing: 0) {
            content(lang: lang)
        }
        .frame(maxWidth: .infinity)
        // The card fills the detail area (consistent with Today/fixtures): after
        // removing fixedSize(vertical:true), standingsCard accepts whatever height the
        // parent (the body VStack's maxHeight:.infinity) offers and the rounded
        // background covers the whole detail area.
        // The stretched-last-row bug is handled by the inner VStack's
        // .fixedSize(vertical:true) in detailedTable/formTable instead.
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .fill(Color.eplSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .strokeBorder(Color.eplHairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
    }

    @ViewBuilder
    private func content(lang: AppLanguage) -> some View {
        if vm.error != nil {
            ErrorView(message: vm.error?.localizedDescription ?? "加载失败")
        } else if vm.rows.isEmpty {
            EmptyStateView(label: UIString.noStandings.text(lang),
                           retryLabel: UIString.refresh.text(lang),
                           retryAction: { Task { await appState.refresh() } })
        } else {
            switch vm.tab {
            case .overall, .home, .away:
                detailedTable(lang: lang)
            case .form:
                formTable(lang: lang)
            }
        }
    }

    // MARK: Overall / home / away table

    @ViewBuilder
    private func detailedTable(lang: AppLanguage) -> some View {
        // Top-level ScrollView (not nested in another vertical one) so small windows scroll
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
            // Key: a VStack stretches its last child to fill available space. The
            // bigger the window, the taller the last row (row 20) looks — "only the
            // last row is extra tall". fixedSize(horizontal:false, vertical:true)
            // forces the VStack's height to the sum of its children; leftover space
            // stays as scroll-view whitespace (or scrolls when content overflows).
            .fixedSize(horizontal: false, vertical: true)
            // Breathing room below the last row: without it, row 20's relegation-red
            // background runs flush into the card's bottom rounded corners.
            .padding(.bottom, 8)
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
        .background(Color.eplSurface)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    /// Header cell: slightly larger font (subheadline); 56 pt for the position column.
    private func headerCell(_ text: String, width: CGFloat?, alignment: Alignment = .center) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    /// Zone background by position (real 2026-27 PL rules):
    /// 1-5 Champions League, 6 Europa League, 7 Conference League, 18-20 relegation;
    /// otherwise clear. Computed from the position rather than the source's status
    /// field, so sample / early-season data still gets stable colors.
    /// ⚠️ Contract: the input must be the **overall** position. Home/away tables have
    /// their own ranks; feeding those yields wrong colors (see detailedRow).
    private func zoneColor(for position: Int) -> Color {
        switch position {
        case 1...5:   return Color.blue.opacity(0.12)    // Champions League zone
        case 6:       return Color.orange.opacity(0.12)  // Europa League zone
        case 7:       return Color.green.opacity(0.12)   // Conference League zone
        case 18...20: return Color.red.opacity(0.12)     // relegation zone
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
        // Zone colors only apply when "displayed rank == overall rank". Home/away
        // tables have independent ranks (a team can be #1 at home but #8 overall);
        // overall-position-derived CL/relegation colors would be wrong there → clear.
        .background((tab == .overall) ? zoneColor(for: row.position) : .clear)
    }

    /// Per-tab stats source.
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

    // MARK: Form tab (simplified: rank + team + last 5)

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
            // Same as detailedTable: keep the last row from being stretched by the ScrollView
            .fixedSize(horizontal: false, vertical: true)
            // Breathing room below the last row (see detailedTable)
            .padding(.bottom, 8)
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
        .background(Color.eplSurface)
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
        // The form tab keeps the main standings order → the displayed rank IS the
        // overall rank, so zone colors apply.
        .background(zoneColor(for: row.position))
    }
}

// MARK: - Flat row stats (avoids repeated optional unwrapping in the SwiftUI body)

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

// MARK: - Form tab row

/// Form tab row: rank + team + last-5 W/D/L sequence (colored chips).
///
/// Chip size deliberately matches detailedRow's text rows (`.body` 17 pt + 6 pt
/// padding = 23 pt): an 18×18 chip + 6 pt padding = 24 pt, so the form tab isn't
/// taller than the other three.
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

// MARK: - Inline team cell (crest + name) — kept for reuse by other views

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
