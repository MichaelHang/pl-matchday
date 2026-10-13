import SwiftUI

#if DEBUG
/// DEBUG player-name override manager (DEBUG builds only, never shipped).
/// Entry: the "Manage Player Names…" button in Settings presents this sheet.
/// Layout: team list on the left, the selected team's players on the right;
/// edits accumulate in `draft`, with a single "Save" commit and "Discard" on the toolbar.
struct PlayerNameManagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var bootstrap: FPLBootstrap?
    @State private var draft: PlayerNameOverrides = PlayerNameStore.shared.overrides
    @State private var selectedTeamId: Int? = nil
    /// The "saved" flash shown briefly after saving (auto-clears after ~1.6 s).
    @State private var justSaved = false
    /// Drives the flash's timer; `save()` bumps it to restart the task.
    @State private var saveFlashToken = 0

    private var language: AppLanguage { appState.language }
    private var store: PlayerNameStore { .shared }

    private var teams: [FPLTeam] { bootstrap?.teams ?? [] }
    /// Team full names (FPLTeam.name) for the sidebar and rows — not the short codes.
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

    /// Commit the draft to the override layer and persist, then flash "Saved" —
    /// otherwise pressing save would give no visible feedback.
    private func save() {
        store.commit(draft)
        justSaved = true
        saveFlashToken &+= 1
    }

    /// Bottom status bar: orange when there are unsaved edits; green "Saved" flash
    /// after saving; otherwise no space taken.
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

/// One row in the list: web_name / team / full name + editable Chinese name.
/// Edits go straight into `draft` (not persisted immediately); the manager's
/// "Save" commits everything at once.
struct PlayerNameManagerRow: View {
    let player: FPLPlayer
    let teamName: String?
    @Binding var draft: PlayerNameOverrides
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.language }

    /// Built-in Chinese name (table only, excluding committed overrides) — the
    /// baseline for flagging redundant overrides.
    private var builtIn: String? { PlayerNameMap.builtInName(forId: player.id) }

    /// The name currently shown: draft override first, else built-in, else empty.
    private var display: String {
        draft.byId[player.id] ?? builtIn ?? ""
    }

    /// Whether this row is overridden (a draft entry exists for this id).
    private var isOverride: Bool { draft.byId[player.id] != nil }

    private var binding: Binding<String> {
        Binding(
            get: { display },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                // Empty, or equal to the built-in name → treat as "no override" and
                // delete the entry (falls back to the built-in name). Prevents an
                // empty-string override blanking the name across the whole app.
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
