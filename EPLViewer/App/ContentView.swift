import SwiftUI

// MARK: - Main container (NavigationSplitView)

/// Sidebar + detail split layout.
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
        // ⚠️ When `autoRefresh == true` is restored from UserDefaults, the Toggle's
        // `.onChange` in SettingsView never fires (the value was already true before
        // the view was built) and the timer never gets created → "UI says on but
        // there is no timer". Configure once when the root view appears: true builds
        // the timer, false is a safe no-op.
        .task { appState.configureAutoRefresh() }
    }
}

/// Switches the detail pane based on the selected section.
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
