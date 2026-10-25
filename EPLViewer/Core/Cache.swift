import Foundation

// MARK: - Cache layer (in-memory + on-disk JSON with TTL)

/// Per-data-type cache TTLs.
enum CacheTTL {
    /// Fixtures/scores: lazy-refresh TTL — only bounds how stale a *passive* fetch
    /// (tab switch / app launch) may be. `Match` carries live scores that keep
    /// updating after full time, but the TTL only decides when passive fetches go
    /// stale; a manual refresh clears the cache and bypasses it entirely, so a
    /// friendly 5 minutes keeps everyday browsing quiet while "refresh now" still
    /// gets the latest scores.
    static let fixtures: TimeInterval = 60 * 5
    /// FPL bootstrap: players / scorers / assists / injuries; only updates after
    /// matches finish, so cache for 2 hours.
    static let bootstrap: TimeInterval = 60 * 60 * 2
    /// Standings: lazy-refresh TTL (same rationale as fixtures). Manual refresh bypasses.
    static let standings: TimeInterval = 60 * 5
    /// Scoreboard: daily-ish data, 5 minutes is plenty.
    static let scoreboard: TimeInterval = 60 * 5

    /// Pure function: is the cache still within its TTL (unit-testable).
    static func isValid(mtime: Date, ttl: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(mtime) < ttl
    }
}

/// In-process memory cache (actor for thread safety).
///
/// The disk cache (`CacheStore`) persists across launches, but every fetch would
/// still pay a file read + full `JSONDecoder` decode — switching tabs decoded the
/// bootstrap twice (currentGameweek + gameweeks): slow and wasteful. This layer
/// decodes once per app session and hands back the in-memory object afterwards.
///
/// ⚠️ Manual refresh / clear-cache must clear this too (see
/// `DataRepository.clearCache`), otherwise the disk clears but stale memory
/// objects keep being served.
actor MemoryStore {
    static let shared = MemoryStore()

    private var bootstrap: FPLBootstrap?
    private var fixtures: [Match]?

    func cachedBootstrap() -> FPLBootstrap? { bootstrap }
    func cacheBootstrap(_ value: FPLBootstrap) { bootstrap = value }

    func cachedFixtures() -> [Match]? { fixtures }
    func cacheFixtures(_ value: [Match]) { fixtures = value }

    /// Clear everything (manual refresh / clear-cache in Settings).
    func clear() {
        bootstrap = nil
        fixtures = nil
    }

    /// Clear fixtures only (live-match polling), keep bootstrap.
    func clearFixtures() { fixtures = nil }

    // MARK: Last-known-good (in-process fallback)
    //
    // A copy is kept after every successful fetch. Deliberately **not** cleared by
    // clear() / clearFixtures(): both the live-match poll and a manual refresh
    // invalidate the caches first and then hit the network — if that network attempt
    // fails, this is the UI's final fallback, so a failed refresh degrades to the
    // previous data instead of wiping a populated page blank (user-reported
    // match-day regression). Only the next successful fetch overwrites these.

    private var lastGoodFixtures: [Match]?
    private var lastGoodBootstrap: FPLBootstrap?
    private var lastGoodStandings: ESPNStandingsCoreResponse?

    func rememberFixtures(_ value: [Match]) { lastGoodFixtures = value }
    func lastGoodFixturesSnapshot() -> [Match]? { lastGoodFixtures }

    func rememberBootstrap(_ value: FPLBootstrap) { lastGoodBootstrap = value }
    func lastGoodBootstrapSnapshot() -> FPLBootstrap? { lastGoodBootstrap }

    func rememberStandings(_ value: ESPNStandingsCoreResponse) { lastGoodStandings = value }
    func lastGoodStandingsSnapshot() -> ESPNStandingsCoreResponse? { lastGoodStandings }
}

/// Minimal on-disk cache (actor for thread safety).
actor CacheStore {
    static let shared = CacheStore()

    private let cacheDir: URL

    /// - Parameter directory: cache directory; nil uses the default
    ///   (App Support/EPLViewer/cache). Tests inject a temp directory to keep
    ///   the real cache untouched.
    init(directory: URL? = nil) {
        if let directory {
            cacheDir = directory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            cacheDir = support.appendingPathComponent("EPLViewer/cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
    }

    private func url(for key: String) -> URL {
        cacheDir.appendingPathComponent(sanitize(key) + ".json")
    }

    /// File-name-safe version of a cache key.
    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: "?", with: "_")
           .replacingOccurrences(of: "&", with: "_")
    }

    /// Read a cache entry (respects TTL).
    func get<T: Decodable>(_ key: String, ttl: TimeInterval) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u),
              let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              let mtime = attrs[.modificationDate] as? Date,
              CacheTTL.isValid(mtime: mtime, ttl: ttl)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Read a cache entry **ignoring TTL** (stale-if-error fallback).
    ///
    /// Used when the network fails/times out and no fresh cache exists: serve the
    /// last successfully persisted data — real content, possibly outdated, better
    /// than a blank page or fake samples. Returns nil on decode failure (corrupt file).
    func getStale<T: Decodable>(_ key: String) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Write a cache entry.
    func set<T: Encodable>(_ key: String, value: T) {
        let u = url(for: key)
        let enc = JSONEncoder()
        if let data = try? enc.encode(value) {
            try? data.write(to: u, options: .atomic)
        }
    }

    /// Remove every cache entry.
    func clear() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
    }

    /// Remove a single key (live-match polling invalidates fixtures only).
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}
