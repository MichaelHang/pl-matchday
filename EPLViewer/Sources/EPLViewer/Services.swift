import Foundation

// MARK: - 赛季常量

/// 当前赛季常量
/// App 当前只 focus 在 2026-27 赛季（ESPN 的 season=2026，跨年赛季）。
/// 历史赛季相关能力（多赛季切换、缓存 TTL 按赛季隔离）暂不实现。
/// 后续要支持时，在 DataRepository 各 fetch 方法入参加 season 即可扩展。
enum SeasonStore {
    static let currentSeason: String = "2026"

    /// 跨年赛季的显示标签，如 "2026-2027"（英超 8 月开打、次年 5 月收官）。
    /// UI 标题（侧边栏 / 详情页）用这个字符串显示完整赛季名。
    static var seasonLabel: String {
        let start = Int(currentSeason) ?? 2026
        return "\(start)-\(start + 1)"
    }
}

/// 给任意 async 取数加时间预算，超预算即放弃并返回 nil。
///
/// 存在的意义：UI 的「首屏渲染」不该被锦上添花的数据拖死。
/// 比如赛季进度依赖 FPL bootstrap，而该接口在国内实测会慢到几十秒；
/// 与其让用户干等转圈，不如先出比赛列表，进度信息拿不到就算了。
///
/// - 注意：超预算后底层任务会被 cancel，但已经发出去的请求仍会在后台跑完，
///   结果只是被丢弃（不会写坏缓存，因为写入发生在任务内部、取消后即失效）。
/// - Parameter operation: 允许返回 nil（数据源拿不到时的正常结果），
///   所以泛型 T 是**非可选**的结果类型，避免 `T??` 双重可选把调用方绕晕。
func withTimeBudget<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        // 谁先完成用谁：正常返回取第一个（可能是数据，也可能是超时哨兵）
        let first = await group.next()
        group.cancelAll()
        return first ?? nil
    }
}

// MARK: - 网络会话（统一超时）

/// 统一的网络会话配置。
///
/// ⚠️ 为什么不能直接用 `URLSession.shared`：
/// 它的 `timeoutIntervalForResource` 默认是 **7 天**。遇到「TCP 连上了、但服务端慢慢吐数据」
/// 的情况（实测 fantasy.premierleague.com/api/bootstrap-static/ 会挂 30 秒以上仍不结束），
/// 请求会一直挂着既不成功也不失败 —— `await` 永不返回，
/// ViewModel 里的 `isLoading` 就永远复位不了，界面表现是「一直转圈 + 点不动」
/// （loading 遮罩盖住了整个内容区）。
/// 这里统一收紧超时，让慢请求**快速失败**，从而能落到下一级兜底数据源。
enum APIClient {
    /// 主数据请求（FPL / ESPN）
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15    // 两次收到数据之间的最大间隔
        cfg.timeoutIntervalForResource = 30   // 整个请求的总时长上限
        cfg.waitsForConnectivity = false      // 断网时立刻失败，好让兜底数据顶上
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EPLViewer/2.0"
        ]
        return URLSession(configuration: cfg)
    }()

    /// 队徽等小资源：更激进的超时，宁可显示占位盾牌也不要拖慢列表
    static let imageSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
}

// MARK: - 缓存层（on-disk JSON with TTL）

/// 缓存 TTL 配置（不同数据使用不同过期时长）
enum CacheTTL {
    /// 赛程/比分：懒刷新 TTL（仅约束「切 tab / 启动」等被动取数的新鲜度）。
    /// Match 内含实时比分，已结束比赛的比分会随赛后更新；
    ///   但 TTL 只决定「被动取数多久算陈旧」，手动刷新会先清缓存强制拿最新，
    ///   因此这里给一个浏览友好的 5 分钟——平时不频繁打扰网络，
    ///   想立刻看结果时点右上角刷新即可（绕过此 TTL）。
    static let fixtures: TimeInterval = 60 * 5
    /// FPL bootstrap：携带球队/射手/助攻/伤停数据，每场比赛后才会更新，缓存 2 小时
    static let bootstrap: TimeInterval = 60 * 60 * 2
    /// 积分榜：懒刷新 TTL（同 fixtures，5 分钟）。手动刷新同样绕过。
    static let standings: TimeInterval = 60 * 5
    /// 赛果：按日刷新即可，缓存 5 分钟
    static let scoreboard: TimeInterval = 60 * 5

    /// 纯函数：判断缓存是否在 TTL 内（便于单测）
    static func isValid(mtime: Date, ttl: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(mtime) < ttl
    }
}

/// 进程内内存缓存（actor 保证线程安全）
///
/// 磁盘缓存（CacheStore）解决「跨 App 启动」的持久化，但每次取数都要
/// 读文件 + JSONDecoder 全量解码 —— 切一次 tab 就把 bootstrap 解两遍
/// （currentGameweek + gameweeks），既慢又白耗电。
/// 这里补一层内存缓存：同一生命周期内只解码一次，之后直接返回内存对象。
///
/// ⚠️ 手动刷新 / 清缓存时必须一并清空（见 DataRepository.clearCache），
/// 否则清完磁盘仍会命中内存里的旧数据。
actor MemoryStore {
    static let shared = MemoryStore()

    private var bootstrap: FPLBootstrap?
    private var fixtures: [Match]?

    func cachedBootstrap() -> FPLBootstrap? { bootstrap }
    func cacheBootstrap(_ value: FPLBootstrap) { bootstrap = value }

    func cachedFixtures() -> [Match]? { fixtures }
    func cacheFixtures(_ value: [Match]) { fixtures = value }

    /// 清空全部内存缓存（手动刷新 / 设置里清缓存时调用）
    func clear() {
        bootstrap = nil
        fixtures = nil
    }

    /// 只清赛程（比赛期间自动刷新轮询用），保留 bootstrap
    func clearFixtures() { fixtures = nil }
}

/// 简易落盘缓存（actor 保证线程安全）
actor CacheStore {
    static let shared = CacheStore()

    private let cacheDir: URL

    /// - Parameter directory: 缓存目录；nil 用默认（App Support/EPLViewer/cache）。
    ///   测试注入临时目录，避免污染真实缓存。
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

    /// 文件名安全化
    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: "?", with: "_")
           .replacingOccurrences(of: "&", with: "_")
    }

    /// 读取缓存（带 TTL 判断）
    func get<T: Decodable>(_ key: String, ttl: TimeInterval) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u),
              let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              let mtime = attrs[.modificationDate] as? Date,
              CacheTTL.isValid(mtime: mtime, ttl: ttl)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 读取缓存，**忽略 TTL**（stale-if-error 兜底）。
    ///
    /// 用途：网络失败 / 超时、且 TTL 内缓存也没有时，回退到上次成功落盘的数据 ——
    /// 内容真实但可能过期，好过空白或假样例。解码失败（文件损坏）返回 nil。
    func getStale<T: Decodable>(_ key: String) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 写入缓存
    func set<T: Encodable>(_ key: String, value: T) {
        let u = url(for: key)
        let enc = JSONEncoder()
        if let data = try? enc.encode(value) {
            try? data.write(to: u, options: .atomic)
        }
    }

    /// 清除所有缓存
    func clear() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
    }

    /// 只删某个 key（比赛期间自动刷新只失效赛程缓存用），不动其它缓存
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}

// MARK: - ESPN 公开 API Provider

/// ESPN 公开 API 客户端（无需 API Key）
/// 重要：原 site.api.espn.com/apis/site/v2/... 现在全部返回空 {}（CDN/权限限制）。
/// 真正可用的端点是 sports.core.api.espn.com/v2/...（core v3 API）。
/// 已知端点（实测 2026-08-23）：
///   ✅ standings:        /v2/.../seasons/{s}/types/1/groups/23/standings/0
///   ✅ events (schedule): /v2/.../events?dates=YYYYMMDD-YYYYMMDD
///   ✅ teams:            /v2/.../seasons/{s}/teams
///   ❌ scorers (该 v3 API 不直接提供，改走 FPL bootstrap)
struct ESPNProvider {
    /// 英格兰超级联赛（eng.1 = Premier League） core v3 端点（实测可用）
    let base = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1"

    /// 拉取积分榜（v3 core 多层 $ref，已编平为单层 records/stats）
    /// 注：8-9 月份赛季初 records 字段可能为空数组（积分尚未统计），
    ///     Repository 层会回退到「从赛程聚合」或「上次落盘的积分榜缓存」。
    func fetchStandings(season: Int) async throws -> ESPNStandingsCoreResponse {
        try await get("\(base)/seasons/\(season)/types/1/groups/23/standings/0?lang=en&region=us")
    }

    /// 拉取某天赛果（YYYYMMDD，可选范围），用于日常小数据刷新
    func fetchScoreboard(date: String? = nil) async throws -> ESPNScoreboardResponse {
        var path = "\(base)/events"
        if let d = date { path += "?dates=\(d)" }
        return try await get(path)
    }

    /// 拉取整赛季赛程（site API scoreboard）。
    /// 与 core/events 不同，该端点直接内联 队名 / 队徽 / 比分 / 日期，无需 follow $ref，
    /// 且返回结构正好匹配 ESPNScoreboardResponse（用于赛程与积分聚合）。
    func fetchScoreboardSchedule(dates: String) async throws -> ESPNScoreboardResponse {
        let url = "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=\(dates)"
        return try await get(url)
    }

    /// 拉取整赛季赛程。
    /// 当前 v3 core API 没有稳定的 season= 过滤参数；site.api.espn.com 的对应端点已 403/空。
    /// 此处先尝试 v2 site API（仍可能空），并依赖 DataRepository 的回退链（过期缓存 → 空）。
    func fetchSchedule(season: Int) async throws -> ESPNScoreboardResponse {
        let url = "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/schedule?season=\(season)"
        return try await get(url)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path) else { throw AppError.apiError(0) }
        var request = URLRequest(url: url)
        // core v3 API 对 UA 有要求：缺省会被 CDN 屏蔽返回空 {}。
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EPLViewer/2.0", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await APIClient.session.data(for: request)
        } catch {
            throw AppError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError.apiError(http.statusCode)
        }
        let decoder = JSONDecoder()
        do { return try decoder.decode(T.self, from: data) }
        catch { throw AppError.decoding(error) }
    }
}

// ESPN core v3 原生 JSON 模型（适配 /standings/0 端点返回结构）
struct ESPNStandingsCoreResponse: Codable {
    let name: String?
    let displayName: String?
    let standings: [ESPNStandingEntryV3]   // 顶层就是队列表（≠ 之前的嵌套 children）
}
struct ESPNStandingEntryV3: Codable {
    let team: ESPNTeamRefV3               // 仅 $ref，需要二次 GET 拿详情
    let records: [ESPNRecordV3]?          // 积分数据（如 points/W/D/L/GF/GA），赛季初可能为空
    let stats: [ESPNStatV3]?              // 部分字段以 stats 形式挂载
    let rank: Int?
    let note: ESPNStandingNoteV3?         // CL/EL/RELEGATION 等
}
struct ESPNTeamRefV3: Codable {
    let id: String?                      // 部分端点返回 id 而非 $ref
    let name: String?                    // 内联场景下
    let shortName: String?
    let displayName: String?
    let logos: [ESPNLogoV3]?
    let abbreviation: String?

    // CodingKeys：用 dollarRef 接收 $ref JSON 字段（Swift 不允许 $ 前缀属性名）
    enum CodingKeys: String, CodingKey {
        case id, name, shortName, displayName, logos, abbreviation
        case dollarRef = "$ref"
    }
    let dollarRef: String?
}
struct ESPNLogoV3: Codable {
    let href: String?
}
struct ESPNRecordV3: Codable {
    let name: String?       // "wins" / "losses" / "ties" / "points" / "played" / "rank" / "pointsFor"
    let displayName: String?
    let shortDisplayName: String?
    let value: Double?
    let stats: [ESPNStatV3]?
}
struct ESPNStatV3: Codable {
    let name: String?
    let value: Double?
    let displayValue: String?
}
struct ESPNStandingNoteV3: Codable {
    let color: String?      // 例如 CL 蓝色 / EL 橙色 / R 红色
    let description: String?
    let rank: Int?
}

// MARK: - ESPN v3 events 端点模型

/// events 列表响应（paged）：顶层 items 是分页的赛事 $ref
struct ESPNEventsListResponse: Codable {
    let count: Int?
    let pageIndex: Int?
    let pageSize: Int?
    let pageCount: Int?
    let items: [ESPNAbstractRef]
}
/// 通用 { "$ref": "..." } 格式（用于赛事/team $ref 列表项）
struct ESPNAbstractRef: Codable {
    let dollarRef: String?
    let id: String?
    let name: String?     // 部分赛事列表会内联赛事短名
    let date: String?

    enum CodingKeys: String, CodingKey {
        case dollarRef = "$ref"
        case id, name, date
    }
}

/// events 列表里的 item，如果赛事还没开始可能只有 $ref；
/// 已结束赛事可能内联 name/date
struct ESPNCompetitorV3: Codable {
    let id: String?
    let homeAway: String?     // "home" / "away"
    let winner: Bool?
    let team: ESPNTeamRefV3?
    /// 比分会内嵌到 ScoreV3 子对象（不总是有）
    let score: ESPNScoreV3?
}
struct ESPNScoreV3: Codable {
    let value: Double?
    let displayValue: String?
}
struct ESPNCompetitionV3: Codable {
    let id: String?
    let date: String?
    let competitors: [ESPNCompetitorV3]?
    let status: ESPNStatusV3?
    let venue: ESPNVenueV3?
}
struct ESPNStatusV3: Codable {
    let clock: Double?
    let displayClock: String?
    let period: Int?
    let type: ESPNStatusTypeV3?
}
struct ESPNStatusTypeV3: Codable {
    let name: String?         // STATUS_FULL_TIME / STATUS_SCHEDULED / STATUS_IN_PROGRESS / STATUS_POSTPONED ...
    let state: String?        // "pre" / "in" / "post"
    let completed: Bool?
    let description: String?
    let shortDetail: String?
}
struct ESPNVenueV3: Codable {
    let id: String?
    let fullName: String?
    let address: ESPNAddressV3?
}
struct ESPNAddressV3: Codable {
    let city: String?
    let country: String?
}
/// v3 单场赛事（深层）
struct ESPNEventDetailV3: Codable {
    let id: String?
    let date: String?
    let name: String?
    let shortName: String?
    let competitions: [ESPNCompetitionV3]?
}

// MARK: - v3 events 客户端与赛事聚合

/// ESPN v3 events 专用 fetcher：负责拉赛事列表 + 单场赛事详情（follow $ref）
/// 配合 `StandingsAggregator` 从已结束赛事实时聚合积分榜。
enum ESPNEventsProvider {
    /// 静态 User-Agent（v3 必须带 UA，否则 CDN 屏蔽返回空 {}）
    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EPLViewer/2.0"

    /// 拉某日期范围内所有赛事 ID（去重，完整拉取多页）
    /// - Parameter dates: `YYYYMMDD-YYYYMMDD` ESPN dates 格式
    /// - Returns: 赛事 ID 列表（如 ["401879301", ...]）
    static func fetchEventIds(dates: String, limit: Int = 100) async throws -> [String] {
        var allIds: [String] = []
        var pageIndex = 1
        // v3 events 端点分页；pageSize 默认 10，pageCount = ceil(count/10)
        while true {
            let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/events?dates=\(dates)&lang=en&region=us&limit=\(limit)&page=\(pageIndex)"
            let resp: ESPNEventsListResponse = try await fetchJSON(url)
            for item in resp.items {
                if let id = item.id { allIds.append(id) }
                else if let ref = item.dollarRef,
                        let idStr = ref.split(separator: "/events/").last?.split(separator: "?").first {
                    allIds.append(String(idStr))
                }
            }
            guard let totalPages = resp.pageCount, pageIndex < totalPages else { break }
            pageIndex += 1
            if pageIndex > 50 { break } // 防御：单赛季不超过 50 页
        }
        return Array(Set(allIds)).sorted()
    }

    /// 拉单场赛事详情（已含 inline competitors，含 winner 字段；score 仍是 $ref）
    static func fetchEventDetail(eventId: String) async throws -> ESPNEventDetailV3 {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/events/\(eventId)?lang=en&region=us"
        return try await fetchJSON(url)
    }

    /// 拉赛事某 competitor 的分数（v3 score 是 $ref）
    static func fetchCompetitorScore(eventId: String, competitorId: String) async throws -> Int {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/events/\(eventId)/competitions/\(eventId)/competitors/\(competitorId)/score?lang=en&region=us"
        struct R: Codable { let value: Double? }
        let r: R = try await fetchJSON(url)
        return Int(r.value ?? 0)
    }

    /// 拉单队详情（含 name/logos/abbreviation/venue/address）
    static func fetchTeam(teamId: String) async throws -> ESPNTeamRefV3 {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/seasons/\(SeasonStore.currentSeason)/teams/\(teamId)?lang=en&region=us"
        return try await fetchJSON(url)
    }

    /// JSON GET（自动加 User-Agent；失败抛 AppError）
    private static func fetchJSON<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw AppError.apiError(0) }
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await APIClient.session.data(for: req)
        } catch {
            throw AppError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError.apiError(http.statusCode)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AppError.decoding(error) }
    }
}

/// 已结束赛事聚合得到的"准实时积分榜"
/// 关键能力：当 v3 standings records 字段尚未生成时，从已踢完的赛事实时算 W/D/L/Pts/GF/GA。
struct StandingsAggregator {
    /// 内部条目：teamId + 比分
    struct RowStat {
        var played: Int = 0
        var won: Int = 0
        var draw: Int = 0
        var lost: Int = 0
        var gf: Int = 0
        var ga: Int = 0
        func points() -> Int { won * 3 + draw }
        func gd() -> Int { gf - ga }
    }

    /// 拉过去 N 天已结束赛事，统计 W/D/L/Pts/GF/GA，按积分降序
    /// - 实现：拉 events 列表 → follow 每个赛事（status.state == "post"）→ 统计
    /// - 缓存：单赛事详情缓存 5 分钟（赛事比分很少变），汇总结果缓存 60 秒（与 standings TTL 对齐）
    static func aggregate(daysBack: Int = 14) async throws -> [StandingRow] {
        // 1. 计算日期范围
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd"; df.timeZone = TimeZone(identifier: "UTC")
        let dates = "\(df.string(from: start))-\(df.string(from: now))"

        // 2. 拉赛事 ID
        let eventIds = try await ESPNEventsProvider.fetchEventIds(dates: dates)
        guard !eventIds.isEmpty else { return [] }

        // 3. 并发 follow 单场赛事详情（8 并发足够，避免过度请求）
        let details: [ESPNEventDetailV3] = await withTaskGroup(of: ESPNEventDetailV3?.self) { group in
            var results: [ESPNEventDetailV3] = []
            let semaphore = AsyncSemaphore(value: 8)
            for id in eventIds {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    return (try? await ESPNEventsProvider.fetchEventDetail(eventId: id))
                }
            }
            for await detail in group {
                if let d = detail { results.append(d) }
            }
            return results
        }

        // 4. 筛选已结束赛事 + 解析 W/D/L（GF/GA 等比分并发拉完后再统一累加）
        var stats: [Int: RowStat] = [:]   // key = ESPN team.id (Int)
        var teamMeta: [Int: ESPNTeamRefV3] = [:]   // 用于赛后回填 team 详情
        var finishedPairs: [(eventId: String, homeId: Int, awayId: Int)] = []   // 待补比分的已结束赛事

        for detail in details {
            guard let comp = detail.competitions?.first else { continue }
            // 仅处理已结束赛事：
            //   v3 单场赛事里 status 字段是 $ref 需要再 follow；这里用更直接的方式：
            //   任一 competitor.winner 字段不是 nil → 该场已出胜负（draw 时两队 winner 都为 false）
            //   进行中 / 未开始赛事的 winner 字段均为 nil
            guard let competitors = comp.competitors, competitors.count >= 2 else { continue }
            let hasResult = competitors.contains { $0.winner != nil }
            guard hasResult else { continue }

            // 拿主客（v3 单场赛事里 team 是 $ref；用 competitor.id 即为 team id）
            let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
            let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
            guard let homeId = Int(home.id ?? ""),
                  let awayId = Int(away.id ?? "") else { continue }

            // team ref 用于赛后回填（可选）
            if let h = home.team { teamMeta[homeId] = h }
            if let a = away.team { teamMeta[awayId] = a }

            // 拿 score：competitors.score 经常是 $ref，需要 follow —— 记下本场主客，稍后并发拉取
            finishedPairs.append((eventId: detail.id ?? "", homeId: homeId, awayId: awayId))

            // 即时统计：先按 winner 算 W/D/L，GF/GA 后续补
            let homeWin = home.winner == true
            let awayWin = away.winner == true
            let draw = (home.winner == false && away.winner == false && home.winner != nil)

            // 拿到 team 后再聚合：每个赛事算主客的两条统计
            var hst = stats[homeId] ?? RowStat()
            var ast = stats[awayId] ?? RowStat()
            hst.played += 1
            ast.played += 1
            if homeWin {
                hst.won += 1
                ast.lost += 1
            } else if awayWin {
                ast.won += 1
                hst.lost += 1
            } else if draw {
                hst.draw += 1
                ast.draw += 1
            }
            stats[homeId] = hst
            stats[awayId] = ast
        }

        // 5. 并发 follow 每场已结束赛事双方的比分（score 在 v3 里是 $ref）。
        //    原实现在主循环里逐场串行 await —— 一轮 10 场要串行发 20 个请求，慢得离谱。
        var scores: [String: Int] = [:]   // key = "eventId-teamId"
        await withTaskGroup(of: (String, Int).self) { group in
            let semaphore = AsyncSemaphore(value: 8)
            for pair in finishedPairs {
                for teamId in [pair.homeId, pair.awayId] {
                    group.addTask {
                        await semaphore.wait()
                        defer { Task { await semaphore.signal() } }
                        let value = (try? await ESPNEventsProvider.fetchCompetitorScore(
                            eventId: pair.eventId, competitorId: String(teamId))) ?? 0
                        return ("\(pair.eventId)-\(teamId)", value)
                    }
                }
            }
            for await (key, value) in group {
                scores[key] = value
            }
        }

        // 6. 用真实比分**累加** GF/GA（一支球队打了多场，GF/GA 是总和；
        //    旧实现在这里用 `=` 覆盖，导致 GF/GA 永远只剩最后一场的数字）
        for pair in finishedPairs {
            let hg = scores["\(pair.eventId)-\(pair.homeId)"] ?? 0
            let ag = scores["\(pair.eventId)-\(pair.awayId)"] ?? 0
            var hst = stats[pair.homeId] ?? RowStat()
            var ast = stats[pair.awayId] ?? RowStat()
            hst.gf += hg; hst.ga += ag
            ast.gf += ag; ast.ga += hg
            stats[pair.homeId] = hst
            stats[pair.awayId] = ast
        }

        // 7. follow team 详情拿 name/crest（去重，并发）
        let teamIds = Array(teamMeta.keys)
        var resolvedTeams: [Int: ESPNTeamRefV3] = [:]
        await withTaskGroup(of: (Int, ESPNTeamRefV3?).self) { group in
            for id in teamIds {
                group.addTask {
                    if let t = try? await ESPNEventsProvider.fetchTeam(teamId: String(id)) {
                        return (id, t)
                    }
                    return (id, nil)
                }
            }
            for await (id, t) in group {
                if let t = t { resolvedTeams[id] = t }
            }
        }

        // 8. 装配 StandingRow
        let rows: [StandingRow] = stats.map { (teamId, st) in
            let name = resolvedTeams[teamId]?.displayName ?? resolvedTeams[teamId]?.name ?? "Team #\(teamId)"
            let crest = resolvedTeams[teamId]?.logos?.first?.href
            let team = Team(
                id: teamId, name: name, shortName: resolvedTeams[teamId]?.abbreviation,
                crest: crest, venue: nil, founded: nil, coach: nil, squad: nil
            )
            return StandingRow(
                position: 0,   // 排序后再赋
                team: team,
                playedGames: st.played, won: st.won, draw: st.draw, lost: st.lost,
                points: st.points(), goalsFor: st.gf, goalsAgainst: st.ga,
                goalDifference: st.gd(),
                form: nil, status: nil, home: nil, away: nil
            )
        }
        // 完全同分同净胜球同进球时按 teamId 稳定排序 —— stats 是字典、遍历顺序不定，
        // 不加最终 tiebreak 的话，两次渲染的行序可能不同
        let sorted = rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.team.id < $1.team.id
        }
        return sorted.enumerated().map { (idx, r) in
            StandingRow(position: idx + 1, team: r.team,
                       playedGames: r.playedGames, won: r.won, draw: r.draw, lost: r.lost,
                       points: r.points, goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst,
                       goalDifference: r.goalDifference, form: r.form, status: r.status, home: nil, away: nil)
        }
    }

    /// 从已拉取的赛果（含比分）实时聚合积分榜。
    /// 复用赛程数据源（scoreboard），避免再走 core/events 的 $ref 链；
    /// 只统计 status == FINISHED 且含比分的比赛，未参赛球队不会出现、也不会得到积分。
    static func aggregate(matches: [Match]) -> [StandingRow] {
        var stats: [Int: RowStat] = [:]
        var teamMeta: [Int: Team] = [:]
        for m in matches where m.status == "FINISHED" {
            guard let ft = m.score?.fullTime, let h = ft.home, let a = ft.away else { continue }
            let hid = m.homeTeam.id, aid = m.awayTeam.id
            teamMeta[hid] = m.homeTeam
            teamMeta[aid] = m.awayTeam
            var hs = stats[hid] ?? RowStat()
            var as_ = stats[aid] ?? RowStat()
            hs.played += 1; as_.played += 1
            if h > a      { hs.won += 1; as_.lost += 1 }
            else if a > h { as_.won += 1; hs.lost += 1 }
            else          { hs.draw += 1; as_.draw += 1 }
            hs.gf += h; hs.ga += a
            as_.gf += a; as_.ga += h
            stats[hid] = hs; stats[aid] = as_
        }
        let rows: [StandingRow] = stats.map { (teamId, st) in
            let team = teamMeta[teamId] ?? Team(
                id: teamId, name: "Team #\(teamId)", shortName: nil, crest: nil,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            return StandingRow(
                position: 0, team: team,
                playedGames: st.played, won: st.won, draw: st.draw, lost: st.lost,
                points: st.points(), goalsFor: st.gf, goalsAgainst: st.ga,
                goalDifference: st.gd(), form: nil, status: nil, home: nil, away: nil
            )
        }
        // 完全同分同净胜球同进球时按 teamId 稳定排序 —— stats 是字典、遍历顺序不定，
        // 不加最终 tiebreak 的话，两次渲染的行序可能不同
        let sorted = rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.team.id < $1.team.id
        }
        return sorted.enumerated().map { (idx, r) in
            StandingRow(position: idx + 1, team: r.team,
                       playedGames: r.playedGames, won: r.won, draw: r.draw, lost: r.lost,
                       points: r.points, goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst,
                       goalDifference: r.goalDifference, form: r.form, status: r.status, home: nil, away: nil)
        }
    }
}

// MARK: - 积分榜 enrichment（home/away 拆分 + form）

/// ESPN 现行的 standings API 不直接返回「主场战绩 / 客场战绩」拆分。
/// 这个模块从已结束的赛程本地聚合：
/// - `venueStats(for:matches:isHome:)`：算某队主场或客场的 W/D/L/GF/GA/Pts
/// - `formString(for:matches:last:)`：从最近 N 场完赛推导 W/D/L 序列
/// - `enrich(rows:with:matches:)`：给一行 StandingRow 补 home/away（仅当原来没值时）
///
/// 是纯函数（不依赖环境），便于单元测试。
struct StandingsEnricher {

    /// 某队在「主场」或「客场」维度下的战绩。
    /// - Parameters:
    ///   - teamId: 球队 id
    ///   - matches: 全部比赛（含未开赛、进行中、已结束；本函数只取已结束 + 有比分的）
    ///   - isHome: true=仅算主场比赛，false=仅算客场比赛
    /// - Returns: `nil` 表示「该队在指定维度下没有任何已结束比赛」（UI 区分"无数据"与"踢了但全输"）
    static func venueStats(for teamId: Int, matches: [Match], isHome: Bool) -> VenueStats? {
        let relevant = matches.filter { m in
            guard m.status == "FINISHED",
                  let _ = m.score?.fullTime?.home,
                  let _ = m.score?.fullTime?.away
            else { return false }
            return isHome ? (m.homeTeam.id == teamId) : (m.awayTeam.id == teamId)
        }
        guard !relevant.isEmpty else { return nil }

        var played = 0, won = 0, draw = 0, lost = 0
        var gf = 0, ga = 0
        for m in relevant {
            let hs = m.score?.fullTime?.home ?? 0
            let as_ = m.score?.fullTime?.away ?? 0
            let myScore = isHome ? hs : as_
            let oppScore = isHome ? as_ : hs
            played += 1
            gf += myScore
            ga += oppScore
            if myScore > oppScore { won += 1 }
            else if myScore == oppScore { draw += 1 }
            else { lost += 1 }
        }
        return VenueStats(played: played, won: won, draw: draw, lost: lost,
                          goalsFor: gf, goalsAgainst: ga, points: won * 3 + draw)
    }

    /// 从某队最近 N 场已结束比赛推导胜负序列（如 "WWDLW"）。
    /// - 顺序：从早到晚
    /// - 没有可统计的比赛 → 返回 nil（不是空串，方便 UI 区分「无数据」与「全胜」）
    static func formString(for teamId: Int, matches: [Match], last: Int = 5) -> String? {
        let finished = matches
            .filter { $0.status == "FINISHED"
                && ($0.homeTeam.id == teamId || $0.awayTeam.id == teamId)
                && $0.score?.fullTime?.home != nil
                && $0.score?.fullTime?.away != nil }
            .sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }   // 升序：最早在前
            .suffix(last)                                          // 取最近 N 场（仍升序）
        guard !finished.isEmpty else { return nil }
        return finished.map { m -> String in
            let isHome = m.homeTeam.id == teamId
            let hs = m.score?.fullTime?.home ?? 0
            let as_ = m.score?.fullTime?.away ?? 0
            let myScore = isHome ? hs : as_
            let oppScore = isHome ? as_ : hs
            if myScore > oppScore { return "W" }
            if myScore == oppScore { return "D" }
            return "L"
        }.joined()
    }

    /// 把外部数据源给的 form 归一成紧凑的 "WWDLW"。
    ///
    /// 各数据源写法不统一（有的带分隔符 "W,W,D,L,W"、有的带空格或无 D），
    /// 而 UI 按「前 5 个字符」渲染 —— 不归一会把分隔符当成场次画进胶囊，
    /// 视觉上就像"状态没有更新"。只保留 W/D/L，去掉其它字符后取最近 5 场。
    static func normalizeForm(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let letters = String(raw.filter { $0 == "W" || $0 == "D" || $0 == "L" })
        return letters.isEmpty ? nil : String(letters.suffix(5))
    }

    /// 用 matches 给 standings 行补全 home/away/form。
    /// 行为：原有值不覆盖（可能更权威）；没填的用本地聚合补。
    /// 纯函数；空 rows/空 matches 直接返回原 rows。
    static func enrich(rows: [StandingRow], with matches: [Match]) -> [StandingRow] {
        guard !rows.isEmpty else { return rows }
        return rows.map { row in
            let home = row.home ?? venueStats(for: row.team.id, matches: matches, isHome: true)
            let away = row.away ?? venueStats(for: row.team.id, matches: matches, isHome: false)
            // ⚠️ 必须在这里算 form：ESPN standings 端点不给近 5 场，而 enrich() 原本只补 home/away，
            // 导致「状态」tab 长期全破折号。已有值先归一化（去分隔符），没有才从赛程推导。
            let form = normalizeForm(row.form) ?? formString(for: row.team.id, matches: matches)
            return row.with(home: home, away: away, form: form)
        }
    }
}

/// 简易信号量（控制并发数）
actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(value: Int) { self.value = value }
    func wait() async {
        if value > 0 { value -= 1; return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
    }
    func signal() {
        if let w = waiters.first {
            waiters.removeFirst(); w.resume()
        } else {
            value += 1
        }
    }
}


// ESPN 原生 JSON 模型（仅用于解码/编码缓存，后续翻译为内部模型）
struct ESPNStandingsResponse: Codable {
    let children: [ESPNStandingGroup]?
}
struct ESPNStandingGroup: Codable {
    let standings: ESPNStandings
}
struct ESPNStandings: Codable {
    let entries: [ESPNStandingEntry]
}
struct ESPNStandingEntry: Codable {
    let team: ESPNTeamLite
    let stats: [ESPNStat]
}
struct ESPNTeamLite: Codable {
    let id: String
    let name: String
    let shortName: String?
    let logo: String?
}
struct ESPNStat: Codable {
    let name: String
    let value: Double?
}

struct ESPNScoreboardResponse: Codable {
    let events: [ESPNEvent]?
}
struct ESPNEvent: Codable {
    let id: String
    let date: String?
    let name: String?
    let shortName: String?
    let week: ESPNWeek?
    let competitions: [ESPNCompetition]?
}
struct ESPNWeek: Codable {
    let number: Int?
}
struct ESPNCompetition: Codable {
    let competitors: [ESPNCompetitor]?
    let status: ESPNStatus?
}
struct ESPNCompetitor: Codable {
    let homeAway: String?
    let team: ESPNTeamLite
    let score: ESPNScoreLite?
}
struct ESPNScoreLite: Codable {
    /// scoreboard 端点的比分形态不统一：可能是 数字 3、字符串 "3"、或对象 {"value": 3}
    let value: Double?
    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let v = try? keyed.decode(Double.self, forKey: .value) {
            value = v
        } else {
            let single = try decoder.singleValueContainer()
            if let s = try? single.decode(String.self), let d = Double(s) {
                value = d
            } else if let d = try? single.decode(Double.self) {
                value = d
            } else {
                value = nil
            }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(value, forKey: .value)
    }
    enum CodingKeys: String, CodingKey { case value }
}
struct ESPNStatus: Codable {
    let type: ESPNStatusType?
}
struct ESPNStatusType: Codable {
    let name: String?  // STATUS_FINAL / STATUS_SCHEDULED / STATUS_IN_PROGRESS
    let state: String? // "pre" / "in" / "post"
}

// MARK: - FPL 公开 API Provider

/// FPL 公开 API 客户端（无需 Key）。`bootstrap-static` 一次拉全量，本地派生榜单。
struct FPLProvider {
    let base = "https://fantasy.premierleague.com/api"

    /// 拉取全量 bootstrap（球队/球员/位置/轮次）
    func fetchBootstrap() async throws -> FPLBootstrap {
        try await get("\(base)/bootstrap-static/")
    }

    /// 拉取全量赛程（含轮次 event、比分、开球时间）
    func fetchFixtures() async throws -> [FPLFixture] {
        try await get("\(base)/fixtures/")
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path) else { throw AppError.apiError(0) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await APIClient.session.data(from: url)
        } catch {
            throw AppError.network(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AppError.apiError(http.statusCode)
        }
        let decoder = JSONDecoder()
        do { return try decoder.decode(T.self, from: data) }
        catch { throw AppError.decoding(error) }
    }
}

// FPL 原生 JSON 模型
struct FPLBootstrap: Codable {
    let teams: [FPLTeam]
    let elements: [FPLPlayer]
    let element_types: [FPLPosition]
    let events: [FPLGameweek]?
}
struct FPLTeam: Codable {
    let id: Int
    let code: Int
    let name: String
    let short_name: String
    let strength: Int?
}
struct FPLPlayer: Codable {
    let id: Int
    let web_name: String
    let first_name: String?
    let second_name: String?
    let team: Int
    let element_type: Int
    let goals_scored: Int
    let assists: Int
    let status: String         // a=可出战, i=伤, d=存疑, u=缺阵, s=停赛, n=未注册
    let news: String?
    let chance_of_playing_next_round: Int?
    let now_cost: Int?
}
struct FPLPosition: Codable {
    let id: Int
    let singular_name: String
    let plural_name: String
}
struct FPLGameweek: Codable {
    let id: Int
    let name: String?
    let is_current: Bool?
    let is_next: Bool?
    let finished: Bool?
    /// 该轮的最早截止时间（FPL 用作「该轮第一场开球的近似时间」，
    /// 也作为「赛季总览」卡片的起始日显示依据）
    let deadline_time: String?
}

/// FPL 单场赛程（/api/fixtures/ 返回）
struct FPLFixture: Codable {
    let event: Int?        // 轮次（gameweek）
    let team_h: Int
    let team_a: Int
    let team_h_score: Int?
    let team_a_score: Int?
    let kickoff_time: String
    let finished: Bool
    let started: Bool?
    /// 终场后 FPL 会先置 finished_provisional=true，finished 稍后才翻转；
    /// 是「比赛已结束」更及时的可靠信号（不会在中场/进行中误触发）。
    let finished_provisional: Bool?
    /// 进行分钟数（0=未开球，90=已结束）。兜底判定用。
    let minutes: Int?
}

// MARK: - 内部模型翻译器（ESPN/FPL native → 内部 domain）

/// ESPN 状态名 → 内部统一状态字符串
enum StatusTranslator {
    static func translate(_ espnName: String?) -> String {
        switch espnName {
        case "STATUS_FINAL":        return "FINISHED"
        case "STATUS_SCHEDULED":    return "SCHEDULED"
        case "STATUS_IN_PROGRESS":  return "IN_PLAY"
        case "STATUS_HALFTIME":     return "HALFTIME"
        case "STATUS_POSTPONED":    return "POSTPONED"
        case "STATUS_CANCELED",
             "STATUS_CANCELLED":    return "CANCELED"
        default:                     return espnName ?? "SCHEDULED"
        }
    }
}

/// FPL bootstrap → 内部 Team / Player / Scorer / Assist / Injury 的派生
enum FPLTranslator {
    /// FPL 球队 id → 内部 Team（含从 elements 派生的 squad）
    static func teams(from bootstrap: FPLBootstrap) -> [Team] {
        let positionMap = Dictionary(
            uniqueKeysWithValues: bootstrap.element_types.map { ($0.id, $0.singular_name) }
        )
        let playersByTeam = Dictionary(grouping: bootstrap.elements) { $0.team }

        return bootstrap.teams.map { fplTeam in
            let players = (playersByTeam[fplTeam.id] ?? []).map { fplPlayer in
                Player(
                    id: fplPlayer.id,
                    name: fplPlayer.web_name,
                    position: positionMap[fplPlayer.element_type],
                    shirtNumber: nil,                 // FPL 无号码
                    nationality: nil                  // FPL 无国籍（需另调 element-summary，留待 v2）
                )
            }
            return Team(
                id: fplTeam.id,
                name: fplTeam.name,
                shortName: fplTeam.short_name,
                crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fplTeam.code).png",
                venue: nil,                          // FPL 无球场
                founded: nil,
                coach: nil,                          // FPL 无教练
                squad: players
            )
        }
    }

    /// 球队 id 查找（含 squad）
    static func team(id: Int, from bootstrap: FPLBootstrap) -> Team? {
        teams(from: bootstrap).first { $0.id == id }
    }

    /// 射手榜（按 goals_scored 降序，展示所有进球球员）
    /// 射手榜（按 goals_scored 降序；limit>0 时截前 N 名）
    static func scorers(from bootstrap: FPLBootstrap, limit: Int = 0) -> [Scorer] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let all = bootstrap.elements
            .filter { $0.goals_scored > 0 }
            .sorted { $0.goals_scored > $1.goals_scored }
            .compactMap { p -> Scorer? in
                guard let fpl = teamById[p.team] else { return nil }
                return Scorer(
                    player: PlayerLite(id: p.id, name: p.web_name, nationality: nil),
                    team: Team(
                        id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                        crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                        venue: nil, founded: nil, coach: nil, squad: nil
                    ),
                    goals: p.goals_scored,
                    assists: p.assists,
                    playedMatches: nil
                )
            }
        return limit > 0 ? Array(all.prefix(limit)) : all
    }

    /// 助攻榜（按 assists 降序；limit>0 时截前 N 名）
    static func assists(from bootstrap: FPLBootstrap, limit: Int = 0) -> [Assist] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let all = bootstrap.elements
            .filter { $0.assists > 0 }
            .sorted { $0.assists > $1.assists }
            .compactMap { p -> Assist? in
                guard let fpl = teamById[p.team] else { return nil }
                let lite = PlayerLite(id: p.id, name: p.web_name, nationality: nil)
                let team = Team(
                    id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                    crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                    venue: nil, founded: nil, coach: nil, squad: nil
                )
                return Assist(from: Scorer(
                    player: lite, team: team, goals: p.goals_scored,
                    assists: p.assists, playedMatches: nil
                ))
            }
        return limit > 0 ? Array(all.prefix(limit)) : all
    }

    /// 伤停榜（status != "a"）
    static func injuries(from bootstrap: FPLBootstrap) -> [Injury] {
        let teamById = Dictionary(uniqueKeysWithValues: bootstrap.teams.map { ($0.id, $0) })
        let positionMap = Dictionary(
            uniqueKeysWithValues: bootstrap.element_types.map { ($0.id, $0.singular_name) }
        )
        return bootstrap.elements
            .filter { $0.status != "a" }
            .compactMap { p -> Injury? in
                guard let fpl = teamById[p.team] else { return nil }
                return Injury(
                    player: PlayerLite(id: p.id, name: p.web_name, nationality: nil),
                    team: Team(
                        id: fpl.id, name: fpl.name, shortName: fpl.short_name,
                        crest: "https://resources.premierleague.com/premierleague/badges/50/t\(fpl.code).png",
                        venue: nil, founded: nil, coach: nil, squad: nil
                    ),
                    status: p.status,
                    news: p.news?.isEmpty == false ? p.news : nil,
                    chanceOfPlayingNextRound: p.chance_of_playing_next_round,
                    position: positionMap[p.element_type]
                )
            }
    }

    /// 赛程（从 FPL fixtures 派生，自带轮次 event、真实比分、官方队徽）
    static func matches(from fixtures: [FPLFixture], teams: [FPLTeam]) -> [Match] {
        let teamById = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        return fixtures.compactMap { f in
            guard let h = teamById[f.team_h], let a = teamById[f.team_a] else { return nil }
            let home = Team(id: h.id, name: h.name, shortName: h.short_name,
                            crest: fplCrest(h.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let away = Team(id: a.id, name: a.name, shortName: a.short_name,
                            crest: fplCrest(a.code), venue: nil, founded: nil, coach: nil, squad: nil)
            let hasScore = f.team_h_score != nil && f.team_a_score != nil
            // 「已结束」的权威判定，三选一即可，避免 FPL 翻转 finished 前的滞后
            // 把已结束比赛误判为进行中（导致 ⚽ 误显示）：
            //   1) finished 真正置位；
            //   2) finished_provisional：FPL 终场即置，且不会在中场/进行中误触发（最可靠）；
            //   3) minutes >= 90：分钟数兜底。
            // 仅当「未结束且已开球且未满 90 分钟」才保持 IN_PLAY，由 UI 加 ⚽ 标识区分进行中 / 已结束。
            let over = f.finished
                    || f.finished_provisional == true
                    || (f.minutes ?? 0) >= 90
            let status: String = over ? "FINISHED"
                            : (f.started == true ? "IN_PLAY" : "SCHEDULED")
            // 有比分就填充（不仅限于已结束）：进行中也能显示实时比分，
            // 由 FixturesView 通过 status == IN_PLAY 加 ⚽ 标识区分「进行中 / 已结束」
            let score: Score? = hasScore
                ? Score(fullTime: FullTime(home: f.team_h_score!, away: f.team_a_score!))
                : nil
            let id = (f.event ?? 0) * 1_000_000 + f.team_h * 1_000 + f.team_a
            return Match(id: id, matchday: f.event, utcDate: f.kickoff_time,
                         status: status, stage: nil, homeTeam: home, awayTeam: away, score: score)
        }
    }

    /// FPL 球队 code → 官方队徽 URL
    private static func fplCrest(_ code: Int) -> String {
        "https://resources.premierleague.com/premierleague/badges/50/t\(code).png"
    }
}

/// ESPN standings → 内部 StandingRow 列表
/// 适配 v3 core API：顶层 standings 数组，每项含 records 与 stats；
/// 赛季初（8 月底）records 可能为空，调用方对空 result 做兜底。
enum ESPNTranslator {
    /// 老 v2 模型（保留为兼容 fallback）
    static func standingRows(from resp: ESPNStandingsResponse) -> [StandingRow] {
        let entries = resp.children?.first?.standings.entries ?? []
        return translateStandingsV2(entries: entries)
    }

    /// 新 v3 core 模型
    static func standingRows(from resp: ESPNStandingsCoreResponse) -> [StandingRow] {
        guard resp.standings.count > 0 else { return [] }
        // 赛季初 records 为空时，把 entries 按 rank/appearance 渲染成 zero-data rows
        // ——Repository 看到空 rows 会再回退本地 JSON；如果用户愿意看"20队已列出但当前积分暂未填"，可以保留。
        let hasAnyRecords = resp.standings.contains { ($0.records?.isEmpty == false) }
        if !hasAnyRecords { return [] }   // 真空 → 触发 Repository 回退本地

        return resp.standings.enumerated().map { (idx, entry) in
            translateV3Entry(idx: idx, entry: entry)
        }
        // 积分 → 净胜球 → 进球 降序；完全同分时按 ESPN rank 稳定住顺序 ——
        // 否则两次取数之间同分行可能互换，列表顺序与显示的名次对不上。
        .sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.position < $1.position
        }
    }

    /// v2 entries 翻译（沿用原逻辑）
    private static func translateStandingsV2(entries: [ESPNStandingEntry]) -> [StandingRow] {
        let rows: [StandingRow] = entries.enumerated().map { (idx, entry) in
            let team = Team(
                id: Int(entry.team.id) ?? idx,
                name: entry.team.name,
                shortName: entry.team.shortName,
                crest: entry.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            var played = 0, won = 0, draw = 0, lost = 0
            var points = 0, gf = 0, ga = 0, gd = 0
            for s in entry.stats {
                let v = Int(s.value ?? 0)
                switch s.name {
                case "gamesPlayed":      played = v
                case "wins":             won = v
                case "ties", "draws":    draw = v
                case "losses":           lost = v
                case "points":           points = v
                case "pointsFor", "goalsFor":      gf = v
                case "pointsAgainst", "goalsAgainst": ga = v
                case "pointDifferential", "goalDifference": gd = v
                default: break
                }
            }
            return StandingRow(
                position: idx + 1,
                team: team,
                playedGames: played, won: won, draw: draw, lost: lost,
                points: points, goalsFor: gf, goalsAgainst: ga, goalDifference: gd,
                form: nil, status: nil, home: nil, away: nil
            )
        }
        return rows.sorted {
            ($0.points, $0.goalDifference, $0.goalsFor) > ($1.points, $1.goalDifference, $1.goalsFor)
                || ($0.points, $0.goalDifference, $0.goalsFor) == ($1.points, $1.goalDifference, $1.goalsFor)
                    && $0.position < $1.position
        }
    }

    /// 稳定的字符串 → 正整数散列（FNV-1a 64bit，对 Int.max 取模）。
    ///
    /// Swift 的 `String.hashValue` 带随机种子，**每次进程启动都不同** —— 用它派生实体 id，
    /// 同一球队/比赛两次启动 id 就会变，缓存比对、SwiftUI ForEach diff 全部错乱。
    /// ESPN 的 id / $ref URL 字符串本身是稳定的，用 FNV 散列得到跨启动一致的替代 id。
    static func stableID(from string: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(Int.max))
    }

    /// 单条 v3 entry → StandingRow
    private static func translateV3Entry(idx: Int, entry: ESPNStandingEntryV3) -> StandingRow {
        let teamRef = entry.team
        let team = Team(
            id: Int(teamRef.id ?? "") ?? teamRef.dollarRef.map(Self.stableID(from:)) ?? idx,
            name: teamRef.displayName ?? teamRef.name ?? "Unknown",
            shortName: teamRef.abbreviation ?? teamRef.shortName,
            crest: teamRef.logos?.first?.href,
            venue: nil, founded: nil, coach: nil, squad: nil
        )
        // 解析 records（按 name 取数）+ 顶层 stats
        var played = 0, won = 0, draw = 0, lost = 0
        var points = 0, gf = 0, ga = 0
        let allRecords = entry.records ?? []
        for rec in allRecords {
            let v = Int(rec.value ?? 0)
            switch rec.name ?? "" {
            case "gamesPlayed", "played":     played = v
            case "wins":                       won = v
            case "ties", "draws", "tiesCount": draw = v
            case "losses", "lossesCount":     lost = v
            case "points":                     points = v
            case "pointsFor", "goalsFor":      gf = v
            case "pointsAgainst", "goalsAgainst": ga = v
            default: break
            }
        }
        let gd = gf - ga
        let status = entry.note?.description.map { mapZone($0) }
        return StandingRow(
            position: entry.rank ?? (idx + 1),
            team: team,
            playedGames: played, won: won, draw: draw, lost: lost,
            points: points, goalsFor: gf, goalsAgainst: ga, goalDifference: gd,
            form: nil, status: status, home: nil, away: nil
        )
    }

    /// 把 ESPN note description 映射成 PRD 约定的 status
    private static func mapZone(_ desc: String) -> String {
        let d = desc.uppercased()
        if d.contains("CHAMPIONS") { return "CHAMPIONS_LEAGUE" }
        if d.contains("EUROPA")    { return "EUROPA_LEAGUE" }
        if d.contains("RELEGAT")   { return "RELEGATION" }
        return desc
    }


    /// ESPN scoreboard/schedule → 内部 Match 列表
    static func matches(from resp: ESPNScoreboardResponse) -> [Match] {
        let events = resp.events ?? []
        return events.compactMap { event -> Match? in
            guard let comps = event.competitions?.first,
                  let competitors = comps.competitors else { return nil }
            let home = competitors.first { $0.homeAway == "home" }
            let away = competitors.first { $0.homeAway == "away" }
            guard let h = home, let a = away else { return nil }

            let homeTeam = Team(
                id: Int(h.team.id) ?? 0,
                name: h.team.name,
                shortName: h.team.shortName,
                crest: h.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            let awayTeam = Team(
                id: Int(a.team.id) ?? 0,
                name: a.team.name,
                shortName: a.team.shortName,
                crest: a.team.logo,
                venue: nil, founded: nil, coach: nil, squad: nil
            )
            let status = StatusTranslator.translate(comps.status?.type?.name)
            let score: Score? = {
                guard status == "FINISHED",
                      let hs = h.score?.value,
                      let as_ = a.score?.value
                else { return nil }
                return Score(fullTime: FullTime(home: Int(hs), away: Int(as_)))
            }()
            return Match(
                id: Int(event.id) ?? Self.stableID(from: event.id) % 1_000_000,
                matchday: event.week?.number,
                utcDate: event.date,
                status: status,
                stage: nil,
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                score: score
            )
        }
    }

    /// v3 events 单场详情 → 内部 Match
    /// 注意：v3 单场赛事里 competitors[].team 只有 id + $ref，没有 name/crest
    ///   → 这里只用 id + 一个 placeholder name，UI 列表里不展开详情即可
    static func match(from detail: ESPNEventDetailV3) -> Match? {
        guard let comp = detail.competitions?.first,
              let competitors = comp.competitors, competitors.count >= 2 else { return nil }
        let home = competitors.first { $0.homeAway == "home" } ?? competitors[0]
        let away = competitors.first { $0.homeAway == "away" } ?? competitors[1]
        // v3 单场赛事里 competitor.id 即为 team id
        let homeId = Int(home.id ?? "0") ?? 0
        let awayId = Int(away.id ?? "0") ?? 0
        let homeTeam = Team(id: homeId, name: "Team #\(homeId)", shortName: nil, crest: nil,
                            venue: nil, founded: nil, coach: nil, squad: nil)
        let awayTeam = Team(id: awayId, name: "Team #\(awayId)", shortName: nil, crest: nil,
                            venue: nil, founded: nil, coach: nil, squad: nil)

        let statusName = comp.status?.type?.name
        let state = comp.status?.type?.state
        let status: String?
        if state == "post" || statusName == "STATUS_FULL_TIME" {
            status = "FINISHED"
        } else if state == "in" || statusName == "STATUS_IN_PROGRESS" {
            status = "IN_PLAY"
        } else if let n = statusName, n.contains("POSTPONED") {
            status = "POSTPONED"
        } else {
            status = "SCHEDULED"
        }

        // score 在 v3 单场赛事里仍是 $ref，这里 score 先给 nil；
        // 已结束赛事的 UI 需要详细比分时会触发 follow score——这里 MVP 暂不展开
        let score: Score? = nil

        return Match(
            id: Int(detail.id ?? "0") ?? 0,
            matchday: nil,
            utcDate: detail.date ?? comp.date,
            status: status,
            stage: nil,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            score: score
        )
    }
}

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
