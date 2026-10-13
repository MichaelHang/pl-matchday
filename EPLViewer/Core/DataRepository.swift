import Foundation

// MARK: - Data repository (single entry point + fallbacks + caching)

/// Unified data access: decides between public APIs and stale cache
/// (stale-if-error). On network failure the last successfully persisted data is
/// served; with no cache at all (e.g. offline on first launch) an empty result is
/// returned and the UI shows its empty state.
enum DataRepository {
    // Cache keys
    private static let kBootstrap = "fpl_bootstrap"
    private static let kStandings = "espn_standings"

    /// Whether the given error should fall through to the next fallback tier
    /// (empty data / stale cache).
    /// - Falls through: 429 (rate limited) / network failure / no data
    /// - Rethrown: 403 / 400 and other HTTP errors, decoding errors
    static func shouldFallback(_ err: AppError) -> Bool {
        switch err {
        case .apiError(let code): return code == 429
        case .network:            return true
        case .noData:             return true
        case .decoding:           return false
        }
    }

    // MARK: Standings: v3 records → aggregate from fixtures → stale cache → empty

    /// Fallback strategy:
    ///   1. v3 standings `records` (ESPN's own table; ESPN fills it in after matches)
    ///   2. **The core of this app**: aggregate points live from finished fixtures
    ///      (FPL fixtures) — does not depend on ESPN populating records
    ///   3. On network failure, the stale on-disk cache (stale-if-error: if fixture
    ///      aggregation is unavailable, use the last persisted v3 table)
    ///   4. Nothing at all → empty array (UI shows its empty state)
    ///
    /// Motivation: matchday 1 can be long finished while ESPN's `records` field
    /// stays empty for ages, so tier 2 is required as the live fallback and must
    /// **not** wait on ESPN.
    static func standings() async throws -> ([StandingRow], DataSource) {
        // 1. Try the direct v3 standings (if records exist)
        if let cached: ESPNStandingsCoreResponse = await CacheStore.shared.get(kStandings, ttl: CacheTTL.standings) {
            let rows = ESPNTranslator.standingRows(from: cached)
            if !rows.isEmpty { return (rows, .live) }
        }
        do {
            let season = Int(SeasonStore.currentSeason) ?? 2026
            let resp = try await ESPNProvider().fetchStandings(season: season)
            await CacheStore.shared.set(kStandings, value: resp)
            let rows = ESPNTranslator.standingRows(from: resp)
            if !rows.isEmpty { return (rows, .live) }
        } catch {
            // v3 failed; fall through to the next tier
        }

        // 2. Aggregate points from finished fixtures (FPL fixtures / scoreboard).
        //    Works even when the fixtures themselves come from the stale cache —
        //    real content, just not fresh; source is tagged accordingly.
        let (ms, src) = await DataRepository.matches()
        if src != .sample {
            let rows = StandingsAggregator.aggregate(matches: ms)
            if !rows.isEmpty { return (rows, src) }
        }

        // 3. Stale v3 standings cache (stale-if-error)
        if let stale: ESPNStandingsCoreResponse = await CacheStore.shared.getStale(kStandings) {
            let rows = ESPNTranslator.standingRows(from: stale)
            if !rows.isEmpty { return (rows, .stale) }
        }

        // 4. Nothing at all
        return ([], .sample)
    }

    // MARK: Fixtures (FPL fixtures first, ESPN scoreboard fallback, stale cache last)

    /// The FPL fixtures endpoint provides matchday, real scores and both teams per
    /// match; mapping teams onto FPL bootstrap teams yields official crests — the
    /// most reliable fixtures source. A TTL hit opens instantly; on network failure
    /// the last persisted fixtures are served (TTL ignored).
    static func matches() async -> ([Match], DataSource) {
        let cacheKey = fixturesCacheKey
        // 1) Memory (fastest path within a session; instant tab switches)
        if let mem = await MemoryStore.shared.cachedFixtures(), !mem.isEmpty {
            return (mem, .live)
        }
        // 2) Disk cache (within TTL)
        if let cached: [Match] = await CacheStore.shared.get(cacheKey, ttl: CacheTTL.fixtures), !cached.isEmpty {
            await MemoryStore.shared.cacheFixtures(cached)
            return (cached, .live)
        }
        // 3) Network (FPL → ESPN fallback) under a 20 s overall budget; no infinite waits.
        if let ms = await withTimeBudget(seconds: 20, operation: { await fetchMatchesFromNetwork() }) {
            await CacheStore.shared.set(cacheKey, value: ms)
            await MemoryStore.shared.cacheFixtures(ms)
            return (ms, .live)
        }
        // 4) Network failed/timed out → last persisted fixtures (TTL ignored, stale-if-error).
        //    Deliberately **not** written into MemoryStore: the memory cache holds
        //    fresh data only, so later paths can't mistake stale for live.
        if let stale: [Match] = await CacheStore.shared.getStale(cacheKey), !stale.isEmpty {
            return (stale, .stale)
        }
        // 5) Nothing at all (e.g. offline on first launch) → empty array, UI shows empty state
        return ([], .sample)
    }

    /// Network fetch for fixtures: FPL fixtures first, ESPN scoreboard fallback;
    /// returns on the first tier that succeeds. Extracted so `withTimeBudget` can
    /// wrap both tiers — otherwise each tier's 30 s timeout stacks up to 60 s
    /// before the stale-cache fallback is even reached.
    private static func fetchMatchesFromNetwork() async -> [Match]? {
        if let ms = try? await loadFPLMatches() { return ms }
        if let ms = try? await loadScoreboardMatches() { return ms }
        return nil
    }

    private static func loadFPLMatches() async throws -> [Match] {
        async let bootstrapResult = loadOrFetchBootstrap()
        async let fixtures = FPLProvider().fetchFixtures()
        let (bs, fx) = try await (bootstrapResult, fixtures)
        let ms = FPLTranslator.matches(from: fx, teams: bs.bootstrap.teams)
        guard !ms.isEmpty else { throw AppError.noData }
        return ms
    }

    private static func loadScoreboardMatches() async throws -> [Match] {
        let startYear = SeasonStore.currentSeason
        let endYear = String((Int(startYear) ?? 2026) + 1)
        let dates = "\(startYear)0801-\(endYear)0531"
        let resp = try await ESPNProvider().fetchScoreboardSchedule(dates: dates)
        let ms = ESPNTranslator.matches(from: resp)
        guard !ms.isEmpty else { throw AppError.noData }
        return ms
    }

    /// Current gameweek: is_current first, then is_next, then the latest finished
    /// round, finally round 1.
    static func currentGameweek() async -> Int? {
        guard let events = await gameweeks() else { return nil }
        return deriveCurrentRound(events)
    }

    /// Pure function: derive the "current round" from FPL events.
    /// Priority: is_current > is_next > latest finished > first round.
    /// A separate function so callers can fetch events once and get both the
    /// current round and season progress without re-decoding the bootstrap.
    static func deriveCurrentRound(_ events: [FPLGameweek]) -> Int? {
        if let cur = events.first(where: { $0.is_current == true }) { return cur.id }
        if let nxt = events.first(where: { $0.is_next == true }) { return nxt.id }
        if let last = events.filter({ $0.finished == true }).map(\.id).max() { return last }
        return events.first?.id
    }

    /// Full gameweek list (is_current / is_next / finished / deadline_time) for the
    /// season overview — heavier than `currentGameweek`, but fetched once and then
    /// served from the memory cache at ~zero cost.
    static func gameweeks() async -> [FPLGameweek]? {
        do {
            let (bootstrap, _) = try await loadOrFetchBootstrap()
            return bootstrap.events ?? []
        } catch {
            return nil
        }
    }

    // MARK: Teams / players (derived from the FPL bootstrap)

    static func teams() async throws -> ([Team], DataSource) {
        do {
            let (bootstrap, source) = try await loadOrFetchBootstrap()
            return (FPLTranslator.teams(from: bootstrap), source)
        } catch {
            if let appErr = error as? AppError, shouldFallback(appErr) {
                return ([], .sample)
            }
            throw error
        }
    }

    static func team(id: Int) async throws -> (Team?, DataSource) {
        do {
            let (bootstrap, source) = try await loadOrFetchBootstrap()
            return (FPLTranslator.team(id: id, from: bootstrap), source)
        } catch {
            if let appErr = error as? AppError, shouldFallback(appErr) {
                return (nil, .sample)
            }
            throw error
        }
    }

    // MARK: Scorers / assists / injuries

    static func scorers() async throws -> ([Scorer], DataSource) {
        do {
            let (bootstrap, source) = try await loadOrFetchBootstrap()
            return (FPLTranslator.scorers(from: bootstrap, limit: 10), source)
        } catch {
            if let appErr = error as? AppError, shouldFallback(appErr) {
                return ([], .sample)
            }
            throw error
        }
    }

    static func assists() async throws -> ([Assist], DataSource) {
        do {
            let (bootstrap, source) = try await loadOrFetchBootstrap()
            return (FPLTranslator.assists(from: bootstrap, limit: 10), source)
        } catch {
            if let appErr = error as? AppError, shouldFallback(appErr) {
                return ([], .sample)
            }
            throw error
        }
    }

    static func injuries() async throws -> ([Injury], DataSource) {
        do {
            let (bootstrap, source) = try await loadOrFetchBootstrap()
            return (FPLTranslator.injuries(from: bootstrap), source)
        } catch {
            if let appErr = error as? AppError, shouldFallback(appErr) {
                return ([], .sample)
            }
            throw error
        }
    }

    // MARK: Internal: bootstrap loading (cached, with stale fallback)

    /// Returns `(bootstrap, source)`. Falls back to the stale disk cache on network
    /// failure (stale-if-error), so derived endpoints (teams / scorers / assists /
    /// injuries / gameweeks) don't need fallbacks of their own.
    private static func loadOrFetchBootstrap() async throws -> (bootstrap: FPLBootstrap, source: DataSource) {
        // 1) Memory: instant hit within a session, zero IO and zero decoding
        if let mem = await MemoryStore.shared.cachedBootstrap() { return (mem, .live) }
        // 2) Disk cache (within TTL)
        if let cached: FPLBootstrap = await CacheStore.shared.get(kBootstrap, ttl: CacheTTL.bootstrap) {
            await MemoryStore.shared.cacheBootstrap(cached)
            return (cached, .live)
        }
        // 3) Network; on failure fall back to the stale cache, rethrow only if that fails too
        do {
            let resp = try await FPLProvider().fetchBootstrap()
            await CacheStore.shared.set(kBootstrap, value: resp)
            await MemoryStore.shared.cacheBootstrap(resp)
            return (resp, .live)
        } catch {
            if let stale: FPLBootstrap = await CacheStore.shared.getStale(kBootstrap) {
                return (stale, .stale)
            }
            throw error
        }
    }

    // MARK: Manual operations

    /// Clear all caches (Settings panel); the next access refetches.
    static func clearCache() async {
        await CacheStore.shared.clear()
        // Memory must be cleared too, otherwise cleared disk data is still served
        // from memory and a manual refresh doesn't get fresh results.
        await MemoryStore.shared.clear()
    }

    /// Fixtures cache key (matches the one used inside `matches()`), shared with
    /// the fixtures-only invalidation path.
    static var fixturesCacheKey: String { "fpl_fixtures_\(SeasonStore.currentSeason)" }

    /// Invalidate only the fixtures cache (memory + disk); bootstrap / standings etc.
    /// are kept. Called by the live-match polling loop so each 60 s tick refreshes
    /// the scores source without re-downloading the whole FPL bootstrap / standings.
    static func invalidateFixtures() async {
        await MemoryStore.shared.clearFixtures()
        await CacheStore.shared.remove(fixturesCacheKey)
    }
}
