import SwiftUI

// MARK: - 射手/助攻 榜 ViewModel（合并版）

/// 同时持有射手榜与助攻榜数据，UI 内部通过 segmented 切换显示
@Observable
final class LeadersViewModel {
    /// 当前选中的排行榜类型
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
        // ⚠️ 两组数据都依赖 FPL bootstrap（实测可能慢到几十秒仍不结束），
        // 原本又是串行 await，最坏要等两遍。改成并发取 + 各 15 秒预算：
        // 超时就放弃那组、UI 显示空状态，绝不让页面一直转圈。
        async let scorersTask: [Scorer]? = withTimeBudget(seconds: 15) {
            (try? await DataRepository.scorers())?.0
        }
        async let assistsTask: [Assist]? = withTimeBudget(seconds: 15) {
            (try? await DataRepository.assists())?.0
        }
        let (s, a) = await (scorersTask, assistsTask)

        scorers = s ?? []
        assists = a ?? []
        source = (s != nil || a != nil) ? .live : .sample
        error = nil
    }

    /// 进球榜：进球降序 → 并列按出场升序 → 并列按名字字典序
    var scorersSorted: [Scorer] {
        scorers.sorted {
            if $0.goals != $1.goals { return $0.goals > $1.goals }
            if ($0.playedMatches ?? 0) != ($1.playedMatches ?? 0) {
                return ($0.playedMatches ?? 0) < ($1.playedMatches ?? 0)
            }
            return $0.player.name < $1.player.name
        }
    }

    /// 助攻榜：助攻降序 → 并列按进球数降序 → 并列按出场升序
    var assistsSorted: [Assist] {
        assists.sorted {
            if $0.assists != $1.assists { return $0.assists > $1.assists }
            let g0 = $0.goals ?? 0, g1 = $1.goals ?? 0
            if g0 != g1 { return g0 > g1 }
            return ($0.playedMatches ?? 0) < ($1.playedMatches ?? 0)
        }
    }
}

// MARK: - 射手/助攻 榜视图（合并版）

/// 射手榜与助攻榜合并到一个 tab，顶部 segmented 切换显示
/// 共享同一份 ViewModel 数据源，避免重复请求
struct LeadersView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = LeadersViewModel()
    @State private var rankType: LeadersViewModel.RankType = .goals

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            // 类型切换（进球 / 助攻）
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
            appState.isLoading = true
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

/// 单行：排名 + 球员 + 球队 + 进球/助攻
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

    /// 前三名奖牌玻璃徽标（金/银/铜），其余只显示名次
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

// MARK: - 伤停榜

@Observable
final class InjuriesViewModel {
    var injuries: [Injury] = []
    var source: DataSource = .sample
    var error: AppError?

    @MainActor
    func load() async {
        // ⚠️ 同样依赖 FPL bootstrap：给 15 秒预算，超时就显示空状态，
        // 绝不让页面一直转圈（原因同 LeadersViewModel）。
        let result = await withTimeBudget(seconds: 15) { () -> [Injury]? in
            (try? await DataRepository.injuries())?.0
        }
        injuries = result ?? []
        source = result != nil ? .live : .sample
        error = nil
    }
}

/// 伤停榜（球员/球队/状态/伤情/出场概率）
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
            appState.isLoading = true
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    /// 伤停状态标签（彩色）
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
