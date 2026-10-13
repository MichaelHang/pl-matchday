import SwiftUI

// MARK: - App entry point

@main
struct EPLViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                // Minimum height estimated from "standings showing all 20 teams":
                // header + 20 rows ≈ 600, plus toolbar (~52) and list padding → 675
                // with headroom. Not sized any larger as a ScrollView safety net
                // (the earlier 680 → 240 swing was far too extreme).
                .frame(minWidth: 900, minHeight: 675)
        }
    }
}

// MARK: - Interface language
/// Global language definitions live in UIStrings.swift (AppLanguage + the UIString table).
