import SwiftUI

/// Liquid Glass sidebar.
struct Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List(AppState.AppSection.allCases, selection: $appState.selected) { section in
            Label(section.title(appState.language), systemImage: section.systemImage)
                .tag(section)
                .padding(.vertical, 4)
        }
        .listStyle(.sidebar)
        .navigationTitle(String(format: UIString.appTitle.text(appState.language),
                                SeasonStore.seasonLabel))
        // Note: never stack .glassEffect() on a self-sizing container like List.
        //   On the macOS 26 SDK it inflates the whole subtree into an oval of glass
        //   (once produced a "giant circle in the sidebar" visual bug). Row glass
        //   comes from .listStyle(.sidebar)'s own material, which is enough.
    }
}
