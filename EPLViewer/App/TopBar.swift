import SwiftUI

/// Toolbar content (manual refresh button only).
/// History: this used to hold three items — refresh / source badge / settings.
///   - The source badge ("live" / "sample data") was removed to reduce noise; in a
///     real fallback scenario the affected list is empty anyway, which is signal enough.
///   - Settings moved to the sidebar ("Settings" entry).
struct TopBar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        @Bindable var appState = appState

        ToolbarItem {
            Button {
                Task { await appState.refresh() }
            } label: {
                Label(UIString.refresh.text(appState.language), systemImage: "arrow.clockwise")
            }
            .disabled(appState.isLoading)
        }
    }
}
