import SwiftUI

/// Toolbar content.
/// History: this used to hold three items — refresh / source badge / settings.
///   - Settings moved to the sidebar ("Settings" entry).
///   - The source badge was later removed entirely to reduce noise; it returned in a
///     narrower form: the offline badge below, shown **only** when the loaded data is
///     stale (network failed, last cache served) — in that case the user must be able
///     to tell the scores/table may be outdated.
struct TopBar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        @Bindable var appState = appState

        ToolbarItem {
            if appState.source == .stale {
                // Own tinted capsule + inner padding: without it the label sits flush
                // against the toolbar item's implicit glass edge (user-reported).
                Label(UIString.staleBadge.text(appState.language), systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }

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
