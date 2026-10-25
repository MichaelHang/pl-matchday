import XCTest
@testable import EPLViewer

// MARK: - Inline test fixtures (the test target can't reach the app target's
// Bundle.module resources). These JSON strings mirror the shapes of the app's
// resources and decode with the same JSONDecoder + .convertFromSnakeCase setup the
// app uses, asserting model fields against the JSON one-to-one. Inline strings
// (rather than bundle lookups) keep the tests self-contained under Xcode / swift test.

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

// A realistic subset of FPL bootstrap-static.
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

// A realistic subset of ESPN standings.
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

// A subset of the ESPN scoreboard.
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

    // MARK: - Basics

    func testExample() {
        XCTAssertTrue(true)
    }

    // MARK: - Fallback decisions

    /// Verifies the rules of the shouldFallback pure function.
    func testShouldFallback() {
        XCTAssertTrue(DataRepository.shouldFallback(.noData))
        XCTAssertTrue(DataRepository.shouldFallback(.apiError(429)))
        XCTAssertTrue(DataRepository.shouldFallback(.network(NSError(domain: "", code: 0))))

        XCTAssertFalse(DataRepository.shouldFallback(.apiError(403)))
        XCTAssertFalse(DataRepository.shouldFallback(.apiError(400)))
        XCTAssertFalse(DataRepository.shouldFallback(.decoding(NSError(domain: "", code: 0))))
    }

    // MARK: - Cache TTL

    /// CacheTTL.isValid pure function: now - mtime < ttl → true; past it → false.
    func testCacheTTLIsValid() {
        let now = Date()
        let recent = now.addingTimeInterval(-30)      // 30 seconds ago
        let stale  = now.addingTimeInterval(-120)     // 120 seconds ago
        XCTAssertTrue(CacheTTL.isValid(mtime: recent, ttl: 60, now: now))
        XCTAssertFalse(CacheTTL.isValid(mtime: stale, ttl: 60, now: now))
        // With ttl = 2h, 120s ago is still valid
        XCTAssertTrue(CacheTTL.isValid(mtime: stale, ttl: 60 * 60 * 2, now: now))
        // ttl = 0 is never valid
        XCTAssertFalse(CacheTTL.isValid(mtime: now, ttl: 0, now: now))
    }

    /// Regression: CacheStore.getStale — the stale-if-error fallback for network
    /// failures. Ignores TTL and returns the last persisted data; the regular TTL
    /// path still respects expiry; a corrupt file returns nil without throwing.
    func testCacheStoreStaleFallback() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("epl-cachestore-\(UUID().uuidString)", isDirectory: true)
        let store = CacheStore(directory: dir)
        struct Payload: Codable, Equatable { let value: Int }
        defer { try? FileManager.default.removeItem(at: dir) }

        await store.set("k", value: Payload(value: 7))
        // Probe whether the write actually landed (some sandboxed environments block
        // disk IO; there's nothing to verify then, so skip)
        guard (try? Data(contentsOf: dir.appendingPathComponent("k.json"))) != nil else {
            throw XCTSkip("CacheStore cannot write to disk in this environment; skipping the stale-fallback verification")
        }

        // Rewind mtime by 2 hours → the regular TTL path (ttl=60s) must miss
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-2 * 3600)],
            ofItemAtPath: dir.appendingPathComponent("k.json").path)
        let fresh: Payload? = await store.get("k", ttl: 60)
        XCTAssertNil(fresh, "an expired entry must miss the regular path")

        // getStale ignores TTL and returns the last data
        let stale: Payload? = await store.getStale("k")
        XCTAssertEqual(stale, Payload(value: 7), "getStale ignores TTL and serves the expired cache")

        // Corrupt file → nil, no throw
        try Data("not json".utf8).write(to: dir.appendingPathComponent("k.json"))
        let broken: Payload? = await store.getStale("k")
        XCTAssertNil(broken, "a corrupt cache file returns nil silently")

        // Missing key → nil
        let missing: Payload? = await store.getStale("nope")
        XCTAssertNil(missing)
    }

    /// Last-known-good slots must survive clearFixtures() AND clear(): the live-match
    /// poll and a manual refresh wipe the regular caches, but the UI's final fallback
    /// keeps the last successfully served data (match-day blank-screen regression:
    /// poll invalidates → network fails → page went empty).
    func testLastGoodSlotsSurviveInvalidation() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        await MemoryStore.shared.cacheFixtures(matches)
        await MemoryStore.shared.rememberFixtures(matches)

        await MemoryStore.shared.clearFixtures()   // live-poll invalidation
        let afterInvalidate = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(afterInvalidate, "the regular fixtures slot should be cleared")
        let last1 = await MemoryStore.shared.lastGoodFixturesSnapshot()
        XCTAssertEqual(last1?.count, matches.count, "invalidateFixtures must not clear last-known-good")

        await MemoryStore.shared.clear()           // manual refresh / clear-cache
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNil(bootstrapAfter, "precondition: clear() wipes the regular bootstrap slot")
        let last2 = await MemoryStore.shared.lastGoodFixturesSnapshot()
        XCTAssertEqual(last2?.count, matches.count, "clear() must not clear last-known-good either")

        // An explicit remember of an empty array overwrites the slot (fetch success
        // always remembers real data; empty only via the deliberate call)
        await MemoryStore.shared.rememberFixtures([])
        let overwritten = await MemoryStore.shared.lastGoodFixturesSnapshot()
        XCTAssertEqual(overwritten?.count, 0)
    }

    // MARK: - Internal model decoding

    /// Reuses the app's snake_case decoding setup (for internal domain models).
    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// For ESPN/FPL native types: the Swift fields are already snake_case — no
    /// conversion needed.
    func makeNativeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    func testStandingsDecoding() throws {
        let response = try makeDecoder().decode(StandingsResponse.self, from: Data(standingsJSON.utf8))
        let table = response.standings.first?.table ?? []
        XCTAssertEqual(table.count, 8, "the standings table should have 8 rows")
        XCTAssertEqual(table.first?.position, 1, "the first row's position should be 1")
        for i in 1..<table.count {
            XCTAssertGreaterThanOrEqual(table[i - 1].points, table[i].points, "points should descend")
        }
        XCTAssertEqual(table.first?.team.id, 65)
        XCTAssertEqual(table.first?.team.shortName, "Man City")
        XCTAssertNil(table[4].status, "status:null should decode as nil")
        XCTAssertEqual(table[0].status, "CHAMPIONS_LEAGUE")
    }

    func testTeamsDecoding() throws {
        let response = try makeDecoder().decode(TeamsResponse.self, from: Data(teamsJSON.utf8))
        XCTAssertEqual(response.teams.count, 8, "there should be 8 teams")
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

    // MARK: - Leaderboard sorting (scorers / assists)

    /// Scorers stable sort: goals desc; ties broken by fewest appearances.
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

    /// Assists stable sort: assists desc; ties by most goals; then by fewest appearances.
    func testAssistStableSort() {
        let teamA = Team(id: 1, name: "A", shortName: nil, crest: nil, venue: nil, founded: nil, coach: nil, squad: nil)
        let pTop = Assist(from: Scorer(player: PlayerLite(id: 1, name: "Top", nationality: nil), team: teamA, goals: 5, assists: 12, playedMatches: 30))
        let pTieMoreGoals = Assist(from: Scorer(player: PlayerLite(id: 2, name: "TieMoreGoals", nationality: nil), team: teamA, goals: 10, assists: 8, playedMatches: 30))
        let pTieLessGoals = Assist(from: Scorer(player: PlayerLite(id: 3, name: "TieLessGoals", nationality: nil), team: teamA, goals: 3, assists: 8, playedMatches: 10))
        let pTieMorePlayed = Assist(from: Scorer(player: PlayerLite(id: 4, name: "TieMorePlayed", nationality: nil), team: teamA, goals: 3, assists: 8, playedMatches: 30))

        let vm = LeadersViewModel()
        vm.assists = [pTieMorePlayed, pTop, pTieLessGoals, pTieMoreGoals]
        let sorted = vm.assistsSorted
        // pTop (12) leads
        XCTAssertEqual(sorted[0].player.id, 1)
        // Tied on 8 assists: more goals (10) ranks higher
        XCTAssertEqual(sorted[1].player.id, 2)
        // Tied on 8 assists + 3 goals: fewer appearances (10) ranks higher
        XCTAssertEqual(sorted[2].player.id, 3)
        XCTAssertEqual(sorted[3].player.id, 4)
    }

    /// StandingsAggregator unit test: 3 synthetic rows (Arsenal 2W+1D = 7 pts vs
    /// Tottenham 1W 1D 1L = 4 pts). Verifies RowStat.points() and the aggregated
    /// StandingRow points / ordering.
    func testStandingsAggregatorPureSort() {
        // Synthetic RowStats exercise the math (no real network fetches)
        let arsenal = StandingsAggregator.RowStat(played: 3, won: 2, draw: 1, lost: 0, gf: 5, ga: 1)
        let tottenham = StandingsAggregator.RowStat(played: 3, won: 1, draw: 1, lost: 1, gf: 3, ga: 3)
        let brighton = StandingsAggregator.RowStat(played: 3, won: 0, draw: 1, lost: 2, gf: 1, ga: 5)

        XCTAssertEqual(arsenal.points(), 7)     // 2*3 + 1
        XCTAssertEqual(tottenham.points(), 4)  // 1*3 + 1
        XCTAssertEqual(brighton.points(), 1)    // 0*3 + 1

        XCTAssertEqual(arsenal.gd(), 4)
        XCTAssertEqual(tottenham.gd(), 0)
        XCTAssertEqual(brighton.gd(), -4)

        // Real aggregation follows $refs in production; here we assert the pure
        // functions and the "equal points → GD" stable ordering rule.
        let stats: [(String, StandingsAggregator.RowStat)] = [
            ("Brighton", brighton), ("Tottenham", tottenham), ("Arsenal", arsenal)
        ]
        let sorted = stats.sorted { ($0.1.points(), $0.1.gd()) > ($1.1.points(), $1.1.gd()) }
        XCTAssertEqual(sorted[0].0, "Arsenal")
        XCTAssertEqual(sorted[1].0, "Tottenham")
        XCTAssertEqual(sorted[2].0, "Brighton")
    }

    // MARK: - FPL bootstrap decoding & derivation

    /// The FPL bootstrap raw JSON decodes and derives the scorers table by goals_scored.
    func testFPLBootstrapDecoding() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        XCTAssertEqual(bootstrap.teams.count, 3)
        XCTAssertEqual(bootstrap.elements.count, 4)
        XCTAssertEqual(bootstrap.element_types.count, 4)

        // Derived scorers: Haaland's 27 goals lead
        let scorers = FPLTranslator.scorers(from: bootstrap)
        XCTAssertEqual(scorers.first?.goals, 27)
        XCTAssertEqual(scorers.first?.player.name, "Haaland")
        XCTAssertEqual(scorers.first?.team.name, "Manchester City")
    }

    /// Derived assists: assists descending.
    func testFPLAssistsDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let assists = FPLTranslator.assists(from: bootstrap)
        XCTAssertEqual(assists.first?.assists, 12)
        XCTAssertEqual(assists.first?.player.name, "Salah")
    }

    /// Scorers/assists show only the top 10 (limit=10); limit=0 means unlimited.
    func testFPLLeaderboardsCappedToTen() throws {
        let team = FPLTeam(id: 1, code: 3, name: "Arsenal", short_name: "ARS", strength: nil)
        let elements = (1...15).map { i in
            FPLPlayer(id: i, web_name: "P\(i)", first_name: nil, second_name: nil,
                      team: 1, element_type: 1, goals_scored: 16 - i, assists: 16 - i,
                      status: "a", news: nil, chance_of_playing_next_round: nil, now_cost: nil)
        }
        let bootstrap = FPLBootstrap(teams: [team], elements: elements, element_types: [], events: nil)

        let scorers = FPLTranslator.scorers(from: bootstrap, limit: 10)
        XCTAssertEqual(scorers.count, 10, "the scorers table should cap at 10")
        XCTAssertEqual(scorers.first?.goals, 15)
        XCTAssertEqual(scorers.last?.goals, 6)

        let assists = FPLTranslator.assists(from: bootstrap, limit: 10)
        XCTAssertEqual(assists.count, 10, "the assists table should cap at 10")

        // limit=0 doesn't truncate
        XCTAssertEqual(FPLTranslator.scorers(from: bootstrap, limit: 0).count, 15)
    }

    /// Derived injuries: only players with status != "a".
    func testFPLInjuriesDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let injuries = FPLTranslator.injuries(from: bootstrap)
        // Of the 4 players: Saka(a) and Salah(a) filtered; Haaland(i) + Watkins(d) = 2
        XCTAssertEqual(injuries.count, 2)
        XCTAssertTrue(injuries.contains { $0.player.name == "Haaland" && $0.status == "i" })
        XCTAssertTrue(injuries.contains { $0.player.name == "Watkins" && $0.status == "d" })
    }

    /// Regression: FPL marks players who LEFT the club as status "u" with a transfer
    /// news line ("Has joined X permanently" / "on loan" / "departed as a free
    /// agent"). Left in, they bury real injuries under transfer noise — the injury
    /// board must exclude them while keeping genuine doubts/injuries.
    func testFPLInjuriesFilterOutTransferDepartures() throws {
        let team = FPLTeam(id: 1, code: 3, name: "Arsenal", short_name: "ARS", strength: nil)
        func element(_ id: Int, _ web: String, _ status: String, _ news: String?) -> FPLPlayer {
            FPLPlayer(id: id, web_name: web, first_name: nil, second_name: nil,
                      team: 1, element_type: 3, goals_scored: 0, assists: 0,
                      status: status, news: news, chance_of_playing_next_round: nil, now_cost: nil)
        }
        let bootstrap = FPLBootstrap(
            teams: [team],
            elements: [
                element(1, "RealInjury", "i", "Hamstring injury - Expected back 24 Oct"),
                element(2, "Transferred", "u", "Has joined Al Hilal permanently"),
                element(3, "Loaned", "u", "Has joined Borussia Dortmund on loan for the rest of the season"),
                element(4, "FreeAgent", "u", "has departed the club as a free agent."),
                element(5, "Doubtful", "d", "Unspecified injury - 75% chance of playing"),
            ],
            element_types: [],
            events: nil)

        let injuries = FPLTranslator.injuries(from: bootstrap)
        XCTAssertEqual(injuries.map { $0.player.name }, ["RealInjury", "Doubtful"],
                       "transfer departures (status=u + transfer news) must not appear on the injury board")
    }

    /// Fixture translation: FPL fixtures → internal Matches (round / status / score / crest).
    func testFPLFixturesToMatches() throws {
        let teams = [
            FPLTeam(id: 1, code: 3, name: "Arsenal", short_name: "ARS", strength: nil),
            FPLTeam(id: 7, code: 11, name: "Chelsea", short_name: "CHE", strength: nil),
        ]
        let fixtures = [
            // Finished (FPL finished=true) with a final score → FINISHED
            FPLFixture(event: 1, team_h: 1, team_a: 7, team_h_score: 3, team_a_score: 0,
                       kickoff_time: "2026-08-21T19:00:00Z", finished: true, started: true,
                       finished_provisional: true, minutes: 90),
            // Live (started=true, finished=false, under 90 minutes) with a live score →
            // IN_PLAY (UI adds ⚽; must not be misread as finished)
            FPLFixture(event: 2, team_h: 7, team_a: 1, team_h_score: 1, team_a_score: 2,
                       kickoff_time: "2026-08-22T19:00:00Z", finished: false, started: true,
                       finished_provisional: false, minutes: 23),
            // FPL hasn't flipped finished after full time, but finished_provisional=true
            // (actually over) → FINISHED, no ⚽.
            // (Repro: round 2 Crystal Palace vs City, 1-4, minutes 90, finished=false)
            FPLFixture(event: 3, team_h: 1, team_a: 7, team_h_score: 1, team_a_score: 4,
                       kickoff_time: "2026-08-23T19:00:00Z", finished: false, started: true,
                       finished_provisional: true, minutes: 90),
            // Not kicked off → SCHEDULED, no score
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
        XCTAssertEqual(m2.status, "IN_PLAY")   // key: live with a score isn't misread as finished
        XCTAssertEqual(m2.score?.fullTime?.home, 1)
        XCTAssertEqual(m2.score?.fullTime?.away, 2)

        let m3 = matches.first(where: { $0.matchday == 3 })!
        XCTAssertEqual(m3.status, "FINISHED")  // key: finished_provisional=true shows no ⚽
        XCTAssertEqual(m3.score?.fullTime?.home, 1)
        XCTAssertEqual(m3.score?.fullTime?.away, 4)

        let m4 = matches.first(where: { $0.matchday == 4 })!
        XCTAssertEqual(m4.status, "SCHEDULED")
        XCTAssertNil(m4.score)
    }

    /// Derived teams: with squads built from elements.
    func testFPLTeamsDerivation() throws {
        let bootstrap = try makeNativeDecoder().decode(FPLBootstrap.self, from: Data(fplBootstrapJSON.utf8))
        let teams = FPLTranslator.teams(from: bootstrap)
        XCTAssertEqual(teams.count, 3)
        let arsenal = teams.first { $0.name == "Arsenal" }
        XCTAssertNotNil(arsenal)
        // Arsenal carries Saka and Salah
        XCTAssertEqual(arsenal?.squad?.count, 2)
        // Crest URL looks like https://resources.premierleague.com/premierleague/badges/50/t3.png
        XCTAssertEqual(arsenal?.crest, "https://resources.premierleague.com/premierleague/badges/50/t3.png")
        // Player positions mapped: Saka is a Midfielder, Haaland a Forward
        let saka = arsenal?.squad?.first { $0.name == "Saka" }
        XCTAssertEqual(saka?.position, "Midfielder")
    }

    // MARK: - ESPN native decoding & translation

    /// ESPN standings raw JSON decodes and translates correctly to StandingRows.
    func testESPNStandingsTranslation() throws {
        let resp = try makeNativeDecoder().decode(ESPNStandingsResponse.self, from: Data(espnStandingsJSON.utf8))
        let rows = ESPNTranslator.standingRows(from: resp)
        XCTAssertEqual(rows.count, 2)
        // Points descending: Arsenal 48 > City 43
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

    /// ESPN scoreboard raw JSON decodes and translates correctly to Matches
    /// (including the status mapping).
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

    /// ESPN status-name translation.
    func testStatusTranslator() {
        XCTAssertEqual(StatusTranslator.translate("STATUS_FINAL"), "FINISHED")
        XCTAssertEqual(StatusTranslator.translate("STATUS_SCHEDULED"), "SCHEDULED")
        XCTAssertEqual(StatusTranslator.translate("STATUS_IN_PROGRESS"), "IN_PLAY")
        XCTAssertEqual(StatusTranslator.translate(nil), "SCHEDULED")
        XCTAssertEqual(StatusTranslator.translate("UNKNOWN"), "UNKNOWN")
    }

    // MARK: - Source-scan utilities

    /// Strip `//` line comments, keeping code only — otherwise explanatory comments
    /// like "why LazyVStack is banned" would false-positive.
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
            .deletingLastPathComponent()                 // repo root
            .appendingPathComponent("EPLViewer")
    }

    func sourceFile(_ name: String) throws -> String {
        try String(contentsOf: try locateSource(named: name), encoding: .utf8)
    }

    /// Locate a source file by name recursively (the layered layout means sources no
    /// longer sit flat under the root).
    func locateSource(named name: String) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: sourceRoot(), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name { return url }
        }
        throw NSError(domain: "EPLViewerTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "source file not found: \(name)"])
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

    /// Non-overlapping substring occurrence count.
    func count(of token: String, in s: String) -> Int {
        var n = 0
        var idx = s.startIndex
        while let r = s.range(of: token, range: idx..<s.endIndex) {
            n += 1
            idx = r.upperBound
        }
        return n
    }

    /// Detects any "lazy container inside another lazy container". Returns an empty
    /// array when the red line is respected. Walks character by character tracking
    /// brace depth: on `LazyXXX(`, record its depth; if the stack already holds
    /// another lazy container at a shallower/equal depth, it's nested inside.
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
                            violations.append("\(n) nested inside \(outer.name)")
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

    /// Finds hardcoded user-facing Chinese strings in source.
    /// DateFormatter templates ("M月d日" / "M月d日 HH:mm") don't count — those are
    /// format strings, not copy.
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

    // MARK: - Network timeouts & fetch budgets

    /// `URLSession.shared`'s resource timeout is 7 days; an endpoint that connects
    /// but trickles (FPL bootstrap-static has hung 30s+ without finishing) would make
    /// `await` never return — an endless spinner and a frozen UI. Guard: the timeouts
    /// must be finite.
    func testAPIClientTimeoutsAreFinite() {
        let cfg = APIClient.session.configuration
        XCTAssertLessThan(cfg.timeoutIntervalForResource, 120,
                          "the overall resource timeout must be bounded, or slow endpoints hang forever")
        XCTAssertLessThanOrEqual(cfg.timeoutIntervalForRequest, cfg.timeoutIntervalForResource)
        XCTAssertFalse(cfg.waitsForConnectivity, "offline should fail immediately so fallback data takes over")

        let imgCfg = APIClient.imageSession.configuration
        XCTAssertLessThanOrEqual(imgCfg.timeoutIntervalForResource, cfg.timeoutIntervalForResource,
                                 "crests are nice-to-have; their timeout must be no looser than the main data's")
    }

    /// The normal fast path: finishes within budget, returns the real value.
    func testWithTimeBudgetReturnsValueWhenFast() async {
        let value = await withTimeBudget(seconds: 5) { 42 }
        XCTAssertEqual(value, 42)
    }

    /// The critical path: an operation over budget must return nil rather than wait forever.
    func testWithTimeBudgetGivesUpWhenOperationIsSlow() async {
        let started = Date()
        let value = await withTimeBudget(seconds: 1) { () -> Int in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // far over budget
            return 42
        }
        XCTAssertNil(value, "over budget should give up and return nil")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "giving up must be decisive: a 1-second budget shouldn't wait 30")
    }

    /// When the data source itself returns nil (no data), pass that nil through
    /// faithfully — don't conflate it with a timeout.
    func testWithTimeBudgetPropagatesNilResult() async {
        let value: Int? = await withTimeBudget(seconds: 5) { nil }
        XCTAssertNil(value)
    }

    // MARK: - Current-round derivation (pure functions)

    func testDeriveCurrentRoundPrefersIsCurrent() {
        let events = [
            FPLGameweek(id: 1, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 2, name: nil, is_current: false, is_next: true,  finished: false, deadline_time: nil),
            FPLGameweek(id: 3, name: nil, is_current: true,  is_next: false, finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(events), 3, "is_current has the highest priority")
    }

    func testDeriveCurrentRoundFallsBackToNextThenLatestFinished() {
        // No is_current → take is_next
        let noCurrent = [
            FPLGameweek(id: 1, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 2, name: nil, is_current: false, is_next: true,  finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(noCurrent), 2)

        // No is_current / is_next → take the latest finished round
        let onlyFinished = [
            FPLGameweek(id: 5, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 7, name: nil, is_current: false, is_next: false, finished: true, deadline_time: nil),
            FPLGameweek(id: 8, name: nil, is_current: false, is_next: false, finished: false, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(onlyFinished), 7)

        // Nothing at all → fall back to the first round
        let empty = [
            FPLGameweek(id: 4, name: nil, is_current: nil, is_next: nil, finished: nil, deadline_time: nil),
        ]
        XCTAssertEqual(DataRepository.deriveCurrentRound(empty), 4)

        XCTAssertNil(DataRepository.deriveCurrentRound([]), "an empty list returns nil")
    }

    /// The local fallback when FPL events are unavailable (timeout / network failure):
    /// take the first round with unfinished matches; if all are finished, the last
    /// round with any matches.
    func testInferCurrentRoundFromMatches() {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: 2),
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 3),
        ]
        XCTAssertEqual(vm.inferCurrentRoundFromMatches(), 2,
                       "round 1 fully played, round 2 not started → the current round is 2")

        // All finished → the last round with matches
        let allDone = FixturesViewModel()
        allDone.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(allDone.inferCurrentRoundFromMatches(), 2)

        XCTAssertNil(FixturesViewModel().inferCurrentRoundFromMatches(), "no data returns nil")
    }

    /// `CurrentRoundInference` is the fallback rule shared by the fixtures and today
    /// pages, covered on its own: the first round with unfinished matches; if all are
    /// finished, the last round with matches.
    func testCurrentRoundInferenceSharedByBothPages() {
        let ongoing = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 3),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "IN_PLAY", matchday: 4),
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: ongoing), 4,
                       "a live match also counts as unfinished → the current round is 4")

        // Shuffled input must still infer correctly (sorted internally)
        let shuffled = [
            makeMatch(id: 3, kickoff: "2025-09-04T14:00:00Z", status: "SCHEDULED", matchday: 9),
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: 6),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: shuffled), 6)

        // All finished → the last round with matches
        let allDone = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: allDone), 2)

        // Matches with a nil matchday are ignored and don't affect the inference
        let withNil = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-28T14:00:00Z", status: "SCHEDULED", matchday: nil),
        ]
        XCTAssertEqual(CurrentRoundInference.infer(from: withNil), 1)

        XCTAssertNil(CurrentRoundInference.infer(from: []), "an empty fixture list returns nil")
    }

}
