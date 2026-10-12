import SwiftUI

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
