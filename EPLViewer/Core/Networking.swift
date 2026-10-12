import Foundation

// MARK: - 网络会话与公开 API 客户端（ESPN / FPL）

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
