import Foundation

// MARK: - 数据仓库（统一入口 + 回退 + 缓存）

// MARK: - 数据仓库（统一入口 + 回退 + 缓存）

/// 统一的数据获取入口，负责「公开 API / 过期缓存（stale-if-error）」的回退决策与缓存。
/// 网络失败时回退上次成功落盘的数据；无任何缓存（如首启即断网）返回空，UI 显示空状态。
enum DataRepository {
    // 缓存 key 前缀
    private static let kBootstrap = "fpl_bootstrap"
    private static let kStandings = "espn_standings"

    /// 是否应降级到下一级兜底（空数据 / 过期缓存）
    /// - 降级：429（限频）/ 网络失败 / 无数据
    /// - 上抛：403 / 400 等其它 HTTP 错误、解析错误
    static func shouldFallback(_ err: AppError) -> Bool {
        switch err {
        case .apiError(let code): return code == 429
        case .network:            return true
        case .noData:             return true
        case .decoding:           return false
        }
    }

    // MARK: 积分榜：fallback（v3 records → 已结束赛事聚合 → 过期缓存 → 空）

    /// fallback 策略：
    ///   1. v3 standings records 字段（ESPN 自带的官方积分榜，等赛后由 ESPN 自己填充）
    ///   2. **本项目核心**：从赛程（FPL fixtures）已结束赛事实时聚合积分（不依赖 ESPN records）
    ///   3. 网络失败时回退磁盘上的过期缓存（stale-if-error：赛程聚合若不可用，用上次落盘的 v3 榜）
    ///   4. 彻底无数据 → 空数组（UI 显示「暂无数据」）
    ///
    /// 用户痛点：英超第一轮已经踢完，但 v3 standings 的 records 字段可能真空很久未更新；
    ///          因此 2 级 fallback 是必需的实时兜底，**不依赖 ESPN 自己攒 records**。
    static func standings() async throws -> ([StandingRow], DataSource) {
        // 1. 尝试 v3 直接积分榜（如 records 已生成）
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
            // v3 失败，跳到下一级
        }

        // 2. 复用赛程（FPL fixtures / scoreboard）已结束赛事实时聚合积分（核心：不等 ESPN records）。
        //    赛程本身是过期缓存时也能聚合 —— 内容真实，只是不新鲜，来源标 .stale。
        let (ms, src) = await DataRepository.matches()
        if src != .sample {
            let rows = StandingsAggregator.aggregate(matches: ms)
            if !rows.isEmpty { return (rows, src) }
        }

        // 3. 过期的 v3 官方榜缓存（stale-if-error）
        if let stale: ESPNStandingsCoreResponse = await CacheStore.shared.getStale(kStandings) {
            let rows = ESPNTranslator.standingRows(from: stale)
            if !rows.isEmpty { return (rows, .stale) }
        }

        // 4. 彻底无数据
        return ([], .sample)
    }

    // MARK: 赛程（FPL fixtures 为主，ESPN scoreboard 兜底；网络失败回退过期缓存）
    /// FPL fixtures 端点直接给出每场比赛的轮次（event）、真实比分、参赛队；
    /// 参赛队映射到 FPL bootstrap teams（自带官方队徽 URL），是最稳的赛程来源。
    /// TTL 内缓存命中后秒开；网络失败时回退上次落盘的赛程（忽略 TTL）。
    static func matches() async -> ([Match], DataSource) {
        let cacheKey = fixturesCacheKey
        // 1) 内存（同一生命周期内最快路径，切 tab 秒开）
        if let mem = await MemoryStore.shared.cachedFixtures(), !mem.isEmpty {
            return (mem, .live)
        }
        // 2) 磁盘缓存（TTL 内）
        if let cached: [Match] = await CacheStore.shared.get(cacheKey, ttl: CacheTTL.fixtures), !cached.isEmpty {
            await MemoryStore.shared.cacheFixtures(cached)
            return (cached, .live)
        }
        // 3) 网络取数（FPL → ESPN 兜底），整体 20 秒预算：超时不无限等。
        if let ms = await withTimeBudget(seconds: 20, operation: { await fetchMatchesFromNetwork() }) {
            await CacheStore.shared.set(cacheKey, value: ms)
            await MemoryStore.shared.cacheFixtures(ms)
            return (ms, .live)
        }
        // 4) 网络失败/超时 → 上次成功落盘的赛程（忽略 TTL，stale-if-error）。
        //    刻意**不**写入 MemoryStore：内存缓存只放新鲜数据，避免 stale 被后续路径当成 live。
        if let stale: [Match] = await CacheStore.shared.getStale(cacheKey), !stale.isEmpty {
            return (stale, .stale)
        }
        // 5) 彻底无数据（如首次安装且断网）→ 空数组，UI 显示「暂无赛程」
        return ([], .sample)
    }

    /// 网络取赛程：FPL fixtures 为主，ESPN scoreboard 兜底。任一级成功即返回。
    /// 抽出来是为了能被 `withTimeBudget` 整体包住 —— 否则两级各 30 秒超时，
    /// 最坏情况要等 60 秒才能确定「两级都失败」再走过期缓存兜底。
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

    /// 当前轮次（gameweek）：优先 is_current，其次 is_next，再次最新已结束轮，最后回退第 1 轮
    static func currentGameweek() async -> Int? {
        guard let events = await gameweeks() else { return nil }
        return deriveCurrentRound(events)
    }

    /// 纯函数：从 events 派生「当前轮次」。
    /// 优先级 is_current > is_next > 最新已结束轮 > 首个轮次。
    /// 独立成函数是为了让调用方能「一次取 events，同时拿到当前轮和赛季进度」，
    /// 避免同一份 bootstrap 被反复解码。
    static func deriveCurrentRound(_ events: [FPLGameweek]) -> Int? {
        if let cur = events.first(where: { $0.is_current == true }) { return cur.id }
        if let nxt = events.first(where: { $0.is_next == true }) { return nxt.id }
        if let last = events.filter({ $0.finished == true }).map(\.id).max() { return last }
        return events.first?.id
    }

    /// 完整 gameweek 列表（含 is_current/is_next/finished/deadline_time），
    /// 供「赛季总览」用 —— 比 currentGameweek 更重，但只调一次（走内存缓存后几乎零成本）。
    static func gameweeks() async -> [FPLGameweek]? {
        do {
            let (bootstrap, _) = try await loadOrFetchBootstrap()
            return bootstrap.events ?? []
        } catch {
            return nil
        }
    }

    // MARK: 球队 / 球员（从 FPL bootstrap 派生）

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

    // MARK: 射手榜 / 助攻榜 / 伤停榜

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

    // MARK: 内部：bootstrap 加载（带缓存 + stale 兜底）

    /// 返回 `(bootstrap, 来源)`。网络失败时回退磁盘上的过期缓存（stale-if-error），
    /// 上层派生端点（球队 / 射手 / 助攻 / 伤停 / 轮次）因此无需各自写兜底。
    private static func loadOrFetchBootstrap() async throws -> (bootstrap: FPLBootstrap, source: DataSource) {
        // 1) 内存：同一生命周期内直接命中，零 IO 零解码
        if let mem = await MemoryStore.shared.cachedBootstrap() { return (mem, .live) }
        // 2) 磁盘缓存（TTL 内）
        if let cached: FPLBootstrap = await CacheStore.shared.get(kBootstrap, ttl: CacheTTL.bootstrap) {
            await MemoryStore.shared.cacheBootstrap(cached)
            return (cached, .live)
        }
        // 3) 网络；失败时回退过期缓存，仍拿不到才上抛
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

    // MARK: 主动操作

    /// 清空所有缓存（设置面板调用，下次访问会重新拉取）
    static func clearCache() async {
        await CacheStore.shared.clear()
        // 必须同时清内存，否则清完磁盘仍会命中内存里的旧数据，手动刷新拿不到最新结果
        await MemoryStore.shared.clear()
    }

    /// 赛程缓存 key（与 matches() 内部一致），供「只失效赛程」复用
    static var fixturesCacheKey: String { "fpl_fixtures_\(SeasonStore.currentSeason)" }

    /// 只失效赛程缓存（内存 + 磁盘），保留 bootstrap / 积分榜等。
    /// 比赛期间自动刷新轮询调用：只刷新比分来源（matches），
    /// 不再每 60s 重下整份 FPL bootstrap / 积分榜。
    static func invalidateFixtures() async {
        await MemoryStore.shared.clearFixtures()
        await CacheStore.shared.remove(fixturesCacheKey)
    }
}
