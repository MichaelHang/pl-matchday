import SwiftUI

// MARK: - 设置面板

/// 设置页面（赛季 / 自动刷新 / 缓存管理），玻璃质感
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var clearing = false
    #if DEBUG
    @State private var showingNameManager = false
    #endif

    var body: some View {
        @Bindable var appState = appState
        Form {
            // 当前 App 只 focus 在 2026-27 赛季，不开放赛季切换；
            // 如未来要支持历史赛季，可恢复以下 Section：
            //   Section("赛季") {
            //       Picker("赛季", selection: $appState.season) { ... }
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
                    // 全局自动刷新已开时本项无意义（已经每 60s），灰掉并给出脚注说明。
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
        // 注意：不要再在 Form 上叠 .glassEffect()。
        //   .formStyle(.grouped) 已有自己的分组材质，叠 .glassEffect() 在 macOS 26 会渲染成
        //   巨大的椭圆玻璃底（曾经因此出现"设置页面背景一个圆圈"的视觉 bug）。
        //   真要玻璃质感，加在某个 Section/Button 局部即可。
    }
}
