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
        #if DEBUG
        // QA convenience: launch with `-epl_snapshot <name>` (plus `-section <x>`)
        // to let the data settle, capture this window to /tmp/epl-<name>.png, and
        // exit. In-process capture needs no Screen Recording permission.
        .task(id: UserDefaults.standard.string(forKey: "epl_snapshot") ?? "") {
            guard let name = UserDefaults.standard.string(forKey: "epl_snapshot"), !name.isEmpty else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)  // let the data load settle
            guard let win = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 500 }) else { exit(2) }
            // Capture the theme frame (content + title bar + toolbar) — the superview
            // of contentView; own-window capture needs no Screen Recording permission.
            let frame = win.contentView.flatMap { $0.superview } ?? win.contentView
            guard let frame, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { exit(2) }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
            try? png.write(to: URL(fileURLWithPath: "/tmp/epl-\(name).png"))
            exit(0)
        }
        #endif
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
