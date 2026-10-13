import SwiftUI

// MARK: - Scorers/assists view model (combined)

/// Holds both leaderboards; the UI switches between them with a segmented control.
@Observable
final class LeadersViewModel {
    /// The currently selected leaderboard type.
    enum RankType: CaseIterable, Identifiable {
        case goals, assists
        var id: String { "\(self)" }
        func title(_ lang: AppLanguage) -> String {
            self == .goals ? UIString.goals.text(lang) : UIString.assists.text(lang)
        }
        func unit(_ lang: AppLanguage) -> String {
            self == .goals ? UIString.goalUnit.text(lang) : UIString.assistUnit.text(lang)
        }
    }

    var scorers: [Scorer] = []
    var assists: [Assist] = []
    var source: DataSource = .sample
    var error: AppError?

    @MainActor
    func load() async {
        // ⚠️ Both datasets depend on the FPL bootstrap (observed to hang for tens of
        // seconds), and they used to be awaited serially — worst case double the wait.
        // Now concurrent with a 15 s budget each: a timed-out group shows empty rather
        // than spinning forever.
        async let scorersResult: ([Scorer], DataSource)? = withTimeBudget(seconds: 15) {
            try? await DataRepository.scorers()
        }
        async let assistsResult: ([Assist], DataSource)? = withTimeBudget(seconds: 15) {
            try? await DataRepository.assists()
        }
        let s = await scorersResult
        let a = await assistsResult

        scorers = s?.0 ?? []
        assists = a?.0 ?? []
        // Trust the repository's reported source: a stale-cache fallback is .stale.
        // The old code marked .live whenever the array was non-nil, mislabeling
        // fallback data as live.
        source = (s?.1 == .live || a?.1 == .live) ? .live : .sample
        error = nil
    }

    /// Goals: goals desc → fewest appearances → name.
    var scorersSorted: [Scorer] {
        scorers.sorted {
            if $0.goals != $1.goals { return $0.goals > $1.goals }
            if ($0.playedMatches ?? 0) != ($1.playedMatches ?? 0) {
                return ($0.playedMatches ?? 0) < ($1.playedMatches ?? 0)
            }
            return $0.player.name < $1.player.name
        }
    }

    /// Assists: assists desc → most goals → fewest appearances.
    var assistsSorted: [Assist] {
        assists.sorted {
            if $0.assists != $1.assists { return $0.assists > $1.assists }
            let g0 = $0.goals ?? 0, g1 = $1.goals ?? 0
            if g0 != g1 { return g0 > g1 }
            return ($0.playedMatches ?? 0) < ($1.playedMatches ?? 0)
        }
    }
}

// MARK: - Scorers/assists view (combined)

/// Both leaderboards in one tab with a segmented switch on top; one shared view
/// model avoids duplicate requests.
struct LeadersView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = LeadersViewModel()
    @State private var rankType: LeadersViewModel.RankType = .goals

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            // Type switch (goals / assists)
            Picker(UIString.leaders.text(appState.language), selection: $rankType) {
                ForEach(LeadersViewModel.RankType.allCases) { type in
                    Text(type.title(appState.language)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.vertical, 8)
            .glassEffect()

            content
        }
        .navigationTitle(UIString.leaders.text(appState.language))
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

    @ViewBuilder
    private var content: some View {
        if let err = vm.error {
            ErrorView(message: err.localizedDescription)
        } else if rankType == .goals && vm.scorers.isEmpty && vm.assists.isEmpty {
            EmptyStateView(label: UIString.noScorers.text(appState.language))
        } else if rankType == .assists && vm.assists.isEmpty {
            EmptyStateView(label: UIString.noAssists.text(appState.language))
        } else {
            List {
                switch rankType {
                case .goals:
                    ForEach(Array(vm.scorersSorted.enumerated()), id: \.element.id) { index, scorer in
                        ScorerRow(index: index, scorer: scorer, primaryValue: scorer.goals, primaryLabel: UIString.goalUnit.text(appState.language), secondaryValue: scorer.assists, secondaryLabel: UIString.assistUnit.text(appState.language))
                    }
                case .assists:
                    ForEach(Array(vm.assistsSorted.enumerated()), id: \.element.id) { index, assist in
                        ScorerRow(index: index,
                                  scorer: Scorer(player: assist.player, team: assist.team, goals: assist.goals ?? 0, assists: assist.assists, playedMatches: assist.playedMatches),
                                  primaryValue: assist.assists, primaryLabel: UIString.assistUnit.text(appState.language),
                                  secondaryValue: assist.goals ?? 0, secondaryLabel: UIString.goalUnit.text(appState.language))
                    }
                }
            }
        }
    }
}

/// One row: rank + player + team + goals/assists.
private struct ScorerRow: View {
    @Environment(AppState.self) private var appState
    let index: Int
    let scorer: Scorer
    let primaryValue: Int
    let primaryLabel: String
    let secondaryValue: Int?
    let secondaryLabel: String?

    var body: some View {
        HStack {
            rankBadge(index)
            VStack(alignment: .leading) {
                Text(scorer.player.displayName(chinese: appState.language == .chinese)).font(.headline)
                Text(scorer.team.displayName(chinese: appState.language == .chinese))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                if let sv = secondaryValue, let sl = secondaryLabel, sv > 0 {
                    Text("\(sv) \(sl)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(primaryValue) \(primaryLabel)")
                    .bold()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Glass medals for the top three (gold/silver/bronze); plain rank otherwise.
    @ViewBuilder
    private func rankBadge(_ index: Int) -> some View {
        if index < 3 {
            Text(["1", "2", "3"][index])
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill([Color.yellow, Color.gray, Color.brown][index]))
                .glassEffect()
        } else {
            Text("\(index + 1)")
                .font(.subheadline)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.ultraThinMaterial))
        }
    }
}

// MARK: - Injuries

@Observable
final class InjuriesViewModel {
    var injuries: [Injury] = []
    var source: DataSource = .sample
    var error: AppError?

    @MainActor
    func load() async {
        // ⚠️ Also depends on the FPL bootstrap: 15 s budget, empty state on timeout —
        // never an endless spinner (same rationale as LeadersViewModel).
        let result: ([Injury], DataSource)? = await withTimeBudget(seconds: 15) { () -> ([Injury], DataSource)? in
            try? await DataRepository.injuries()
        }
        injuries = result?.0 ?? []
        // Trust the repository's reported source (same fix as LeadersViewModel:
        // non-nil array ≠ live)
        source = result?.1 ?? .sample
        error = nil
    }
}

/// Injuries (player / team / status / news / chance of playing).
struct InjuriesView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = InjuriesViewModel()

    var body: some View {
        @Bindable var appState = appState
        Group {
            if vm.error != nil {
                ErrorView(message: vm.error?.localizedDescription ?? "加载失败")
            } else if vm.injuries.isEmpty {
                EmptyStateView(label: UIString.noInjuries.text(appState.language))
            } else {
                List {
                    ForEach(vm.injuries) { injury in
                        HStack(spacing: 10) {
                            statusTag(injury.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(injury.player.displayName(chinese: appState.language == .chinese)).font(.headline)
                                HStack(spacing: 6) {
                                    Text(injury.team.displayName(chinese: appState.language == .chinese))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let pos = injury.position {
                                        Text("· \(pos)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let news = injury.news, !news.isEmpty {
                                    Text(news)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if let chance = injury.chanceOfPlayingNextRound, chance < 100 {
                                VStack(alignment: .trailing) {
                                Text(UIString.nextRound.text(appState.language))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: UIString.playChance.text(appState.language), chance))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(chance == 0 ? .red : .orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(UIString.injuries.text(appState.language))
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

    /// Colored injury status tag.
    @ViewBuilder
    private func statusTag(_ status: String) -> some View {
        let lang = appState.language
        let (label, color): (String, Color) = {
            switch status {
            case "i": return (UIString.stInjured.text(lang), .red)
            case "d": return (UIString.stDoubtful.text(lang), .orange)
            case "u": return (UIString.stOut.text(lang), .gray)
            case "s": return (UIString.stSuspended.text(lang), .purple)
            case "n": return (UIString.stUnreg.text(lang), .secondary)
            default:  return (status, .secondary)
            }
        }()
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 22)
            .background(Capsule().fill(color))
    }
}
