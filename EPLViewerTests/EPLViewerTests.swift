import XCTest
@testable import EPLViewer

import XCTest
@testable import EPLViewer

// MARK: - 内联测试夹具（避免 test target 无法访问主 target Bundle.module 资源）
// 这些 JSON 镜像 Sources/EPLViewer/Resources 中的真实结构，使用与 App 一致的
// JSONDecoder + .convertFromSnakeCase 解码，用于断言模型字段与 JSON 一一对应。
// 采用内联字符串而非 Bundle.module，确保测试在 Xcode / `swift test` 下独立可跑。

let standingsJSON = """
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

let teamsJSON = """
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

let scorersJSON = """
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

let matchesJSON = """
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

let injuriesJSON = """
{
  "injuries": [
    {"player":{"id":10,"name":"Erling Haaland","nationality":"Norway"},"team":{"id":65,"name":"Manchester City","shortName":"Man City","crest":"https://crests.football-data.org/65.png"},"status":"i","news":"Foot injury","chanceOfPlayingNextRound":25,"position":"Centre-Forward"},
    {"player":{"id":20,"name":"Mohamed Salah","nationality":"Egypt"},"team":{"id":64,"name":"Liverpool","shortName":"Liverpool","crest":"https://crests.football-data.org/64.png"},"status":"d","news":"Hamstring","chanceOfPlayingNextRound":75,"position":"Right Winger"}
  ]
}
"""

// FPL bootstrap-static 真实结构子集
let fplBootstrapJSON = """
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
let espnStandingsJSON = """
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
let espnScoreboardJSON = """
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
    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// 用于 ESPN/FPL 原生类型：Swift 字段已经是 snake_case，不需要转换
    func makeNativeDecoder() -> JSONDecoder {
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

    // MARK: - 源码扫描工具

    /// 剥掉 `//` 行注释只留代码 —— 否则「为什么不能用 LazyVStack」这类解释性注释会误报
    func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)                  // .../EPLViewerTests/EPLViewerTests.swift
            .deletingLastPathComponent()                 // EPLViewerTests/
            .deletingLastPathComponent()                 // 仓库根
            .appendingPathComponent("EPLViewer")
    }

    func sourceFile(_ name: String) throws -> String {
        try String(contentsOf: try locateSource(named: name), encoding: .utf8)
    }

    /// 在源码目录树中按文件名递归定位（分层目录后源码不再平铺在根下）
    func locateSource(named name: String) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: sourceRoot(), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        throw NSError(domain: "EPLViewerTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "源文件未找到: \(name)"])
    }

    func allSourceFiles() throws -> [(name: String, text: String)] {
        let enumerator = FileManager.default.enumerator(at: sourceRoot(), includingPropertiesForKeys: nil)
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL, url.pathExtension == "swift" {
            urls.append(url)
        }
        return try urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { (name: $0.lastPathComponent, text: try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// 子串出现次数（非重叠）
    func count(of token: String, in s: String) -> Int {
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
    func lazyNestingViolations(_ code: String) -> [String] {
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
    func hardcodedCJK(in code: String) -> [String] {
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

}
