import XCTest
@testable import EPLViewer

// MARK: - 内联测试夹具（避免 test target 无法访问主 target Bundle.module 资源）
// 这些 JSON 镜像 Sources/EPLViewer/Resources 中的真实结构，使用与 App 一致的
// JSONDecoder + .convertFromSnakeCase 解码，用于断言模型字段与 JSON 一一对应。
// 采用内联字符串而非 Bundle.module，确保测试在 Xcode / `swift test` 下独立可跑。

private let standingsJSON = """
{
  "standings": [
    {
      "stage": "REGULAR_SEASON",
      "type": "TOTAL",
      "table": [
        {"position":1,"team":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png","venue":"Etihad Stadium","founded":1880},"playedGames":38,"won":28,"draw":7,"lost":3,"points":91,"goalsFor":90,"goalsAgainst":35,"goalDifference":55,"form":"W,W,D,L,W","status":"CHAMPIONS_LEAGUE"},
        {"position":2,"team":{"id":57,"name":"Arsenal","shortName":"Arsenal","crest":"https://crests.football-data.org/57.png","venue":"Emirates Stadium","founded":1886},"playedGames":38,"won":26,"draw":6,"lost":6,"points":84,"goalsFor":85,"goalsAgainst":40,"goalDifference":45,"form":"W,D,W,W,L","status":"CHAMPIONS_LEAGUE"},
        {"position":3,"team":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png","venue":"Anfield","founded":1892},"playedGames":38,"won":24,"draw":9,"lost":5,"points":81,"goalsFor":82,"goalsAgainst":38,"goalDifference":44,"form":"W,W,D,W,W","status":"CHAMPIONS_LEAGUE"},
        {"position":4,"team":{"id":58,"name":"Aston Villa","shortName":"Aston Villa","crest":"https://crests.football-data.org/58.png","venue":"Villa Park","founded":1874},"playedGames":38,"won":21,"draw":10,"lost":7,"points":73,"goalsFor":78,"goalsAgainst":45,"goalDifference":33,"form":"D,W,W,D,W","status":"CHAMPIONS_LEAGUE"},
        {"position":5,"team":{"id":73,"name":"Tottenham Hotspur","shortName":"Tottenham","crest":"https://crests.football-data.org/73.png","venue":"Tottenham Hotspur Stadium","founded":1882},"playedGames":38,"won":19,"draw":8,"lost":11,"points":65,"goalsFor":70,"goalsAgainst":50,"goalDifference":20,"form":"L,W,D,L,W","status":null},
        {"position":6,"team":{"id":67,"name":"Newcastle United","shortName":"Newcastle","crest":"https://crests.football-data.org/67.png","venue":"St James' Park","founded":1892},"playedGames":38,"won":18,"draw":9,"lost":11,"points":63,"goalsFor":72,"goalsAgainst":52,"goalDifference":20,"form":"W,D,L,W,D","status":null},
        {"position":7,"team":{"id":397,"name":"Brighton & Hove Albion","shortName":"Brighton","crest":"https://crests.football-data.org/397.png","venue":"Amex Stadium","founded":1901},"playedGames":38,"won":10,"draw":10,"lost":18,"points":40,"goalsFor":50,"goalsAgainst":60,"goalDifference":-10,"form":"L,L,D,L,D","status":"RELEGATION"},
        {"position":8,"team":{"id":61,"name":"Chelsea","shortName":"Chelsea","crest":"https://crests.football-data.org/61.png","venue":"Stamford Bridge","founded":1905},"playedGames":38,"won":9,"draw":9,"lost":20,"points":36,"goalsFor":48,"goalsAgainst":65,"goalDifference":-17,"form":"L,D,L,L,D","status":"RELEGATION"}
      ]
    }
  ]
}
"""

private let teamsJSON = """
{
  "teams": [
    {"id":57,"name":"Arsenal","shortName":"Arsenal","crest":"https://crests.football-data.org/57.png","venue":"Emirates Stadium","founded":1886,"coach":{"id":1,"name":"Mikel Arteta","nationality":"Spain"},"squad":[{"id":1,"name":"Bukayo Saka","position":"Right Winger","shirtNumber":7,"nationality":"England"}]},
    {"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png","venue":"Etihad Stadium","founded":1880,"coach":{"id":6,"name":"Pep Guardiola","nationality":"Spain"},"squad":[{"id":10,"name":"Erling Haaland","position":"Centre-Forward","shirtNumber":9,"nationality":"Norway"}]},
    {"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png","venue":"Anfield","founded":1892,"coach":{"id":15,"name":"Arne Slot","nationality":"Netherlands"},"squad":[{"id":20,"name":"Mohamed Salah","position":"Right Winger","shirtNumber":11,"nationality":"Egypt"}]},
    {"id":61,"name":"Chelsea","shortName":"Chelsea","crest":"https://crests.football-data.org/61.png","venue":"Stamford Bridge","founded":1905,"coach":{"id":25,"name":"Enzo Maresca","nationality":"Italy"},"squad":[{"id":30,"name":"Cole Palmer","position":"Attacking Midfield","shirtNumber":20,"nationality":"England"}]},
    {"id":73,"name":"Tottenham Hotspur","shortName":"Tottenham","crest":"https://crests.football-data.org/73.png","venue":"Tottenham Hotspur Stadium","founded":1882,"coach":{"id":34,"name":"Ange Postecoglou","nationality":"Australia"},"squad":[{"id":40,"name":"Son Heung-min","position":"Left Winger","shirtNumber":7,"nationality":"South Korea"}]},
    {"id":67,"name":"Newcastle United","shortName":"Newcastle","crest":"https://crests.football-data.org/67.png","venue":"St James' Park","founded":1892,"coach":{"id":45,"name":"Eddie Howe","nationality":"England"},"squad":[{"id":50,"name":"Alexander Isak","position":"Centre-Forward","shirtNumber":14,"nationality":"Sweden"}]},
    {"id":58,"name":"Aston Villa","shortName":"Aston Villa","crest":"https://crests.football-data.org/58.png","venue":"Villa Park","founded":1874,"coach":{"id":54,"name":"Unai Emery","nationality":"Spain"},"squad":[{"id":60,"name":"Ollie Watkins","position":"Centre-Forward","shirtNumber":11,"nationality":"England"}]},
    {"id":397,"name":"Brighton & Hove Albion","shortName":"Brighton","crest":"https://crests.football-data.org/397.png","venue":"Amex Stadium","founded":1901,"coach":{"id":64,"name":"Fabian Hurzeler","nationality":"Germany"},"squad":[{"id":70,"name":"Kaoru Mitoma","position":"Left Winger","shirtNumber":22,"nationality":"Japan"}]}
  ]
}
"""

private let scorersJSON = """
{
  "scorers": [
    {"player":{"id":10,"name":"Erling Haaland","nationality":"Norway"},"team":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png"},"goals":27,"assists":5,"playedMatches":35},
    {"player":{"id":20,"name":"Mohamed Salah","nationality":"Egypt"},"team":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png"},"goals":25,"assists":12,"playedMatches":36},
    {"player":{"id":30,"name":"Cole Palmer","nationality":"England"},"team":{"id":61,"name":"Chelsea","shortName":"Chelsea","crest":"https://crests.football-data.org/61.png"},"goals":22,"assists":11,"playedMatches":35},
    {"player":{"id":40,"name":"Son Heung-min","nationality":"South Korea"},"team":{"id":73,"name":"Tottenham Hotspur","shortName":"Tottenham","crest":"https://crests.football-data.org/73.png"},"goals":19,"assists":9,"playedMatches":34},
    {"player":{"id":73,"name":"Joao Pedro","nationality":"Brazil"},"team":{"id":397,"name":"Brighton & Hove Albion","shortName":"Brighton","crest":"https://crests.football-data.org/397.png"},"goals":18,"assists":6,"playedMatches":35},
    {"player":{"id":60,"name":"Ollie Watkins","nationality":"England"},"team":{"id":58,"name":"Aston Villa","shortName":"Aston Villa","crest":"https://crests.football-data.org/58.png"},"goals":18,"assists":8,"playedMatches":36},
    {"player":{"id":1,"name":"Bukayo Saka","nationality":"England"},"team":{"id":57,"name":"Arsenal","shortName":"Arsenal","crest":"https://crests.football-data.org/57.png"},"goals":16,"assists":10,"playedMatches":33},
    {"player":{"id":70,"name":"Kaoru Mitoma","nationality":"Japan"},"team":{"id":397,"name":"Brighton & Hove Albion","shortName":"Brighton","crest":"https://crests.football-data.org/397.png"},"goals":14,"assists":4,"playedMatches":31}
  ]
}
"""

private let matchesJSON = """
{
  "matches": [
    {"id":1001,"matchday":1,"utcDate":"2024-08-17T14:00:00Z","status":"FINISHED","stage":"REGULAR_SEASON","homeTeam":{"id":57,"name":"Arsenal","shortName":"Arsenal","crest":"https://crests.football-data.org/57.png"},"awayTeam":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png"},"score":{"fullTime":{"home":1,"away":1}}},
    {"id":1002,"matchday":1,"utcDate":"2024-08-17T16:30:00Z","status":"FINISHED","stage":"REGULAR_SEASON","homeTeam":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png"},"awayTeam":{"id":61,"name":"Chelsea","shortName":"Chelsea","crest":"https://crests.football-data.org/61.png"},"score":{"fullTime":{"home":2,"away":1}}},
    {"id":1003,"matchday":1,"utcDate":"2024-08-18T14:00:00Z","status":"SCHEDULED","stage":"REGULAR_SEASON","homeTeam":{"id":73,"name":"Tottenham Hotspur","shortName":"Tottenham","crest":"https://crests.football-data.org/73.png"},"awayTeam":{"id":67,"name":"Newcastle United","shortName":"Newcastle","crest":"https://crests.football-data.org/67.png"},"score":null},
    {"id":1004,"matchday":2,"utcDate":"2024-08-24T14:00:00Z","status":"FINISHED","stage":"REGULAR_SEASON","homeTeam":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png"},"awayTeam":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png"},"score":{"fullTime":{"home":3,"away":2}}},
    {"id":1005,"matchday":2,"utcDate":"2024-08-25T14:00:00Z","status":"SCHEDULED","stage":"REGULAR_SEASON","homeTeam":{"id":67,"name":"Newcastle United","shortName":"Newcastle","crest":"https://crests.football-data.org/67.png"},"awayTeam":{"id":58,"name":"Aston Villa","shortName":"Aston Villa","crest":"https://crests.football-data.org/58.png"},"score":null}
  ]
}
"""

private let injuriesJSON = """
{
  "injuries": [
    {"player":{"id":10,"name":"Erling Haaland","nationality":"Norway"},"team":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png"},"status":"i","news":"Foot injury","chanceOfPlayingNextRound":25,"position":"Centre-Forward"},
    {"player":{"id":20,"name":"Mohamed Salah","nationality":"Egypt"},"team":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png"},"status":"d","news":"Hamstring","chanceOfPlayingNextRound":75,"position":"Right Winger"}
  ]
}
"""

// FPL bootstrap-static 真实结构子集
private let fplBootstrapJSON = """
{
  "teams": [
    {"id":1,"code":3,"name":"Arsenal","short_name":"ARS","strength":5},
    {"id":2,"code":6,"name":"Aston Villa","short_name":"AVL","strength":4},
    {"id":11,"code":12,"name":"Manchester City","short_name":"MCI","strength":5}
  ],
  "element_types": [
    {"id":1,"singular_name":"Goalkeeper","plural_name":"Goalkeepers"},
    {"id":2,"singular_name":"Defender","plural_name":"Defenders"},
    {"id":3,"singular_name":"Midfielder","plural_name":"Midfielders"},
    {"id":4,"singular_name":"Forward","plural_name":"Forwards"}
  ],
  "elements": [
    {"id":100,"web_name":"Saka","first_name":"Bukayo","second_name":"Saka","team":1,"element_type":3,"goals_scored":16,"assists":10,"status":"a","news":"","chance_of_playing_next_round":100,"now_cost":100},
    {"id":101,"web_name":"Haaland","first_name":"Erling","second_name":"Haaland","team":11,"element_type":4,"goals_scored":27,"assists":5,"status":"i","news":"Foot injury","chance_of_playing_next_round":25,"now_cost":140},
    {"id":102,"web_name":"Salah","first_name":"Mohamed","second_name":"Salah","team":1,"element_type":3,"goals_scored":25,"assists":12,"status":"a","news":"","chance_of_playing_next_round":100,"now_cost":130},
    {"id":103,"web_name":"Watkins","first_name":"Ollie","second_name":"Watkins","team":2,"element_type":4,"goals_scored":18,"assists":8,"status":"d","news":"Knock","chance_of_playing_next_round":50,"now_cost":85}
  ],
  "events": [{"id":1,"name":"Gameweek 1","is_current":true,"is_next":false}]
}
"""

// ESPN standings 真实结构子集
private let espnStandingsJSON = """
{
  "children": [{
    "standings": {
      "entries": [
        {"team":{"id":"1","name":"Arsenal","shortName":"ARS","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/1.png"},"stats":[
          {"name":"gamesPlayed","value":20},
          {"name":"wins","value":15},
          {"name":"ties","value":3},
          {"name":"losses","value":2},
          {"name":"points","value":48},
          {"name":"pointsFor","value":42},
          {"name":"pointsAgainst","value":15},
          {"name":"pointDifferential","value":27}
        ]},
        {"team":{"id":"11","name":"Manchester City","shortName":"MCI","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/11.png"},"stats":[
          {"name":"gamesPlayed","value":20},
          {"name":"wins","value":13},
          {"name":"ties","value":4},
          {"name":"losses","value":3},
          {"name":"points","value":43},
          {"name":"pointsFor","value":40},
          {"name":"pointsAgainst","value":20},
          {"name":"pointDifferential","value":20}
        ]}
      ]
    }
  }]
}
"""

// ESPN scoreboard 子集
private let espnScoreboardJSON = """
{
  "events": [
    {"id":"74982035","date":"2025-08-17T14:00:00Z","name":"Arsenal vs Manchester City","shortName":"ARS v MCI","week":{"number":1},"competitions":[{
      "status":{"type":{"name":"STATUS_FINAL","state":"post"}},
      "competitors":[
        {"homeAway":"home","team":{"id":"1","name":"Arsenal","shortName":"ARS","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/1.png"},"score":{"value":2}},
        {"homeAway":"away","team":{"id":"11","name":"Manchester City","shortName":"MCI","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/11.png"},"score":{"value":1}}
      ]
    }]},
    {"id":"74982036","date":"2025-08-24T14:00:00Z","name":"Liverpool vs Chelsea","shortName":"LIV v CHE","week":{"number":2},"competitions":[{
      "status":{"type":{"name":"STATUS_SCHEDULED","state":"pre"}},
      "competitors":[
        {"homeAway":"home","team":{"id":"10","name":"Liverpool","shortName":"LIV","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/10.png"},"score":null},
        {"homeAway":"away","team":{"id":"8","name":"Chelsea","shortName":"CHE","logo":"https://a.espncdn.com/i/teamlogos/soccer/500/8.png"},"score":null}
      ]
    }]}
  ]
}
"""

final class EPLViewerTests: XCTestCase {

    // MARK: - 基础占位

    func testExample() {
        XCTAssertTrue(true)
    }

    // MARK: - 回退决策（保留）

    /// 验证回退决策纯函数 shouldFallback 的规则
    func testShouldFallback() {
        XCTAssertTrue(DataRepository.shouldFallback(.noData))
        XCTAssertTrue(DataRepository.shouldFallback(.apiError(429)))
        XCTAssertTrue(DataRepository.shouldFallback(.network(NSError(domain: "", code: 0))))

        XCTAssertFalse(DataRepository.shouldFallback(.apiError(403)))
        XCTAssertFalse(DataRepository.shouldFallback(.apiError(400)))
        XCTAssertFalse(DataRepository.shouldFallback(.decoding(NSError(domain: "", code: 0))))
    }

    // MARK: - 缓存 TTL（新增）

    /// CacheTTL.isValid 纯函数：mtime 距 now < ttl → true；超过 → false
    func testCacheTTLIsValid() {
        let now = Date()
        let recent = now.addingTimeInterval(-30)      // 30 秒前
        let stale  = now.addingTimeInterval(-120)     // 120 秒前
        XCTAssertTrue(CacheTTL.isValid(mtime: recent, ttl: 60, now: now))
        XCTAssertFalse(CacheTTL.isValid(mtime: stale, ttl: 60, now: now))
        // ttl=2h 时 120s 前仍有效
        XCTAssertTrue(CacheTTL.isValid(mtime: stale, ttl: 60 * 60 * 2, now: now))
        // ttl=0 永远无效
        XCTAssertFalse(CacheTTL.isValid(mtime: now, ttl: 0, now: now))
    }

    /// 回归：CacheStore.getStale —— 网络失败时的 stale-if-error 兜底。
    /// 忽略 TTL 返回上次落盘的数据；TTL 常规路径仍然尊重过期时间；坏文件返回 nil 不抛错。
    func testCacheStoreStaleFallback() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("epl-cachestore-\(UUID().uuidString)", isDirectory: true)
        let store = CacheStore(directory: dir)
        struct Payload: Codable, Equatable { let value: Int }
        defer { try? FileManager.default.removeItem(at: dir) }

        await store.set("k", value: Payload(value: 7))
        // 探测落盘是否真的成功（部分沙箱环境磁盘 IO 被拦截，此时本用例无从验证，跳过）
        guard (try? Data(contentsOf: dir.appendingPathComponent("k.json"))) != nil else {
            throw XCTSkip("此环境下 CacheStore 无法写盘，跳过 stale 兜底验证")
        }

        // 把 mtime 拨回 2 小时前 → 常规 TTL 路径（ttl=60s）不应命中
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 3600)],
            ofItemAtPath: dir.appendingPathComponent("k.json").path)
        let fresh: Payload? = await store.get("k", ttl: 60)
        XCTAssertNil(fresh, "TTL 过期后常规路径不应命中")

        // getStale 忽略 TTL，返回上次数据
        let stale: Payload? = await store.getStale("k")
        XCTAssertEqual(stale, Payload(value: 7), "getStale 应忽略 TTL 返回过期缓存")

        // 文件损坏 → 返回 nil，不抛错
        try Data("not json".utf8).write(to: dir.appendingPathComponent("k.json"))
        let broken: Payload? = await store.getStale("k")
        XCTAssertNil(broken, "损坏的缓存文件应静默返回 nil")

        // key 不存在 → nil
        let missing: Payload? = await store.getStale("nope")
        XCTAssertNil(missing)
    }

    // MARK: - 内部模型解码（保留）

    /// 复用 App 的 snake_case 解码配置（用于内部 domain 模型）
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// 用于 ESPN/FPL 原生类型：Swift 字段已经是 snake_case，不需要转换
    private func makeNativeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    func testStandingsDecoding() throws {
        let response = try makeDecoder().decode(StandingsResponse.self, from: Data(standingsJSON.utf8))
        let table = response.standings.first?.table ?? []
        XCTAssertEqual(table.count, 8, "积分榜 table 应为 8 行")
        XCTAssertEqual(table.first?.position, 1, "首行 position 应为 1")
        for i in 1..<table.count {
            XCTAssertGreaterThanOrEqual(table[i - 1].points, table[i].points, "积分应降序")
        }
        XCTAssertEqual(table.first?.team.id, 65)
        XCTAssertEqual(table.first?.team.shortName, "Man City")
        XCTAssertNil(table[4].status, "status:null 应解码为 nil")
        XCTAssertEqual(table[0].status, "CHAMPIONS_LEAGUE")
    }

    func testTeamsDecoding() throws {
        let response = try makeDecoder().decode(TeamsResponse.self, from: Data(teamsJSON.utf8))
        XCTAssertEqual(response.teams.count, 8, "球队应为 8 支")
        XCTAssertNotNil(response.teams.first { ($0.squad?.isEmpty ?? true) == false })
        XCTAssertNotNil(response.teams.first { $0.coach != nil })
        XCTAssertEqual(response.teams.first { $0.coach?.name == "Mikel Arteta" }?.coach?.name, "Mikel Arteta")
    }

    func testScorersDecoding() throws {
        let response = try makeDecoder().decode(ScorersResponse.self, from: Data(scorersJSON.utf8))
        XCTAssertFalse(response.scorers.isEmpty)
        for s in response.scorers {
            XCTAssertGreaterThanOrEqual(s.goals, 0)
        }
        XCTAssertTrue(response.scorers.contains { $0.goals > 0 })
    }

    func testMatchesDecoding() throws {
        let response = try makeDecoder().decode(MatchesResponse.self, from: Data(matchesJSON.utf8))
        XCTAssertGreaterThan(response.matches.count, 0)
        let statuses = Set(response.matches.compactMap { $0.status })
        XCTAssertTrue(statuses.contains("FINISHED"))
        XCTAssertTrue(statuses.contains("SCHEDULED"))
        let scheduled = response.matches.first { $0.status == "SCHEDULED" }
        XCTAssertNil(scheduled?.score)
    }

    func testInjuriesDecoding() throws {
        let response = try makeDecoder().decode(InjuriesResponse.self, from: Data(injuriesJSON.utf8))
        XCTAssertEqual(response.injuries.count, 2)
        XCTAssertEqual(response.injuries.first?.status, "i")
        XCTAssertEqual(response.injuries.first?.chanceOfPlayingNextRound, 25)
    }

    // MARK: - 排序逻辑（射手榜/助攻榜）

    /// 射手榜稳定排序：进球降序；并列按出场数升序
    func testScorerStableSort() {
        let teamA = Team(id: 1, name: "A", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        let teamB = Team(id: 2, name: "B", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        let pHigh = PlayerLite(id: 1, name: "High", nationality: nil)
        let pTieMore = PlayerLite(id: 2, name: "TieMore", nationality: nil)
        let pTieLess = PlayerLite(id: 3, name: "TieLess", nationality: nil)

        let top = Scorer(player: pHigh, team: teamA, goals: 15, assists: nil, playedMatches: 5)
        let tieMore = Scorer(player: pTieMore, team: teamB, goals: 10, assists: nil, playedMatches: 20)
        let tieLess = Scorer(player: pTieLess, team: teamA, goals: 10, assists: nil, playedMatches: 8)

        let vm = LeadersViewModel()
        vm.scorers = [tieMore, top, tieLess]
        let sorted = vm.scorersSorted
        XCTAssertEqual(sorted[0].player.id, 1)
        XCTAssertEqual(sorted[1].player.id, 3)
        XCTAssertEqual(sorted[2].player.id, 2)
    }

    /// 助攻榜稳定排序：助攻降序；并列按进球数降序；再并列按出场数升序
    func testAssistStableSort() {
        let teamA = Team(id: 1, name: "A", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        let pTop = Assist(from: Scorer(player: PlayerLite(id: 1, name: "Top", nationality: nil), team: teamA, goals: 5, assists: 12, playedMatches: 30))
        let pTieMoreGoals = Assist(from: Scorer(player: PlayerLite(id: 2, name: "TieMoreGoals", nationality: nil), team: teamA, goals: 10, assists: 8, playedMatches: 30))
        let pTieLessGoals = Assist(from: Scorer(player: PlayerLite(id: 3, name: "TieLessGoals", nationality: nil), team: teamA, goals: 3, assists: 8, playedMatches: 10))
        let pTieMorePlayed = Assist(from: Scorer(player: PlayerLite(id: 4, name: "TieMorePlayed", nationality: nil), team: teamA, goals: 3, assists: 8, playedMatches: 30))

        let vm = LeadersViewModel()
        vm.assists = [pTieMorePlayed, pTop, pTieLessGoals, pTieMoreGoals]
        let sorted = vm.assistsSorted
        // pTop (12) 排第一
        XCTAssertEqual(sorted[0].player.id, 1)
        // 并列 8 助攻：进球多者(10) 排前
        XCTAssertEqual(sorted[1].player.id, 2)
        // 并列 8 助攻+3 球：出场少者(10) 排前
        XCTAssertEqual(sorted[2].player.id, 3)
        XCTAssertEqual(sorted[3].player.id, 4)
    }

    /// StandingsAggregator 单测：3 场人造赛事（Arsenal 2胜 + 1平 = 7分 vs Tottenham 1胜1平1负 = 4分）
    /// 验证 RowStat.points() 与聚合输出的 StandingRow.points/排序正确
    func testStandingsAggregatorPureSort() {
        // 用人造 RowStat 测算逻辑（避开真实网络 fetch）
        let arsenal = StandingsAggregator.RowStat(played: 3, won: 2, draw: 1, lost: 0, gf: 5, ga: 1)
        let tottenham = StandingsAggregator.RowStat(played: 3, won: 1, draw: 1, lost: 1, gf: 3, ga: 3)
        let brighton = StandingsAggregator.RowStat(played: 3, won: 0, draw: 1, lost: 2, gf: 1, ga: 5)

        XCTAssertEqual(arsenal.points(), 7)     // 2*3 + 1
        XCTAssertEqual(tottenham.points(), 4)  // 1*3 + 1
        XCTAssertEqual(brighton.points(), 1)    // 0*3 + 1

        XCTAssertEqual(arsenal.gd(), 4)
        XCTAssertEqual(tottenham.gd(), 0)
        XCTAssertEqual(brighton.gd(), -4)

        // 实际聚合在 production 走 follow/network；这里仅断言纯函数与"积分相同则按净胜球"的稳定排序规则
        let stats: [(String, StandingsAggregator.RowStat)] = [
            ("Brighton", brighton), ("Tottenham", tottenham), ("Arsenal", arsenal)
        ]
        let sorted = stats.sorted { ($0.1.points(), $0.1.gd()) > ($1.1.points(), $1.1.gd()) }
        XCTAssertEqual(sorted[0].0, "Arsenal")
        XCTAssertEqual(sorted[1].0, "Tottenham")
        XCTAssertEqual(sorted[2].0, "Brighton")
    }

    // MARK: - FPL bootstrap 解码与派生

    /// FPL bootstrap 原始 JSON 可解码，并按 goals_scored 派生射手榜
    func testFPLBootstrapDecoding() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        XCTAssertEqual(bootstrap.teams.count, 3)
        XCTAssertEqual(bootstrap.elements.count, 4)
        XCTAssertEqual(bootstrap.element_types.count, 4)

        // 派生射手榜：Haaland 27 球排第一
        let scorers = FPLTranslator.scorers(from: bootstrap)
        XCTAssertEqual(scorers.first?.goals, 27)
        XCTAssertEqual(scorers.first?.player.name, "Haaland")
        XCTAssertEqual(scorers.first?.team.name, "Manchester City")
    }

    /// 派生助攻榜：按 assists 降序
    func testFPLAssistsDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let assists = FPLTranslator.assists(from: bootstrap)
        XCTAssertEqual(assists.first?.assists, 12)
        XCTAssertEqual(assists.first?.player.name, "Salah")
    }

    /// 射手榜/助攻榜只显示前 10 名（limit=10）；limit=0 表示不限制
    func testFPLLeaderboardsCappedToTen() throws {
        let team = FPLTeam(id: 1, code: 3, name: "Arsenal", short_name: "ARS", strength: nil)
        let elements = (1...15).map { i in
            FPLPlayer(id: i, web_name: "P\(i)", first_name: nil, second_name: nil,
                      team: 1, element_type: 1, goals_scored: 16 - i, assists: 16 - i,
                      status: "a", news: nil, chance_of_playing_next_round: nil, now_cost: nil)
        }
        let bootstrap = FPLBootstrap(teams: [team], elements: elements, element_types: [], events: nil)

        let scorers = FPLTranslator.scorers(from: bootstrap, limit: 10)
        XCTAssertEqual(scorers.count, 10, "射手榜应只显示前 10 名")
        XCTAssertEqual(scorers.first?.goals, 15)
        XCTAssertEqual(scorers.last?.goals, 6)

        let assists = FPLTranslator.assists(from: bootstrap, limit: 10)
        XCTAssertEqual(assists.count, 10, "助攻榜应只显示前 10 名")

        // limit=0 不截断
        XCTAssertEqual(FPLTranslator.scorers(from: bootstrap, limit: 0).count, 15)
    }

    /// 派生伤停榜：仅含 status != "a" 的球员
    func testFPLInjuriesDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let injuries = FPLTranslator.injuries(from: bootstrap)
        // 4 个球员中：Saka(a) 和 Salah(a) 被过滤；Haaland(i) + Watkins(d) = 2
        XCTAssertEqual(injuries.count, 2)
        XCTAssertTrue(injuries.contains { $0.player.name == "Haaland" && $0.status == "i" })
        XCTAssertTrue(injuries.contains { $0.player.name == "Watkins" && $0.status == "d" })
    }

    /// 赛程翻译：FPL fixtures → 内部 Match（轮次 / 状态 / 比分 / 队徽）
    func testFPLFixturesToMatches() throws {
        let teams = [
            FPLTeam(id: 1, code: 3, name: "Arsenal", short_name: "ARS", strength: nil),
            FPLTeam(id: 7, code: 11, name: "Chelsea", short_name: "CHE", strength: nil),
        ]
        let fixtures = [
            // 已结束（FPL 标记 finished=true），带最终比分 → FINISHED
            FPLFixture(event: 1, team_h: 1, team_a: 7, team_h_score: 3, team_a_score: 0,
                       kickoff_time: "2026-08-21T19:00:00Z", finished: true, started: true,
                       finished_provisional: true, minutes: 90),
            // 进行中（started=true 但 finished=false，未满 90 分钟），有实时比分 → IN_PLAY（UI 加 ⚽，不误判为已结束）
            FPLFixture(event: 2, team_h: 7, team_a: 1, team_h_score: 1, team_a_score: 2,
                       kickoff_time: "2026-08-22T19:00:00Z", finished: false, started: true,
                       finished_provisional: false, minutes: 23),
            // 终场后 FPL 尚未翻转 finished，但已置 finished_provisional=true（实际已结束）→ FINISHED，不应显示 ⚽
            // （复现：第 2 轮 水晶宫 vs 曼城，score 1-4、minutes 90、finished=false）
            FPLFixture(event: 3, team_h: 1, team_a: 7, team_h_score: 1, team_a_score: 4,
                       kickoff_time: "2026-08-23T19:00:00Z", finished: false, started: true,
                       finished_provisional: true, minutes: 90),
            // 未开球 → SCHEDULED，无比分
            FPLFixture(event: 4, team_h: 1, team_a: 7, team_h_score: nil, team_a_score: nil,
                       kickoff_time: "2026-08-28T19:00:00Z", finished: false, started: false,
                       finished_provisional: false, minutes: 0),
        ]
        let matches = FPLTranslator.matches(from: fixtures, teams: teams)
        XCTAssertEqual(matches.count, 4)

        let m1 = matches.first(where: { $0.matchday == 1 })!
        XCTAssertEqual(m1.status, "FINISHED")
        XCTAssertEqual(m1.score?.fullTime?.home, 3)
        XCTAssertEqual(m1.score?.fullTime?.away, 0)
        XCTAssertEqual(m1.homeTeam.crest, "https://resources.premierleague.com/premierleague/badges/50/t3.png")

        let m2 = matches.first(where: { $0.matchday == 2 })!
        XCTAssertEqual(m2.status, "IN_PLAY")   // 关键：进行中有实时比分时不被误判为已结束
        XCTAssertEqual(m2.score?.fullTime?.home, 1)
        XCTAssertEqual(m2.score?.fullTime?.away, 2)

        let m3 = matches.first(where: { $0.matchday == 3 })!
        XCTAssertEqual(m3.status, "FINISHED")  // 关键：finished_provisional=true 的终场比赛不应显示 ⚽
        XCTAssertEqual(m3.score?.fullTime?.home, 1)
        XCTAssertEqual(m3.score?.fullTime?.away, 4)

        let m4 = matches.first(where: { $0.matchday == 4 })!
        XCTAssertEqual(m4.status, "SCHEDULED")
        XCTAssertNil(m4.score)
    }

    /// 派生球队：含从 elements 派生的 squad
    func testFPLTeamsDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let teams = FPLTranslator.teams(from: bootstrap)
        XCTAssertEqual(teams.count, 3)
        let arsenal = teams.first { $0.name == "Arsenal" }
        XCTAssertNotNil(arsenal)
        // Arsenal 含 Saka 和 Salah 两名球员
        XCTAssertEqual(arsenal?.squad?.count, 2)
        // 队徽 URL 形如 https://resources.premierleague.com/premierleague/badges/50/t3.png
        XCTAssertEqual(arsenal?.crest, "https://resources.premierleague.com/premierleague/badges/50/t3.png")
        // 球员 position 已映射：Saka 是 Midfielder，Haaland 是 Forward
        let saka = arsenal?.squad?.first { $0.name == "Saka" }
        XCTAssertEqual(saka?.position, "Midfielder")
    }

    // MARK: - ESPN 原生解码与翻译

    /// ESPN standings 原生 JSON 可解码，并正确翻译为内部 StandingRow
    func testESPNStandingsTranslation() throws {
        let resp = try makeNativeDecoder().decode(ESPNStandingsResponse.self, from: Data(espnStandingsJSON.utf8))
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertEqual(rows.count, 2)
        // 按 points 降序：Arsenal 48 > City 43
        XCTAssertEqual(rows[0].team.name, "Arsenal")
        XCTAssertEqual(rows[0].points, 48)
        XCTAssertEqual(rows[0].playedGames, 20)
        XCTAssertEqual(rows[0].won, 15)
        XCTAssertEqual(rows[0].draw, 3)
        XCTAssertEqual(rows[0].lost, 2)
        XCTAssertEqual(rows[0].goalsFor, 42)
        XCTAssertEqual(rows[0].goalsAgainst, 15)
        XCTAssertEqual(rows[0].goalDifference, 27)
        XCTAssertEqual(rows[0].position, 1)
        XCTAssertEqual(rows[1].team.name, "Manchester City")
    }

    /// ESPN scoreboard 原生 JSON 可解码，并正确翻译为内部 Match（含状态映射）
    func testESPNScoreboardTranslation() throws {
        let resp = try makeNativeDecoder().decode(ESPNScoreboardResponse.self, from: Data(espnScoreboardJSON.utf8))
        let matches = ESPNTranslator.matches(from: resp)
        XCTAssertEqual(matches.count, 2)
        let finished = matches.first { $0.status == "FINISHED" }
        XCTAssertNotNil(finished)
        XCTAssertEqual(finished?.score?.fullTime?.home, 2)
        XCTAssertEqual(finished?.score?.fullTime?.away, 1)
        let scheduled = matches.first { $0.status == "SCHEDULED" }
        XCTAssertNotNil(scheduled)
        XCTAssertNil(scheduled?.score)
    }

    /// ESPN 状态名翻译
    func testStatusTranslator() {
        XCTAssertEqual(StatusTranslator.translate("STATUS_FINAL"), "FINISHED")
        XCTAssertEqual(StatusTranslator.translate("STATUS_SCHEDULED"), "SCHEDULED")
        XCTAssertEqual(StatusTranslator.translate("STATUS_IN_PROGRESS"), "IN_PLAY")
        XCTAssertEqual(StatusTranslator.translate(nil), "SCHEDULED")
        XCTAssertEqual(StatusTranslator.translate("UNKNOWN"), "UNKNOWN")
    }

    // MARK: - 球队中英文映射

    /// 中文队名映射：chinese=true 命中返回中文、未命中回退英文；false 恒为英文
    func testTeamDisplayNameChinese() throws {
        let arsenal = Team(id: 1, name: "Arsenal", shortName: "ARS", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(arsenal.displayName(chinese: true), "阿森纳")
        XCTAssertEqual(arsenal.displayName(chinese: false), "Arsenal")

        let city = Team(id: 15, name: "Manchester City", shortName: "MCI", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(city.displayName(chinese: true), "曼城")

        // 未知 short_name：中文模式回退英文原名
        let unknown = Team(id: 999, name: "Nowhere FC", shortName: "NOW", crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(unknown.displayName(chinese: true), "Nowhere FC")

        // 缺 short_name：无法匹配中文，回退英文
        let noShort = Team(id: 998, name: "Some Team", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(noShort.displayName(chinese: true), "Some Team")
    }

    // MARK: - 今日筛选

    /// matchday 用可选：`nil` 表示 FPL 里尚未分配轮次的比赛（真实数据里确实存在），
    /// 用于覆盖「未分配比赛不应影响当前轮推断」这类场景。
    private func makeMatch(id: Int, kickoff: String, status: String?, matchday: Int? = 1) -> Match {
        let team = Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
                        venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: team, awayTeam: team, score: nil)
    }

    /// 与 makeMatch 类似，但主客队可不同（用于需要「两队名次」的推荐卡选取测试）
    private func makeMatchTeams(id: Int, home: Int, away: Int, kickoff: String,
                                status: String?, matchday: Int? = 1) -> Match {
        let h = Team(id: home, name: "H\(home)", shortName: "H\(home)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        let a = Team(id: away, name: "A\(away)", shortName: "A\(away)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: h, awayTeam: a, score: nil)
    }

    /// 只保留「所选时区的当天」比赛，且按开球时间升序
    func testTodayFilterKeepsSameDaySorted() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 参考时刻：北京时间 2026-08-31 20:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "IN_PLAY"),   // 北京 21:00 同一天
            makeMatch(id: 2, kickoff: "2026-08-31T04:00:00Z", status: "FINISHED"),  // 北京 12:00 同一天
            makeMatch(id: 3, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // 北京 次日 00:00
            makeMatch(id: 4, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),  // 前一天
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertEqual(today.map(\.id), [2, 1], "只保留当天比赛，且按开球时间升序")
    }

    /// 「今日」必须按所选时区判断：同一时刻在北京已进入次日、在伦敦仍是当天
    func testTodayFilterRespectsSelectedTimeZone() throws {
        let beijing = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let london  = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // UTC 18:00 → 北京 次日 02:00；伦敦（BST UTC+1）当天 19:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T18:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T18:00:00Z", status: "IN_PLAY"),   // 次日(北京) / 当天(伦敦)
            makeMatch(id: 2, kickoff: "2026-08-31T02:00:00Z", status: "FINISHED"),  // 当天(两地)
        ]

        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: beijing).map(\.id), [1])
        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: london).map(\.id), [2, 1])
    }

    /// 今日比赛按状态分组：进行中 / 未开赛 / 已结束
    func testTodayGroupsByStatus() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T04:00:00Z", status: "IN_PLAY"),
            makeMatch(id: 2, kickoff: "2026-08-31T05:00:00Z", status: "FINISHED"),
            makeMatch(id: 3, kickoff: "2026-08-31T06:00:00Z", status: "SCHEDULED"),
        ]

        let vm = TodayViewModel()
        vm.matches = matches
        let g = vm.grouped(tz: tz, now: now)
        XCTAssertEqual(g.live.map(\.id), [1])
        XCTAssertEqual(g.finished.map(\.id), [2])
        XCTAssertEqual(g.upcoming.map(\.id), [3])
        XCTAssertEqual(g.total, 3)
        XCTAssertFalse(g.isEmpty)
    }

    /// 回归：跨日进行中的比赛（北京 23:30 开球、打到次日凌晨）开球日期算「昨天」，
    /// 但此刻正在踢，必须出现在「今日」——否则进行中的比赛会凭空消失。
    func testTodayFilterIncludesLiveMatchStartedYesterday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 当前：北京时间 2026-08-31 00:23（UTC 16:23 跨日 +8h）
        // 曼联那场北京时间 8月30日 23:30 开球 → 开球日期在所选时区里是「昨天」
        let now = try XCTUnwrap(parseKickoffDate("2026-08-30T16:23:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T15:30:00Z", status: "IN_PLAY"),   // 北京 23:30 开球，跨日进行中
            makeMatch(id: 2, kickoff: "2026-08-30T13:00:00Z", status: "FINISHED"),  // 北京 21:00，昨天已结束 → 不算今日
            makeMatch(id: 3, kickoff: "2026-08-31T11:00:00Z", status: "SCHEDULED"), // 北京 19:00，今天
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertTrue(today.contains { $0.id == 1 }, "进行中的比赛必须出现在今日，即使开球日期是昨天")
        XCTAssertFalse(today.contains { $0.id == 2 }, "昨天已结束的比赛不应出现在今日")
        XCTAssertTrue(today.contains { $0.id == 3 })
        XCTAssertEqual(today.map(\.id), [1, 3], "按开球时间升序")
    }

    /// 「下一场」取严格晚于当前时刻的第一场（等于 now 的不算）
    func testTodayNextMatchIsStrictlyAfterNow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),   // 过去
            makeMatch(id: 2, kickoff: "2026-08-31T12:00:00Z", status: "IN_PLAY"),    // == now
            makeMatch(id: 3, kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED"),
            makeMatch(id: 4, kickoff: "2026-09-05T12:00:00Z", status: "SCHEDULED"),
        ]
        XCTAssertEqual(TodayFilter.nextMatch(from: matches, now: now)?.id, 3)
    }

    // MARK: - 推荐比赛（featured 大卡片）选取

    /// 优先级 1：进行中优先于「即将开赛」
    func testFeaturedPrefersLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // 1 小时后开球
            makeMatch(id: 2, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY"),   // 进行中
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 2：无进行中 → 取 3.5 小时内开球的（超窗的不算）
    func testFeaturedFallsBackToKickoffWithinThreeAndHalfHours() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // +1h  → 命中
            makeMatch(id: 2, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // +4h  → 超窗
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// 优先级 3：无进行中、无即将开赛 → 今日已结束中「时间最近」的一场
    func testFeaturedFallsBackToMostRecentFinishedToday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED"),  // 北京 18:00
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED"),  // 北京 19:00 → 更近
            makeMatch(id: 3, kickoff: "2026-08-31T18:00:00Z", status: "SCHEDULED"), // +6h，超窗
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 5：今日无可推荐 → 取本轮下一场（可跨日，如明天）
    func testFeaturedFallsBackToNextMatchOfCurrentRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T10:00:00Z", status: "FINISHED", matchday: 5),  // 昨天
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 本轮下一场
            makeMatch(id: 3, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 6), // 下一轮
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// 优先级 5：时间不同的比赛，取开球最早的一场（不因排名更好去推后更晚的强强对话）。
    func testFeaturedRoundNextPicksEarliestKickoffWhenTimesDiffer() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 10, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17，时间中
            makeMatchTeams(id: 11, home: 3, away: 4,  kickoff: "2026-09-04T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 7（排名最好），但最晚
            makeMatchTeams(id: 12, home: 8, away: 9,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17，但最早 → 命中
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4, 8: 8, 9: 9]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 12,
                       "时间不同时取最早开球的一场（#8 vs #9），不因后面有更强强对话而推后")
    }

    /// 优先级 5：同一时刻开球且多场 → 按名次和最小选强强对话。
    func testFeaturedRoundNextSameKickoffChosenByRankingSum() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 20, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 17
            makeMatchTeams(id: 21, home: 3, away: 4,  kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 同时刻，和 7 → 命中
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 21,
                       "同一时刻开球时按名次和最小选：#3 vs #4（和 7）优于 #2 vs #15（和 17）")
    }

    /// 优先级 5：同一时刻且名次和相同 → 比较两队里排名最高的（更小者）胜出。
    func testFeaturedRoundNextSameKickoffRankingTieBreakByBestTeam() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 7, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 9，最佳 #2
            makeMatchTeams(id: 31, home: 1, away: 8, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 和 9，最佳 #1 → 命中
        ]
        let positions = [1: 1, 8: 8, 2: 2, 7: 7]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 31,
                       "同时刻且和相同（都是 9）时取榜首更靠前的那场：#1 vs #8 优于 #2 vs #7")
    }

    /// 优先级 5：最早开球时刻只有一场 → 直接取它，不因后面有更强强对话而推后。
    func testFeaturedRoundNextEarliestSlotSingleMatchPickedDirectly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 40, home: 10, away: 11, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 最早且唯一 → 命中
            makeMatchTeams(id: 41, home: 1,  away: 2,  kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED", matchday: 5), // 更晚（排名更好也不考虑）
        ]
        let positions = [10: 10, 11: 11, 1: 1, 2: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 40,
                       "最早时刻只有一场时直接取它，不跨时段为更强强对话推后")
    }

    /// 名次缺失时（取数超时 / 示例数据）必须优雅回退成「开球最早的一场」，不能崩。
    func testFeaturedRoundNextFallsBackToKickoffWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 15, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatchTeams(id: 31, home: 3, away: 4,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // 开球最早 → 命中
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: [:])?.id, 31,
                       "名次缺失时必须回退到开球最早的一场，而不是报错或选错")
    }

    /// 优先级 6：本轮已结束 → 显示本轮第一场（最早开球）的赛果
    func testFeaturedFallsBackToFirstMatchOfFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5), // 本轮最早
            makeMatch(id: 2, kickoff: "2026-08-29T14:00:00Z", status: "FINISHED", matchday: 5),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// 本轮已**全部结束** → 推荐卡应显示本轮的「强强对话」，而不是开球最早那场。
    ///
    /// 回归场景（用户报的 Bug）：第 3 轮已全部结束，卡片显示利物浦的早场，
    /// 期望显示阿森纳 vs 切尔西（名次和最小的强强对话）。
    ///
    /// 路由说明：`currentRound = 3` 时，优先级 5（本轮**未开赛**）的候选为空，
    /// 且 now 不在比赛日（跳过优先级 3/4），所以落到**优先级 6**。
    func testFeaturedFinishedRoundPicksMarqueeNotEarliestKickoff() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // now = 第 3 轮结束两天后，非比赛日 → 优先级 3（今日已结束）/ 4（今日未开赛）都不命中
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))

        let ars = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let che = Team(id: 61, name: "Chelsea", shortName: "CHE", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let liv = Team(id: 64, name: "Liverpool", shortName: "LIV", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let bha = Team(id: 397, name: "Brighton", shortName: "BHA", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        func m(_ id: Int, _ home: Team, _ away: Team, _ kickoff: String,
               _ md: Int, _ status: String) -> Match {
            Match(id: id, matchday: md, utcDate: kickoff, status: status,
                  stage: nil, homeTeam: home, awayTeam: away, score: nil)
        }

        let matches = [
            // 第 3 轮：全部已结束。id 1 开球最早（北京 11:00），id 2 最晚但名次和最小
            m(1, liv, bha, "2026-08-30T03:00:00Z", 3, "FINISHED"),   // 利物浦早场
            m(2, ars, che, "2026-08-30T06:00:00Z", 3, "FINISHED"),   // 阿森纳 vs 切尔西（强强对话）
            m(3, bha, liv, "2026-08-30T09:00:00Z", 3, "FINISHED"),
            // 第 4 轮已排期但未开赛 —— currentRound 仍是 3，所以不会走优先级 5
            m(4, ars, bha, "2026-09-05T11:00:00Z", 4, "SCHEDULED"),
        ]
        // 名次：阿森纳 1 / 切尔西 3（和 4）；利物浦 8 / 布莱顿 15（和 23）
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "本轮已结束时应显示强强对话（阿森纳 vs 切尔西），" +
                       "而不是开球最早的利物浦那场")
    }

    /// 控制组：证明优先级 5（本轮**下一场未开赛**）仍然是「时间优先」——
    /// 同一轮里时间不同的比赛取最早，不会因为排名更「强强」而推到更晚的场次。
    /// 这条同时锁住「优先级 6 的改动没有误伤优先级 5」。
    func testFeaturedUpcomingRoundStillPrefersEarliestKickoffOverMarquee() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))

        let ars = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let che = Team(id: 61, name: "Chelsea", shortName: "CHE", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let liv = Team(id: 64, name: "Liverpool", shortName: "LIV", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        let bha = Team(id: 397, name: "Brighton", shortName: "BHA", crest: nil,
                       venue: nil, founded: nil, coach: nil, squad: nil)
        func m(_ id: Int, _ home: Team, _ away: Team, _ kickoff: String,
               _ md: Int, _ status: String) -> Match {
            Match(id: id, matchday: md, utcDate: kickoff, status: status,
                  stage: nil, homeTeam: home, awayTeam: away, score: nil)
        }

        let matches = [
            m(1, ars, che, "2026-08-30T03:00:00Z", 3, "FINISHED"),
            // 第 3 轮还有未开赛的场次 → 命中优先级 5：取最早开球（id 2），而非名次的 id 3
            m(2, liv, bha, "2026-09-05T11:00:00Z", 3, "SCHEDULED"),  // 最早
            m(3, ars, che, "2026-09-05T14:00:00Z", 3, "SCHEDULED"),  // 更晚但更强强
        ]
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "优先级 5 仍应是时间优先：本轮未开赛场次里取最早，不因排名推到更晚")
    }

    // MARK: - QA 独立复审：优先级 6 的边界与错误路径

    /// 本轮已结束 + `positions` 完全缺失（积分榜取数超时 / 失败）→
    /// 必须退回「本轮最早开球」，不能崩、不能返回 nil。
    ///
    /// 这条同时是**哨兵溢出**的回归测试：两队都取不到名次时
    /// `rankKey` 会算 `Int.max / 2 + Int.max / 2`，debug 构建下若溢出会直接 trap（signal 5），
    /// 表现是测试进程整体崩溃而不是单条失败 —— 能跑到这里就说明没溢出。
    func testFeaturedFinishedRoundFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3),
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 最早
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: [:])
        XCTAssertNotNil(picked, "名次全缺时不能返回 nil —— 必须回退到本轮最早开球那场")
        XCTAssertEqual(picked?.id, 2, "名次全缺时回退到本轮最早开球（id 2）")
    }

    /// 两队名次都取不到的比赛应**沉底**，让位给名次已知的比赛（哨兵 Int.max/2 的语义）。
    func testFeaturedFinishedRoundRanksUnknownTeamsLast() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // 两队都无名次 → 沉底（即使开球最早）
            makeMatchTeams(id: 1, home: 91, away: 92, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // 名次已知且最小 → 命中（开球更晚也不影响，本轮已结束）
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [23: 5, 24: 7]   // 91 / 92 缺失
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2, "名次未知的比赛应沉底，让位给名次已知且和最小的那场")
    }

    /// `positions` 部分缺失（只有一支球队有名次）→ 该场会被哨兵拉高而落选。
    /// 这里锁住当前行为，便于后续讨论是否要改（见 QA 报告）。
    func testFeaturedFinishedRoundPartialPositionsSinkTheMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // 榜首(#1) vs 无名次球队 → 和 ≈ Int.max/2 + 1，会被拉高
            makeMatchTeams(id: 1, home: 1, away: 99, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // 中游对中游，两队名次都已知 → 和 21
            makeMatchTeams(id: 2, home: 10, away: 11, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 10: 10, 11: 11]   // 99 缺失
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "部分缺失时：两队名次都已知的比赛（和 21）应胜出，" +
                       "榜首 + 未知队（和 ≈ Int.max/2）被哨兵拉高 —— 当前行为，非崩溃")
    }

    /// 名次和**完全相同**时（`min(by:)` 的语义）应稳定返回开球最早的那场，不能随机跳。
    func testFeaturedFinishedRoundTieReturnsEarliestStable() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // 两场 rankKey 完全相同：(1+8, min(1,8)) == (8+1, min(8,1)) == (9, 1)
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 8, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 最早
            makeMatchTeams(id: 2, home: 8, away: 1, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 8: 8]
        // 跑多次确认稳定，不是偶然
        for _ in 0..<20 {
            let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                            now: now, tz: tz, positions: positions)
            XCTAssertEqual(picked?.id, 1, "名次和完全相同且最佳名次也相同时，应稳定返回开球最早那场")
        }
    }

    /// 真正的全局最小值：最小值不在首/尾，且轮次里还有更晚的下一轮比赛干扰。
    func testFeaturedFinishedRoundPicksTrueMinimumAmongMany() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 和 30
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T04:00:00Z", status: "FINISHED", matchday: 3), // 和 12
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // 和 25
            makeMatchTeams(id: 4, home: 27, away: 28, kickoff: "2026-08-30T06:00:00Z", status: "FINISHED", matchday: 3), // 和  8 ← 最小，位置在中间
            makeMatchTeams(id: 5, home: 29, away: 30, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // 和 40
            // 下一轮已排期：currentRound 仍是 3，不应被选
            makeMatchTeams(id: 6, home: 31, away: 32, kickoff: "2026-09-05T11:00:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 25: 12, 26: 13,
                         27: 3, 28: 5, 29: 20, 30: 20, 31: 1, 32: 2]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 4,
                       "应选出名次和最小（8）的那场；最小值既不在首位也不在末位，" +
                       "且不能选到下一轮（id 6，和 3 更小但属于第 4 轮）")
    }

    /// 本轮在 matches 里没有任何比赛 → 返回 nil，不能崩。
    func testFeaturedFinishedRoundReturnsNilWhenRoundHasNoMatches() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [21: 1, 22: 2, 23: 3, 24: 4]
        XCTAssertNil(TodayFeatured.pick(from: matches, currentRound: 99,
                                        now: now, tz: tz, positions: positions),
                     "currentRound 没有对应比赛时应返回 nil")
        XCTAssertNil(TodayFeatured.pick(from: [], currentRound: 3,
                                        now: now, tz: tz, positions: positions),
                     "matches 为空时应返回 nil")
    }

    /// 工程师刻意不复用 `chooseByRanking` 的理由必须成立：
    /// 它会先把候选收敛到「最早开球那一批」，所以对本轮各场开球时间不同的场景
    /// 会退化成「取最早开球」—— 正是被修掉的 Bug。
    /// 这里用纯数据证明二者在优先级 6 的场景下结果不同。
    func testChooseByRankingWouldCollapseToEarliestForFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // 本轮已全部结束，三场开球时间各不相同
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // 和 30，最早
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // 和 12
            makeMatchTeams(id: 3, home: 27, away: 28, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // 和  8 ← 最小
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 27: 3, 28: 5]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 3, "优先级 6 应跨时段选名次和最小的那场")

        // 若退化成「取最早开球」，结果就会是 id 1 —— 正是用户报的 Bug
        let earliest = matches.min(by: { $0.utcDate ?? "" < $1.utcDate ?? "" })
        XCTAssertEqual(earliest?.id, 1, "最早开球的是 id 1（利物浦早场式的错误结果）")
        XCTAssertNotEqual(picked?.id, earliest?.id,
                          "修复后不应再等于最早开球那场 —— 证明确实跨时段比了名次")
    }

    // MARK: - QA：优先级 2 / 4 同刻多场按名次（本次缺陷修复的回归）

    /// 优先级 2（3.5 小时内开球）同刻多场 → 按名次和最小选强强对话，
    /// 而不是退化成「取原始数组顺序第一个」。
    ///
    /// 场景还原（2026-09-12 真实缺陷）：伦敦 13:57，15:00 BST（14:00Z）有若干场同刻开球，
    /// 距 now 63 分钟落在 3.5h 窗口内。FPL fixtures 里排在最前的是名次最差那场（名次和 34），
    /// 修复前会被它偷走推荐位；按名次应选中名次和最小的那场。
    ///
    /// 命中场 id 3 刻意放在数组**第三位**，确保测的是「按名次」而非「碰巧第一个」。
    func testFeaturedSoonWindowSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 伦敦 2026-09-12 13:57（BST）= 12:57Z；15:00 BST = 14:00Z，距 now 63 分钟
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // 数组里排第一，但名次最差（18 + 16 = 34）—— 修复前会被这个偷走
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 和 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 和 7 → 命中
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "同刻开球时应按名次和最小选强强对话（和 7），" +
                       "而不是数组顺序第一个（和 34）")
    }

    /// 控制组：优先级 2 仍「时间优先」—— 最早时刻只有一场（名次很差）时直接取它，
    /// 不能为了「更强强对话」把推荐推到更晚的场次。
    func testFeaturedSoonWindowPicksEarliestSlotNotMarquee() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // 最早时刻唯一（14:00Z），名次最差（和 34）→ 必须选它
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            // 更晚（14:15Z），名次很好（和 3）→ 不能因为「更强强」而推后
            makeMatchTeams(id: 2, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [2: 18, 7: 16, 4: 1, 5: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 1,
                       "最早时刻只有一场时直接取它，不跨时段为更强强对话推后")
    }

    /// 向后兼容：`positions` 为空（名次取不到）→ 优先级 2 仍返回「最早开球那一场」，
    /// 与改动前 `first(where:)` 完全一致，且不崩。
    func testFeaturedSoonWindowFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:30:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // 最早 → 命中
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: [:])?.id, 2,
                       "名次缺失时必须回退到开球最早的一场（id 2），行为与改动前一致")
    }

    /// 优先级 4（今日下一场未开赛）同刻多场 → 同样按名次和最小选强强对话。
    /// 开球距 now 超过 3.5h（跳过优先级 2），但仍是伦敦当日 → 落到优先级 4。
    func testFeaturedTodayUpcomingSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        // 18:00Z = 19:00 BST（伦敦同日），距 now 5h3m > 3.5h → 优先级 2 不命中
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // 和 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // 和 7 → 命中
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "今日未开赛同刻多场时也应按名次和最小选强强对话")
    }

    // MARK: - 第四行第二列（今日开赛）

    /// 第二列只取今日未开赛，并剔除推荐卡那场
    func testTodayColumnsExcludesFeaturedMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5

        // ① 今日多场未开赛 → 推荐卡占最早那场，第二列保留其余
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5), // +1h → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5), // 北京 23:00
        ]
        let c1 = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(c1.upcoming.map(\.id), [2], "推荐卡那场不应重复出现在第二列")

        // ② 今日仅剩推荐卡那场未开赛 → 第二列为空（不做轮次回退）
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5), // 推荐卡
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // 本轮后续，但不算今日
        ]
        let c2 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c2.upcoming.isEmpty, "第二列只看今日，不回退到本轮下一场")

        // ③ 今日没有未开赛（只有已结束的）→ 第二列为空
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let c3 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c3.upcoming.isEmpty)
    }

    /// 本轮已全部结束 → 第二列**不**跳到下一轮，保持为空（显示「暂无数据」）
    func testTodayColumnsDoesNotFallBackToNextEvent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 北京 2026-08-31 20:00
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // 今日已结束 → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-09-05T10:00:00Z", status: "SCHEDULED", matchday: 6), // 下一轮
            makeMatch(id: 4, kickoff: "2026-09-05T14:00:00Z", status: "SCHEDULED", matchday: 7),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertTrue(cols.upcoming.isEmpty, "轮次还是第 5 轮，不该把第 6/7 轮的赛程铺到今日页")
    }

    /// 第一列是「正在进行中 & 近期」的合流：直播在前，今日已结束在后（最近的在前）
    func testTodayColumnsFirstColumnShowsLiveAndRecent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "IN_PLAY", matchday: 5),      // 直播最早 → 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),      // 直播
            makeMatch(id: 3, kickoff: "2026-08-31T08:00:00Z", status: "FINISHED", matchday: 5),     // 今日已结束（较晚）
            makeMatch(id: 4, kickoff: "2026-08-31T07:00:00Z", status: "FINISHED", matchday: 5),     // 今日已结束（较早）
            makeMatch(id: 5, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5),     // 昨天，不算今日
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2, 3, 4], "直播在前（按开球升序），已结束在后（最近的在前）")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// 没有直播时，第一列只列今日已结束，标题降级为「近期」
    func testTodayColumnsFirstColumnRecentOnly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // 今日已结束
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED", matchday: 5), // 今日最晚一场 → 推荐卡
            makeMatch(id: 3, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5), // 昨天，不算今日
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 2, "推荐卡取今日最近结束的一场")
        XCTAssertEqual(cols.live.map(\.id), [1], "第一列只列今日已结束的其余比赛")
        XCTAssertEqual(cols.liveSource, .recent)
    }

    /// 有直播时，第一列不再重复推荐卡那场
    func testTodayColumnsFirstColumnExcludesFeaturedLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),     // 推荐卡
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),     // 另一场直播
            makeMatch(id: 3, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2], "直播时第一列也不该重复推荐卡那场")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// 无论哪种情形，推荐卡那场都不会出现在第二列
    func testTodayColumnsNeverDuplicatesFeatured() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),    // 进行中
            makeMatch(id: 2, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let featured = try XCTUnwrap(vm.featured(tz: tz, now: now))
        XCTAssertEqual(featured.id, 1, "进行中的比赛优先成为推荐卡")
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertFalse(cols.upcoming.contains { $0.id == featured.id })
        XCTAssertEqual(cols.upcoming.map(\.id), [2, 3])
    }

    // MARK: - 赛程页（截图风格布局）

    /// focusedRound 决定 displayed 该展示哪一轮，无论 mode 是什么
    func testFixturesFocusedRoundDrivesDisplayed() throws {
        let vm = FixturesViewModel()
        vm.focusedRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2025-09-12T11:00:00Z", status: "FINISHED", matchday: 12),
        ]
        XCTAssertEqual(vm.displayed.map(\.id), [1])

        // 用户从「赛季总览」点击「第 N 轮」 → focusedRound 被改写
        vm.focusedRound = 12
        XCTAssertEqual(vm.displayed.map(\.id), [2])
    }

    /// 按日期分组的赛程页布局：每节包含该日所有比赛，按开球时间升序
    func testFixturesGroupedSectionsByLocalDate() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let vm = FixturesViewModel()
        vm.focusedRound = 1
        vm.matches = [
            // 北京 8月29 日三场
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-29T14:00:00Z", status: "FINISHED", matchday: 1),
            // 北京 9月1 日一场
            makeMatch(id: 3, kickoff: "2025-09-01T03:00:00Z", status: "FINISHED", matchday: 1),
        ]
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].matches.map(\.id), [1, 2], "同日内按开球升序")
        XCTAssertEqual(sections[1].matches.map(\.id), [3])
    }

    /// 赛季总览快照：每轮一张，至多 3 场预览，状态由 currentRound 决定
    func testFixturesRoundSnapshotsBySeasonProgress() throws {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 4, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 5, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let progress = SeasonProgress(
            currentRound: 2, totalRounds: 3,
            playedRounds: 1, remainingRounds: 2,
            fraction: 1.0 / 3.0, seasonYear: 2025
        )
        let snaps = vm.roundSnapshots(seasonProgress: progress)
        XCTAssertEqual(snaps.count, 3)
        XCTAssertEqual(snaps[0].progress, .past)
        XCTAssertEqual(snaps[1].progress, .current)
        XCTAssertEqual(snaps[2].progress, .future)
        XCTAssertEqual(snaps[0].previews.count, 2, "第 1 轮 2 场")
        XCTAssertEqual(snaps[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(snaps[2].previews.map(\.id), [5])
    }

    /// 赛季总览快照：超过 3 场的轮次只预览前 3 场
    func testFixturesRoundSnapshotsPreviewLimitIsThree() throws {
        let vm = FixturesViewModel()
        vm.matches = (1...8).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T1\(i):00:00Z", status: "FINISHED", matchday: 1)
        }
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 1, totalRounds: 38, playedRounds: 0, remainingRounds: 38,
            fraction: 0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps[0].previews.count, 3, "每张总览卡片上限 3 场")
    }

    /// 赛季总览：未来轮次数据未发 → 显示 unknown 状态
    func testFixturesRoundSnapshotsFutureWithoutDataIsUnknown() throws {
        let vm = FixturesViewModel()
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 5, totalRounds: 38, playedRounds: 4, remainingRounds: 34,
            fraction: 4.0 / 38.0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps.count, 38)
        // 第 5 轮 = current；第 6-38 = future 数据未发 → unknown
        XCTAssertEqual(snaps[4].progress, .current)
        XCTAssertEqual(snaps[5].progress, .unknown)
        XCTAssertTrue(snaps[5].previews.isEmpty, "未知轮次无预览")
    }

    /// 索引随 matches 赋值自动重建：availableRounds 同步、roundStart 取该轮最早开球
    ///
    /// 这条是性能回归的护栏 —— 38 个轮次 chip 每个都要 roundStart，
    /// 一旦有人改回「每次全表扫描 matches」，本测试仍会过，但界面会卡死。
    /// 所以 roundStart 必须只查预计算字典（O(1)）。
    func testFixturesIndexesRebuiltOnMatchesAssignment() throws {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1), // 最早
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(vm.availableRounds, [1, 2], "赋值即同步轮次列表")

        let earliest = try XCTUnwrap(parseKickoffDate("2025-08-21T11:00:00Z"))
        XCTAssertEqual(vm.roundStart(1), earliest, "roundStart 取该轮最早开球")
        XCTAssertNil(vm.roundStart(9), "无数据轮次返回 nil")

        // 分组直接读预计算桶，同样按开球升序
        vm.focusedRound = 1
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].matches.map(\.id), [2, 1])
    }

    /// `displayed` 必须走预计算桶，不能回到 380 场全表 filter
    func testFixturesDisplayedReadsPrebuiltBucket() {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        vm.focusedRound = 1
        XCTAssertEqual(vm.displayed.map(\.id), [2, 1], "桶内已按开球升序")
        vm.focusedRound = 2
        XCTAssertEqual(vm.displayed.map(\.id), [3])
        vm.focusedRound = 99
        XCTAssertTrue(vm.displayed.isEmpty, "无数据轮次返回空，不崩溃")
    }

    // MARK: - 布局陷阱回归护栏

    /// 赛程页踩过的两个坑都会让 SwiftUI 布局阶段打满主线程（表现为「一直转圈 + 界面卡死」）：
    ///   1. LazyVStack 内嵌 LazyVGrid —— lazy 容器提议的宽度不确定，网格算不出列数
    ///   2. GridItem(.adaptive(maximum: .infinity)) —— 列宽无上界，列数计算发散
    /// 这里直接扫源码兜底，防止以后改版又把陷阱写回来。
    func testFixturesViewHasNoLayoutDeadlockTraps() throws {
        let path = URL(fileURLWithPath: #filePath)          // .../Tests/EPLViewerTests/EPLViewerTests.swift
            .deletingLastPathComponent()                    // Tests/EPLViewerTests
            .deletingLastPathComponent()                    // Tests
            .deletingLastPathComponent()                    // 包根目录
            .appendingPathComponent("Sources/EPLViewer/FixturesView.swift")
        let src = try String(contentsOf: path, encoding: .utf8)
        // 只扫代码：先剥掉 // 注释，否则解释「为什么不能用 LazyVStack」的注释会误报
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertFalse(codeOnly.contains("LazyVStack"),
                       "赛程页禁止 LazyVStack：嵌套 lazy 容器会让 LazyVGrid 尺寸协商死循环")
        XCTAssertFalse(codeOnly.contains("maximum: .infinity"),
                       "GridItem 的 maximum 必须是具体数值，不能是 .infinity")
    }

    /// 轮次 chip bar 的两个护栏必须同时成立：
    ///   1. 用 LazyHStack —— 普通 HStack 会为每一个轮次都建视图，
    ///      轮次数涨到几百上千时布局阶段会一次性算上千个 chip 的尺寸，主线程打满。
    ///   2. 保留 .frame(height: 32) —— 这是修「嵌在纵向 ScrollView 里的横向
    ///      ScrollView 无限协商尺寸导致卡死」的护栏，删掉会回归；
    ///      同时它也是 LazyHStack 能算出尺寸的前提。
    /// 同样先剥掉 // 注释再匹配，否则解释性注释会误报。
    func testRoundChipBarUsesLazyHStack() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/EPLViewer/FixturesView.swift")
        let src = try String(contentsOf: path, encoding: .utf8)
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertTrue(codeOnly.contains("LazyHStack"),
                      "轮次 chip bar 必须用 LazyHStack，否则轮次一多就会全量渲染卡住主线程")
        XCTAssertTrue(codeOnly.contains(".frame(height: 32)"),
                      "横向 chip bar 的固定高度约束不能删：删了会回归布局死循环")
    }

    /// `roundSnapshots` 在 SwiftUI body 求值路径上被调用，必须缓存：
    /// 输入没变时直接返回上次结果（不重算），输入变了必须重新算。
    func testRoundSnapshotsAreCached() {
        let vm = FixturesViewModel()
        vm.matches = (1...6).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T1\(i):00:00Z", status: "FINISHED", matchday: i % 3 + 1)
        }
        let progress = SeasonProgress(
            currentRound: 2, totalRounds: 3,
            playedRounds: 1, remainingRounds: 2,
            fraction: 1.0 / 3.0, seasonYear: 2025
        )

        // 第一次调用：缓存为空 → 必然重算
        let first = vm.roundSnapshots(seasonProgress: progress)
        let computesAfterFirst = vm.roundSnapshotsComputeCount
        XCTAssertEqual(computesAfterFirst, 1, "首次调用应真正计算一次")

        // 第二次调用：输入完全没变 → 命中缓存，不再重算
        let second = vm.roundSnapshots(seasonProgress: progress)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst,
                       "输入未变时应命中缓存，不应重算")
        XCTAssertEqual(fingerprint(second), fingerprint(first), "缓存命中的结果与首次一致")

        // 换个 seasonProgress（关键输入变了）→ 必须重算且结果随之更新
        let moved = SeasonProgress(
            currentRound: 3, totalRounds: 3,
            playedRounds: 2, remainingRounds: 1,
            fraction: 2.0 / 3.0, seasonYear: 2025
        )
        let third = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 1,
                       "seasonProgress 变化后必须重算")
        XCTAssertEqual(third[1].progress, .past, "当前轮推进后，第 2 轮由 current 变 past")
        XCTAssertEqual(third[2].progress, .current)

        // 再改 matches（走 didSet 重建索引）→ 缓存必须失效，结果跟着数据更新
        vm.matches = [makeMatch(id: 99, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3)]
        let afterRematch = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 2,
                       "matches 变化后必须重算")
        XCTAssertEqual(afterRematch[2].previews.map(\.id), [99], "快照内容应反映新的比赛数据")
        XCTAssertTrue(afterRematch[0].previews.isEmpty, "旧的第 1 轮数据已不在")
    }

    // MARK: - 轮次窗口（chip bar 固定窗口分页）

    /// 造 `count` 个轮次（每轮 1 场），只为撑出 availableRounds，内容不重要
    private func makeRounds(_ count: Int) -> [Match] {
        (1...count).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: i)
        }
    }

    // MARK: - 首次聚焦轮次（load() 仅在首次拿数据时聚焦；刷新不得重置浏览位置）

    /// 把 makeRounds 的结果按轮次分桶（matchesByRound 的形状）
    private func roundsByRound(_ count: Int) -> (byRound: [Int: [Match]], rounds: [Int]) {
        var byRound: [Int: [Match]] = [:]
        for m in makeRounds(count) { byRound[m.matchday ?? 0, default: []].append(m) }
        return (byRound, Array(1...count))
    }

    /// 当前轮有数据 → 聚焦当前轮
    func testInitialFocusRoundPrefersCurrentRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 7,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            7, "当前轮有数据 → 聚焦当前轮")
    }

    /// 当前轮暂无赛程（如 FPL 已推进到下一轮但赛程未发）→ 回退第一个有数据的轮次
    func testInitialFocusRoundFallsBackToFirstAvailableRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 11,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            1, "当前轮无数据 → 聚焦首个有数据的轮次")
    }

    /// 完全没有赛程 → 维持传入的 currentRound（load() 侧此时根本不会调用本函数）
    func testInitialFocusRoundWithNoDataKeepsCurrentRound() {
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 5,
                                                availableRounds: [],
                                                matchesByRound: [:]),
            5, "无任何轮次数据 → 维持当前轮")
    }

    /// 聚焦中间轮 → 窗口以它为**中心**（前 2 后 2）
    func testRoundWindowCentersOnFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.roundWindowStart = 0            // 手动把窗口推回最左，真正考验对齐逻辑
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "MD20 居中 → MD18–MD22")
        XCTAssertEqual(vm.roundWindowStart, 17)
    }

    /// 聚焦靠左的轮次（第 1 / 第 2 轮）→ 窗口**左对齐**，起点不会变负
    func testRoundWindowAlignsLeftNearStart() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // 第 1 轮：idx 0 - 2 = -2 → 夹到 0
        vm.roundWindowStart = 20
        vm.focusedRound = 1
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0, "起点不能为负")

        // 第 2 轮：idx 1 - 2 = -1 → 同样夹到 0
        vm.roundWindowStart = 20
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// 聚焦靠右的轮次（倒数第 2 / 最后 1 轮）→ 窗口**右对齐**，不越过上界
    func testRoundWindowAlignsRightNearEnd() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // 倒数第 2 轮（MD37）：idx 36 - 2 = 34 → 夹到上界 33
        vm.roundWindowStart = 0
        vm.focusedRound = 37
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33, "38 轮时上界是 33")

        // 最后一轮（MD38）：idx 37 - 2 = 35 → 同样夹到 33
        vm.roundWindowStart = 0
        vm.focusedRound = 38
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33)
    }

    /// 轮次总数不足一屏 → 全部显示，上界为 0（两个翻页箭头都该隐藏）
    func testRoundWindowShowsAllWhenFewerThanWindowSize() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(3)
        vm.roundWindowStart = 99            // 越界起点也要能被夹回来
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3], "只有 3 轮 → 全部显示")
        XCTAssertEqual(vm.roundWindowStart, 0)
        XCTAssertEqual(vm.roundWindowMaxStart, 0, "不足一屏 → 上界 0，箭头全隐藏")
    }

    /// 翻页边界：向右翻到底停在上界不再增长，向左翻到头停在 0 不会变负
    func testRoundWindowPagingStopsAtBounds() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1

        // 一路向右翻
        for _ in 0..<20 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 33, "38 轮的上界 = 38 - 5")
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.focusedRound, 1, "翻页只移动窗口，不改选中的轮次")

        // 继续右翻不会越界
        vm.pageRoundsForward()
        XCTAssertEqual(vm.roundWindowStart, 33)
        XCTAssertEqual(vm.roundWindowMaxStart, 33)

        // 一路向左翻
        for _ in 0..<20 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, 0, "起点不会变负")
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.focusedRound, 1, "翻页只移动窗口，选中轮次始终不变")

        // 继续左翻不会变负
        vm.pageRoundsBackward()
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// 右翻后焦点与翻页前完全相同：窗口动了，focusedRound 没动，
    /// 于是新窗口里没有任何 chip 处于高亮态（这正是用户要的"焦点原地不动"）。
    func testPagingPreservesFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "初始居中窗口 MD18–MD22")

        vm.pageRoundsForward()
        XCTAssertEqual(vm.focusedRound, 20, "右翻后焦点仍是 20")
        XCTAssertNotEqual(vm.roundWindowStart, 17, "窗口起点确实移动了")
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27])
        XCTAssertFalse(vm.visibleRounds.contains(20), "新窗口不含 20 → 无高亮 chip")
    }

    /// 连续右翻 N 次再左翻同样 N 次：
    /// 窗口起点回到原值、focusedRound 始终未变、且焦点重新落回 visibleRounds（MD20 重新高亮）。
    func testPagingRoundTripRestoresWindowAndFocus() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        let originalStart = vm.roundWindowStart
        XCTAssertEqual(originalStart, 17)

        // 右翻 3 次（17→22→27→32，未触碰上界 33，保证来回对称）
        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.focusedRound, 20, "右翻过程中焦点恒定")

        // 左翻同样 3 次：窗口回到原处、焦点始终未变、MD20 重新高亮
        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "来回翻页窗口回到原处")
        XCTAssertEqual(vm.focusedRound, 20, "焦点始终没变")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "回到原窗口后 MD20 重新高亮")
        XCTAssertTrue(vm.visibleRounds.contains(20))
    }

    /// 翻页后 visibleRounds 不含 focusedRound：渲染不崩、高亮判定 `r == focusedRound`
    /// 对窗口内每个 chip 都为 false（无高亮，符合预期，不是 bug）。
    func testPagingAwayFromFocusRendersNoSelection() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.pageRoundsForward()                 // 窗口 MD23–MD27，焦点仍在 20
        XCTAssertFalse(vm.visibleRounds.contains(20))

        // 模拟 chip bar 的高亮判定：窗口里没有任何 chip 应被高亮
        let anyHighlighted = vm.visibleRounds.contains { $0 == vm.focusedRound }
        XCTAssertFalse(anyHighlighted, "窗口里无 chip 处于高亮态，符合预期")

        // 不变量：翻到窗口外仍成立
        XCTAssertLessThanOrEqual(vm.visibleRounds.count, FixturesViewModel.roundWindowSize)
        XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart)
    }

    /// 从赛季总览点 MD30 跳过来：窗口原本在最左，必须自动重新对齐并包含 MD30
    func testRoundWindowAlignsToFarAwayFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5], "起点在最左")

        // 模拟「总览页点 MD30 卡片」—— 只改 focusedRound，窗口由 didSet 自动对齐
        vm.focusedRound = 30
        XCTAssertTrue(vm.visibleRounds.contains(30), "对齐后窗口必须包含 focusedRound")
        XCTAssertEqual(vm.visibleRounds, [28, 29, 30, 31, 32])

        // 已经在窗口内时不应该乱动（否则翻页后焦点落回首轮会把窗口重新居中、来回弹）
        let before = vm.roundWindowStart
        vm.focusedRound = 29
        XCTAssertEqual(vm.roundWindowStart, before, "焦点仍在窗内 → 窗口保持不动")
    }

    /// 不变量：任何数据规模 / 任何操作序列下，窗口都不越界、不超长
    func testRoundWindowInvariantsHoldAcrossDataSizes() {
        let size = FixturesViewModel.roundWindowSize
        // 覆盖：空数据 / 1 轮 / 不足一屏 / 刚好一屏 / 多一屏 / 38 轮 / 200 轮
        for count in [0, 1, 3, 5, 6, 12, 38, 200] {
            let vm = FixturesViewModel()
            vm.matches = count == 0 ? [] : makeRounds(count)
            // 覆盖：越界的小值 / 中间值 / 越界的大值
            for focused in [1, 2, 3, 5, count / 2 + 1, count - 1, count, 999] {
                vm.roundWindowStart = 0
                vm.focusedRound = focused
                vm.alignWindowToFocusedRound()

                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size,
                                         "轮次 \(count) 场 / 聚焦 \(focused)：窗口不得超过 \(size) 个")
                XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                            "轮次 \(count) 场 / 聚焦 \(focused)：起点不能为负")
                XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                         "轮次 \(count) 场 / 聚焦 \(focused)：起点不能越过上界")

                // 翻到最右，再验一遍不变量
                for _ in 0..<(count + 1) { vm.pageRoundsForward() }
                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size)
                XCTAssertEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                               "一直右翻后应停在上界")
                XCTAssertEqual(vm.visibleRounds,
                               Array(vm.availableRounds.suffix(min(size, count))),
                               "最右窗口应是最后 \(min(size, count)) 个轮次")
            }
        }
    }

    /// 把快照压成可比较的指纹：轮次 + 状态 + 预览场次 id
    /// （元组数组不能直接 XCTAssertEqual，所以压成字符串）
    private func fingerprint(_ snaps: [RoundSnapshot]) -> String {
        snaps.map { snap -> String in
            let progress: String
            switch snap.progress {
            case .past:    progress = "past"
            case .current: progress = "current"
            case .future:  progress = "future"
            case .unknown: progress = "unknown"
            }
            let ids = snap.previews.map { String($0.id) }.joined(separator: ",")
            return "\(snap.round):\(progress):[\(ids)]"
        }.joined(separator: "|")
    }

    // MARK: - QA 独立验证：快照缓存正确性

    // 为什么不用工程师自己加的 `roundSnapshotsComputeCount`：
    // 那个计数器只能证明「有没有重算」—— 计数器没涨说明命中了缓存，
    // 但**命中时返回的内容对不对，它一个字也证明不了**。
    // 真正的风险是「该失效却没失效」返回陈旧快照，那才是用户能看到的数据错误。
    // 所以下面一律用一个独立 oracle 对拍：直接从 `vm.matches` 原始数据重算期望结果，
    // 每次调 `roundSnapshots` 都和它对齐。任何一次失效漏判都会在这里暴露。

    /// 独立 oracle：不读 VM 的任何缓存/索引，直接从 `vm.matches` 原始数据重算期望快照。
    /// 输出格式与 `fingerprint(_:)` 完全一致，便于直接比对。
    private func oracleSnapshots(for vm: FixturesViewModel, progress: SeasonProgress?) -> String {
        let cur = progress?.currentRound ?? vm.currentRound
        let maxRound = progress?.totalRounds ?? (vm.availableRounds.sorted().last ?? 38)
        // 生产实现在 maxRound < 1 时会因 `1...maxRound` 直接 trap。
        // oracle 不重演这个 crash，返回哨兵值，让断言给出可读的失败信息。
        guard maxRound >= 1 else { return "<INVALID maxRound=\(maxRound)>" }

        var byRound: [Int: [Match]] = [:]
        for m in vm.matches {
            guard let r = m.matchday else { continue }
            byRound[r, default: []].append(m)
        }
        for (r, list) in byRound {
            byRound[r] = list.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }
        }

        let known = Set(vm.availableRounds)
        var out: [String] = []
        for r in 1...maxRound {
            let base: RoundProgress = r < cur ? .past : (r == cur ? .current : .future)
            let effective = known.contains(r) ? base : (base == .future ? .unknown : base)
            let ids = (byRound[r] ?? []).prefix(3).map { String($0.id) }.joined(separator: ",")
            out.append("\(r):\(progressName(effective)):[\(ids)]")
        }
        return out.joined(separator: "|")
    }

    private func progressName(_ p: RoundProgress) -> String {
        switch p {
        case .past:    return "past"
        case .current: return "current"
        case .future:  return "future"
        case .unknown: return "unknown"
        }
    }

    /// 五场样例：第 1 轮 2 场、第 2 轮 2 场、第 3 轮 1 场
    private func sampleMatches() -> [Match] {
        [
            makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 4, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 5, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3),
        ]
    }

    /// 内容相等但分别构造的两个 `SeasonProgress`：缓存 key 靠 Equatable 比对，
    /// 必须认「值相等」而不是认「同一个对象」（结构体本来也没有引用身份，
    /// 这里覆盖的是「key 里存了 Optional<SeasonProgress> 却没正确解包比较」这类写法）。
    func testRoundSnapshotsCacheTreatsEqualSeasonProgressValuesAsSameInput() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let a = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        let b = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        XCTAssertEqual(a, b, "前置条件：两个 seasonProgress 必须值相等")

        let r1 = vm.roundSnapshots(seasonProgress: a)
        let r2 = vm.roundSnapshots(seasonProgress: b)
        XCTAssertEqual(fingerprint(r1), oracleSnapshots(for: vm, progress: a))
        XCTAssertEqual(fingerprint(r2), fingerprint(r1),
                       "内容相等的不同 seasonProgress 必须得出同一份快照")
        XCTAssertEqual(fingerprint(r2), oracleSnapshots(for: vm, progress: b))

        // 只有与快照无关的字段（playedRounds / fraction）变化 → key 不等 → 重算，
        // 但内容不该变（currentRound 与 totalRounds 都没动）
        let c = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 2,
                               remainingRounds: 1, fraction: 2.0 / 3.0, seasonYear: 2025)
        XCTAssertNotEqual(a, c, "前置条件：两个 seasonProgress 必须值不等")
        let r3 = vm.roundSnapshots(seasonProgress: c)
        XCTAssertEqual(fingerprint(r3), oracleSnapshots(for: vm, progress: c))
        XCTAssertEqual(fingerprint(r3), fingerprint(r1),
                       "currentRound / totalRounds 没变，快照内容就不该变")
    }

    /// `seasonProgress` 在 nil ↔ 非 nil 之间来回切，是 key 比对最容易写错的分支
    /// （Optional 参与 == 时，nil 与 nil 必须判等、nil 与 .some 必须判不等）。
    func testRoundSnapshotsNilProgressToggleNeverReturnsStaleSnapshot() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()                 // availableRounds = [1, 2, 3]

        let nilFirst = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(nilFirst.count, 3, "nil 时 totalRounds 兜底为 availableRounds.last")
        XCTAssertEqual(fingerprint(nilFirst), oracleSnapshots(for: vm, progress: nil))
        let nilSecond = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(nilSecond), fingerprint(nilFirst), "连续两次 nil 结果必须一致")

        let p = SeasonProgress(currentRound: 3, totalRounds: 5, playedRounds: 2,
                               remainingRounds: 3, fraction: 0.4, seasonYear: 2025)
        let nonNil = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(nonNil.count, 5)
        XCTAssertEqual(fingerprint(nonNil), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(nonNil), fingerprint(nilFirst),
                          "前置条件：nil 与非 nil 的结果必须不同，否则这条测不出陈旧缓存")

        // 切回 nil —— 不能残留上一次非 nil 的缓存
        let backToNil = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(backToNil), fingerprint(nilFirst),
                       "切回 nil 必须回到 nil 的结果，不能残留上一次非 nil 的缓存")
        XCTAssertEqual(fingerprint(backToNil), oracleSnapshots(for: vm, progress: nil))

        // 再切回非 nil —— 反过来也不能残留 nil 那一份
        let again = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(again), fingerprint(nonNil),
                       "切回非 nil 也不能残留 nil 的缓存")
        XCTAssertEqual(fingerprint(again), oracleSnapshots(for: vm, progress: p))
    }

    /// 只改 `currentRound`（matches 与 seasonProgress 都不动），缓存必须失效。
    /// 注意必须传 `seasonProgress: nil`：非 nil 时 cur 取 seasonProgress.currentRound，
    /// vm.currentRound 根本不参与输出，那样测不出这条失效路径。
    func testRoundSnapshotsInvalidatesWhenOnlyCurrentRoundChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        vm.currentRound = 1

        let before = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(before[0].progress, .current, "前置条件：当前轮是第 1 轮")
        XCTAssertEqual(fingerprint(before), oracleSnapshots(for: vm, progress: nil))

        vm.currentRound = 3                          // 只动这一个输入
        let after = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(after), oracleSnapshots(for: vm, progress: nil))
        XCTAssertNotEqual(fingerprint(after), fingerprint(before))
        XCTAssertEqual(after[0].progress, .past, "currentRound 变了缓存必须失效：第 1 轮应变 past")
        XCTAssertEqual(after[1].progress, .past)
        XCTAssertEqual(after[2].progress, .current)

        // 改回原值也要回到原结果，不能是「只失效一次」的一次性开关
        vm.currentRound = 1
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)), fingerprint(before),
                       "currentRound 还原后应回到第一次的结果")
    }

    /// 轮次集合的退化形态：1 轮 / 0 轮（matches 为空）/ 乱序不连续 [7, 3, 19] / 极多（1000 轮）
    func testRoundSnapshotsHandlesDegenerateRoundSets() {
        // 1) 只有 1 轮
        let one = FixturesViewModel()
        one.matches = [makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1)]
        let oneSnaps = one.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(oneSnaps.count, 1)
        XCTAssertEqual(fingerprint(oneSnaps), oracleSnapshots(for: one, progress: nil))
        XCTAssertEqual(oneSnaps[0].progress, .current)
        XCTAssertEqual(oneSnaps[0].previews.map(\.id), [1])

        // 2) matches 为空 → availableRounds 空 → 走 38 兜底，不崩、不越界
        let empty = FixturesViewModel()
        let emptySnaps = empty.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(emptySnaps.count, 38)
        XCTAssertEqual(fingerprint(emptySnaps), oracleSnapshots(for: empty, progress: nil))
        XCTAssertTrue(emptySnaps.allSatisfy { $0.previews.isEmpty }, "无数据时全部空占位")

        // 3) 轮次编号乱序且不连续
        let sparse = FixturesViewModel()
        sparse.matches = [
            makeMatch(id: 7, kickoff: "2025-10-01T11:00:00Z", status: "SCHEDULED", matchday: 7),
            makeMatch(id: 3, kickoff: "2025-09-01T11:00:00Z", status: "FINISHED", matchday: 3),
            makeMatch(id: 19, kickoff: "2025-12-01T11:00:00Z", status: "SCHEDULED", matchday: 19),
        ]
        XCTAssertEqual(sparse.availableRounds, [3, 7, 19], "轮次号应升序")
        let sparseSnaps = sparse.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(sparseSnaps.count, 19, "总轮数取 availableRounds.last")
        XCTAssertEqual(fingerprint(sparseSnaps), oracleSnapshots(for: sparse, progress: nil))
        XCTAssertEqual(sparseSnaps.map(\.round), Array(1...19),
                       "轮次号必须连续铺满 1...max，不能跟着数据里的洞跳号")
        XCTAssertEqual(sparseSnaps[2].previews.map(\.id), [3])
        XCTAssertEqual(sparseSnaps[6].previews.map(\.id), [7])
        XCTAssertEqual(sparseSnaps[18].previews.map(\.id), [19])
        XCTAssertTrue(sparseSnaps[0].previews.isEmpty, "第 1 轮无数据 → 空占位，不能越界取到别的轮")

        // 4) 轮次极多：这是「一次性渲染全部轮次」质疑的压测口径，1000 轮不许崩
        let many = FixturesViewModel()
        many.matches = (1...1000).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T11:00:00Z", status: "SCHEDULED", matchday: i)
        }
        let manySnaps = many.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(manySnaps.count, 1000)
        XCTAssertEqual(manySnaps.first?.round, 1)
        XCTAssertEqual(manySnaps.last?.round, 1000)
        XCTAssertEqual(fingerprint(manySnaps), oracleSnapshots(for: many, progress: nil))
    }

    /// `matches` 换成不同内容、`seasonProgress` 保持不变 —— 只能靠 `indexGeneration` 失效。
    func testRoundSnapshotsInvalidatesWhenMatchesContentChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let p = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)

        let first = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(first[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(fingerprint(first), oracleSnapshots(for: vm, progress: p))

        // 换一批完全不同的比赛，seasonProgress 一个字没变
        vm.matches = [
            makeMatch(id: 71, kickoff: "2025-08-21T09:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 72, kickoff: "2025-09-04T09:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let second = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(second), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(second), fingerprint(first))
        XCTAssertEqual(second[0].previews.map(\.id), [71], "快照必须跟着新数据走，不能返回旧缓存")
        XCTAssertEqual(second[2].previews.map(\.id), [72])

        // 内容相同但重新赋一次值（indexGeneration 自增）→ 结果仍须与 oracle 一致
        vm.matches = vm.matches
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                       oracleSnapshots(for: vm, progress: p))
    }

    /// 交叉遍历输入组合，每一步都对拍 oracle，兜住「该失效却没失效」。
    ///
    /// ⚠️ 这一条第一版是**假通过**：当时在循环里反复给 `vm.seasonProgress` / `vm.matches` 赋值，
    /// 而这两个属性的 `didSet` 会无条件清空缓存 —— 于是无论 `SnapshotCacheKey` 里
    /// 到底比了什么字段，每次都会重算，测试永远绿。
    /// key 真正成为**唯一防线**的场景只有一个：**函数入参与已存属性不一致**
    /// （此时不触发任何 didSet，只有 key 比对能救命）。所以下面第一轮全程不再写属性。
    func testRoundSnapshotsNeverGoesStaleAcrossInputMutationSweep() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let progresses: [SeasonProgress?] = [
            nil,
            SeasonProgress(currentRound: 1, totalRounds: 3, playedRounds: 0,
                           remainingRounds: 3, fraction: 0, seasonYear: 2025),
            SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                           remainingRounds: 2, fraction: 0.33, seasonYear: 2025),
            SeasonProgress(currentRound: 3, totalRounds: 8, playedRounds: 2,
                           remainingRounds: 6, fraction: 0.25, seasonYear: 2025),
        ]

        // —— 第一轮：key 是唯一防线。此后不再写 vm.seasonProgress / vm.matches ——
        vm.seasonProgress = progresses[1]
        for pass in 0..<2 {
            for (i, p) in progresses.enumerated() {
                for (j, q) in progresses.enumerated() {
                    _ = vm.roundSnapshots(seasonProgress: p)
                    XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: q)),
                                   oracleSnapshots(for: vm, progress: q),
                                   "pass\(pass)：入参由 #\(i) 换成 #\(j) 后返回了陈旧快照 —— " +
                                   "SnapshotCacheKey 漏了 seasonProgress 字段？")
                }
            }
            vm.currentRound = 4
            XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)),
                           oracleSnapshots(for: vm, progress: nil),
                           "pass\(pass)：只改 currentRound 后返回了陈旧快照 —— " +
                           "didSet 与 key 两道保险同时失效")
            vm.currentRound = 2
        }

        // —— 第二轮：改 matches 内容（indexGeneration 路径）——
        for k in 0..<3 {
            vm.matches = sampleMatches() + [
                makeMatch(id: 900 + k, kickoff: "2025-09-11T11:00:00Z",
                          status: "FINISHED", matchday: 2),
            ]
            for (i, p) in progresses.enumerated() {
                XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                               oracleSnapshots(for: vm, progress: p),
                               "第 \(k) 次改 matches / 入参 #\(i) 后返回了陈旧快照")
            }
        }
    }

    // MARK: - QA 独立验证：lazy 化与布局红线

    /// 静态扫源码确认 lazy 化的结构（比「源码里含不含 LazyHStack」更严格）：
    /// LazyHStack 必须是横向 ScrollView 的**第一个直接子视图** ——
    /// 中间夹任何容器都可能是「lazy 套 lazy」，那是布局死循环红线。
    func testRoundChipBarLazyHStackIsDirectChildOfHorizontalScrollView() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "ScrollView(.horizontal", in: code), 1,
                       "期望只有轮次 chip bar 一处横向 ScrollView；结构变了本护栏需同步更新")

        guard let sv = code.range(of: "ScrollView(.horizontal") else {
            return XCTFail("找不到横向 ScrollView")
        }
        guard let brace = code[sv.upperBound...].firstIndex(of: "{") else {
            return XCTFail("横向 ScrollView 后面没有内容块")
        }
        var i = code.index(after: brace)
        while i < code.endIndex, code[i].isWhitespace { i = code.index(after: i) }
        let firstToken = code[i...]
        XCTAssertTrue(firstToken.hasPrefix("LazyHStack"),
                      "横向 ScrollView 的第一个直接子视图必须是 LazyHStack，不能是别的容器（" +
                      "lazy 套 lazy 会布局死循环，退回 HStack 则轮次一多就全量建视图）。" +
                      "实际开头：\(firstToken.prefix(40))")

        guard let fn = code.range(of: "func roundChipBar") else {
            return XCTFail("找不到 roundChipBar")
        }
        // 上面的 hasPrefix("LazyHStack") 已经排除了退回普通 HStack 的情况
        // （不能再用 contains("HStack(spacing: 8)") 反查 —— LazyHStack 本身就含这段子串）
        XCTAssertTrue(code[fn.lowerBound...].contains(".frame(height: 32)"),
                      "roundChipBar 的横向 ScrollView 必须保留 .frame(height: 32)")
        XCTAssertTrue(code[fn.lowerBound...].contains("roundPageButton"),
                      "两个翻页按钮应复用 roundPageButton，保证样式与无障碍文案口径一致")
        // 固定窗口：chip bar 只渲染窗口内的轮次，不能回到「列出全部 availableRounds」
        XCTAssertTrue(code[fn.lowerBound...].contains("vm.visibleRounds"),
                      "chip bar 必须渲染 vm.visibleRounds（固定窗口），" +
                      "直接 ForEach(vm.availableRounds) 会让渲染量随总轮次数线性增长")
    }

    /// 全项目硬红线：lazy 容器互相嵌套 / GridItem 无上界 / URLSession.shared / .help 硬编码
    func testSourcesHaveNoLayoutOrNetworkRedLines() throws {
        let violations = try allSourceFiles().flatMap { f -> [String] in
            let code = codeOnly(f.text)
            var v: [String] = []
            if code.contains("LazyVStack") {
                v.append("\(f.name)：出现 LazyVStack（lazy 容器嵌套会让布局尺寸协商死循环）")
            }
            if code.contains("maximum: .infinity") {
                v.append("\(f.name)：GridItem 的 maximum 不能是 .infinity")
            }
            if code.contains("URLSession.shared") {
                v.append("\(f.name)：禁止使用 URLSession.shared（资源超时 7 天会让 await 永不返回）")
            }
            if code.contains(".help(\"") {
                v.append("\(f.name)：.help( 里出现硬编码字符串字面量，必须走 UIString")
            }
            return v
        }
        XCTAssertEqual(violations, [], "硬约束红线被踩：\n" + violations.joined(separator: "\n"))
    }

    /// 逐字符扫括号深度，检出任何「lazy 容器嵌在 lazy 容器里」。
    /// 比单纯 `contains("LazyVStack")` 强：就算以后换了别的 lazy 容器名也拦得住。
    func testNoLazyContainerNestedInsideAnotherLazyContainer() throws {
        for f in try allSourceFiles() {
            let v = lazyNestingViolations(codeOnly(f.text))
            XCTAssertEqual(v, [], "\(f.name) 出现 lazy 容器嵌套：\(v.joined(separator: "; "))")
        }
    }

    /// 嵌在纵向 ScrollView 里的横向 ScrollView 必须有确定高度，否则无限协商尺寸卡死主线程
    func testHorizontalScrollViewsAreHeightConstrained() throws {
        for f in try allSourceFiles() {
            let code = codeOnly(f.text)
            var search = code.startIndex
            while let r = code.range(of: "ScrollView(.horizontal", range: search..<code.endIndex) {
                // 窗口要够长：横向 ScrollView 的内容块（LazyHStack + 若干 chip）本身就有上千字符
                let windowEnd = code.index(r.upperBound, offsetBy: 3000, limitedBy: code.endIndex)
                    ?? code.endIndex
                XCTAssertTrue(code[r.upperBound..<windowEnd].contains(".frame(height:"),
                              "\(f.name) 的横向 ScrollView 缺少 .frame(height:)：" +
                              "嵌在纵向 ScrollView 里会和父视图无限协商尺寸")
                search = r.upperBound
            }
        }
    }

    // MARK: - QA 独立验证：文案与本地化

    /// 翻页按钮的两条提示：中英都要存在、且**不带任何占位符**。
    /// 翻页的目标轮次由当前窗口决定，不是固定值 —— 塞个 %d 进去反而误导。
    func testRoundsPageStringsAreLocalizedWithoutPlaceholders() {
        let cases: [(String, UIString)] = [
            ("prevRoundsPage", UIString.prevRoundsPage),
            ("nextRoundsPage", UIString.nextRoundsPage),
        ]
        for (name, s) in cases {
            let zh = s.text(.chinese)
            let en = s.text(.english)
            XCTAssertFalse(zh.isEmpty, "\(name).zh 不能为空")
            XCTAssertFalse(en.isEmpty, "\(name).en 不能为空")
            XCTAssertNotEqual(zh, en, "\(name) 必须真的做了本地化，不能中英同文")
            for token in ["%d", "%@", "%f", "%lld"] {
                XCTAssertEqual(count(of: token, in: zh), 0,
                               "\(name).zh 不应含 \(token)（纯动作描述，不带参数）")
                XCTAssertEqual(count(of: token, in: en), 0,
                               "\(name).en 不应含 \(token)（纯动作描述，不带参数）")
            }
        }
    }

    /// 上一版的三个跳转文案（jumpToFirstRound / jumpToLastRound / jumpToNextRound）
    /// 随翻页按钮一起被删掉了，不能留死文案在 UIStrings.swift 里。
    func testRemovedJumpRoundStringsDoNotComeBack() throws {
        let src = try sourceFile("UIStrings.swift")
        for dead in ["jumpToFirstRound", "jumpToLastRound", "jumpToNextRound"] {
            XCTAssertEqual(count(of: dead, in: src), 0,
                           "\(dead) 对应的按钮已删除，UIStrings 里不该再留着这条死文案")
        }
    }

    /// 全量校验 UIStrings.swift 里每一条的中英占位符数量一致
    func testAllUIStringsKeepZhEnPlaceholderParity() throws {
        let src = try sourceFile("UIStrings.swift")
        let re = try NSRegularExpression(
            pattern: #"UIString\(\s*zh:\s*"([^"]*)"\s*,\s*en:\s*"([^"]*)"\s*\)"#,
            options: .dotMatchesLineSeparators
        )
        let ns = src as NSString
        let matches = re.matches(in: src, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThan(matches.count, 40, "解析到的 UIString 条数偏少，正则可能失配")

        for m in matches {
            guard let zr = Range(m.range(at: 1), in: src),
                  let er = Range(m.range(at: 2), in: src) else { continue }
            let zh = String(src[zr])
            let en = String(src[er])
            for token in ["%d", "%@", "%f", "%lld"] {
                XCTAssertEqual(count(of: token, in: zh), count(of: token, in: en),
                               "中英占位符数量不一致会让 String(format:) 读脏参数：" +
                               "\(token) / zh=\(zh) / en=\(en)")
            }
        }
    }

    /// 两个翻页按钮的无障碍文案必须走 UIString，不能写死字面量
    func testPageButtonsWireHelpThroughUIStrings() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        for key in ["prevRoundsPage", "nextRoundsPage"] {
            XCTAssertEqual(count(of: "UIString.\(key)", in: code), 1,
                           "\(key) 应在 roundChipBar 里被且只被使用一次")
            XCTAssertFalse(code.contains("String(format: UIString.\(key)"),
                           "\(key) 不带参数，不该走 String(format:)")
        }
        XCTAssertFalse(code.contains(".help(\""), "翻页按钮的 .help 不能写死字符串字面量")
        XCTAssertTrue(code.contains(".help(help)"),
                      "roundPageButton 应统一用传入的 help 参数，保证两个按钮口径一致")
    }

    /// 本次改动不得新增硬编码的用户可见中文。
    /// 下面这些是**既存**违规（本次改动没碰，已在 QA 报告里单列），数字只能降不能升。
    func testNoNewHardcodedUserFacingChineseInViews() throws {
        let baseline = [
            "FixturesView.swift": 1,             // :418  "加载失败"
            "LeadersAndInjuriesViews.swift": 1,  // :213  "加载失败"
            "StandingsView.swift": 1,            // :43   "加载失败"
            "Models.swift": 9,                   // 5 条伤停状态 + 4 条 AppError.errorDescription
        ]
        for f in try allSourceFiles() where f.name != "UIStrings.swift" && f.name != "TeamNames.swift" && f.name != "PlayerNames.swift" {
            let found = hardcodedCJK(in: codeOnly(f.text))
            XCTAssertLessThanOrEqual(found.count, baseline[f.name] ?? 0,
                                     "\(f.name) 新增了硬编码中文，应改用 UIString：" +
                                     "\(found.joined(separator: " / "))")
        }
    }

    // MARK: - 源码扫描工具

    /// 剥掉 `//` 行注释只留代码 —— 否则「为什么不能用 LazyVStack」这类解释性注释会误报
    private func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)                  // .../Tests/EPLViewerTests/EPLViewerTests.swift
            .deletingLastPathComponent()                 // Tests/EPLViewerTests
            .deletingLastPathComponent()                 // Tests
            .deletingLastPathComponent()                 // 包根
            .appendingPathComponent("Sources/EPLViewer")
    }

    private func sourceFile(_ name: String) throws -> String {
        try String(contentsOf: sourceRoot().appendingPathComponent(name), encoding: .utf8)
    }

    private func allSourceFiles() throws -> [(name: String, text: String)] {
        let root = sourceRoot()
        return try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// 子串出现次数（非重叠）
    private func count(of token: String, in s: String) -> Int {
        var n = 0
        var idx = s.startIndex
        while let r = s.range(of: token, range: idx..<s.endIndex) {
            n += 1
            idx = r.upperBound
        }
        return n
    }

    /// 扫出「lazy 容器嵌在 lazy 容器里」的位置。返回空数组即未踩红线。
    /// 做法：逐字符走，跟踪花括号深度；遇到 `LazyXXX(` 记下它所在深度，
    /// 若栈里已有另一个 lazy 容器处于更浅/相等深度，说明它被套在里面。
    private func lazyNestingViolations(_ code: String) -> [String] {
        let names = ["LazyVStack", "LazyHStack", "LazyVGrid", "LazyHGrid"]
        var violations: [String] = []
        var stack: [(name: String, depth: Int)] = []
        var depth = 0
        var inString = false
        var escaped = false

        var idx = code.startIndex
        while idx < code.endIndex {
            let c = code[idx]
            var advance = 1
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"":
                    inString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    while let top = stack.last, depth <= top.depth { stack.removeLast() }
                default:
                    for n in names where code[idx...].hasPrefix(n + "(") {
                        if let outer = stack.last {
                            violations.append("\(n) 嵌在 \(outer.name) 内")
                        }
                        stack.append((n, depth))
                        advance = n.count + 1
                    }
                }
            }
            idx = code.index(idx, offsetBy: advance, limitedBy: code.endIndex) ?? code.endIndex
        }
        return violations
    }

    /// 找源码里写死的、用户可见的中文字符串。
    /// DateFormatter 模板（"M月d日" / "M月d日 HH:mm"）不算 —— 那是格式串不是文案。
    private func hardcodedCJK(in code: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "\"([^\"\\\n]*)\"")
        let ns = code as NSString
        var out: [String] = []
        for m in re.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            guard let r = Range(m.range(at: 1), in: code) else { continue }
            let s = String(code[r])
            let hasCJK = s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            guard hasCJK else { continue }
            let isDateFormat = s.allSatisfy { $0.isASCII || $0 == "月" || $0 == "日" }
                && s.contains(where: { "MEHhmy".contains($0) })
            if !isDateFormat { out.append(s) }
        }
        return out
    }

    // MARK: - 网络超时与取数预算

    /// `URLSession.shared` 的资源超时是 7 天，遇到「连上了但服务端慢慢吐」的接口
    /// （实测 FPL bootstrap-static 会挂 30s+ 不结束）会让 await 永不返回，
    /// 表现为界面一直转圈 + 点不动。这里守住超时必须是有限值。
    func testAPIClientTimeoutsAreFinite() {
        let cfg = APIClient.session.configuration
        XCTAssertLessThan(cfg.timeoutIntervalForResource, 120,
                          "资源总时长必须有上限，否则慢接口会无限挂起")
        XCTAssertLessThanOrEqual(cfg.timeoutIntervalForRequest, cfg.timeoutIntervalForResource)
        XCTAssertFalse(cfg.waitsForConnectivity, "断网应立即失败，好让兜底数据顶上")

        let imgCfg = APIClient.imageSession.configuration
        XCTAssertLessThanOrEqual(imgCfg.timeoutIntervalForResource, cfg.timeoutIntervalForResource,
                                 "队徽属于锦上添花，超时不应比主数据还宽松")
    }

    /// 正常快路径：预算内完成，返回真实值
    func testWithTimeBudgetReturnsValueWhenFast() async {
        let value = await withTimeBudget(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    /// 关键路径：操作超预算时必须返回 nil，而不是一直等下去
    func testWithTimeBudgetGivesUpWhenOperationIsSlow() async {
        let started = Date()
        let value = await withTimeBudget(seconds: 1) { () -> Int in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 远超预算
            return 42
        }
        XCTAssertNil(value, "超预算应放弃并返回 nil")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "放弃要干脆：1 秒预算不该等上 30 秒")
    }

    /// 数据源本身返回 nil（拿不到数据）时，要如实传递 nil，不与「超时」混淆
    func testWithTimeBudgetPropagatesNilResult() async {
        let value: Int? = await withTimeBudget(seconds: 5) { nil }
        XCTAssertNil(value)
    }

    // MARK: - 当前轮派生（纯函数）

    func testDeriveCurrentRoundPrefersIsCurrent() {
        let events = [
            FPLGameweek(id: 1, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 2, name: nil, is_current: false, is_next: true,  finished: false, deadline_time: nil),
            FPLGameweek(id: 3, name: nil, is_current: true,  is_next: false, finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(events), 3, "is_current 优先级最高")
    }

    func testDeriveCurrentRoundFallsBackToNextThenLatestFinished() {
        // 无 is_current → 取 is_next
        let noCurrent = [
            FPLGameweek(id: 1, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 2, name: nil, is_current: false, is_next: true,  finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(noCurrent), 2)

        // 无 is_current / is_next → 取最新已结束轮
        let onlyFinished = [
            FPLGameweek(id: 5, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 7, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 8, name: nil, is_current: false, is_next: false, finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(onlyFinished), 7)

        // 什么都没有 → 回退首轮
        let empty = [
            FPLGameweek(id: 4, name: nil, is_current: nil, is_next: nil, finished: nil, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(empty), 4)

        XCTAssertNil(DataRepository.deriveCurrentRound([]), "空列表返回 nil")
    }

    /// FPL events 拿不到（超时/网络失败）时的本地兜底：
    /// 取第一个还有未结束比赛的轮次，全部结束则取最后一轮。
    func testInferCurrentRoundFromMatches() {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: 2),
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 3),
        ]
        XCTAssertEqual(vm.inferCurrentRoundFromMatches(), 2,
                       "第 1 轮全踢完、第 2 轮还没开始 → 当前轮应为 2")

        // 全部结束 → 取最后一个有比赛的轮次
        let allDone = FixturesViewModel()
        allDone.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(allDone.inferCurrentRoundFromMatches(), 2)

        XCTAssertNil(FixturesViewModel().inferCurrentRoundFromMatches(), "无数据返回 nil")
    }

    /// `CurrentRoundInference` 是赛程页与今日页共用的兜底规则，单独覆盖：
    /// 第一个还有未结束比赛的轮次；全部结束则取最后一个有比赛的轮次。
    func testCurrentRoundInferenceSharedByBothPages() {
        let ongoing = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 3),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "IN_PLAY", matchday: 4),
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: ongoing), 4,
                       "进行中的比赛也算未结束 → 当前轮是 4")

        // 轮次乱序传入也要正确（内部自行排序）
        let shuffled = [
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 9),
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: 6),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: shuffled), 6)

        // 全部结束 → 最后一个有比赛的轮次
        let allDone = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: allDone), 2)

        // matchday 为 nil 的未分配比赛应被忽略，不影响推断
        let withNil = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: nil),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: withNil), 1)

        XCTAssertNil(CurrentRoundInference.infer(from: []), "空赛程返回 nil")
    }

    // MARK: - QA 独立复审：改动 1 / 2 / 3

    /// 从 `from` 起截到 `to`（不含 `to`）；`to` 为 nil 时截到末尾。
    private func qaSlice(_ s: String, from: String, to: String? = nil) -> String? {
        guard let lo = s.range(of: from) else { return nil }
        let rest = s[lo.lowerBound...]
        guard let to, let hi = rest.range(of: to) else { return String(rest) }
        return String(rest[rest.startIndex..<hi.lowerBound])
    }

    // ── 改动 1：推荐卡改成写死渐变背景 ──

    /// 渐变必须是写死的 `Color` 字面量，不得读系统强调色 / AppState。
    func testFeaturedCardGradientIsHardcodedNotAccentDriven() throws {
        let src = try sourceFile("TodayView.swift")
        let block = try XCTUnwrap(
            qaSlice(src, from: "private let featuredCardGradient", to: "\n)"),
            "找不到 featuredCardGradient 常量声明"
        )
        XCTAssertTrue(block.contains("LinearGradient"), "推荐卡背景应是 LinearGradient")
        XCTAssertEqual(count(of: "Color(red:", in: block), 2, "渐变两端各一个写死的 Color")
        XCTAssertTrue(block.contains("startPoint: .leading"), "渐变方向应为左→右")
        XCTAssertTrue(block.contains("endPoint: .trailing"), "渐变方向应为左→右")
        for forbidden in ["AppState", "accent", "Accent", "NSColor", "@Environment", ".tint"] {
            XCTAssertEqual(count(of: forbidden, in: block), 0,
                           "渐变里出现 \(forbidden) —— 那就又变回随系统强调色变了")
        }
    }

    /// `FeaturedMatchCard` 里已无 `.glassEffect`；但 `columnCard` 那处 Liquid Glass 必须保留。
    func testFeaturedCardDroppedGlassEffectButColumnCardKeptIt() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "找不到 FeaturedMatchCard")
        XCTAssertEqual(count(of: "glassEffect", in: card), 0,
                       "FeaturedMatchCard 里仍有 .glassEffect 残留 —— 背景没换干净")

        let columnCard = try XCTUnwrap(
            qaSlice(code, from: "private func columnCard", to: "struct FeaturedMatchCard"),
            "找不到 columnCard"
        )
        XCTAssertEqual(count(of: "glassEffect", in: columnCard), 1,
                       "columnCard 的 Liquid Glass 属于改动范围外，必须原样保留")
        XCTAssertTrue(columnCard.contains("RoundedRectangle(cornerRadius: 12)"),
                      "columnCard 的圆角应保持 12")
    }

    /// 暗化层的圆角必须与外层一致，否则边缘会露出毛边。
    func testFeaturedCardOverlaySharesCornerRadiusWithGradient() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let bg = try XCTUnwrap(qaSlice(card, from: ".background("), "找不到推荐卡的 .background(")

        XCTAssertEqual(count(of: "cornerRadius:", in: bg), 2,
                       "背景块里应恰好两处圆角：渐变一层 + 暗化 overlay 一层")
        XCTAssertEqual(count(of: "RoundedRectangle(cornerRadius: featuredCardCornerRadius)", in: bg), 2,
                       "两处圆角必须都用同一个 featuredCardCornerRadius 常量，不能写死数字")
        XCTAssertTrue(bg.contains(".fill(featuredCardGradient)"), "渐变没被填进背景")
        XCTAssertTrue(bg.contains(".fill(Color.black.opacity(0.12))"), "缺少暗化 overlay")
    }

    /// 只许动背景：圆角 / 内边距 / 队徽尺寸 / 比分字号 / 球队块留白一律不得变。
    func testFeaturedCardLayoutConstantsUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        XCTAssertTrue(code.contains("private let featuredCardCornerRadius: CGFloat = 12"),
                      "推荐卡圆角应保持 12")
        XCTAssertTrue(code.contains("private let featuredCardSideInset: CGFloat = 40"),
                      "球队块额外留白应保持 40")

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        XCTAssertTrue(card.contains("CrestImage(urlString: team.crest, size: 56)"),
                      "队徽应按 56×56 渲染（CrestImage.size，外层 .frame 放不大固定尺寸的子视图）")
        XCTAssertTrue(card.contains(".system(size: 44, weight: .bold, design: .rounded)"),
                      "比分字号应保持 44")
        XCTAssertTrue(card.contains(".padding(22)"), "卡片内边距应保持 22")
        XCTAssertTrue(card.contains("padding(.horizontal, featuredCardSideInset)"),
                      "中部球队块应仍用 featuredCardSideInset 留白")
        XCTAssertTrue(card.contains("VStack(spacing: 18)"), "卡片纵向间距应保持 18")
        XCTAssertTrue(card.contains("Spacer(minLength: 24)"), "比分两侧最小间距应保持 24")
    }

    /// 渐变换成写死的深紫红→亮粉后，卡上文字在**浅色模式**下还读得清吗？
    ///
    /// 修复方案：卡片子树强制深色语义（`.environment(\.colorScheme, .dark)`），
    /// 让 `.primary` / `.secondary` / 默认前景色在浅色模式下也解析成**白/浅灰**，
    /// 而不是黑字压深紫红（那样 WCAG 对比度只有 1.71:1）。
    /// 这里按 WCAG 相对亮度验证「白字 vs 渐变两端」的对比度都 ≥ AA 大字号门槛 3.0。
    func testFeaturedCardGradientKeepsTextReadableInLightMode() throws {
        let src = try sourceFile("TodayView.swift")

        // 修复的核心：卡片子树必须强制深色语义，否则浅色模式下文字解析成黑字
        XCTAssertTrue(src.contains(".environment(\\.colorScheme, .dark)"),
                      "推荐卡必须强制深色语义（.environment(\\.colorScheme, .dark)），否则浅色模式下黑字压深紫红几乎不可读")

        let block = try XCTUnwrap(qaSlice(src, from: "private let featuredCardGradient", to: "\n)"))

        let re = try NSRegularExpression(
            pattern: #"Color\(\s*red:\s*([\d.]+)\s*,\s*green:\s*([\d.]+)\s*,\s*blue:\s*([\d.]+)\s*\)"#
        )
        var stops: [(Double, Double, Double)] = []
        for m in re.matches(in: block, range: NSRange(location: 0, length: (block as NSString).length)) {
            guard let rr = Range(m.range(at: 1), in: block),
                  let gg = Range(m.range(at: 2), in: block),
                  let bb = Range(m.range(at: 3), in: block),
                  let r = Double(block[rr]), let g = Double(block[gg]), let b = Double(block[bb])
            else { continue }
            stops.append((r, g, b))
        }
        XCTAssertEqual(stops.count, 2, "应解析出渐变的两个端点")

        // 暗化层：0.12 的黑叠在渐变之上
        let dim = 0.12
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func chan(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * chan(c.0) + 0.7152 * chan(c.1) + 0.0722 * chan(c.2)
        }
        func contrast(_ a: Double, _ b: Double) -> Double {
            let (hi, lo) = a > b ? (a, b) : (b, a)
            return (hi + 0.05) / (lo + 0.05)
        }

        // 深色语义下 .primary / 默认前景色 == 白（亮度 1）
        let white: Double = 1.0
        // WCAG AA 大字号（≥24pt）最低 3.0 —— 取最宽松的一档，避免误报
        let bar = 3.0
        for (i, s) in stops.enumerated() {
            let eff = (s.0 * (1 - dim), s.1 * (1 - dim), s.2 * (1 - dim))
            let ratio = contrast(luminance(eff), white)
            XCTAssertGreaterThanOrEqual(
                ratio, bar,
                "渐变端点 \(i)（rgb \(s)）叠上 0.12 暗化层后，与深色语义下的白字对比度只有 " +
                String(format: "%.2f", ratio) + ":1，低于 \(bar):1"
            )
        }
    }

    // ── 改动 2：状态徽标移左 + 删除「推荐比赛」字样 ──

    /// `UIString.featured` 必须零残留；同时确认删的不是 `vm.featured(...)` 选比赛的方法。
    func testFeaturedUIStringIsFullyRemovedButPickerSurvives() throws {
        for f in try allSourceFiles() {
            XCTAssertEqual(count(of: "UIString.featured", in: f.text), 0,
                           "\(f.name) 里仍有 UIString.featured —— 已删的「推荐比赛」字样回来了")
        }
        let strings = try sourceFile("UIStrings.swift")
        XCTAssertEqual(count(of: "featured", in: strings), 0,
                       "UIStrings.swift 里不该再有任何 featured 条目")

        // ⚠️ 反例护栏：选推荐比赛的**方法**必须完好，不能被误删
        let today = try sourceFile("TodayView.swift")
        XCTAssertTrue(today.contains("func featured(tz: TimeZone, now: Date = Date()) -> Match?"),
                      "TodayViewModel.featured(tz:now:) 被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("enum TodayFeatured"),
                      "TodayFeatured 枚举被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("func pick(from matches: [Match]"),
                      "TodayFeatured.pick 被误删了 —— 这是严重回归")
        XCTAssertTrue(today.contains("if let featured = vm.featured(tz: timeZone)"),
                      "今日页仍在用 vm.featured(...) 取推荐比赛")
    }

    /// 行为层面确认选推荐比赛的逻辑没被删改（不只是「源码里还有这个符号」）。
    func testFeaturedPickerStillWorksAfterStringRemoval() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T04:00:00Z", status: "FINISHED",  matchday: 5),
            makeMatch(id: 2, kickoff: "2026-08-31T11:30:00Z", status: "IN_PLAY",   matchday: 5),
            makeMatch(id: 3, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 2,
                       "进行中的比赛优先成为推荐卡 —— featured(tz:now:) 仍然有效")
    }

    /// 顶部一行：轮次 → 状态徽标（靠左）→ Spacer 撑开右侧；且不再有「推荐比赛」文案。
    func testFeaturedCardTopRowIsRoundBadgeThenSpacer() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let top = try XCTUnwrap(qaSlice(card, from: "HStack(spacing: 8) {", to: "\n            }"),
                                "找不到推荐卡顶部的 HStack")

        XCTAssertFalse(top.contains("UIString.featured"), "顶部不该再有「推荐比赛」文案")
        XCTAssertTrue(top.contains("UIString.roundN.text(lang)"), "轮次要走 UIString.roundN")
        XCTAssertTrue(top.contains("statusBadge(lang: lang)"), "状态徽标应紧跟轮次")
        XCTAssertTrue(top.contains("Spacer()"), "末尾要有 Spacer 撑开右侧留白")

        // 顺序：轮次 < 徽标 < Spacer（徽标靠左、Spacer 收尾）
        let rRound = try XCTUnwrap(top.range(of: "UIString.roundN"))
        let rBadge = try XCTUnwrap(top.range(of: "statusBadge(lang: lang)"))
        let rSpacer = try XCTUnwrap(top.range(of: "Spacer()"))
        XCTAssertLessThan(rRound.lowerBound, rBadge.lowerBound, "轮次应在徽标之前")
        XCTAssertLessThan(rBadge.lowerBound, rSpacer.lowerBound, "徽标应靠左，Spacer 收尾")
    }

    /// `UIString.roundN` 必须保留，且今日页 / 赛程页两处调用都还在。
    func testRoundNStringStillServesTwoCallSites() throws {
        XCTAssertEqual(UIString.roundN.text(.chinese), "第 %d 轮")
        XCTAssertEqual(UIString.roundN.text(.english), "Round %d")
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.chinese)), 1)
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.english)), 1,
                       "中英占位符数量不一致会让 String(format:) 读脏参数")

        let today = codeOnly(try sourceFile("TodayView.swift"))
        let fixtures = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.roundN", in: today), 1,
                       "今日页推荐卡顶部仍应显示轮次")
        XCTAssertEqual(count(of: "UIString.roundN", in: fixtures), 1,
                       "赛程页赛季总览卡片仍应显示轮次")
    }

    // ── 改动 3：翻页只移窗口、不动 focusedRound ──

    /// 翻页函数体里不许出现 `focusedRound` —— 从源头锁住「翻页改焦点」。
    func testPagingFunctionsNeverTouchFocusedRound() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        let paging = try XCTUnwrap(
            qaSlice(code, from: "func pageRoundsBackward", to: "func groupedSections"),
            "找不到两个翻页函数"
        )
        XCTAssertEqual(count(of: "focusedRound", in: paging), 0,
                       "翻页函数不得改写 focusedRound —— 翻页只是移动 chip 的取景框")
        XCTAssertTrue(paging.contains("clampWindowStart()"),
                      "两个翻页函数都要夹回合法区间")
    }

    /// 大标题读的是 `vm.focusedRound`，不是窗口首轮 —— 翻页时标题必须稳定。
    func testFixturesHeaderReadsFocusedRoundNotWindow() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.fixturesHeader", in: code), 1,
                       "大标题只应出现一次")
        let section = try XCTUnwrap(
            qaSlice(code, from: "func thisRoundSection", to: "func seasonOverviewSection"),
            "找不到 thisRoundSection"
        )
        XCTAssertTrue(section.contains("UIString.fixturesHeader.text(lang), vm.focusedRound"),
                      "大标题必须读 vm.focusedRound，窗口移动时标题才不会跳变")
        XCTAssertFalse(section.contains("visibleRounds.first"),
                       "大标题不该跟着窗口首轮变")
    }

    /// 翻页对称往返：右翻 3 次再左翻 3 次，窗口与高亮都回到原处，focusedRound 全程恒定。
    ///
    /// ⚠️ 步数刻意选 3 —— 从起点 17 右翻 4 次会撞上界 33（clamp），
    /// 那时左翻 4 次回不到 17（非对称是 clamp 的正常结果，不是 bug）。
    func testPagingRoundTripKeepsFocusedRoundAndRestoresWindow() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "初始居中：MD20 居中 → 起点 17")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22])

        let originalStart = vm.roundWindowStart
        let shownMDs = vm.displayed.map(\.matchday)

        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 32, "右翻 3 次：17 → 22 → 27 → 32")
        XCTAssertEqual(vm.visibleRounds, [33, 34, 35, 36, 37])
        XCTAssertEqual(vm.focusedRound, 20, "翻页绝不改 focusedRound")
        XCTAssertEqual(vm.displayed.map(\.matchday), shownMDs, "内容区应始终显示 MD20")

        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "左翻 3 次窗口回到原处")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "回到原窗口后 MD20 重新高亮")
        XCTAssertEqual(vm.focusedRound, 20, "来回翻页后高亮仍是 MD20")
        XCTAssertTrue(vm.visibleRounds.contains(vm.focusedRound))
    }

    /// 单步右翻：窗口应正好从 MD18–22 挪到 MD23–27（窗口大小 5 的整页位移）。
    func testSingleForwardPageShiftsWindowByExactlyFive() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20

        vm.pageRoundsForward()
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27], "右翻一页 → MD23–MD27")
        XCTAssertEqual(vm.focusedRound, 20, "focusedRound 不动")

        vm.pageRoundsBackward()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "左翻一页 → 回到 MD18–MD22")
    }

    /// 初始居中仍成立：中间 / 靠左 / 靠右三种位置分别居中 / 左对齐 / 右对齐，且不越界。
    func testWindowAlignmentCoversMiddleLeftRightEdges() {
        // 中间：MD20 → 前 2 后 2
        let mid = FixturesViewModel()
        mid.matches = makeRounds(38)
        mid.roundWindowStart = 0
        mid.focusedRound = 20
        XCTAssertEqual(mid.visibleRounds, [18, 19, 20, 21, 22], "MD20 → 居中")

        // 靠左：MD1 / MD2 / MD3 → 起点夹到 0，不会变负
        for r in [1, 2, 3] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 30
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 0, "MD\(r) 靠左 → 起点夹到 0")
            XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        }

        // 靠右：MD36 / MD37 / MD38 → 起点夹到上界 33
        for r in [36, 37, 38] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 0
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 33, "MD\(r) 靠右 → 起点夹到上界 33")
            XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        }

        // 恰好比一屏多一轮（6 轮）→ 上界 1，右翻两格仍停在上界
        let six = FixturesViewModel()
        six.matches = makeRounds(6)
        six.focusedRound = 3
        XCTAssertEqual(six.roundWindowMaxStart, 1)
        six.pageRoundsForward()
        XCTAssertEqual(six.visibleRounds, [2, 3, 4, 5, 6])
        six.pageRoundsForward()
        XCTAssertEqual(six.roundWindowStart, 1, "再右翻仍停在上界")
    }

    /// 窗口不变量全量遍历：count × focusedRound × 翻页步数，逐一验三条不变量。
    func testWindowInvariantsHoldForAllCountsFocusedAndSteps() {
        let size = FixturesViewModel.roundWindowSize
        let counts = [0, 1, 3, 5, 6, 12, 38, 200]

        for count in counts {
            let vm = FixturesViewModel()
            vm.matches = count == 0 ? [] : makeRounds(count)

            var focusedCandidates = [1, 2, 3, 5, max(1, count / 2 + 1), count - 1, count, 999]
            focusedCandidates.append(contentsOf: [-5, 0])

            for focused in focusedCandidates {
                vm.focusedRound = focused
                let alignedStart = vm.roundWindowStart

                for step in 0...4 {
                    for _ in 0..<step { vm.pageRoundsForward() }

                    XCTAssertLessThanOrEqual(vm.visibleRounds.count, size,
                                             "count=\(count) focused=\(focused) fwd=\(step)：窗口超过 5")
                    XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                                "count=\(count) focused=\(focused) fwd=\(step)：起点为负")
                    XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                             "count=\(count) focused=\(focused) fwd=\(step)：起点越过上界")
                    XCTAssertEqual(vm.visibleRounds.count,
                                   min(size, max(0, count - vm.roundWindowStart)),
                                   "count=\(count) focused=\(focused) fwd=\(step)：窗口切片长度不对")
                    XCTAssertEqual(vm.focusedRound, focused,
                                   "count=\(count) fwd=\(step)：翻页改了 focusedRound")

                    // 再原路翻回去。⭐ 起点不是 0，而是上面 focusedRound 对齐后的位置。
                    // 往返的精确预期值：
                    //   - 右翻没撞上界（alignedStart + 5·step <= maxStart）→ 必须精确回到 alignedStart；
                    //   - 撞了上界 → 回程落点是 max(maxStart - 5·step, 0)（clamp 的正常结果，不是 bug）。
                    for _ in 0..<step { vm.pageRoundsBackward() }
                    let hitClamp = alignedStart + step * size > vm.roundWindowMaxStart
                    let expected = hitClamp
                        ? max(vm.roundWindowMaxStart - step * size, 0)
                        : alignedStart
                    XCTAssertEqual(vm.roundWindowStart, expected,
                                   "count=\(count) focused=\(focused) step=\(step)：" +
                                   "往返落点不符合预期（起点 \(alignedStart)，上界 \(vm.roundWindowMaxStart)）")
                }
            }
        }
    }

    /// `roundChipBar` 的文档注释曾写着「翻到的新窗口首轮自动成为新的聚焦轮次」——
    /// 那正是本次改动**删掉**的行为。注释与代码不符比没有注释更害人。
    func testRoundChipBarDocCommentDoesNotClaimPagingChangesFocus() throws {
        let src = try sourceFile("FixturesView.swift")
        let doc = try XCTUnwrap(
            qaSlice(src, from: "/// 「本轮」模式下的横向轮次切换", to: "private func roundChipBar"),
            "找不到 roundChipBar 的文档注释"
        )
        for stale in ["自动成为新的聚焦轮次", "翻到的新窗口首轮", "自动成为新的"] {
            XCTAssertEqual(count(of: stale, in: doc), 0,
                           "roundChipBar 的文档注释仍在描述已被删除的「翻页即改焦点」行为：" + stale)
        }
    }

    // MARK: - QA 独立复审：今日页两处改动（每列 4 场 / 直播分钟数）

    /// `formatLiveClock` 全分支表驱动覆盖（纯函数，直接单测）。
    func testFormatLiveClockCoversAllBranches() {
        let cases: [(elapsed: Int, halftime: Bool, expected: String)] = [
            // 上半场（≤45）：直接用实际分钟
            (0, false, "0'"), (1, false, "1'"), (19, false, "19'"),
            (44, false, "44'"), (45, false, "45'"),
            // 中场休息区间 46–60（状态还没翻成 HALFTIME）→ 钳到 45'
            (46, false, "45'"), (50, false, "45'"), (60, false, "45'"),
            // 下半场 61–105：扣掉中场的 15 分钟
            (61, false, "46'"), (75, false, "60'"), (90, false, "75'"), (105, false, "90'"),
            // 补时 / 超长 → 钳到 90+'
            (106, false, "90+'"), (200, false, "90+'"),
            // 中场休息：无论已过多少分钟都固定 45'
            (0, true, "45'"), (45, true, "45'"), (46, true, "45'"),
            (80, true, "45'"), (200, true, "45'"),
        ]
        for c in cases {
            XCTAssertEqual(
                FeaturedMatchCard.formatLiveClock(elapsed: c.elapsed, isHalftime: c.halftime),
                c.expected,
                "elapsed=\(c.elapsed) isHalftime=\(c.halftime)"
            )
        }
    }

    /// 分段边界的 off-by-one：每一对相邻输入都必须落在正确的段里。
    func testFormatLiveClockSegmentBoundariesAreExact() {
        let boundaries: [(elapsed: Int, expected: String, note: String)] = [
            (45,  "45'",  "上半场末"),
            (46,  "45'",  "进入中场区间 → 钳位"),
            (60,  "45'",  "中场区间末"),
            (61,  "46'",  "下半场开始 → 扣 15"),
            (105, "90'",  "下半场末"),
            (106, "90+'", "进入补时 → 钳位"),
        ]
        for b in boundaries {
            XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: b.elapsed, isHalftime: false),
                           b.expected, "边界 \(b.elapsed)（\(b.note)）")
        }
    }

    /// 时钟偏差 / 状态提前置 IN_PLAY 时，已踢分钟数不得为负。
    /// `elapsedMinutes` 现已改为接收 `now` 的**纯函数**（可真正单测，见 `testElapsedMinutesPureFunction`），
    /// 这里守住声明本身的结构契约，确保它不会退化成「内部偷读 Date()」。
    func testElapsedMinutesClampsFutureKickoffToZero() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "找不到 elapsedMinutes"
        )
        XCTAssertTrue(decl.contains("max(0,"),
                      "elapsedMinutes 必须把负值夹到 0（时钟偏差时不能出负数）")
        XCTAssertTrue(decl.contains("guard let kickoff else { return nil }") ||
                      decl.contains("guard let kickoff else {return nil}"),
                      "拿不到开球时间必须返回 nil，供 statusLine 回退")
        XCTAssertTrue(decl.contains("floor("), "分钟数应向下取整")
    }

    /// 开球时间解析失败时，`statusLine` 的 live 分支要回退到「进行中」文案，不能崩或显示空串。
    func testStatusLineFallsBackToLiveTextWhenKickoffMissing() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "private func statusLine", to: "private func statusBadge"),
            "找不到 statusLine"
        )
        XCTAssertTrue(fn.contains("guard let elapsed = Self.elapsedMinutes(kickoff: kickoff, now: now) else { return UIString.live.text(lang) }"),
                      "拿不到已踢分钟数时，live 分支必须回退到「进行中」文案")
        XCTAssertTrue(fn.contains("Self.formatLiveClock(elapsed: elapsed"),
                      "live 分支应调用纯函数 formatLiveClock")
        XCTAssertTrue(fn.contains("isHalftime: match.status == \"HALFTIME\""),
                      "中场状态要传给 formatLiveClock")
        XCTAssertFalse(fn.contains("formatLiveClock(elapsed: elapsedMinutes!"),
                      "不得对 elapsedMinutes 强制解包")
    }

    /// 非 live 分支（已结束 / 未开赛）不能被这次改动误伤。
    func testStatusLineNonLiveBranchesUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "private func statusLine", to: "private func statusBadge"),
            "找不到 statusLine"
        )
        XCTAssertTrue(fn.contains("if TodayFilter.isFinished(match) { return UIString.statusFinished.text(lang) }"),
                      "已结束仍应返回「已结束」")
        XCTAssertTrue(fn.contains("guard let kickoff else { return UIString.tbd.text(lang) }"),
                      "未开赛且无开球时间仍应回退「待定」")
        XCTAssertTrue(fn.contains("df.dateFormat = lang == .english ? \"MMM d\" : \"M月d日\""),
                      "未开赛仍有开球时间时应返回日期")
        // 顺序：live → finished → upcoming，live 判断必须在最前
        guard let live = fn.range(of: "TodayFilter.isLive(match, now: now)"),
              let finished = fn.range(of: "TodayFilter.isFinished(match)") else {
            return XCTFail("statusLine 缺少状态分支")
        }
        XCTAssertLessThan(live.lowerBound, finished.lowerBound, "live 分支必须在最前面")
    }

    // MARK: - 实时分钟数：纯函数 + TimelineView 解耦（修复「分钟数冻结」）

    /// `elapsedMinutes(kickoff:now:)` 全分支：把 `now` 显式传入后，时间 → 分钟数完全可单测
    /// （旧实现偷偷读 `Date()`，只能靠源码扫描）。
    func testElapsedMinutesPureFunction() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func mins(_ seconds: TimeInterval) throws -> Int {
            try XCTUnwrap(FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                           now: kickoff.addingTimeInterval(seconds)),
                          "elapsedMinutes 不应为 nil")
        }

        XCTAssertNil(FeaturedMatchCard.elapsedMinutes(kickoff: nil, now: kickoff),
                     "拿不到开球时间 → nil")

        XCTAssertEqual(try mins(0), 0, "恰好开球 → 0'")
        XCTAssertEqual(try mins(-30), 0, "now 早于 kickoff → clamp 到 0，不得为负")
        XCTAssertEqual(try mins(-3600), 0, "时钟偏差 1 小时 → 仍 clamp 到 0")
        XCTAssertEqual(try mins(59.9), 0, "59.9s 尚未跨分钟 → 0'")
        XCTAssertEqual(try mins(60.0), 1, "60.0s 正好跨分钟 → 1'")
        XCTAssertEqual(try mins(60.5), 1, "60.5s 仍取下界 → 1'")
        XCTAssertEqual(try mins(16 * 60), 16, "题目场景：16 分钟 → 16'")
        XCTAssertEqual(try mins(6000), 100, "长时差（100 分钟）→ 100'")
    }

    /// 「时间 → 显示文本」整条链路纯函数化：`elapsedMinutes(now)` 组合 `formatLiveClock` 即可断言文本。
    func testLiveMinuteTextChainIsPure() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func text(atSeconds seconds: TimeInterval, isHalftime: Bool = false) throws -> String {
            let elapsed = try XCTUnwrap(
                FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                 now: kickoff.addingTimeInterval(seconds)))
            return FeaturedMatchCard.formatLiveClock(elapsed: elapsed, isHalftime: isHalftime)
        }
        XCTAssertEqual(try text(atSeconds: 4 * 60), "4'")
        XCTAssertEqual(try text(atSeconds: 16 * 60), "16'", "用户报的卡住场景")
        XCTAssertEqual(try text(atSeconds: 0), "0'")
        XCTAssertEqual(try text(atSeconds: 50 * 60, isHalftime: true), "45'", "中场固定 45'")
    }

    /// 实时分钟数必须挂在 `TimelineView(.periodic(by: 1))` 上（独立于数据刷新的重绘源），
    /// 否则 `match` 未变时 SwiftUI 跳过本卡 body，分钟数冻结。
    func testFeaturedCardLiveMinuteWrappedInTimelineView() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "找不到 FeaturedMatchCard")
        XCTAssertEqual(count(of: "TimelineView(", in: card), 1,
                       "实时分钟数应且只应有一个 TimelineView")
        XCTAssertTrue(card.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "TimelineView 必须是 1 秒周期，才能跨分钟刷新")

        // TimelineView 只包住那一个 Text（在 centerBlock 的实时分支里），不包整张卡
        let center = try XCTUnwrap(qaSlice(card, from: "private func centerBlock",
                                           to: "private func scoreRow"),
                                   "找不到 centerBlock")
        XCTAssertTrue(center.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "TimelineView 必须只在 centerBlock 的实时分支里")
        XCTAssertTrue(center.contains("context.date"),
                      "TimelineView 闭包应把 context.date 作为 now 传入状态行")
        XCTAssertTrue(center.contains("Text(statusLine(lang: lang, now: Date()))"),
                      "非实时分支仍用 Date() 单次求值，不引入每秒重绘")
    }

    /// `elapsedMinutes` 不得再内部读 `Date()` —— 时间来源必须是显式 `now` 参数（本 bug 的根治点）。
    func testElapsedMinutesHasNoImplicitDateRead() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "找不到 elapsedMinutes"
        )
        XCTAssertFalse(decl.contains("Date()"),
                       "elapsedMinutes 不得内部读 Date() —— 必须由调用方（TimelineView）传入 now")
        XCTAssertTrue(decl.contains("now: Date"), "elapsedMinutes 应显式接收 now")
    }

    // MARK: - autoRefresh 持久化（UserDefaults）

    /// `autoRefresh` 应持久化到 UserDefaults（key `epl_autorefresh`）：写入后重读一致。
    @MainActor
    func testAutoRefreshPersistsToUserDefaults() throws {
        let key = "epl_autorefresh"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            // 还原，避免污染本机 App 默认值 / 其它测试
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        let state = AppState()
        XCTAssertFalse(state.autoRefresh, "未写入时默认应为 false")

        state.autoRefresh = true
        XCTAssertTrue(defaults.bool(forKey: key), "打开后应写回 UserDefaults")
        XCTAssertTrue(AppState().autoRefresh, "新实例应从 UserDefaults 恢复 true")

        state.autoRefresh = false
        XCTAssertFalse(defaults.bool(forKey: key), "关闭后应写回 false")
        XCTAssertFalse(AppState().autoRefresh, "新实例应恢复 false")
    }

    /// 未写入 key 时默认关闭（`UserDefaults.bool` 缺省即 false）。
    @MainActor
    func testAutoRefreshDefaultsToFalseWhenKeyAbsent() throws {
        let key = "epl_autorefresh"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertFalse(AppState().autoRefresh, "未写入 key 时默认 false")
    }

    /// 从 UserDefaults 恢复 `autoRefresh == true` 时，Toggle 的 `.onChange` 不会触发，
    /// 必须在根视图出现时补配置一次定时器，否则「UI 显示开启但 timer 没建」。
    func testRootViewConfiguresAutoRefreshOnAppear() throws {
        let code = codeOnly(try sourceFile("EPLViewerApp.swift"))
        XCTAssertTrue(code.contains(".task { appState.configureAutoRefresh() }"),
                      "ContentView 应在出现时调用 configureAutoRefresh()，以恢复持久化的开启状态")
    }

    /// `autoRefresh` 声明应从 UserDefaults 读（Bool 直接读）、`didSet` 写回，key 与既有命名一致。
    func testAutoRefreshDeclarationUsesUserDefaults() throws {
        let code = codeOnly(try sourceFile("EPLViewerApp.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "var autoRefresh: Bool", to: "var isLoading"),
            "找不到 autoRefresh 声明"
        )
        XCTAssertTrue(decl.contains("UserDefaults.standard.bool(forKey: \"epl_autorefresh\")"),
                      "autoRefresh 应从 UserDefaults 读取（Bool 直接读，不套 rawValue）")
        XCTAssertTrue(decl.contains("UserDefaults.standard.set(autoRefresh, forKey: \"epl_autorefresh\")"),
                      "didSet 应把 autoRefresh 写回 UserDefaults")
        XCTAssertFalse(decl.contains(".rawValue"), "Bool 读写不需要 rawValue")
    }

    // MARK: - 「比赛期间自动刷新」调度器（AutoRefreshScheduler 纯函数）

    /// 调度常量锁定（改动需同步契约表）。
    func testAutoRefreshSchedulerConstants() throws {
        XCTAssertEqual(AutoRefreshScheduler.liveInterval, 60, "有比赛时 60s")
        XCTAssertEqual(AutoRefreshScheduler.kickoffLeadTime, 15 * 60, "开球前 15 分钟提前醒")
        XCTAssertEqual(AutoRefreshScheduler.maxIdleSleep, 6 * 60 * 60, "空闲最长休眠 6h")
        XCTAssertEqual(AutoRefreshScheduler.matchWindow, 3 * 60 * 60, "单场最大跨度 3h")
    }

    /// `refreshInterval` 决策表 —— 逐行覆盖（行为契约，唯一间隔入口）。
    func testRefreshIntervalDecisionTable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:00:00Z"))

        // 行 1：全局 autoRefresh=true → 始终 60（与 duringMatches / schedule 无关）
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "全局开 → 60s")
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "全局开 → 60s（与其它无关）")

        // 行 2：全局关 + 比赛期间关 → nil（不设定时器）
        XCTAssertNil(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: now.addingTimeInterval(600)), now: now),
            "两项都关 → 不设定时器")

        // 行 3：全局关 + 比赛期间开 + 有比赛进行中 → 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "有比赛进行中 → 60s")

        // 行 4：无比赛，下一场 +2h → 睡到开球前 15 分钟 = 2h - 15min = 6300s
        //   ⚠️ 团队需求表里此处写作 6900；但 6900 = 2h − 5min，与 kickoffLeadTime(=15min) 不自洽。
        //   按常量语义（开球前 15 分钟醒）应为 6300，本测试锁 6300。
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(2 * 3600)), now: now),
            2 * 3600 - 15 * 60, "睡到下一场开球前 15 分钟（6300s）")

        // 行 5：下一场 +10min（已进入开球前 15 分钟窗口）→ 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(10 * 60)), now: now),
            AutoRefreshScheduler.liveInterval, "已进入开球前窗口 → 60s")

        // 行 6：下一场 +3 天 → clamp 到 maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(3 * 24 * 3600)), now: now),
            AutoRefreshScheduler.maxIdleSleep, "太久远 → clamp 到 6h")

        // 行 7：无下一场 → maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.maxIdleSleep, "无赛程 → 6h 兜底")
    }

    /// 开球 30 分钟前、未结束 → 时间窗判定为进行中；无未来比赛 → nextKickoff = nil。
    func testScheduleDetectsLiveMatchByKickoffWindow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let live = makeMatchTeams(id: 1, home: 1, away: 2,
                                  kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY")
        let s = AutoRefreshScheduler.schedule(matches: [live], now: now)
        XCTAssertTrue(s.hasLiveMatch, "开球 30 分钟前、未结束 → 进行中")
        XCTAssertNil(s.nextKickoff, "没有晚于 now 的比赛")
    }

    /// 数据源状态还没翻（status 仍是 SCHEDULED），但 kickoff 已过且未超窗 → 仍算进行中
    /// （本项目有前科：FPL 开球后约 8 分钟状态/比分未更新）。
    func testScheduleKickoffWindowIgnoresStaleStatus() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:55:00Z", status: "SCHEDULED")
        XCTAssertTrue(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                      "刚开球、状态未翻 → 用时间窗判定为进行中")
    }

    /// 回归：延期 / 取消的比赛即使原开球时间落进时间窗，也不得触发 60s 直播轮询
    /// （否则一场延期的比赛会让调度器空转轮询整整 3 小时）。
    func testScheduleIgnoresPostponedAndCanceledMatches() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let postponed = makeMatchTeams(id: 1, home: 1, away: 2,
                                       kickoff: "2026-09-12T13:55:00Z", status: "POSTPONED")
        let canceled = makeMatchTeams(id: 2, home: 3, away: 4,
                                      kickoff: "2026-09-12T13:55:00Z", status: "CANCELED")
        let s = AutoRefreshScheduler.schedule(matches: [postponed, canceled], now: now)
        XCTAssertFalse(s.hasLiveMatch, "延期 / 取消不算比赛进行中")
    }

    /// 已结束且已超出 3h 时间窗 → 非进行中。
    func testScheduleFinishedOutsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T10:00:00Z", status: "FINISHED")
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "已结束且超窗口 → 非进行中")
    }

    /// ⚠️ 补真实覆盖缺口：已 FINISHED 且**开球仍在 3h 时间窗内** → 必须判为「非进行中」。
    /// 既有的 `testScheduleFinishedOutsideWindowIsNotLive` 用的是 4h 前开球（本就超出窗口），
    /// 因此 `!TodayFilter.isFinished(m)` 这个条件**曾经实际没有被任何用例覆盖**（删掉它也全绿：
    /// 独立 QA 的变异测试 N1 已证实）。本用例专门堵这个洞。
    func testScheduleFinishedInsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:00:00Z", status: "FINISHED") // 1h 前开球，仍在 3h 窗内
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "已结束的比赛即使仍落在时间窗内，也必须判为非进行中")
    }

    /// 结构性守卫：定时器 repeats、视图回报去抖、两处上报点齐全。
    /// （这三条此前均无用例把守 —— 独立 QA 变异 N4 / N6 / N7 删掉后测试仍全绿。）
    func testLiveScheduleWiringGuards() throws {
        let app = codeOnly(try sourceFile("EPLViewerApp.swift"))

        // N4：定时器必须 repeats —— 「睡到开球前」是先睡一个长间隔、再靠 tick 重算收尾，
        //     改成一次性的话只会醒一次，之后再也无人重建它。
        let cfg = try XCTUnwrap(
            qaSlice(app, from: "func configureAutoRefresh()", to: "private func refreshTick"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(cfg.contains("repeats: true"),
                      "定时器必须 repeats:true；改成一次性会导致长睡之后无人再建定时器")

        // N6：去抖 + 记下最新赛程（后者是 refreshTick 能重算 schedule 的前提）
        XCTAssertTrue(app.contains("guard s != liveSchedule else { return }"),
                      "reportLiveSchedule 必须保留去抖，否则每次视图回报都会重建 timer")
        XCTAssertTrue(app.contains("lastKnownMatches = matches"),
                      "reportLiveSchedule 必须记下最新赛程，供 refreshTick 按最新 now 重算 schedule")

        // N7：两个加载赛程的页面都必须上报（漏一个就可能在停在该页时睡过比赛）
        XCTAssertTrue(codeOnly(try sourceFile("TodayView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "TodayView 必须回报赛程")
        XCTAssertTrue(codeOnly(try sourceFile("FixturesView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "FixturesView 必须回报赛程")
    }

    /// 未来比赛不算进行中；`nextKickoff` 取最早的未来开球。
    func testScheduleFutureMatchNotLiveAndReportsNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T16:00:00Z", status: "SCHEDULED"),
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T15:00:00Z", status: "SCHEDULED"), // 最早
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertFalse(s.hasLiveMatch, "未来的比赛不算进行中")
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T15:00:00Z")),
                       "nextKickoff 应是最早的未来开球")
    }

    /// 同时存在进行中与未来比赛 → 两者都要报出来。
    func testScheduleReportsBothLiveAndNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY"),  // 进行中
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T17:00:00Z", status: "SCHEDULED"), // 未来
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertTrue(s.hasLiveMatch)
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T17:00:00Z")))
    }

    /// 空数组 / `utcDate` 不可解析 → 不崩，返回 false/nil。
    func testScheduleEmptyAndUnparseable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let empty = AutoRefreshScheduler.schedule(matches: [], now: now)
        XCTAssertFalse(empty.hasLiveMatch)
        XCTAssertNil(empty.nextKickoff)

        let bad = makeMatchTeams(id: 9, home: 1, away: 2, kickoff: "not-a-date", status: "SCHEDULED")
        let s = AutoRefreshScheduler.schedule(matches: [bad], now: now)
        XCTAssertFalse(s.hasLiveMatch, "不可解析的 utcDate 应被跳过")
        XCTAssertNil(s.nextKickoff)
    }

    /// `configureAutoRefresh` 必须走 `refreshInterval` 决策，不得再硬编码 60s。
    func testConfigureAutoRefreshUsesSchedulerNotHardcoded60() throws {
        let code = codeOnly(try sourceFile("EPLViewerApp.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "func reportLiveSchedule"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(fn.contains("AutoRefreshScheduler.refreshInterval("),
                      "间隔决策必须走 refreshInterval，不得硬编码")
        XCTAssertFalse(fn.contains("withTimeInterval: 60"),
                       "不应再硬编码 60s 间隔")
        XCTAssertTrue(fn.contains("withTimeInterval: interval"),
                      "应把 refreshInterval 的结果传给定时器")
    }

    /// 🚨 守护栏：定时器唤醒后必须**重算间隔**，否则会睡过整场比赛。
    /// 场景：睡到「开球前 15 分钟」醒来时，`schedule` 内容与睡眠前完全相同（`hasLiveMatch` 仍 false、
    /// `nextKickoff` 仍是同一场）→ `reportLiveSchedule` 会早退不重建；只有 tick 自己重算才能把
    /// 间隔切到 60s。删掉 `refreshTick` 里的 `configureAutoRefresh()` 本测试必须变红。
    func testRefreshTickRecomputesIntervalOnEveryWake() throws {
        let code = codeOnly(try sourceFile("EPLViewerApp.swift"))

        // 1) refreshTick 体内必须「先刷新、再重算间隔」
        let tick = try XCTUnwrap(
            qaSlice(code, from: "private func refreshTick", to: "func reportLiveSchedule"),
            "找不到 refreshTick"
        )
        XCTAssertTrue(tick.contains("await refresh(scoresOnly: true)"),
                      "refreshTick 必须先刷新数据，且比赛期间轮询只失效赛程（scoresOnly），不清整份 bootstrap")
        XCTAssertTrue(tick.contains("configureAutoRefresh()"),
                      "refreshTick 必须重算间隔（configureAutoRefresh），否则会睡过整场比赛")
        // ⚠️ 关键：必须用**最新 now 重新算 schedule**，不能只拿存下来的 liveSchedule 算间隔。
        // `hasLiveMatch` 只是存储 Bool、不会自己翻转；只有在 tick 里按开球时间窗重算，
        // 时间越过比赛结束后才会变成 false。否则停在不上报赛程的 tab（积分榜/设置/球员榜/伤停）
        // 时 liveSchedule 被冻结 → 比赛全结束仍永久 60s 轮询。
        XCTAssertTrue(tick.contains("AutoRefreshScheduler.schedule("),
                      "refreshTick 必须用最新 now 重算 schedule，否则停在不上报的 tab 时会永久 60s 轮询")

        // 2) 定时器 fire 闭包必须指向 refreshTick()，而不是只调 refresh()
        let cfg = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "private func refreshTick"),
            "找不到 configureAutoRefresh"
        )
        XCTAssertTrue(cfg.contains("await self?.refreshTick()"),
                      "定时器 fire 闭包应调用 refreshTick()，在每次唤醒后重算间隔")
        XCTAssertFalse(cfg.contains("await self?.refresh()"),
                       "fire 闭包不应再直接调 refresh()（应调 refreshTick()）")

        // 3) 不得残留「绝不在 tick 里重新 configure」的反向说明（防后人照抄改回去）
        let raw = try sourceFile("EPLViewerApp.swift")
        XCTAssertFalse(raw.contains("绝不在 tick 里重新 configure"),
                       "错误理由的注释必须删除，避免后人当契约改回去")
    }

    // MARK: - 「比赛期间自动刷新」持久化 + 文案

    @MainActor
    func testAutoRefreshDuringMatchesPersistsToUserDefaults() throws {
        let key = "epl_autorefresh_matches"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        let state = AppState()
        XCTAssertTrue(state.autoRefreshDuringMatches, "未写入（新装 / 从未动过这项）→ 默认开启")

        state.autoRefreshDuringMatches = true
        XCTAssertTrue(defaults.bool(forKey: key), "打开后应写回 UserDefaults")
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "新实例应从 UserDefaults 恢复 true")

        state.autoRefreshDuringMatches = false
        XCTAssertFalse(defaults.bool(forKey: key), "关闭后应写回 false")
        // ⚠️ 关键回归：用户显式关掉后，新实例必须仍是 false，不能被「默认开」顶回 true。
        // 这条守的是三态判定（object(forKey:) == nil）—— 若退化成 bool(forKey:)，
        // 默认值 true 就没法实现，或者关掉后一重启又变开。
        XCTAssertFalse(AppState().autoRefreshDuringMatches,
                       "用户显式关掉后，新实例必须仍是 false（不能被默认值顶回 true）")
    }

    /// 缺 key（新装 / 从未动过这项设置）→ **默认 true**（用户要求「装好就勾上」）。
    @MainActor
    func testAutoRefreshDuringMatchesDefaultsTrueWhenKeyAbsent() throws {
        let key = "epl_autorefresh_matches"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "缺 key → 默认开启")
    }

    /// 文案必须中英双语，禁止写死中文。
    func testAutoRefreshDuringMatchesStringsBilingual() throws {
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.chinese), "比赛期间自动刷新")
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.english), "Auto-refresh during matches")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.chinese), "已开启全局自动刷新，此项无需设置")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.english),
                       "Global auto-refresh is on; this setting is not needed")
    }

    /// 全局自动刷新开启时，「比赛期间自动刷新」Toggle 应被 disable，并显示脚注说明。
    func testSettingsDisablesDuringMatchesToggleWhenGlobalOn() throws {
        let code = codeOnly(try sourceFile("EPLViewerApp.swift"))
        XCTAssertTrue(code.contains(".disabled(appState.autoRefresh)"),
                      "全局自动刷新开启时，「比赛期间自动刷新」应被 disable")
        XCTAssertTrue(code.contains("UIString.autoRefreshDuringMatchesHint.text(appState.language)"),
                      "应显示「无需设置」的脚注")
    }

    /// 每列最多 4 场：确认只作用于两列，且「查看全部 →」入口完好。
    func testColumnCardCapsAtFourAndViewAllIntact() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        // columnCard 只有两处调用（左右两列），没有别的调用点被顺带截断
        XCTAssertEqual(count(of: "columnCard(", in: code), 3,
                       "期望 columnCard 定义 1 处 + 调用 2 处；出现新的调用点需确认是否该被截断")
        XCTAssertEqual(count(of: "ForEach(Array(matches.prefix(4)))", in: code), 1,
                       "截断只应发生在 columnCard 内部一处")

        // 「查看全部 →」仍在，且仍跳赛程页 —— 被截断的比赛要有去处
        XCTAssertEqual(count(of: "UIString.viewAll", in: code), 1,
                       "列卡片右上角的「查看全部 →」不能丢")
        XCTAssertTrue(code.contains("appState.selected = .fixtures"),
                      "「查看全部 →」必须仍跳转到赛程页")

        // 截断不应影响 ViewModel 数据本身（列里超过 4 场时数据仍在，只是不渲染）
        XCTAssertTrue(code.contains("ForEach(Array(matches.prefix(4))) { match in"),
                      "应保留 ForEach 的 match 绑定")
    }

    /// 卡片强制 `.dark` 后 `.primary` 是纯白（对比度过 bar）。
    /// 但 `.secondary` 在 macOS 深色下是**半透明**的 secondaryLabelColor（≈60% 白），
    /// 会**跟着背景一起变暗**；写死的深紫红→亮粉渐变上实测仅 2.31~2.51:1（< 3.0 大字号下限），肉眼发灰。
    /// 量化证明见 companion 测试 `testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient`（不透明白 ≥ bar）。
    /// 因此修法：推荐卡上的小字一律用不透明白 `.white`。
    /// 这里守住「FeaturedMatchCard 内不得再用 `.secondary`」—— 一旦有人回退成 `.secondary`，对比度会塌回发灰。
    func testFeaturedCardSecondaryTextMeetsReadabilityBar() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(
            qaSlice(code, from: "struct FeaturedMatchCard"),
            "找不到 FeaturedMatchCard 定义"
        )
        XCTAssertEqual(count(of: ".secondary", in: card), 0,
            "推荐卡（FeaturedMatchCard）上的小字必须改用不透明白 .white，不能用 .secondary —— " +
            "深紫红→亮粉渐变上 .secondary 对比度仅 2.31:1，达不到 3.0:1，肉眼发灰。")
    }

    /// 参照组：证明「不透明的白字」这个修法确实够用（给工程师一个明确的改法方向）。
    func testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient() throws {
        let src = try sourceFile("TodayView.swift")
        let block = try XCTUnwrap(qaSlice(src, from: "private let featuredCardGradient", to: "\n)"))
        let re = try NSRegularExpression(
            pattern: #"Color\(\s*red:\s*([\d.]+)\s*,\s*green:\s*([\d.]+)\s*,\s*blue:\s*([\d.]+)\s*\)"#
        )
        var stops: [(Double, Double, Double)] = []
        for m in re.matches(in: block, range: NSRange(location: 0, length: (block as NSString).length)) {
            guard let rr = Range(m.range(at: 1), in: block),
                  let gg = Range(m.range(at: 2), in: block),
                  let bb = Range(m.range(at: 3), in: block),
                  let r = Double(block[rr]), let g = Double(block[gg]), let b = Double(block[bb])
            else { continue }
            stops.append((r, g, b))
        }
        XCTAssertEqual(stops.count, 2)

        func luminance(_ c: (Double, Double, Double)) -> Double {
            func chan(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * chan(c.0) + 0.7152 * chan(c.1) + 0.0722 * chan(c.2)
        }
        let white: Double = 1.0
        for (i, s) in stops.enumerated() {
            let bg = (s.0 * 0.88, s.1 * 0.88, s.2 * 0.88)
            let lb = luminance(bg)
            let ratio = (max(white, lb) + 0.05) / (min(white, lb) + 0.05)
            XCTAssertGreaterThanOrEqual(ratio, 3.0,
                                        "不透明白字在端点 \(i) 的对比度应达标")
        }
    }
}

// MARK: - StandingsEnricher（主场/客场/形态本地聚合）

extension EPLViewerTests {
    /// 造一支球队（id/name 自由指定）
    fileprivate func makeTeam2(_ id: Int, _ name: String) -> Team {
        Team(id: id, name: name, shortName: name, crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// 造一场含主客两队 + 全场比分的已结束比赛
    fileprivate func makeFinishedMatch(id: Int, kickoff: String,
                                       home: Team, away: Team,
                                       homeGoals: Int, awayGoals: Int) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away,
              score: Score(fullTime: FullTime(home: homeGoals, away: awayGoals)))
    }

    /// 造一场已结束但没比分的（应被聚合器忽略）
    fileprivate func makeUnscoredMatch(id: Int, kickoff: String,
                                       home: Team, away: Team) -> Match {
        Match(id: id, matchday: 1, utcDate: kickoff, status: "FINISHED",
              stage: nil, homeTeam: home, awayTeam: away, score: nil)
    }

    /// venueStats 主场：team 100 主场比赛 3 场（2 胜 1 平 0 负，进 5 失 2，积 7 分）
    func testVenueStatsHomeCountsCorrectly() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 3, awayGoals: 1),  // 胜
            makeFinishedMatch(id: 2, kickoff: "2026-08-25T12:00:00Z",
                              home: a, away: c, homeGoals: 1, awayGoals: 1),  // 平
            makeFinishedMatch(id: 3, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 0),  // 胜
        ]
        let s = try! XCTUnwrap(StandingsEnricher.venueStats(for: 100, matches: matches, isHome: true))
        XCTAssertEqual(s.played, 3)
        XCTAssertEqual(s.won, 2)
        XCTAssertEqual(s.draw, 1)
        XCTAssertEqual(s.lost, 0)
        XCTAssertEqual(s.goalsFor, 5)
        XCTAssertEqual(s.goalsAgainst, 2)
        XCTAssertEqual(s.points, 7)
    }

    /// venueStats 客场：team 100 客场比赛 2 场（1 胜 1 负，进 3 失 3，积 3 分）
    /// 验证「从客队视角」统计能正确翻转主客。
    func testVenueStatsAwayFlipsHomeAway() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let c = makeTeam2(300, "Charlie")
        let matches = [
            // 客胜：Alpha 是 away 队，away 进球 2 > home 1
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 1, awayGoals: 2),
            // 客负：Alpha 是 away 队，away 进球 1 < home 2
            makeFinishedMatch(id: 2, kickoff: "2026-08-25T12:00:00Z",
                              home: c, away: a, homeGoals: 2, awayGoals: 1),
        ]
        let s = try! XCTUnwrap(StandingsEnricher.venueStats(for: 100, matches: matches, isHome: false))
        XCTAssertEqual(s.played, 2)
        XCTAssertEqual(s.won, 1)
        XCTAssertEqual(s.draw, 0)
        XCTAssertEqual(s.lost, 1)
        XCTAssertEqual(s.goalsFor, 3)     // 2 + 1
        XCTAssertEqual(s.goalsAgainst, 3) // 1 + 2
        XCTAssertEqual(s.points, 3)
    }

    /// venueStats：没比赛或没比分 → nil（区分"无数据"和"踢了但全输"）
    func testVenueStatsNoMatchesReturnsNil() {
        let a = makeTeam2(100, "Alpha")
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [], isHome: true),
                     "空 matches → nil")
        // SCHEDULED 的比赛应该被忽略
        let scheduled = Match(id: 9, matchday: 1, utcDate: "2026-08-22T12:00:00Z",
                              status: "SCHEDULED", stage: nil, homeTeam: a, awayTeam: a, score: nil)
        XCTAssertNil(StandingsEnricher.venueStats(for: 100, matches: [scheduled], isHome: true),
                     "未开赛的不应计入")
    }

    /// formString：team 100 最近 5 场按时间顺序 → "WWDLW"
    func testFormStringReturnsMostRecentFiveChronological() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        // 5 场：W W D L W（按时间从早到晚）—— Alpha 有时主有时客
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-01T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),  // W（主）
            makeFinishedMatch(id: 2, kickoff: "2026-08-08T12:00:00Z",
                              home: b, away: a, homeGoals: 0, awayGoals: 1),  // W（客）
            makeFinishedMatch(id: 3, kickoff: "2026-08-15T12:00:00Z",
                              home: a, away: b, homeGoals: 1, awayGoals: 1),  // D（主）
            makeFinishedMatch(id: 4, kickoff: "2026-08-22T12:00:00Z",
                              home: b, away: a, homeGoals: 3, awayGoals: 0),  // L（客）
            makeFinishedMatch(id: 5, kickoff: "2026-08-29T12:00:00Z",
                              home: a, away: b, homeGoals: 4, awayGoals: 2),  // W（主）
            // 第 6 场：比第 5 场更早，但假定 6 场只取最近 5，应被丢弃
            makeFinishedMatch(id: 0, kickoff: "2026-07-25T12:00:00Z",
                              home: a, away: b, homeGoals: 5, awayGoals: 0),  // 应被丢弃
        ]
        XCTAssertEqual(StandingsEnricher.formString(for: 100, matches: matches, last: 5),
                       "WWDLW")
    }

    /// formString：没有任何比赛 → nil
    func testFormStringNoMatchesReturnsNil() {
        let s = StandingsEnricher.formString(for: 100, matches: [], last: 5)
        XCTAssertNil(s)
    }

    /// enrich：rows 的 home/away 是 nil → 本地补全
    func testEnrichFillsNilHomeAwayFromLocalAggregate() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 1, won: 1, draw: 0, lost: 0,
            points: 3, goalsFor: 2, goalsAgainst: 0, goalDifference: 2,
            form: "W", status: nil,
            home: nil, away: nil
        )
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),
        ]
        let enriched = StandingsEnricher.enrich(rows: [row], with: matches)
        XCTAssertNotNil(enriched[0].home, "主场应被补全")
        XCTAssertEqual(enriched[0].home?.played, 1)
        XCTAssertEqual(enriched[0].home?.points, 3)
        XCTAssertNil(enriched[0].away, "客场无比赛仍为 nil")
    }

    /// enrich：rows 已有 home/away → 不覆盖（保留权威值）
    func testEnrichPreservesExistingHomeAway() {
        let a = makeTeam2(100, "Alpha")
        let b = makeTeam2(200, "Beta")
        let preexistingHome = VenueStats(played: 99, won: 99, draw: 0, lost: 0,
                                         goalsFor: 99, goalsAgainst: 0, points: 99)
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 0, won: 0, draw: 0, lost: 0,
            points: 0, goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
            form: nil, status: nil,
            home: preexistingHome, away: nil
        )
        let matches = [
            makeFinishedMatch(id: 1, kickoff: "2026-08-22T12:00:00Z",
                              home: a, away: b, homeGoals: 2, awayGoals: 0),
        ]
        let enriched = StandingsEnricher.enrich(rows: [row], with: matches)
        XCTAssertEqual(enriched[0].home?.played, 99,
                       "原有 home 不应被本地聚合覆盖")
        XCTAssertNil(enriched[0].away,
                     "无客场比赛时 away 应为 nil（不是全 0 VenueStats）")
    }

    /// enrich：空 rows / 空 matches 都安全
    func testEnrichSafeOnEmptyInputs() {
        let a = makeTeam2(100, "Alpha")
        let row = StandingRow(
            position: 1, team: a,
            playedGames: 0, won: 0, draw: 0, lost: 0,
            points: 0, goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
            form: nil, status: nil,
            home: nil, away: nil
        )
        XCTAssertTrue(StandingsEnricher.enrich(rows: [], with: []).isEmpty)
        XCTAssertEqual(StandingsEnricher.enrich(rows: [row], with: []).count, 1)
        XCTAssertNil(StandingsEnricher.enrich(rows: [row], with: []).first?.home)
    }

    /// StandingRow.with：只补 home/away 时，其它字段全部沿用
    func testStandingRowWithPreservesOtherFields() {
        let a = makeTeam2(100, "Alpha")
        let row = StandingRow(
            position: 5, team: a,
            playedGames: 3, won: 2, draw: 1, lost: 0,
            points: 7, goalsFor: 6, goalsAgainst: 2, goalDifference: 4,
            form: "WDW", status: "CHAMPIONS_LEAGUE",
            home: nil, away: nil
        )
        let newHome = VenueStats(played: 1, won: 1, draw: 0, lost: 0,
                                 goalsFor: 2, goalsAgainst: 0, points: 3)
        let updated = row.with(home: newHome)
        XCTAssertEqual(updated.position, 5, "其它字段不能丢")
        XCTAssertEqual(updated.points, 7)
        XCTAssertEqual(updated.form, "WDW")
        XCTAssertEqual(updated.status, "CHAMPIONS_LEAGUE")
        XCTAssertEqual(updated.home?.played, 1)
        XCTAssertNil(updated.away)
    }
}

// MARK: - 赛季标签 + 应用主标题占位符

extension EPLViewerTests {
    /// `SeasonStore.seasonLabel` 把 currentSeason（"2026"）格式化为跨年字符串 "2026-2027"。
    /// 验证跨年赛季（如英超 8 月开打、次年 5 月收官）显示完整赛季名。
    func testSeasonLabelFormatsAsStartPlusEndYear() {
        XCTAssertEqual(SeasonStore.seasonLabel, "\(SeasonStore.currentSeason)-\(Int(SeasonStore.currentSeason)! + 1)",
                       "seasonLabel 应是 startYear-(startYear+1)")
        // 已知 currentSeason = "2026"，期望 "2026-2027"
        XCTAssertEqual(SeasonStore.seasonLabel, "2026-2027",
                       "当前赛季的标签应为 2026-2027")
    }

    /// `UIString.appTitle` 中英文各带 1 个 `%@` 占位符（用于填赛季标签）。
    /// 防止后续误删/多加占位符导致渲染错位。
    func testAppTitleHasOnePlaceholderInBothLanguages() {
        let placeholders = { (s: String) -> Int in
            // `%@` 在字符串里以"%"开头；数 1 个
            var count = 0
            var idx = s.startIndex
            while let r = s.range(of: "%@", range: idx..<s.endIndex) {
                count += 1
                idx = r.upperBound
            }
            return count
        }
        XCTAssertEqual(placeholders(UIString.appTitle.zh), 1, "中文占位符应恰好 1 个")
        XCTAssertEqual(placeholders(UIString.appTitle.en), 1, "英文占位符应恰好 1 个")
    }

    /// 整体渲染示例：中文 → "2026-2027 英超联赛"，英文 → "EPL 2026-2027"
    func testAppTitleRendersWithSeasonLabel() {
        let zh = String(format: UIString.appTitle.text(.chinese), SeasonStore.seasonLabel)
        let en = String(format: UIString.appTitle.text(.english), SeasonStore.seasonLabel)
        XCTAssertEqual(zh, "2026-2027 英超联赛")
        XCTAssertEqual(en, "EPL 2026-2027")
    }
}

// MARK: - StandingsView 布局护栏

extension EPLViewerTests {
    /// StandingsView 的「表格卡片」必须用 RoundedRectangle 圆角，不能用裸背景。
    /// 防止以后有人把圆角去掉回退到普通 List 视觉。
    func testStandingsCardUsesRoundedRectangleBackground() throws {
        let src = try sourceFile("StandingsView.swift")
        // 剥掉 // 注释再匹配
        let stripped = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(stripped.contains("RoundedRectangle"),
                      "表格卡片必须用 RoundedRectangle 圆角背景")
        XCTAssertTrue(stripped.contains("clipShape(RoundedRectangle"),
                      "卡片必须 clipShape 圆角（防止行内容溢出圆角）")
    }

    /// 改动后的 StandingsView 不再用 List（用 ScrollView + VStack 自己管理行），
    /// 且没有横向 ScrollView 嵌套在纵向 ScrollView（项目红线）。
    func testStandingsViewAvoidsLayoutDeadlockTraps() throws {
        let src = try sourceFile("StandingsView.swift")
        let stripped = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(stripped.contains("LazyVStack"),
                       "积分榜禁止 LazyVStack（嵌套 lazy 容器会让尺寸协商死循环）")
        XCTAssertFalse(stripped.contains("maximum: .infinity"),
                       "GridItem 的 maximum 必须是具体数值，不能是 .infinity")
    }
}

// MARK: - 4 个 tab 卡片高度对齐护栏

extension EPLViewerTests {
    /// 4 个 tab 的卡片总高度应一致（总/主/客 ≈ 状态）。
    /// detailedRow 用 `.body` 文字 + padding 6 = 约 23pt；formRow 用 FormChipsView。
    /// FormChipsView 胶囊 18×18 + padding 6 = 24pt，与 detailed 差 1pt，4 个 tab 卡片高度肉眼一致。
    /// 护栏：FormChipsView 胶囊 width/height 都必须 ≤ 20（防止以后改大后让状态 tab 卡片高出 100pt+）。
    func testFormChipsKeepsHeightAlignedWithOtherTabs() throws {
        let src = try sourceFile("StandingsView.swift")
        // 扫所有 `frame(width: N, height: M)` 双参帧（单参 width/height 的是列表布局，不影响行高）
        let pattern = #"frame\(\s*width:\s*(\d+)\s*,\s*height:\s*(\d+)\s*\)"#
        let re = try NSRegularExpression(pattern: pattern)
        let matches = re.matches(in: src, range: NSRange(src.startIndex..., in: src))
        XCTAssertFalse(matches.isEmpty, "StandingsView 至少应有一个 frame(width:height:) 双参帧")
        var chipFrames: [(width: Int, height: Int, line: Int)] = []
        for m in matches {
            let w = Int(src[Range(m.range(at: 1), in: src)!]) ?? 0
            let h = Int(src[Range(m.range(at: 2), in: src)!]) ?? 0
            // 行号 = 数字 r.location 之前的 \n 数量 + 1
            let line = src[..<Range(m.range, in: src)!.lowerBound]
                .reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
            chipFrames.append((w, h, line))
        }
        for f in chipFrames {
            XCTAssertLessThanOrEqual(f.width, 20,
                "frame(width:\(f.width), height:\(f.height)) at line \(f.line)：宽度过大会让状态 tab 卡片比总/主/客高一截")
            XCTAssertLessThanOrEqual(f.height, 20,
                "frame(width:\(f.width), height:\(f.height)) at line \(f.line)：高度过大会让状态 tab 卡片比总/主/客高一截")
        }
    }
}

// MARK: - 所有 detail view 必须显式设 navigationTitle

extension EPLViewerTests {
    /// macOS 26 的 NavigationSplitView 在 detail column 没有自己的 navigationTitle 时，
    /// 会"借"sidebar column 的标题显示在 detail 顶部。StandingsView 之前漏设，
    /// 导致 detail 顶部漏出旧的 "EPL Viewer"（即使 sidebar 已改成 "2026-2027 英超联赛"）。
    /// 护栏：所有 detail 视图（Today/Standings/Fixtures/Leaders/Injuries/Settings）
    /// 必须**显式**设 navigationTitle（哪怕是空串清空），绝不依赖继承。
    func testAllDetailViewsSetNavigationTitleExplicitly() throws {
        let detailFiles = ["TodayView.swift", "StandingsView.swift", "FixturesView.swift",
                           "LeadersAndInjuriesViews.swift"]
        for name in detailFiles {
            let src = try sourceFile(name)
            // 剥掉 // 注释再匹配（注释里写"显式 navigationTitle"的解释不算真设了）
            let stripped = src.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertTrue(stripped.contains(".navigationTitle("),
                          "\(name) 必须显式 .navigationTitle(...) —— 否则 macOS NavigationSplitView 会借 sidebar 标题，detail 顶部会显示错误的旧标题")
        }
    }
}

// MARK: - 详情页标题契约

extension EPLViewerTests {
    /// 积分榜详情页的 navigationTitle 必须用 `appTitle`（"xxxx-xxxx 英超联赛"），
    /// 而不是用 "积分榜" / "Standings" 等页面名。
    /// 理由：全 app 顶部统一显示「这是哪个赛季的英超」，具体在哪一页由侧边栏选中项表达。
    func testStandingsDetailTitleUsesAppTitle() throws {
        let src = try sourceFile("StandingsView.swift")
        // 必须出现 `String(format: UIString.appTitle.text(...), SeasonStore.seasonLabel)` 模式
        XCTAssertTrue(src.contains("UIString.appTitle"),
                      "积分榜详情页 navigationTitle 必须用 UIString.appTitle（xxxx-xxxx 英超联赛）")
        XCTAssertTrue(src.contains("SeasonStore.seasonLabel"),
                      "积分榜详情页 navigationTitle 必须用 SeasonStore.seasonLabel 填赛季标签")
        // 不能再用 standings 文案
        XCTAssertFalse(src.contains(".navigationTitle(UIString.standings.text"),
                       "积分榜详情页 navigationTitle 不应再是 UIString.standings（\"积分榜\"）")
    }
}

// MARK: - 窗口尺寸契约

extension EPLViewerTests {
    /// 窗口最小高度契约：必须落在 [400, 700] 区间。
    /// - 下限 400：窗口不能缩到比"积分榜 2 行"还矮（实际是 [30 tab + 28 表头 + 46 两行 + 16 卡内 + 26 卡外 + 52 toolbar + 28 title bar] ≈ 226pt 留余量）。
    /// - 上限 700：之前涨到 680 时用户嫌太矮（"挤得看不到第 20 队"），改到 240 嫌太极端，最终定 660。
    /// 防止以后随便改这个值破坏两端体验。
    func testWindowMinHeightIsWithinReasonableRange() throws {
        let src = try sourceFile("EPLViewerApp.swift")
        let pattern = #"minHeight:\s*(\d+)"#
        let re = try NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: src, range: NSRange(src.startIndex..., in: src)) else {
            XCTFail("EPLViewerApp.swift 必须有 minHeight: 限制")
            return
        }
        let value = Int(src[Range(m.range(at: 1), in: src)!]) ?? 0
        XCTAssertGreaterThanOrEqual(value, 400,
            "窗口 minHeight 不能小于 400（当前 \(value)），否则窗口会小到比『2 行积分榜』还挤、影响可用性")
        XCTAssertLessThanOrEqual(value, 700,
            "窗口 minHeight 不能超过 700（当前 \(value)），否则窗口最小高度把积分榜卡片撑得过大、没必要")
    }

    // MARK: - 推荐卡「进行中分钟数」记法

    /// 守卫 `FeaturedMatchCard.formatLiveClock` 的分支逻辑。
    /// 这是用户明确要的「进行中 → 显示已踢分钟数（如 19'）」的渲染契约，
    /// 工程师特意把它抽成不依赖 `Date()` 的纯函数，便于单测覆盖每一个分支。
    /// 分支规则见 TodayView.swift 中 `formatLiveClock` 的注释。
    func testFormatLiveClockBranches() throws {
        // 中场休息：固定 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 50, isHalftime: true), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: true), "45'")

        // 上半场（≤45）：实际分钟
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: false), "0'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 19, isHalftime: false), "19'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 45, isHalftime: false), "45'")

        // 中场休息区间（46–60，状态还没翻成 HALFTIME）：钳到 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 46, isHalftime: false), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 60, isHalftime: false), "45'")

        // 下半场（61–105）：实际分钟扣掉中场 15 分钟（61→46'，90→75'，105→90'）
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 61, isHalftime: false), "46'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 90, isHalftime: false), "75'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 105, isHalftime: false), "90'")

        // 补时 / 超长（>105）：钳到 90+'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 106, isHalftime: false), "90+'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 120, isHalftime: false), "90+'")
    }

    // MARK: - 推荐卡中间大槽内容（centerContent）

    /// 造一支只靠 id 区分的球队（`makeMatch series` 不够用时自建）
    private func ccTeam(_ id: Int) -> Team {
        Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// 造一场比赛；`homeScore` / `awayScore` 均为 nil 表示「无比分」（`score = nil`）。
    /// 注意 `makeMatch` / `makeMatchTeams` 的 score 恒为 nil，测比分相关分支需要这个辅助。
    private func ccMatch(id: Int = 1,
                         kickoff: String? = "2026-09-12T14:00:00Z",
                         status: String?,
                         home: Int = 1, away: Int = 2,
                         homeScore: Int? = nil, awayScore: Int? = nil) -> Match {
        let score: Score? = (homeScore != nil || awayScore != nil)
            ? Score(fullTime: FullTime(home: homeScore, away: awayScore))
            : nil
        return Match(id: id, matchday: 4, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: ccTeam(home), awayTeam: ccTeam(away), score: score)
    }

    /// 核心回归：**进行中但无比分** → `.pendingLiveScore`（改动前会错误地退化成 `.kickoff`，
    /// 于是卡片上方显示开球时间、下方显示已踢分钟数，自相矛盾）。
    func testCenterContentLiveWithoutScoreIsPendingLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay), .pendingLiveScore,
                       "IN_PLAY 但数据源还没给比分时，必须按 0-0 展示，不能显示开球时间")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime), .pendingLiveScore,
                       "HALFTIME 但无比分时同样按 0-0 展示")
    }

    /// 进行中**且有比分** → `.score`，且 `isLive == true`（判定顺序里「有比分」优先于 live）。
    func testCenterContentLiveWithScoreReturnsLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: 1, awayScore: 0)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay),
                       .score(home: 1, away: 0, isLive: true),
                       "进行中且有比分时应显示真实比分（绝不能退化成 0-0）")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: 2, awayScore: 1)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime),
                       .score(home: 2, away: 1, isLive: true),
                       "中场休息状态也算 live，应显示真实比分")
    }

    /// 未开赛（`SCHEDULED`）+ 有开球时间 → `.kickoff`（行为与改动前一致）。
    func testCenterContentScheduledReturnsKickoff() throws {
        let m = ccMatch(kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED")
        let expected = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m), .kickoff(expected),
                       "未开赛且有开球时间时应显示开球时间")
    }

    /// 已结束 + 有比分 → `.score`，且 `isLive == false`。
    func testCenterContentFinishedWithScoreReturnsNonLiveScore() throws {
        let m = ccMatch(status: "FINISHED", homeScore: 2, awayScore: 2)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m),
                       .score(home: 2, away: 2, isLive: false),
                       "已结束应显示最终比分，且不带 live 语义")
    }

    /// 非 live、无开球时间、无比分 → `.tbd`。
    func testCenterContentNonLiveNoKickoffNoScoreReturnsTbd() throws {
        let scheduled = ccMatch(kickoff: nil, status: "SCHEDULED")
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: scheduled), .tbd,
                       "拿不到比分也拿不到开球时间 → 待定")

        let noStatus = ccMatch(kickoff: nil, status: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: noStatus), .tbd,
                       "状态缺失且无开球时间 / 比分 → 待定")
    }

    // MARK: - 「未开赛 → 进行中」过渡对齐（显示侧与调度器同一套开球窗口径）

    /// 核心回归：开球后、但数据源 `status` 还没翻（FPL 滞后约 8 分钟）时，
    /// 一场 `SCHEDULED` 且已落在「开球 → 开球+3h」窗内的比赛，显示侧应把它当**进行中**
    /// 处理（卡片显示 0 - 0 + ⚽），而不是退化成「未开赛 / 开球时间」。
    /// 这正是「调度器已在轮询、UI 却还显示未开赛」那个缺口的修复点。
    func testCenterContentScheduledButInKickoffWindowIsPendingLiveScore() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))
        // 开球后 2 分钟、比分尚未出版（数据源滞后）
        let now = kickoff.addingTimeInterval(2 * 60)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m, now: now), .pendingLiveScore,
                       "开球窗内的 SCHEDULED（无比分）应显示 0-0 进行中，而非开球时间")
    }

    /// `TodayFilter.isLive(_:now:)` 双信号等价性：状态 OR 开球窗，与 `AutoRefreshScheduler` 一致。
    func testTodayFilterIsLiveWindowAlignedWithScheduler() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))

        // 1) 状态信号永远为真（不依赖 now）
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "IN_PLAY")), "IN_PLAY 应判为进行中")
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "HALFTIME")), "HALFTIME 应判为进行中")

        // 2) 开球窗信号：窗内为真
        let inWindow = kickoff.addingTimeInterval(2 * 60)
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: inWindow),
                      "开球后落在 3h 窗内应判为进行中")

        // 3) 开球前：尚未进行中
        let beforeKickoff = kickoff.addingTimeInterval(-60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: beforeKickoff),
                       "开球前不应判为进行中")

        // 4) 开球 4 小时后（超出 3h 窗）：不再进行中
        let afterWindow = kickoff.addingTimeInterval(4 * 60 * 60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: afterWindow),
                       "超出 3h 窗不应判为进行中")

        // 5) 已结束优先于时间窗：即使仍在窗内，FINISHED 也非进行中
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "FINISHED"), now: inWindow),
                       "已结束优先于时间窗，不应判为进行中")
    }

    /// 回归：延期 / 取消的比赛虽未结束，但原开球时间同样落进 3h 时间窗 ——
    /// 不得被时间窗兜底判成「进行中」（否则赛果卡显示 ⚽ 0-0，而非「延期 / 取消」）。
    func testIsLiveExcludesPostponedAndCanceledEvenInWindow() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(30 * 60)

        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "POSTPONED"), now: now),
                       "开球窗内的 POSTPONED 不应判为进行中")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELED"), now: now),
                       "开球窗内的 CANCELED 不应判为进行中")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELLED"), now: now),
                       "开球窗内的 CANCELLED 不应判为进行中")

        // 同一时刻、同一开球时间的 SCHEDULED 仍按窗内进行中处理（防止把兜底逻辑改死）
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: now),
                      "状态滞后的正常比赛仍应按时间窗判为进行中")
    }

    /// 分区回归：开球窗内的 SCHEDULED 比赛应进入「进行中」分组，而非「未开赛」分组
    /// （今日页 / 赛程页 header 计数与分栏的对齐依据）。
    func testGroupedScheduledInWindowCountedAsLiveNotUpcoming() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(2 * 60)
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let today = TodayFilter.todayMatches(from: [m], now: now, tz: tz)
        let live = today.filter { TodayFilter.isLive($0, now: now) }
        let upcoming = today.filter { TodayFilter.isUpcoming($0, now: now) }

        XCTAssertEqual(live.count, 1, "开球窗内的 SCHEDULED 应计入进行中")
        XCTAssertEqual(upcoming.count, 0, "开球窗内的 SCHEDULED 不应同时计入未开赛")
    }

    // MARK: - 积分榜名次聚合（teamId 去重）

    /// 回归测试：积分榜聚合时若同一 teamId 出现两次（脏数据 / 主客场拆分残留），
    /// 旧的 `Dictionary(uniqueKeysWithValues:)` 会直接 trap（fatalError）；
    /// 改用 `uniquingKeysWith:` 后不再崩溃，且保留**先出现**的那条名次。
    func testBuildPositionsKeepsFirstOnDuplicateTeamId() throws {
        let team = Team(
            id: 1, name: "Arsenal", shortName: "ARS",
            crest: nil, venue: nil, founded: nil, coach: nil, squad: nil
        )
        let first = StandingRow(
            position: 3, team: team, playedGames: 1, won: 1, draw: 0, lost: 0,
            points: 3, goalsFor: 2, goalsAgainst: 1, goalDifference: 1,
            form: nil, status: nil, home: nil, away: nil
        )
        let second = StandingRow(
            position: 7, team: team, playedGames: 1, won: 0, draw: 1, lost: 0,
            points: 1, goalsFor: 1, goalsAgainst: 1, goalDifference: 0,
            form: nil, status: nil, home: nil, away: nil
        )

        // 不应 trap；重复的 teamId 保留先出现的名次（3）。
        let positions = TodayViewModel.buildPositions(from: [first, second])
        XCTAssertEqual(positions.count, 1, "重复 teamId 只应产出一条记录")
        XCTAssertEqual(positions[1], 3, "重复 key 应保留先出现的名次")
    }

    // MARK: - 稳定 ID 与积分榜排序确定性

    /// 回归：stableID 必须跨启动稳定 —— 旧实现用 `String.hashValue`（每次启动随机种子），
    /// 派生出的球队/比赛 id 两次启动不一致，缓存比对与 ForEach diff 全乱。
    /// 基准值用独立实现算好的 FNV-1a 64bit 锁死算法。
    func testStableIDIsDeterministicFNV1a() {
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), 7_430_836_138_530_658_124)
        XCTAssertEqual(
            ESPNTranslator.stableID(from: "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/teams/359"),
            6_167_624_713_123_287_027)
        // 同输入恒同输出；结果必须是非负 Int（可安全用作 id）
        XCTAssertEqual(ESPNTranslator.stableID(from: "abc"), ESPNTranslator.stableID(from: "abc"))
        XCTAssertGreaterThanOrEqual(ESPNTranslator.stableID(from: "x"), 0, "结果必须是非负 Int")
        XCTAssertNotEqual(ESPNTranslator.stableID(from: "a"), ESPNTranslator.stableID(from: "b"))
    }

    /// 回归：v3 积分榜同分时按 净胜球 → 进球 → ESPN rank 稳定排序。
    /// 旧实现只按积分排，同分行两次取数间可能互换，列表顺序与显示名次对不上。
    func testStandingsV3RowsSortTiebreaksByGDThenRank() throws {
        func entry(id: String, rank: Int, pts: Int, gf: Int, ga: Int) -> ESPNStandingEntryV3 {
            func rec(_ name: String, _ v: Int) -> ESPNRecordV3 {
                ESPNRecordV3(name: name, displayName: nil, shortDisplayName: nil,
                             value: Double(v), stats: nil)
            }
            return ESPNStandingEntryV3(
                team: ESPNTeamRefV3(id: id, name: id, shortName: nil, displayName: "Team \(id)",
                                    logos: nil, abbreviation: nil, dollarRef: nil),
                records: [rec("points", pts), rec("pointsFor", gf), rec("pointsAgainst", ga)],
                stats: nil, rank: rank, note: nil)
        }
        let resp = ESPNStandingsCoreResponse(
            name: nil, displayName: nil,
            standings: [
                entry(id: "5", rank: 1, pts: 3, gf: 1, ga: 1),   // 同分、GD 0
                entry(id: "6", rank: 2, pts: 3, gf: 2, ga: 0),   // 同分、GD +2 → 应排最前
                entry(id: "7", rank: 3, pts: 3, gf: 1, ga: 2),   // 同分、GD -1 → 垫底
                entry(id: "8", rank: 4, pts: 3, gf: 1, ga: 1),   // 与 team5 完全同分 → 按 rank 排在 team5 后
            ])
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertFalse(rows.isEmpty, "有 records 的响应不应回退为空")
        XCTAssertEqual(rows.map(\.team.id), [6, 5, 8, 7],
                       "同分先比净胜球、再比进球，完全同分按 ESPN rank 稳定住")
        XCTAssertEqual(rows.map(\.position), [2, 1, 4, 3],
                       "position 沿用 ESPN rank，排序不应改写名次标签")
    }

    /// 回归：v3 team 只有 $ref（无数字 id）时，id 用 FNV 散列派生 —— 跨启动一致。
    func testStandingsV3RefOnlyTeamGetsStableID() throws {
        let ref = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/eng.1/teams/359"
        let resp = ESPNStandingsCoreResponse(
            name: nil, displayName: nil,
            standings: [
                ESPNStandingEntryV3(
                    team: ESPNTeamRefV3(id: nil, name: nil, shortName: nil, displayName: nil,
                                        logos: nil, abbreviation: nil, dollarRef: ref),
                    records: [ESPNRecordV3(name: "points", displayName: nil, shortDisplayName: nil,
                                           value: 3, stats: nil)],
                    stats: nil, rank: 1, note: nil)
            ])
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertFalse(rows.isEmpty, "有 records 的响应不应回退为空")
        XCTAssertEqual(rows.first?.team.id, ESPNTranslator.stableID(from: ref),
                       "无数字 id 的 $ref 球队应得到跨启动稳定的 id")
    }

    /// 回归：从赛果聚合积分榜时，积分/净胜球/进球完全相同的球队按 teamId 稳定排序 ——
    /// stats 是字典、遍历顺序不定，没有最终 tiebreak 时两次聚合的行序可能不同。
    func testAggregateMatchesFullTieOrdersByTeamId() {
        func finishedMatch(id: Int, home: Int, away: Int, homeScore: Int, awayScore: Int) -> Match {
            let h = Team(id: home, name: "T\(home)", shortName: nil, crest: nil,
                         venue: nil, founded: nil, coach: nil, squad: nil)
            let a = Team(id: away, name: "T\(away)", shortName: nil, crest: nil,
                         venue: nil, founded: nil, coach: nil, squad: nil)
            return Match(id: id, matchday: 1, utcDate: "2026-08-15T14:00:00Z", status: "FINISHED",
                         stage: nil, homeTeam: h, awayTeam: a,
                         score: Score(fullTime: FullTime(home: homeScore, away: awayScore)))
        }
        // 两队各 1-0 取胜：积分/净胜球/进球完全相同
        let matches = [
            finishedMatch(id: 1, home: 30, away: 40, homeScore: 1, awayScore: 0),   // team 30 胜
            finishedMatch(id: 2, home: 20, away: 50, homeScore: 1, awayScore: 0),   // team 20 胜
        ]
        let rows = StandingsAggregator.aggregate(matches: matches)
        XCTAssertEqual(rows.map(\.team.id), [20, 30, 40, 50],
                       "完全同分的胜者按 teamId 升序，零分球队同样按 teamId 升序")
        XCTAssertEqual(rows.map(\.position), [1, 2, 3, 4])
        XCTAssertEqual(rows[0].points, 3)
        XCTAssertEqual(rows[1].points, 3)
        XCTAssertEqual(rows[0].goalsFor, 1)
        XCTAssertEqual(rows[1].goalsFor, 1)
    }

    // MARK: - 积分榜排序（主场/客场榜按维度独立排名）

    private func standing(id: Int, position: Int, pts: Int,
                          gf: Int = 0, ga: Int = 0,
                          home: VenueStats? = nil, away: VenueStats? = nil,
                          form: String? = nil) -> StandingRow {
        StandingRow(position: position, team: Team(id: id, name: "T\(id)", shortName: "T\(id)",
                                                   crest: nil, venue: nil, founded: nil,
                                                   coach: nil, squad: nil),
                    playedGames: 0, won: 0, draw: 0, lost: 0,
                    points: pts, goalsFor: gf, goalsAgainst: ga, goalDifference: gf - ga,
                    form: form, status: nil, home: home, away: away)
    }

    private func vs(played: Int, won: Int, draw: Int, lost: Int,
                    gf: Int, ga: Int) -> VenueStats {
        VenueStats(played: played, won: won, draw: draw, lost: lost,
                   goalsFor: gf, goalsAgainst: ga, points: won * 3 + draw)
    }

    private func scoredMatch(id: Int, home: Int, away: Int, date: String,
                             score: (Int, Int)) -> Match {
        Match(id: id, matchday: 1, utcDate: date, status: "FINISHED", stage: nil,
              homeTeam: Team(id: home, name: "H\(home)", shortName: "H\(home)", crest: nil,
                             venue: nil, founded: nil, coach: nil, squad: nil),
              awayTeam: Team(id: away, name: "A\(away)", shortName: "A\(away)", crest: nil,
                             venue: nil, founded: nil, coach: nil, squad: nil),
              score: Score(fullTime: FullTime(home: score.0, away: score.1)))
    }

    func testVenueTabSortsByVenuePointsAndRenumbers() {
        // B 总榜第 1 但主场榜应排末位；A 主场榜第一。名次编号必须按主场榜重排。
        let rows = [
            standing(id: 1, position: 1, pts: 90,
                     home: vs(played: 10, won: 9, draw: 0, lost: 1, gf: 25, ga: 8)),
            standing(id: 2, position: 2, pts: 80,
                     home: vs(played: 10, won: 1, draw: 0, lost: 9, gf: 5, ga: 30)),
            standing(id: 3, position: 3, pts: 70,
                     home: vs(played: 10, won: 8, draw: 1, lost: 1, gf: 20, ga: 6))
        ]
        let home = StandingsSorter.rankedStandings(rows: rows, for: .home)
        let names = home.map { $0.row.team.name }
        let ranks = home.compactMap { $0.rank }
        XCTAssertEqual(names, ["T1", "T3", "T2"],
                       "主场榜应按主场积分降序，而不是沿用总榜顺序")
        XCTAssertEqual(ranks, [1, 2, 3], "主场榜名次应重新编号 1...N")
    }

    func testVenueTabTieBreaksByGoalDifferenceThenGoalsFor() {
        // 同积分：T1 净胜球 -6 垫底；T2/T3 同为 +8，进球多者(20>12)靠前
        let rows = [
            standing(id: 1, position: 1, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 4, ga: 10)),
            standing(id: 2, position: 2, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 12, ga: 4)),
            standing(id: 3, position: 3, pts: 5, away: vs(played: 3, won: 1, draw: 2, lost: 0, gf: 20, ga: 12))
        ]
        let away = StandingsSorter.rankedStandings(rows: rows, for: .away)
        XCTAssertEqual(away.map { $0.row.team.id }, [3, 2, 1],
                       "同分时应按净胜球、再按进球降序")
    }

    func testVenueTabPushesTeamsWithoutVenueDataToBottomUnranked() {
        // 尚未在主/客场踢过球的队伍：沉底、不给名次，且不占用名次编号
        let rows = [
            standing(id: 1, position: 1, pts: 50, home: vs(played: 2, won: 2, draw: 0, lost: 0, gf: 6, ga: 1)),
            standing(id: 2, position: 2, pts: 40),
            standing(id: 3, position: 3, pts: 30, home: vs(played: 2, won: 1, draw: 1, lost: 0, gf: 3, ga: 1))
        ]
        let home = StandingsSorter.rankedStandings(rows: rows, for: .home)
        XCTAssertEqual(home.map { $0.row.team.id }, [1, 3, 2])
        XCTAssertEqual(home.map { $0.rank }, [1, 2, nil],
                       "无主场数据的队伍不给名次")
        XCTAssertEqual(Set(home.map { $0.id }).count, 3, "行 id 必须互不相同")
    }

    func testOverallAndFormTabKeepSourceOrder() {
        let rows = [
            standing(id: 7, position: 3, pts: 10),
            standing(id: 8, position: 1, pts: 30),
            standing(id: 9, position: 2, pts: 20)
        ]
        for tab in [StandingsTab.overall, .form] {
            let out = StandingsSorter.rankedStandings(rows: rows, for: tab)
            XCTAssertEqual(out.map { $0.row.team.id }, [7, 8, 9],
                           "\(tab.rawValue) tab 应保持数据源顺序")
            XCTAssertEqual(out.map { $0.rank }, [3, 1, 2],
                           "\(tab.rawValue) tab 名次应沿用总榜 position")
        }
    }

    func testRankedStandingIdDiffersByRank() {
        // 关键护栏：同一支球队在不同名次下 id 不同，否则切 tab 会让 ForEach 错配
        let row = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(RankedStanding(row: row, rank: 1).id,
                          RankedStanding(row: row, rank: 3).id,
                          "同一球队在不同名次下 id 必须不同")
        XCTAssertNotEqual(RankedStanding(row: row, rank: nil).id,
                          RankedStanding(row: row, rank: 1).id)
    }

    func testStandingRowIdIsStableUnderRerank() {
        let a = standing(id: 1, position: 1, pts: 30)
        let b = standing(id: 1, position: 3, pts: 10)
        XCTAssertNotEqual(a.id, b.id, "同一球队在不同 position 下 id 必须不同")
        XCTAssertEqual(a.id, "pos1-team1")
    }

    // MARK: - 积分榜 form（状态）补全

    func testEnrichDerivesFormFromMatchesWhenMissing() {
        // 这是「状态 tab 长期全破折号」的回归用例：enrich 必须从赛程推导 form
        let rows = [standing(id: 1, position: 1, pts: 6)]
        let matches = [
            scoredMatch(id: 1, home: 1, away: 2, date: "2026-09-01T14:00:00Z", score: (2, 0)),   // W
            scoredMatch(id: 2, home: 1, away: 3, date: "2026-09-08T14:00:00Z", score: (0, 3)),   // L
            scoredMatch(id: 3, home: 4, away: 1, date: "2026-09-15T14:00:00Z", score: (1, 1))    // D
        ]
        let enriched = StandingsEnricher.enrich(rows: rows, with: matches)
        XCTAssertEqual(enriched.first?.form, "WLD",
                       "form 应从最近 3 场按时间升序推导，而不是留空")
        XCTAssertNotNil(enriched.first?.home, "主场数据应被补全")
        XCTAssertNotNil(enriched.first?.away, "客场数据应被补全")
    }

    func testEnrichNormalizesCommaSeparatedForm() {
        // 本地示例数据是 "D,W,W,D,W"，UI 按前 5 个字符渲染，不归一会把逗号画成胶囊
        let rows = [standing(id: 1, position: 1, pts: 6, form: "D,W,W,D,W")]
        let enriched = StandingsEnricher.enrich(rows: rows, with: [])
        XCTAssertEqual(enriched.first?.form, "DWWDW")
    }

    func testEnrichKeepsGivenFormButDerivesMissingOne() {
        let rows = [
            standing(id: 1, position: 1, pts: 6, form: "D,W,W,D,W"),
            standing(id: 2, position: 2, pts: 4)
        ]
        let matches = [
            scoredMatch(id: 1, home: 1, away: 2, date: "2026-09-01T14:00:00Z", score: (2, 0)),
            scoredMatch(id: 2, home: 2, away: 1, date: "2026-09-08T14:00:00Z", score: (1, 0))
        ]
        let enriched = StandingsEnricher.enrich(rows: rows, with: matches)
        XCTAssertEqual(enriched[0].form, "DWWDW", "已有 form 应归一化后保留")
        XCTAssertEqual(enriched[1].form, "LW",
                       "缺失的 form 应从赛程按时间推导（第 1 场客战 0:2 输、第 2 场主场 1:0 赢）")
    }

    func testNormalizeFormEdgeCases() {
        XCTAssertEqual(StandingsEnricher.normalizeForm("W,W,D,L,W"), "WWDLW")
        XCTAssertEqual(StandingsEnricher.normalizeForm("  W L D  "), "WLD")
        XCTAssertEqual(StandingsEnricher.normalizeForm("WWWWWW"), "WWWWW",
                       "应截断到最近 5 场")
        XCTAssertEqual(StandingsEnricher.normalizeForm("———"), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(""), nil)
        XCTAssertEqual(StandingsEnricher.normalizeForm(nil), nil)
    }
}

// MARK: - 比赛期间自动刷新：只失效赛程缓存（不重下整份 bootstrap）

extension EPLViewerTests {
    /// 比赛期间 60s 轮询必须只清「赛程」缓存，不能走 full clearCache()（那会把整份
    /// FPL bootstrap / 积分榜一起清掉，导致每 60s 重下大文件）。
    /// 护栏：invalidateFixtures() 后，内存里的 fixtures 被清、bootstrap 保留。
    func testInvalidateFixturesClearsFixturesKeepsBootstrap() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "夹具 matchesJSON 应可解码出赛程")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        await DataRepository.invalidateFixtures()

        // 赛程被失效
        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "invalidateFixtures 必须清掉内存赛程缓存")
        // bootstrap 保留 —— 若误用 full clearCache()，这里会是 nil
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "invalidateFixtures 不能清掉 bootstrap（否则每 60s 重下整份 bootstrap）")
    }

    /// 端到端护栏：AppState.refresh(scoresOnly:) 的定时器路径不清整份缓存。
    /// 预填内存 fixtures + bootstrap，调用 scoresOnly 刷新后，
    /// fixtures 被清、bootstrap 仍在（证明没走 full clearCache，否则 bootstrap 也会被清）。
    /// 注：CacheStore 磁盘 IO 在本沙箱被拦截，这里用内存缓存层做等价断言。
    @MainActor
    func testRefreshScoresOnlyDoesNotWipeAllCaches() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "夹具 matchesJSON 应可解码出赛程")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        let appState = AppState()
        await appState.refresh(scoresOnly: true)

        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "scoresOnly 刷新必须失效赛程缓存")
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "scoresOnly 刷新不能清掉 bootstrap（否则每 60s 重下整份 bootstrap）")
    }

    // MARK: - 球员中英文名映射（PlayerNames）

    /// 中文模式下已知球星返回中文全名；英文模式恒为原名；未知球员回退英文原名（绝不空白/崩溃）。
    /// 用 sentinel id（999999，不在 zhById 中）隔离出 web_name 回退路径，避免与真实 id 碰撞。
    func testPlayerDisplayNameChineseKnownAndFallback() {
        let haaland = PlayerLite(id: 999999, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "Haaland 应命中中文全名（web_name 回退路径）")
        XCTAssertEqual(haaland.displayName(chinese: false), "Haaland",
                       "英文模式恒为 FPL web_name 原名")

        let nobody = PlayerLite(id: 999999, name: "Unknown Player", nationality: nil)
        XCTAssertEqual(nobody.displayName(chinese: true), "Unknown Player",
                       "未知球员中文模式应回退英文原名，不能空白")
    }

    /// 主键路径：FPL element id 命中时直接返回中文全名（id 跨赛季/转会稳定，优先于 web_name）。
    func testPlayerDisplayNameByIdPrimaryKey() {
        // Haaland 的 FPL element id 长期稳定为 411；即便未来 id 漂移，web_name 回退仍给出中文，故不脆弱。
        let haaland = PlayerLite(id: 411, name: "Haaland", nationality: nil)
        XCTAssertEqual(haaland.displayName(chinese: true), "埃尔林·哈兰德",
                       "按 id 主键应命中中文全名")
    }

    /// 带重音的 web_name（如 Paquetá）应命中中文名。
    func testPlayerNameAccentedWebNameMatches() {
        // Paquetá 已不在 2026/27 阵容（FPL 无此人），故改用同样带重音且确实入表的 Núñez。
        // 目的：带重音的 web_name 仍能命中中文译名，而非退回英文原文。
        let accented = PlayerLite(id: 999998, name: "Núñez", nationality: nil)
        XCTAssertEqual(accented.displayName(chinese: true), "达尔文·努涅斯")
    }

    /// 维护差量工具：missing(from:) 只返回表中没有的 web_name，且已排序去重（已知项被排除）。
    func testPlayerNameMapMissingExcludesKnown() {
        // Haaland / Watkins / Rice 均在数据集中；Salah 本赛季不在阵容，故也不应被当成已知。
        let webNames = ["Haaland", "Watkins", "Rice", "Some New Guy", "Another New Guy", "Haaland"]
        let missing = PlayerNameMap.missing(from: webNames)
        XCTAssertFalse(missing.contains("Haaland"))
        XCTAssertFalse(missing.contains("Watkins"))
        XCTAssertFalse(missing.contains("Rice"))
        XCTAssertEqual(missing, ["Another New Guy", "Some New Guy"],
                       "missing 应排序去重，且不含已知项")
    }

    /// 回归：译名表已外部化为 bundle 资源（`Resources/PlayerNames-zh-Hans.json`），
    /// 加载器必须能在 App bundle 里找到并解码 —— 上面各 displayName 测试若全绿但本用例红，
    /// 说明资源文件没被打进 target（pbxproj 引用丢失）。
    func testTranslationResourcesAreBundledAndLoadable() {
        // byId 维度（资源文件的主键表；1 与 411 是表内锚点值）
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 1), "戴维·拉亚")
        XCTAssertEqual(PlayerNameMap.builtInName(forId: 411), "埃尔林·哈兰德")
        // 表必须是真实加载的完整表，而不是加载失败后的空表兜底：1..20 全命中
        XCTAssertEqual(PlayerNameMap.missing(ids: Array(1...20)), [],
                       "id 1..20 应全部在译名表中（资源未加载时这里会全量 missing）")
        // 球队表
        let arsenal = Team(id: 57, name: "Arsenal", shortName: "ARS", crest: nil,
                           venue: nil, founded: nil, coach: nil, squad: nil)
        XCTAssertEqual(TeamNameMap.zh(for: arsenal), "阿森纳")
    }

    /// 加载器健壮性：locale 不存在（或文件损坏）→ nil，由调用方回退空表显示英文。
    func testTranslationStoreMissingLocaleReturnsNil() {
        struct Payload: Decodable {}
        XCTAssertNil(TranslationStore.load("PlayerNames", locale: "xx-Nope") as Payload?,
                     "不存在的 locale 资源应返回 nil，而不是抛错或崩溃")
    }

    // MARK: - 调试期球员中文名覆盖层（PlayerNameOverrides）

    /// 覆盖层按 id 维度优先：覆盖 426 后返回覆盖名；复位后回退内置「布鲁诺·费尔南德斯」。
    /// 每个测试都 defer 复位 `PlayerNameOverrides.current`，避免污染其它测试。
    func testPlayerNameOverrideByIdPrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [426: "测试覆盖名"], byName: [:])
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "测试覆盖名",
            "id 维度覆盖应优先于内置中文名"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 426, name: "B.Fernandes", nationality: nil).displayName(chinese: true),
            "布鲁诺·费尔南德斯",
            "复位覆盖后应回退到内置中文名"
        )
    }

    /// 覆盖层按 name 维度：覆盖 byName["Saka"] 后返回覆盖名；复位后回退内置「布卡约·萨卡」。
    /// 注意：id 维度优先于 name 维度，故必须用「不在 zhById 中的 id」才能落到 name 分支
    /// （若 id 命中内置表，name 覆盖根本不会被走到）。沿用本文件既有的合成 id 约定（999998/999999）。
    func testPlayerNameOverrideByNamePrecedence() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = PlayerNameOverrides(byId: [:], byName: ["Saka": "测试名"])
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "测试名",
            "name 维度覆盖应优先于内置中文名"
        )
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 999997, name: "Saka", nationality: nil).displayName(chinese: true),
            "布卡约·萨卡",
            "复位覆盖后应回退到内置中文名"
        )
    }

    /// 守卫内置默认值不被回归：无覆盖时 id 1 → 「戴维·拉亚」。
    func testPlayerNameOverrideDefaultsUnchanged() {
        defer { PlayerNameStore.current = .init() }
        PlayerNameStore.current = .init()
        XCTAssertEqual(
            PlayerLite(id: 1, name: "Raya", nationality: nil).displayName(chinese: true),
            "戴维·拉亚",
            "无覆盖时应返回内置中文名"
        )
    }

    /// 直接覆盖 `PlayerNameStore.commit(_:)`：替换内存覆盖层 + 同步静态快照；
    /// 提交空值应清空两者。落盘失败被 `save()` 吞掉，不影响内存断言。
    func testPlayerNameStoreCommit() {
        defer {
            PlayerNameStore.shared.commit(.init())
            PlayerNameStore.current = .init()
        }
        let store = PlayerNameStore.shared
        let sample = PlayerNameOverrides(byId: [426: "提交覆盖名"], byName: [:])

        store.commit(sample)
        XCTAssertEqual(store.overrides, sample, "commit 后内存覆盖层应等于提交值")
        XCTAssertEqual(PlayerNameStore.current, sample, "commit 后静态快照应同步")

        store.commit(.init())
        XCTAssertEqual(store.overrides, .init(), "commit 空值应清空内存覆盖层")
        XCTAssertEqual(PlayerNameStore.current, .init(), "commit 空值应清空静态快照")
    }
}
