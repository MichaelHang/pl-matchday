import Foundation
import SwiftUI

// MARK: - DEBUG player-name override layer
//
// Developers edit Chinese player names visually in the DEBUG panel; overrides are
// persisted to `~/Library/Application Support/<bundleId>/playerNameOverrides.json`
// and never committed. The pure function `PlayerNameMap.zh(for:)` reads the latest
// overrides synchronously via `PlayerNameStore.current`, so no actor or async hop
// is needed.

/// Override data: developer-defined Chinese names overriding
/// `PlayerNameMap`'s tables. Primary dimension `byId` (FPL element id), secondary
/// `byName` (web_name).
struct PlayerNameOverrides: Codable, Equatable {
    /// Override by FPL element id (primary; stable across seasons/transfers, highest priority)
    var byId: [Int: String] = [:]
    /// Override by web_name (secondary; on collisions the last one wins)
    var byName: [String: String] = [:]
}

/// Override storage.
///
/// - A plain Swift object (no global actor) so unit tests can call it synchronously.
/// - Every mutation refreshes the static `current` snapshot for the pure resolver.
/// - `ObservableObject` lets the DEBUG panel observe `overrides` (override badges).
final class PlayerNameStore: ObservableObject {
    /// Synchronous snapshot, refreshed on every mutation; read by the pure
    /// `PlayerNameMap.zh(for:)`. A non-isolated static so tests can assign/reset it
    /// directly (the app only touches it from the main thread, hence `nonisolated(unsafe)`).
    nonisolated(unsafe) static var current: PlayerNameOverrides = .init()

    /// Singleton; first access loads any overrides already on disk (defaults to
    /// empty when the file doesn't exist).
    nonisolated(unsafe) static let shared = PlayerNameStore()

    /// The in-memory overrides (equivalent to `current`; observable by SwiftUI).
    @Published var overrides = PlayerNameOverrides()

    /// Where the overrides JSON is persisted.
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let bundleId = Bundle.main.bundleIdentifier ?? "com.eplviewer.app"
        let dir = support.appendingPathComponent(bundleId, isDirectory: true)
        self.fileURL = dir.appendingPathComponent("playerNameOverrides.json", isDirectory: false)
        load()
    }

    /// Decode the file into `overrides` and refresh the snapshot when present;
    /// otherwise keep the defaults.
    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(PlayerNameOverrides.self, from: data) else { return }
        overrides = decoded
        PlayerNameStore.current = decoded
    }

    /// Create the directory if needed and encode `overrides` to disk.
    func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Replace the whole override layer and persist (global save button).
    func commit(_ overrides: PlayerNameOverrides) {
        self.overrides = overrides
        PlayerNameStore.current = overrides
        save()
    }

    /// Set an override by id; an empty name deletes the entry.
    func set(id: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides.byId.removeValue(forKey: id)
        } else {
            overrides.byId[id] = trimmed
        }
        PlayerNameStore.current = overrides
        save()
    }

    /// Set an override by web_name; an empty name deletes the entry.
    func set(webName: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides.byName.removeValue(forKey: webName)
        } else {
            overrides.byName[webName] = trimmed
        }
        PlayerNameStore.current = overrides
        save()
    }

    /// Delete the override for an id.
    func reset(id: Int) {
        overrides.byId.removeValue(forKey: id)
        PlayerNameStore.current = overrides
        save()
    }

    /// Delete the override for a web_name.
    func reset(webName: String) {
        overrides.byName.removeValue(forKey: webName)
        PlayerNameStore.current = overrides
        save()
    }
}
