import Foundation

// MARK: - Network session & public API clients (ESPN / FPL)

/// Unified URLSession configuration.
///
/// ⚠️ Why not `URLSession.shared`: its `timeoutIntervalForResource` defaults to
/// **7 days**. When a TCP connection succeeds but the server trickles bytes
/// (fantasy.premierleague.com/api/bootstrap-static/ has been observed hanging for
/// 30+ seconds without finishing), the request neither succeeds nor fails — the
/// `await` never returns, `isLoading` in the view model never resets, and the UI
/// looks frozen under the loading overlay. Tightening the timeouts here makes slow
/// requests **fail fast** so the next fallback tier can take over.
enum APIClient {
    /// Main data requests (FPL / ESPN)
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15    // max gap between two received data chunks
        cfg.timeoutIntervalForResource = 30   // overall request duration cap
        cfg.waitsForConnectivity = false      // fail immediately when offline, so fallbacks kick in
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EPLViewer/2.0"
        ]
        return URLSession(configuration: cfg)
    }()

    /// Small resources like crests: even tighter timeouts — a placeholder shield
    /// beats a slow list.
    static let imageSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()
}

// MARK: - ESPN public API provider

/// ESPN public API client (no API key required).
/// Important: the old site.api.espn.com/apis/site/v2/... endpoints now all return
/// an empty {} (CDN / permission restrictions). The endpoints that actually work
/// live under sports.core.api.espn.com/v2/... (core v3 API).
/// Known endpoints (verified 2026-08-23):
///   ✅ standings:        /v2/.../seasons/{s}/types/1/groups/23/standings/0
///   ✅ events (schedule): /v2/.../events?dates=YYYYMMDD-YYYYMMDD
///   ✅ teams:            /v2/.../seasons/{s}/teams
///   ❌ scorers (not offered by the v3 API; derived from the FPL bootstrap instead)
struct ESPNProvider {
    /// Premier League (eng.1) core v3 endpoint (verified working)
    let base = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1"

    /// Fetch the standings (v3 core nests several `$ref` layers; flattened here to
    /// single-level records/stats).
    /// Note: early in the season (Aug–Sep) `records` may be an empty array (no
    /// points yet); the repository falls back to fixture aggregation or the last
    /// persisted standings cache.
    func fetchStandings(season: Int) async throws -> ESPNStandingsCoreResponse {
        try await get("\(base)/seasons/\(season)/types/1/groups/23/standings/0?lang=en&region=us")
    }

    /// Fetch one day's results (YYYYMMDD, optional range) for small daily refreshes.
    func fetchScoreboard(date: String? = nil) async throws -> ESPNScoreboardResponse {
        var path = "\(base)/events"
        if let d = date { path += "?dates=\(d)" }
        return try await get(path)
    }

    /// Fetch the full-season schedule (site API scoreboard).
    /// Unlike core/events, this endpoint inlines team names / crests / scores /
    /// dates — no `$ref` chasing — and its shape maps straight onto
    /// `ESPNScoreboardResponse` (used for fixtures and standings aggregation).
    func fetchScoreboardSchedule(dates: String) async throws -> ESPNScoreboardResponse {
        let url = "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard?dates=\(dates)"
        return try await get(url)
    }

    /// Fetch the full-season schedule (v2 site API).
    /// The v3 core API has no stable season= filter, and the equivalent
    /// site.api.espn.com endpoint has been 403/empty. This attempt may return
    /// nothing; the DataRepository fallback chain (stale cache → empty) takes over.
    func fetchSchedule(season: Int) async throws -> ESPNScoreboardResponse {
        let url = "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/schedule?season=\(season)"
        return try await get(url)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path) else { throw AppError.apiError(0) }
        var request = URLRequest(url: url)
        // The core v3 API requires a User-Agent: the default one gets blocked by
        // the CDN and returns an empty {}.
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

// ESPN core v3 native JSON models (shape of the /standings/0 endpoint)
struct ESPNStandingsCoreResponse: Codable {
    let name: String?
    let displayName: String?
    let standings: [ESPNStandingEntryV3]   // top level is the team table (≠ the old nested children)
}
struct ESPNStandingEntryV3: Codable {
    let team: ESPNTeamRefV3               // often just a $ref; a second GET fetches details
    let records: [ESPNRecordV3]?          // points data (points/W/D/L/GF/GA); may be empty early season
    let stats: [ESPNStatV3]?              // some fields arrive as stats instead
    let rank: Int?
    let note: ESPNStandingNoteV3?         // CL/EL/RELEGATION etc.
}
struct ESPNTeamRefV3: Codable {
    let id: String?                      // some endpoints return id instead of $ref
    let name: String?                    // when inlined
    let shortName: String?
    let displayName: String?
    let logos: [ESPNLogoV3]?
    let abbreviation: String?

    // CodingKeys: dollarRef receives the "$ref" JSON field (Swift disallows $ in property names)
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
    let color: String?      // e.g. CL blue / EL orange / R red
    let description: String?
    let rank: Int?
}

// MARK: - ESPN v3 events models

/// Events list response (paged): top-level `items` are paginated event `$ref`s.
struct ESPNEventsListResponse: Codable {
    let count: Int?
    let pageIndex: Int?
    let pageSize: Int?
    let pageCount: Int?
    let items: [ESPNAbstractRef]
}
/// Generic { "$ref": "..." } shape (for event/team list items).
struct ESPNAbstractRef: Codable {
    let dollarRef: String?
    let id: String?
    let name: String?     // some event lists inline a short name
    let date: String?

    enum CodingKeys: String, CodingKey {
        case dollarRef = "$ref"
        case id, name, date
    }
}

/// An event competitor: before kickoff it may carry only a `$ref`;
/// finished events may inline name/date.
struct ESPNCompetitorV3: Codable {
    let id: String?
    let homeAway: String?     // "home" / "away"
    let winner: Bool?
    let team: ESPNTeamRefV3?
    /// Score is nested in a ScoreV3 sub-object (not always present)
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
/// A single v3 event (deep object).
struct ESPNEventDetailV3: Codable {
    let id: String?
    let date: String?
    let name: String?
    let shortName: String?
    let competitions: [ESPNCompetitionV3]?
}

// MARK: - v3 events client

/// ESPN v3 events fetcher: pulls the event list plus per-event details
/// (following `$ref`s). Works with `StandingsAggregator` to build live standings
/// from finished events.
enum ESPNEventsProvider {
    /// Static User-Agent (v3 requires one; the default gets blocked to an empty {})
    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) EPLViewer/2.0"

    /// Fetch all event IDs within a date range (deduplicated, follows pagination).
    /// - Parameter dates: ESPN `YYYYMMDD-YYYYMMDD` dates format
    /// - Returns: event IDs (e.g. ["401879301", ...])
    static func fetchEventIds(dates: String, limit: Int = 100) async throws -> [String] {
        var allIds: [String] = []
        var pageIndex = 1
        // The v3 events endpoint is paginated; pageSize defaults to 10, pageCount = ceil(count/10)
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
            if pageIndex > 50 { break } // guard: a season never exceeds 50 pages
        }
        return Array(Set(allIds)).sorted()
    }

    /// Fetch one event's details (includes inline competitors with `winner`; score is still a $ref).
    static func fetchEventDetail(eventId: String) async throws -> ESPNEventDetailV3 {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/events/\(eventId)?lang=en&region=us"
        return try await fetchJSON(url)
    }

    /// Fetch one competitor's score (v3 keeps scores behind $refs).
    static func fetchCompetitorScore(eventId: String, competitorId: String) async throws -> Int {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/events/\(eventId)/competitions/\(eventId)/competitors/\(competitorId)/score?lang=en&region=us"
        struct R: Codable { let value: Double? }
        let r: R = try await fetchJSON(url)
        return Int(r.value ?? 0)
    }

    /// Fetch one team's details (name/logos/abbreviation/venue/address).
    static func fetchTeam(teamId: String) async throws -> ESPNTeamRefV3 {
        let url = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/seasons/\(SeasonStore.currentSeason)/teams/\(teamId)?lang=en&region=us"
        return try await fetchJSON(url)
    }

    /// JSON GET (adds the User-Agent; throws AppError on failure).
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

// ESPN legacy (v2 site API) JSON models (decode/cache only; translated to domain models afterwards)
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
    /// The scoreboard endpoint's score is not uniform: it may be the number 3,
    /// the string "3", or an object {"value": 3}.
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

// MARK: - FPL public API provider

/// FPL public API client (no key). `bootstrap-static` pulls everything in one
/// shot; leaderboards are derived locally from it.
struct FPLProvider {
    let base = "https://fantasy.premierleague.com/api"

    /// Fetch the full bootstrap (teams / players / positions / gameweeks).
    func fetchBootstrap() async throws -> FPLBootstrap {
        try await get("\(base)/bootstrap-static/")
    }

    /// Fetch the full fixture list (gameweek, scores, kickoff times).
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

// FPL native JSON models
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
    let status: String         // a=available, i=injured, d=doubtful, u=unavailable, s=suspended, n=not registered
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
    /// The round's earliest deadline time (FPL treats it as an approximation of
    /// the round's first kickoff; also used as the season-overview start date).
    let deadline_time: String?
}

/// An FPL fixture (from /api/fixtures/).
struct FPLFixture: Codable {
    let event: Int?        // gameweek
    let team_h: Int
    let team_a: Int
    let team_h_score: Int?
    let team_a_score: Int?
    let kickoff_time: String
    let finished: Bool
    let started: Bool?
    /// FPL sets finished_provisional=true at full time, flipping `finished` later;
    /// it is the more timely, reliable "match is over" signal (never fires at
    /// halftime / mid-match).
    let finished_provisional: Bool?
    /// Minutes played (0 = not kicked off, 90 = over). Fallback signal.
    let minutes: Int?
}
