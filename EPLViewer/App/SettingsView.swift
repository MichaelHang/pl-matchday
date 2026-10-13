import SwiftUI

// MARK: - Settings panel

/// Settings page (season / auto-refresh / cache management).
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var clearing = false
    #if DEBUG
    @State private var showingNameManager = false
    #endif

    var body: some View {
        @Bindable var appState = appState
        Form {
            // The app only targets the 2026-27 season; no season switching.
            // To support historical seasons later, restore this Section:
            //   Section("Season") {
            //       Picker("Season", selection: $appState.season) { ... }
            //   }
            Section(UIString.currentSeason.text(appState.language)) {
                LabeledContent(UIString.season.text(appState.language), value: "2026-27")
            }

            Section(UIString.interfaceLang.text(appState.language)) {
                Picker(UIString.interfaceLang.text(appState.language), selection: $appState.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(UIString.refresh.text(appState.language)) {
                Toggle(UIString.autoRefresh.text(appState.language), isOn: $appState.autoRefresh)
                    .onChange(of: appState.autoRefresh) { _, _ in
                        appState.configureAutoRefresh()
                    }
                Toggle(UIString.autoRefreshDuringMatches.text(appState.language),
                       isOn: $appState.autoRefreshDuringMatches)
                    // Meaningless when the global auto-refresh is on (already 60 s
                    // everywhere): disable it and explain in the footnote.
                    .disabled(appState.autoRefresh)
                    .onChange(of: appState.autoRefreshDuringMatches) { _, _ in
                        appState.configureAutoRefresh()
                    }
                if appState.autoRefresh {
                    Text(UIString.autoRefreshDuringMatchesHint.text(appState.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label(UIString.refreshNow.text(appState.language), systemImage: "arrow.clockwise")
                }
            }

            Section(UIString.timezone.text(appState.language)) {
                Picker(UIString.timezone.text(appState.language), selection: $appState.timeZone) {
                    ForEach(DisplayTimeZone.allCases) { tz in
                        Text(tz.label(appState.language)).tag(tz)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(UIString.cache.text(appState.language)) {
                Button(role: .destructive) {
                    clearing = true
                    Task {
                        await appState.refresh()
                        clearing = false
                    }
                } label: {
                    if clearing {
                        ProgressView()
                    } else {
                        Label(UIString.clearCache.text(appState.language), systemImage: "trash")
                    }
                }
            }

            #if DEBUG
            Section {
                Button {
                    showingNameManager = true
                } label: {
                    Label(UIString.debugPlayerNamesManage.text(appState.language),
                          systemImage: "person.text.rectangle")
                }
            } header: {
                Text(UIString.debugPlayerNamesTitle.text(appState.language))
            }
            #endif

            Section {
                Text(UIString.dataSourceDesc.text(appState.language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(UIString.settings.text(appState.language))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if DEBUG
        .sheet(isPresented: $showingNameManager) {
            PlayerNameManagerView()
        }
        #endif
        // Note: never stack .glassEffect() on the Form.
        //   .formStyle(.grouped) already brings its own grouped material; adding
        //   .glassEffect() on macOS 26 renders a giant oval glass behind the page
        //   (once produced a "circle in the settings background" visual bug). For a
        //   glass look, apply it to an individual Section/Button instead.
    }
}
