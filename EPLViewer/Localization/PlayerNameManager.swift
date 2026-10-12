import SwiftUI

#if DEBUG
/// 调试期球员中文名覆盖管理器（仅 DEBUG 编译，不进 Release）。
/// 入口：设置页「管理球员译名…」按钮弹出的 sheet。
/// 布局：左侧球队列表（分球队显示），右侧选中球队的球员名单；
/// 编辑累积在 `draft` 里，工具栏一个「保存」统一提交，一个「放弃修改」撤销。
struct PlayerNameManagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var bootstrap: FPLBootstrap?
    @State private var draft: PlayerNameOverrides = PlayerNameStore.shared.overrides
    @State private var selectedTeamId: Int? = nil
    /// 保存后短暂显示的「已保存」提示标记（约 1.6s 后自动清除）。
    @State private var justSaved = false
    /// 驱动「已保存」提示自动消退的令牌；`save()` 时自增以重启计时任务。
    @State private var saveFlashToken = 0

    private var language: AppLanguage { appState.language }
    private var store: PlayerNameStore { .shared }

    private var teams: [FPLTeam] { bootstrap?.teams ?? [] }
    /// 球队全名（FPLTeam.name），供侧边栏与行内展示，不用缩写 short_name。
    private var teamNameById: [Int: String] {
        Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.name) })
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(teams, id: \.id, selection: $selectedTeamId) { team in
                    Text(team.name)
                }
                .navigationTitle(UIString.debugPlayerNamesManagerTitle.text(language))
            } detail: {
                detailContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .frame(minWidth: 720, minHeight: 540)
        .navigationTitle(UIString.debugPlayerNamesManagerTitle.text(language))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(UIString.debugPlayerNamesClose.text(language)) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .automatic) {
                Button(UIString.debugPlayerNamesDiscard.text(language)) {
                    draft = store.overrides
                }
                .disabled(draft == store.overrides)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(UIString.debugPlayerNamesSave.text(language)) {
                    save()
                }
                .disabled(draft == store.overrides)
            }
        }
        .task {
            bootstrap = await MemoryStore.shared.cachedBootstrap()
        }
        .task(id: saveFlashToken) {
            guard saveFlashToken > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            justSaved = false
        }
    }

    /// 提交草稿到覆盖层并落盘；随后短暂点亮「已保存」提示，解决「点了保存没反应」的反馈缺失。
    private func save() {
        store.commit(draft)
        justSaved = true
        saveFlashToken &+= 1
    }

    /// 底部状态栏：有未保存修改时橙色提示；刚保存后绿色「已保存」。否则不占空间。
    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 6) {
            if justSaved {
                Label(UIString.debugPlayerNamesSaved.text(language), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if draft != store.overrides {
                Label(UIString.debugPlayerNamesUnsaved.text(language),
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let teamId = selectedTeamId, let bootstrap {
            let players = bootstrap.elements.filter { $0.team == teamId }
            List(players, id: \.id) { player in
                PlayerNameManagerRow(
                    player: player,
                    teamName: teamNameById[player.team],
                    draft: $draft
                )
            }
            .navigationTitle(teamNameById[teamId] ?? "")
        } else {
            Text(UIString.debugPlayerNamesSelectTeam.text(language))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 名单中的单行：web_name / 球队 / 全名 + 可编辑中文名。
/// 编辑直接写入 `draft`（不即时持久化）；由管理器的「保存」统一提交。
struct PlayerNameManagerRow: View {
    let player: FPLPlayer
    let teamName: String?
    @Binding var draft: PlayerNameOverrides
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.language }

    /// 内置中文名（仅 zhById，不含已提交覆盖）——作为「是否产生冗余覆盖」的基线。
    private var builtIn: String? { PlayerNameMap.builtInName(forId: player.id) }

    /// 当前应显示的中文名：草稿覆盖优先，否则回退内置（无则为空串）。
    private var display: String {
        draft.byId[player.id] ?? builtIn ?? ""
    }

    /// 是否处于「覆盖」态（草稿里有该 id 的覆盖条目）。
    private var isOverride: Bool { draft.byId[player.id] != nil }

    private var binding: Binding<String> {
        Binding(
            get: { display },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // 空串 或 等于内置名 → 视为「无覆盖」删除条目（回退到内置名），
                // 避免写入空串覆盖导致该球员中文名在全 app 变空白。
                if trimmed.isEmpty || trimmed == (builtIn ?? "") {
                    draft.byId.removeValue(forKey: player.id)
                } else {
                    draft.byId[player.id] = trimmed
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.web_name).font(.headline)
                    if let teamName {
                        Text(teamName).font(.caption).foregroundStyle(.secondary)
                    }
                    if isOverride {
                        Text(UIString.debugPlayerNamesOverrideBadge.text(language))
                            .font(.caption2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.orange.opacity(0.2)).cornerRadius(4)
                    }
                }
                if let first = player.first_name, let second = player.second_name {
                    Text("\(first) \(second)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("", text: binding)
                .frame(width: 160)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 2)
    }
}
#endif
