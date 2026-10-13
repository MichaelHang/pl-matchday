import XCTest
@testable import EPLViewer

// Today page: filtering / featured card / live minutes.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    // MARK: - Today filtering

    /// `matchday` is optional: nil means FPL hasn't assigned a round yet (real data
    /// does this), covering "unassigned matches must not affect round inference".
    func makeMatch(id: Int, kickoff: String, status: String?, matchday: Int? = 1) -> Match {
        let team = Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
                        venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: team, awayTeam: team, score: nil)
    }

    /// Like makeMatch but with distinct home/away teams (for featured-pick tests
    /// that need "the sum of two ranks").
    func makeMatchTeams(id: Int, home: Int, away: Int, kickoff: String,
                                status: String?, matchday: Int? = 1) -> Match {
        let h = Team(id: home, name: "H\(home)", shortName: "H\(home)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        let a = Team(id: away, name: "A\(away)", shortName: "A\(away)", crest: nil,
                     venue: nil, founded: nil, coach: nil, squad: nil)
        return Match(id: id, matchday: matchday, utcDate: kickoff, status: status,
                     stage: nil, homeTeam: h, awayTeam: a, score: nil)
    }

    /// Keep only "today in the selected time zone", ascending by kickoff.
    func testTodayFilterKeepsSameDaySorted() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // Reference: 2026-08-31 20:00 Beijing
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "IN_PLAY"),   // 21:00 Beijing, same day
            makeMatch(id: 2, kickoff: "2026-08-31T04:00:00Z", status: "FINISHED"),  // 12:00 Beijing, same day
            makeMatch(id: 3, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // next day 00:00 Beijing
            makeMatch(id: 4, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),  // yesterday
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertEqual(today.map(\.id), [2, 1], "keep only same-day matches, ascending by kickoff")
    }

    /// "Today" must follow the selected time zone: the same instant is tomorrow in
    /// Beijing but still today in London.
    func testTodayFilterRespectsSelectedTimeZone() throws {
        let beijing = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let london  = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 18:00 UTC → next day 02:00 Beijing; same day 19:00 London (BST UTC+1)
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T18:00:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T18:00:00Z", status: "IN_PLAY"),   // next day (BJ) / same day (LDN)
            makeMatch(id: 2, kickoff: "2026-08-31T02:00:00Z", status: "FINISHED"),  // same day in both
        ]

        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: beijing).map(\.id), [1])
        XCTAssertEqual(TodayFilter.todayMatches(from: matches, now: now, tz: london).map(\.id), [2, 1])
    }

    /// Today's matches grouped by status: live / upcoming / finished.
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

    /// Regression: a live match crossing midnight (23:30 Beijing kickoff running past
    /// 1 a.m.) kicked off "yesterday" but is playing right now — it must appear under
    /// Today, otherwise live matches would vanish.
    func testTodayFilterIncludesLiveMatchStartedYesterday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // Now: 2026-08-31 00:23 Beijing (16:23Z)
        // The United match kicked off 23:30 Beijing on Aug 30 → "yesterday" in this zone
        let now = try XCTUnwrap(parseKickoffDate("2026-08-30T16:23:00Z"))

        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T15:30:00Z", status: "IN_PLAY"),   // 23:30 Beijing, live across midnight
            makeMatch(id: 2, kickoff: "2026-08-30T13:00:00Z", status: "FINISHED"),  // 21:00 Beijing, finished yesterday → not today
            makeMatch(id: 3, kickoff: "2026-08-31T11:00:00Z", status: "SCHEDULED"), // 19:00 Beijing, today
        ]

        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        XCTAssertTrue(today.contains { $0.id == 1 }, "a live match must appear today even when it kicked off yesterday")
        XCTAssertFalse(today.contains { $0.id == 2 }, "a match finished yesterday must not appear today")
        XCTAssertTrue(today.contains { $0.id == 3 })
        XCTAssertEqual(today.map(\.id), [1, 3], "ascending by kickoff")
    }

    /// "Next match" takes the first strictly after now (one equal to now doesn't count).
    func testTodayNextMatchIsStrictlyAfterNow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T12:00:00Z", status: "FINISHED"),   // past
            makeMatch(id: 2, kickoff: "2026-08-31T12:00:00Z", status: "IN_PLAY"),    // == now
            makeMatch(id: 3, kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED"),
            makeMatch(id: 4, kickoff: "2026-09-05T12:00:00Z", status: "SCHEDULED"),
        ]
        XCTAssertEqual(TodayFilter.nextMatch(from: matches, now: now)?.id, 3)
    }

    // MARK: - Featured match selection

    /// Priority 1: live beats "upcoming".
    func testFeaturedPrefersLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // kicks off in 1 h
            makeMatch(id: 2, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY"),   // live
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// Priority 2: nothing live → the first kickoff within 3.5 h (outside the window doesn't count).
    func testFeaturedFallsBackToKickoffWithinThreeAndHalfHours() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED"), // +1h  → hit
            makeMatch(id: 2, kickoff: "2026-08-31T16:00:00Z", status: "SCHEDULED"), // +4h  → outside
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// Priority 3: nothing live or upcoming → today's most recently finished match.
    func testFeaturedFallsBackToMostRecentFinishedToday() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED"),  // 18:00 Beijing
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED"),  // 19:00 Beijing → more recent
            makeMatch(id: 3, kickoff: "2026-08-31T18:00:00Z", status: "SCHEDULED"), // +6h, outside the window
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// Priority 5: nothing to feature today → the current round's next match (may cross days).
    func testFeaturedFallsBackToNextMatchOfCurrentRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-30T10:00:00Z", status: "FINISHED", matchday: 5),  // yesterday
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // round 5's next match
            makeMatch(id: 3, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 6), // next round
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 2)
    }

    /// Priority 5: when kickoff times differ, take the earliest (never delay to a
    /// later marquee pairing for better ranks).
    func testFeaturedRoundNextPicksEarliestKickoffWhenTimesDiffer() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 10, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 17, middle time
            makeMatchTeams(id: 11, home: 3, away: 4,  kickoff: "2026-09-04T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 7 (best ranks), but latest
            makeMatchTeams(id: 12, home: 8, away: 9,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 17, earliest → hit
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4, 8: 8, 9: 9]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 12,
                       "with different kickoff times take the earliest (#8 vs #9); a later marquee pairing must not delay it")
    }

    /// Priority 5: same kickoff time, several matches → smallest rank sum wins.
    func testFeaturedRoundNextSameKickoffChosenByRankingSum() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 20, home: 2, away: 15, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 17
            makeMatchTeams(id: 21, home: 3, away: 4,  kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // same slot, sum 7 → hit
        ]
        let positions = [2: 2, 15: 15, 3: 3, 4: 4]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 21,
                       "same kickoff slot: smallest rank sum wins — #3 vs #4 (7) over #2 vs #15 (17)")
    }

    /// Priority 5: same slot and equal rank sum → the pair containing the better
    /// (lower) single rank wins.
    func testFeaturedRoundNextSameKickoffRankingTieBreakByBestTeam() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 7, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 9, best #2
            makeMatchTeams(id: 31, home: 1, away: 8, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // sum 9, best #1 → hit
        ]
        let positions = [1: 1, 8: 8, 2: 2, 7: 7]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 31,
                       "equal slot and sum (both 9): the match containing the league leader wins — #1 vs #8 over #2 vs #7")
    }

    /// Priority 5: a lone match in the earliest slot is picked outright — never
    /// delayed for a later marquee pairing.
    func testFeaturedRoundNextEarliestSlotSingleMatchPickedDirectly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 40, home: 10, away: 11, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // earliest and alone → hit
            makeMatchTeams(id: 41, home: 1,  away: 2,  kickoff: "2026-09-02T12:00:00Z", status: "SCHEDULED", matchday: 5), // later (better ranks, ignored)
        ]
        let positions = [10: 10, 11: 11, 1: 1, 2: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: positions)?.id, 40,
                       "a lone earliest-slot match is taken directly; never delay across slots for a marquee pairing")
    }

    /// Missing ranks (timeout / no standings data) must degrade gracefully to
    /// "earliest kickoff" — no crash.
    func testFeaturedRoundNextFallsBackToKickoffWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 30, home: 2, away: 15, kickoff: "2026-09-03T10:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatchTeams(id: 31, home: 3, away: 4,  kickoff: "2026-09-01T10:00:00Z", status: "SCHEDULED", matchday: 5), // earliest → hit
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz, positions: [:])?.id, 31,
                       "missing ranks must fall back to the earliest kickoff, not error or mispick")
    }

    /// Priority 6: the round is over → the round's first match (earliest kickoff).
    func testFeaturedFallsBackToFirstMatchOfFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let matches = [
            makeMatch(id: 1, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5), // round's earliest
            makeMatch(id: 2, kickoff: "2026-08-29T14:00:00Z", status: "FINISHED", matchday: 5),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 5, now: now, tz: tz)?.id, 1)
    }

    /// Round **fully finished** → the featured card should show the round's marquee
    /// pairing, not merely the earliest kickoff.
    ///
    /// Regression (user-reported): with round 3 fully played the card showed
    /// Liverpool's early game; expected Arsenal vs Chelsea (smallest rank sum).
    ///
    /// Routing: with currentRound = 3, priority 5 (round's **unplayed**) is empty and
    /// now is not a matchday (3/4 skip) → falls through to **priority 6**.
    func testFeaturedFinishedRoundPicksMarqueeNotEarliestKickoff() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // now = two days after round 3, not a matchday → priorities 3 (finished today) / 4 (upcoming today) miss
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
            // Round 3: all finished. id 1 kicked off earliest (11:00 Beijing), id 2 latest but smallest rank sum
            m(1, liv, bha, "2026-08-30T03:00:00Z", 3, "FINISHED"),   // Liverpool early game
            m(2, ars, che, "2026-08-30T06:00:00Z", 3, "FINISHED"),   // Arsenal vs Chelsea (marquee)
            m(3, bha, liv, "2026-08-30T09:00:00Z", 3, "FINISHED"),
            // Round 4 scheduled but unplayed — currentRound is still 3, so priority 5 won't fire
            m(4, ars, bha, "2026-09-05T11:00:00Z", 4, "SCHEDULED"),
        ]
        // Ranks: Arsenal 1 / Chelsea 3 (sum 4); Liverpool 8 / Brighton 15 (sum 23)
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "with the round finished show the marquee pairing (Arsenal vs Chelsea), " +
                       "not the earliest-kickoff Liverpool game")
    }

    /// Control group: priority 5 (round's **next unplayed**) is still time-first —
    /// within a round, different kickoff times take the earliest; a stronger pairing
    /// later must not push the pick. Locks in "the priority-6 change didn't harm 5".
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
            // Round 3 still has unplayed matches → priority 5: earliest kickoff (id 2), not the higher-ranked id 3
            m(2, liv, bha, "2026-09-05T11:00:00Z", 3, "SCHEDULED"),  // earliest
            m(3, ars, che, "2026-09-05T14:00:00Z", 3, "SCHEDULED"),  // later but more marquee
        ]
        let positions = [57: 1, 61: 3, 64: 8, 397: 15]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "priority 5 stays time-first: earliest of the round's unplayed, never pushed later by ranks")
    }

    // MARK: - QA: priority 6 edges & error paths

    /// Round finished + `positions` entirely missing (standings timeout / failure) →
    /// must fall back to the round's earliest kickoff; no crash, no nil.
    ///
    /// This is also the **sentinel overflow** regression test: with both ranks
    /// unknown, `rankKey` computes Int.max/2 + Int.max/2; an overflow would trap in
    /// debug builds (signal 5) crashing the whole test process rather than failing
    /// one case — reaching here proves no overflow.
    func testFeaturedFinishedRoundFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3),
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // earliest
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: [:])
        XCTAssertNotNil(picked, "with all ranks missing, never return nil — fall back to the round's earliest kickoff")
        XCTAssertEqual(picked?.id, 2, "with all ranks missing, fall back to the round's earliest (id 2)")
    }

    /// Matches where neither team has a rank should **sink**, yielding to matches
    /// with known ranks (the Int.max/2 sentinel semantics).
    func testFeaturedFinishedRoundRanksUnknownTeamsLast() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // Both ranks unknown → sinks (even with the earliest kickoff)
            makeMatchTeams(id: 1, home: 91, away: 92, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // Ranks known and smallest → hit (later kickoff irrelevant; the round is over)
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [23: 5, 24: 7]   // 91 / 92 missing
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2, "unknown-rank matches should sink behind known, smallest-sum matches")
    }

    /// Partially missing `positions` (only one team ranked) → the sentinel pushes
    /// that match out. Pins current behavior for future debate (see the QA report).
    func testFeaturedFinishedRoundPartialPositionsSinkTheMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            // Leader (#1) vs unranked → sum ≈ Int.max/2 + 1, pushed out
            makeMatchTeams(id: 1, home: 1, away: 99, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3),
            // Mid-table vs mid-table, both known → sum 21
            makeMatchTeams(id: 2, home: 10, away: 11, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 10: 10, 11: 11]   // 99 missing
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 2,
                       "partial data: the fully-known match (sum 21) should win; " +
                       "leader + unknown (sum ≈ Int.max/2) is pushed out by the sentinel — current behavior, not a crash")
    }

    /// A **perfect** rank-sum tie (`min(by:)` semantics) must stably return the
    /// earliest kickoff, never jump randomly.
    func testFeaturedFinishedRoundTieReturnsEarliestStable() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // Identical rankKeys: (1+8, min(1,8)) == (8+1, min(8,1)) == (9, 1)
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 8, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // earliest
            makeMatchTeams(id: 2, home: 8, away: 1, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let positions = [1: 1, 8: 8]
        // Repeat to confirm stability, not coincidence
        for _ in 0..<20 {
            let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                            now: now, tz: tz, positions: positions)
            XCTAssertEqual(picked?.id, 1, "with identical sums and best ranks, stably return the earliest kickoff")
        }
    }

    /// The true global minimum sits mid-array, with a later next-round match as noise.
    func testFeaturedFinishedRoundPicksTrueMinimumAmongMany() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // sum 30
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T04:00:00Z", status: "FINISHED", matchday: 3), // sum 12
            makeMatchTeams(id: 3, home: 25, away: 26, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // sum 25
            makeMatchTeams(id: 4, home: 27, away: 28, kickoff: "2026-08-30T06:00:00Z", status: "FINISHED", matchday: 3), // sum  8 ← minimum, mid-array
            makeMatchTeams(id: 5, home: 29, away: 30, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // sum 40
            // Next round scheduled: currentRound is still 3, must not be picked
            makeMatchTeams(id: 6, home: 31, away: 32, kickoff: "2026-09-05T11:00:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 25: 12, 26: 13,
                         27: 3, 28: 5, 29: 20, 30: 20, 31: 1, 32: 2]
        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 4,
                       "pick the smallest rank sum (8); the minimum is neither first nor last, " +
                       "and the next round (id 6, sum 3 but round 4) must not be chosen")
    }

    /// The current round has no matches at all → nil, no crash.
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
                     "a currentRound with no matches should return nil")
        XCTAssertNil(TodayFeatured.pick(from: [], currentRound: 3,
                                        now: now, tz: tz, positions: positions),
                     "empty matches should return nil")
    }

    /// The engineer's stated reason for not reusing `chooseByRanking` must hold: it
    /// narrows to the earliest kickoff batch first, degenerating to "earliest
    /// kickoff" when the round's kickoffs differ — exactly the bug that was fixed.
    /// Proves with plain data that the two differ in the priority-6 scenario.
    func testChooseByRankingWouldCollapseToEarliestForFinishedRound() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-01T12:00:00Z"))
        // Round fully finished; three different kickoff times
        let matches = [
            makeMatchTeams(id: 1, home: 21, away: 22, kickoff: "2026-08-30T03:00:00Z", status: "FINISHED", matchday: 3), // sum 30, earliest
            makeMatchTeams(id: 2, home: 23, away: 24, kickoff: "2026-08-30T05:00:00Z", status: "FINISHED", matchday: 3), // sum 12
            makeMatchTeams(id: 3, home: 27, away: 28, kickoff: "2026-08-30T07:00:00Z", status: "FINISHED", matchday: 3), // sum  8 ← minimum
        ]
        let positions = [21: 10, 22: 20, 23: 5, 24: 7, 27: 3, 28: 5]

        let picked = TodayFeatured.pick(from: matches, currentRound: 3,
                                        now: now, tz: tz, positions: positions)
        XCTAssertEqual(picked?.id, 3, "priority 6 crosses time slots and picks the smallest rank sum")

        // Degenerating to "earliest kickoff" would pick id 1 — the user-reported bug
        let earliest = matches.min(by: { $0.utcDate ?? "" < $1.utcDate ?? "" })
        XCTAssertEqual(earliest?.id, 1, "the earliest kickoff is id 1 (the Liverpool-early-game style wrong answer)")
        XCTAssertNotEqual(picked?.id, earliest?.id,
                          "after the fix the pick must differ from the earliest kickoff — proving ranks were compared across slots")
    }

    // MARK: - QA: priorities 2 / 4 same-slot ranking (regression for the reported defect)

    /// Priority 2 (kickoff within 3.5 h) with several same-slot matches → smallest
    /// rank sum, not "first in array order".
    ///
    /// Scenario (real defect, 2026-09-12): 13:57 London, several matches kick off at
    /// 15:00 BST (14:00Z), 63 min away — inside the 3.5 h window. FPL fixtures listed
    /// the worst-ranked match first (sum 34) and it stole the slot before the fix;
    /// by rank, the smallest sum should win.
    ///
    /// The winning match (id 3) is deliberately placed **third** in the array to
    /// prove the pick is "by rank", not "by accident of position".
    func testFeaturedSoonWindowSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // 13:57 London (BST) = 12:57Z; 15:00 BST = 14:00Z, 63 min from now
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // First in the array but worst ranks (18 + 16 = 34) — it stole the slot before the fix
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // sum 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // sum 7 → hit
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "same kickoff slot: smallest rank sum (7) wins, " +
                       "not the first array entry (34)")
    }

    /// Control: priority 2 stays time-first — a lone earliest-slot match (even badly
    /// ranked) is taken directly; never delay for a "stronger" pairing.
    func testFeaturedSoonWindowPicksEarliestSlotNotMarquee() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            // Lone earliest slot (14:00Z), worst ranks (sum 34) → must be picked
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4),
            // Later (14:15Z), excellent ranks (sum 3) → must not delay the pick
            makeMatchTeams(id: 2, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        let positions = [2: 18, 7: 16, 4: 1, 5: 2]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 1,
                       "a lone earliest-slot match is taken directly; never delay across slots")
    }

    /// Backwards compatibility: empty `positions` → priority 2 still returns the
    /// earliest kickoff, exactly like the old `first(where:)`, without crashing.
    func testFeaturedSoonWindowFallsBackToEarliestWhenPositionsMissing() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T14:30:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED", matchday: 4), // earliest → hit
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T14:15:00Z", status: "SCHEDULED", matchday: 4),
        ]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: [:])?.id, 2,
                       "missing ranks must fall back to the earliest kickoff (id 2), same as before")
    }

    /// Priority 4 (today's next unplayed) same-slot matches → smallest rank sum too.
    /// Kickoff is >3.5 h away (priority 2 skipped) but still the same London day →
    /// priority 4.
    func testFeaturedTodayUpcomingSameKickoffChosenByRanking() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:57:00Z"))
        // 18:00Z = 19:00 BST (same London day), 5 h 3 m from now > 3.5 h → priority 2 misses
        let matches = [
            makeMatchTeams(id: 1, home: 2, away: 7, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4),
            makeMatchTeams(id: 2, home: 3, away: 6, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // sum 17
            makeMatchTeams(id: 3, home: 4, away: 5, kickoff: "2026-09-12T18:00:00Z", status: "SCHEDULED", matchday: 4), // sum 7 → hit
        ]
        let positions = [2: 18, 7: 16, 3: 8, 6: 9, 4: 4, 5: 3]
        XCTAssertEqual(TodayFeatured.pick(from: matches, currentRound: 4,
                                          now: now, tz: tz, positions: positions)?.id, 3,
                       "same-slot today's-upcoming matches also pick the smallest rank sum")
    }

    // MARK: - Bottom row, column 2 (today's fixtures)

    /// Column 2 takes only today's upcoming and excludes the featured match.
    func testTodayColumnsExcludesFeaturedMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5

        // ① Several today's upcoming → the featured card takes the earliest, column 2 keeps the rest
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5), // +1h → featured
            makeMatch(id: 2, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5), // 23:00 Beijing
        ]
        let c1 = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(c1.upcoming.map(\.id), [2], "the featured match must not duplicate into column 2")

        // ② Only the featured match is left unplayed today → column 2 empty (no round fallback)
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5), // featured
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5), // round 5 continues, but not today
        ]
        let c2 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c2.upcoming.isEmpty, "column 2 is today-only; no fallback to the round's next match")

        // ③ Nothing upcoming today (only finished) → column 2 empty
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2026-09-02T10:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let c3 = vm.columns(tz: tz, now: now)
        XCTAssertTrue(c3.upcoming.isEmpty)
    }

    /// Round fully finished → column 2 must **not** jump to the next round; stays
    /// empty ("no data").
    func testTodayColumnsDoesNotFallBackToNextEvent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        // 20:00 Beijing, 2026-08-31
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // finished today → featured
            makeMatch(id: 2, kickoff: "2026-08-29T10:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-09-05T10:00:00Z", status: "SCHEDULED", matchday: 6), // next round
            makeMatch(id: 4, kickoff: "2026-09-05T14:00:00Z", status: "SCHEDULED", matchday: 7),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertTrue(cols.upcoming.isEmpty, "still round 5 — rounds 6/7 must not spill onto the Today page")
    }

    /// Column 1 merges live & recent: live first, today's finished after (most recent first).
    func testTodayColumnsFirstColumnShowsLiveAndRecent() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "IN_PLAY", matchday: 5),      // earliest live → featured
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),      // live
            makeMatch(id: 3, kickoff: "2026-08-31T08:00:00Z", status: "FINISHED", matchday: 5),     // finished today (later)
            makeMatch(id: 4, kickoff: "2026-08-31T07:00:00Z", status: "FINISHED", matchday: 5),     // finished today (earlier)
            makeMatch(id: 5, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5),     // yesterday, not today
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2, 3, 4], "live first (kickoff ascending), finished after (most recent first)")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// With no live matches, column 1 lists only today's finished; title degrades to "Recent".
    func testTodayColumnsFirstColumnRecentOnly() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T10:00:00Z", status: "FINISHED", matchday: 5), // finished today
            makeMatch(id: 2, kickoff: "2026-08-31T11:00:00Z", status: "FINISHED", matchday: 5), // today's latest → featured
            makeMatch(id: 3, kickoff: "2026-08-30T11:00:00Z", status: "FINISHED", matchday: 5), // yesterday, not today
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 2, "the featured card takes today's most recently finished")
        XCTAssertEqual(cols.live.map(\.id), [1], "column 1 lists the rest of today's finished matches")
        XCTAssertEqual(cols.liveSource, .recent)
    }

    /// With live matches, column 1 must not duplicate the featured match.
    func testTodayColumnsFirstColumnExcludesFeaturedLiveMatch() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),     // featured
            makeMatch(id: 2, kickoff: "2026-08-31T10:30:00Z", status: "IN_PLAY", matchday: 5),     // another live match
            makeMatch(id: 3, kickoff: "2026-08-31T14:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertEqual(vm.featured(tz: tz, now: now)?.id, 1)
        XCTAssertEqual(cols.live.map(\.id), [2], "with live matches, column 1 must not duplicate the featured match")
        XCTAssertEqual(cols.liveSource, .liveAndRecent)
    }

    /// In every scenario the featured match never appears in column 2.
    func testTodayColumnsNeverDuplicatesFeatured() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(parseKickoffDate("2026-08-31T12:00:00Z"))
        let vm = TodayViewModel()
        vm.currentRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2026-08-31T09:00:00Z", status: "IN_PLAY", matchday: 5),    // live
            makeMatch(id: 2, kickoff: "2026-08-31T13:00:00Z", status: "SCHEDULED", matchday: 5),
            makeMatch(id: 3, kickoff: "2026-08-31T15:00:00Z", status: "SCHEDULED", matchday: 5),
        ]
        let featured = try XCTUnwrap(vm.featured(tz: tz, now: now))
        XCTAssertEqual(featured.id, 1, "a live match becomes the featured card first")
        let cols = vm.columns(tz: tz, now: now)
        XCTAssertFalse(cols.upcoming.contains { $0.id == featured.id })
        XCTAssertEqual(cols.upcoming.map(\.id), [2, 3])
    }

    // MARK: - QA: changes 1 / 2 / 3

    /// Slice from `from` up to (excluding) `to`; nil `to` runs to the end.
    func qaSlice(_ s: String, from: String, to: String? = nil) -> String? {
        guard let lo = s.range(of: from) else { return nil }
        let rest = s[lo.lowerBound...]
        guard let to, let hi = rest.range(of: to) else { return String(rest) }
        return String(rest[rest.startIndex..<hi.lowerBound])
    }

    // ── Change 1: the featured card got a pinned gradient background ──

    /// The gradient must be a pinned `Color` literal — never the system accent / AppState.
    func testFeaturedCardGradientIsHardcodedNotAccentDriven() throws {
        let src = try sourceFile("TodayView.swift")
        let block = try XCTUnwrap(
            qaSlice(src, from: "let featuredCardGradient", to: "\n)"),
            "featuredCardGradient constant declaration not found"
        )
        XCTAssertTrue(block.contains("LinearGradient"), "the card background should be a LinearGradient")
        XCTAssertEqual(count(of: "Color(red:", in: block), 2, "one pinned Color per gradient end")
        XCTAssertTrue(block.contains("startPoint: .leading"), "gradient should run left → right")
        XCTAssertTrue(block.contains("endPoint: .trailing"), "gradient should run left → right")
        for forbidden in ["AppState", "accent", "Accent", "NSColor", "@Environment", ".tint"] {
            XCTAssertEqual(count(of: forbidden, in: block), 0,
                           "\(forbidden) appeared in the gradient — it would follow the system accent again")
        }
    }

    /// `FeaturedMatchCard` must contain no `.glassEffect`; the columnCard's Liquid
    /// Glass must stay.
    func testFeaturedCardDroppedGlassEffectButColumnCardKeptIt() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "FeaturedMatchCard not found")
        XCTAssertEqual(count(of: "glassEffect", in: card), 0,
                       ".glassEffect remains in FeaturedMatchCard — the background wasn't fully replaced")

        let columnCard = try XCTUnwrap(
            qaSlice(code, from: "func columnCard", to: "struct FeaturedMatchCard"),
            "columnCard not found"
        )
        XCTAssertEqual(count(of: "glassEffect", in: columnCard), 1,
                       "columnCard's Liquid Glass is out of scope for that change and must stay")
        XCTAssertTrue(columnCard.contains("RoundedRectangle(cornerRadius: 12)"),
                      "columnCard's corner radius should stay 12")
    }

    /// The dimming overlay must share the outer corner radius, or the edges fray.
    func testFeaturedCardOverlaySharesCornerRadiusWithGradient() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let bg = try XCTUnwrap(qaSlice(card, from: ".background("), "the card's .background( not found")

        XCTAssertEqual(count(of: "cornerRadius:", in: bg), 2,
                       "exactly two corner radii in the background: the gradient + the dim overlay")
        XCTAssertEqual(count(of: "RoundedRectangle(cornerRadius: featuredCardCornerRadius)", in: bg), 2,
                       "both must use the featuredCardCornerRadius constant, not hardcoded numbers")
        XCTAssertTrue(bg.contains(".fill(featuredCardGradient)"), "the gradient isn't filled into the background")
        XCTAssertTrue(bg.contains(".fill(Color.black.opacity(0.12))"), "missing the dim overlay")
    }

    /// Background only: corner radius / padding / crest size / score font / insets
    /// must all stay untouched.
    func testFeaturedCardLayoutConstantsUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        XCTAssertTrue(code.contains("let featuredCardCornerRadius: CGFloat = 12"),
                      "the card corner radius should stay 12")
        XCTAssertTrue(code.contains("let featuredCardSideInset: CGFloat = 40"),
                      "the team-block inset should stay 40")

        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        XCTAssertTrue(card.contains("CrestImage(urlString: team.crest, size: 56)"),
                      "the crest should render at 56×56 (CrestImage.size; an outer .frame can't scale a fixed-size child)")
        XCTAssertTrue(card.contains(".system(size: 44, weight: .bold, design: .rounded)"),
                      "the score font should stay 44")
        XCTAssertTrue(card.contains(".padding(22)"), "card padding should stay 22")
        XCTAssertTrue(card.contains("padding(.horizontal, featuredCardSideInset)"),
                      "the middle team blocks should keep the featuredCardSideInset")
        XCTAssertTrue(card.contains("VStack(spacing: 18)"), "card vertical spacing should stay 18")
        XCTAssertTrue(card.contains("Spacer(minLength: 24)"), "the score's side spacing minimum should stay 24")
    }

    /// After switching to the pinned magenta→pink gradient, is the text readable in
    /// **light mode**?
    ///
    /// Fix: force dark semantics on the card subtree
    /// (`.environment(\.colorScheme, .dark)`) so `.primary` / `.secondary` / the
    /// default foreground resolve to white/light-gray even in light mode — instead of
    /// near-black on magenta (WCAG contrast a mere 1.71:1). Verified here by WCAG
    /// relative luminance: white text vs both gradient ends (after the 0.12 dimming)
    /// must clear the AA large-text bar of 3.0.
    func testFeaturedCardGradientKeepsTextReadableInLightMode() throws {
        let src = try sourceFile("TodayView.swift")

        // The core of the fix: the card subtree must force dark semantics
        XCTAssertTrue(src.contains(".environment(\\.colorScheme, .dark)"),
                      "the card must force dark semantics (.environment(\\.colorScheme, .dark)); otherwise light-mode text on magenta is nearly unreadable")

        let block = try XCTUnwrap(qaSlice(src, from: "let featuredCardGradient", to: "\n)"))

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
        XCTAssertEqual(stops.count, 2, "both gradient stops should parse")

        // Dim layer: 0.12 black over the gradient
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

        // Under dark semantics .primary / default foreground == white (luminance 1)
        let white: Double = 1.0
        // WCAG AA large text (≥24pt) minimum 3.0 — the loosest tier, to avoid false alarms
        let bar = 3.0
        for (i, s) in stops.enumerated() {
            let eff = (s.0 * (1 - dim), s.1 * (1 - dim), s.2 * (1 - dim))
            let ratio = contrast(luminance(eff), white)
            XCTAssertGreaterThanOrEqual(
                ratio, bar,
                "gradient stop \(i) (rgb \(s)) after the 0.12 dim layer has only " +
                String(format: "%.2f", ratio) + ":1 contrast against white — below \(bar):1"
            )
        }
    }

    // ── Change 2: status badge moved left + the "featured match" copy removed ──

    /// `UIString.featured` must be fully gone; confirm what was deleted was the copy,
    /// not the `vm.featured(...)` picker.
    func testFeaturedUIStringIsFullyRemovedButPickerSurvives() throws {
        for f in try allSourceFiles() {
            XCTAssertEqual(count(of: "UIString.featured", in: f.text), 0,
                           "\(f.name) still contains UIString.featured — the removed copy came back")
        }
        let strings = try sourceFile("UIStrings.swift")
        XCTAssertEqual(count(of: "featured", in: strings), 0,
                       "UIStrings.swift should have no featured entries left")

        // ⚠️ Counter-guard: the **picker method** must be intact, never mis-deleted
        let today = try sourceFile("TodayView.swift")
        XCTAssertTrue(today.contains("func featured(tz: TimeZone, now: Date = Date()) -> Match?"),
                      "TodayViewModel.featured(tz:now:) was deleted — a serious regression")
        XCTAssertTrue(today.contains("enum TodayFeatured"),
                      "the TodayFeatured enum was deleted — a serious regression")
        XCTAssertTrue(today.contains("func pick(from matches: [Match]"),
                      "TodayFeatured.pick was deleted — a serious regression")
        XCTAssertTrue(today.contains("if let featured = vm.featured(tz: timeZone)"),
                      "the Today page still uses vm.featured(...) for the featured match")
    }

    /// Behavioral confirmation the picker still works (not just "the symbol exists").
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
                       "a live match becomes the featured card first — featured(tz:now:) still works")
    }

    /// Top row: round → status badge (left) → Spacer; no "featured match" copy.
    func testFeaturedCardTopRowIsRoundBadgeThenSpacer() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"))
        let top = try XCTUnwrap(qaSlice(card, from: "HStack(spacing: 8) {", to: "\n            }"),
                                "the card's top HStack not found")

        XCTAssertFalse(top.contains("UIString.featured"), "no 'featured match' copy in the top row")
        XCTAssertTrue(top.contains("UIString.roundN.text(lang)"), "the round goes through UIString.roundN")
        XCTAssertTrue(top.contains("statusBadge(lang: lang)"), "the status badge follows the round")
        XCTAssertTrue(top.contains("Spacer()"), "a Spacer ends the row, filling the right side")

        // Order: round < badge < Spacer (badge left, Spacer last)
        let rRound = try XCTUnwrap(top.range(of: "UIString.roundN"))
        let rBadge = try XCTUnwrap(top.range(of: "statusBadge(lang: lang)"))
        let rSpacer = try XCTUnwrap(top.range(of: "Spacer()"))
        XCTAssertLessThan(rRound.lowerBound, rBadge.lowerBound, "the round precedes the badge")
        XCTAssertLessThan(rBadge.lowerBound, rSpacer.lowerBound, "badge left, Spacer last")
    }

    /// `UIString.roundN` must survive, serving both the Today page and the fixtures page.
    func testRoundNStringStillServesTwoCallSites() throws {
        XCTAssertEqual(UIString.roundN.text(.chinese), "第 %d 轮")
        XCTAssertEqual(UIString.roundN.text(.english), "Round %d")
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.chinese)), 1)
        XCTAssertEqual(count(of: "%d", in: UIString.roundN.text(.english)), 1,
                       "mismatched placeholder counts would feed String(format:) dirty arguments")

        let today = codeOnly(try sourceFile("TodayView.swift"))
        let fixtures = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.roundN", in: today), 1,
                       "the Today featured card should still show the round")
        XCTAssertEqual(count(of: "UIString.roundN", in: fixtures), 1,
                       "the season-overview cards should still show the round")
    }

    // ── Change 3: paging moves only the window, never focusedRound ──

    /// The paging function bodies must not mention `focusedRound` — locking out
    /// "paging changes focus" at the source.
    func testPagingFunctionsNeverTouchFocusedRound() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        let paging = try XCTUnwrap(
            qaSlice(code, from: "func pageRoundsBackward", to: "func groupedSections"),
            "the two paging functions not found"
        )
        XCTAssertEqual(count(of: "focusedRound", in: paging), 0,
                       "paging functions must not rewrite focusedRound — paging only moves the chip viewport")
        XCTAssertTrue(paging.contains("clampWindowStart()"),
                      "both paging functions must clamp back into range")
    }

    /// The big title reads `vm.focusedRound`, not the window's first round — the
    /// title must stay stable while paging.
    func testFixturesHeaderReadsFocusedRoundNotWindow() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "UIString.fixturesHeader", in: code), 1,
                       "the big title should appear exactly once")
        let section = try XCTUnwrap(
            qaSlice(code, from: "func thisRoundSection", to: "func seasonOverviewSection"),
            "thisRoundSection not found"
        )
        XCTAssertTrue(section.contains("UIString.fixturesHeader.text(lang), vm.focusedRound"),
                      "the title must read vm.focusedRound so it never jumps while paging")
        XCTAssertFalse(section.contains("visibleRounds.first"),
                       "the title must not follow the window's first round")
    }

    /// Paging round trip: 3 right + 3 left returns both window and highlight, with
    /// focusedRound constant throughout.
    ///
    /// ⚠️ Deliberately 3 steps: from start 17, four right steps hit the bound 33
    /// (clamp), and then four lefts can't return to 17 (asymmetry is normal clamp
    /// behavior, not a bug).
    func testPagingRoundTripKeepsFocusedRoundAndRestoresWindow() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "initial centering: MD20 centered → start 17")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22])

        let originalStart = vm.roundWindowStart
        let shownMDs = vm.displayed.map(\.matchday)

        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 32, "3 right: 17 → 22 → 27 → 32")
        XCTAssertEqual(vm.visibleRounds, [33, 34, 35, 36, 37])
        XCTAssertEqual(vm.focusedRound, 20, "paging never changes focusedRound")
        XCTAssertEqual(vm.displayed.map(\.matchday), shownMDs, "the content area keeps showing MD20")

        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "3 left restores the window")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "back at the original window, MD20 highlights again")
        XCTAssertEqual(vm.focusedRound, 20, "after the round trip MD20 is still focused")
        XCTAssertTrue(vm.visibleRounds.contains(vm.focusedRound))
    }

    /// Single forward page: the window moves exactly MD18–22 → MD23–27 (a full
    /// window-size shift).
    func testSingleForwardPageShiftsWindowByExactlyFive() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20

        vm.pageRoundsForward()
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27], "one page right → MD23–MD27")
        XCTAssertEqual(vm.focusedRound, 20, "focusedRound untouched")

        vm.pageRoundsBackward()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "one page left → back to MD18–MD22")
    }

    /// Initial centering holds: middle / left / right positions center / align
    /// left / align right, never out of bounds.
    func testWindowAlignmentCoversMiddleLeftRightEdges() {
        // Middle: MD20 → 2 before, 2 after
        let mid = FixturesViewModel()
        mid.matches = makeRounds(38)
        mid.roundWindowStart = 0
        mid.focusedRound = 20
        XCTAssertEqual(mid.visibleRounds, [18, 19, 20, 21, 22], "MD20 → centered")

        // Left: MD1 / MD2 / MD3 → start clamps to 0, never negative
        for r in [1, 2, 3] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 30
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 0, "MD\(r) near the left → start clamps to 0")
            XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        }

        // Right: MD36 / MD37 / MD38 → start clamps to the bound 33
        for r in [36, 37, 38] {
            let vm = FixturesViewModel()
            vm.matches = makeRounds(38)
            vm.roundWindowStart = 0
            vm.focusedRound = r
            XCTAssertEqual(vm.roundWindowStart, 33, "MD\(r) near the right → start clamps to 33")
            XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        }

        // Exactly one round more than a window (6 rounds) → bound 1; a second right
        // page still stops at the bound
        let six = FixturesViewModel()
        six.matches = makeRounds(6)
        six.focusedRound = 3
        XCTAssertEqual(six.roundWindowMaxStart, 1)
        six.pageRoundsForward()
        XCTAssertEqual(six.visibleRounds, [2, 3, 4, 5, 6])
        six.pageRoundsForward()
        XCTAssertEqual(six.roundWindowStart, 1, "another right page still stops at the bound")
    }

    /// Window invariants over the full matrix: count × focusedRound × paging steps,
    /// checking three invariants each.
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
                                             "count=\(count) focused=\(focused) fwd=\(step): window exceeds 5")
                    XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                                "count=\(count) focused=\(focused) fwd=\(step): negative start")
                    XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                             "count=\(count) focused=\(focused) fwd=\(step): start past the bound")
                    XCTAssertEqual(vm.visibleRounds.count,
                                   min(size, max(0, count - vm.roundWindowStart)),
                                   "count=\(count) focused=\(focused) fwd=\(step): wrong window slice length")
                    XCTAssertEqual(vm.focusedRound, focused,
                                   "count=\(count) fwd=\(step): paging changed focusedRound")

                    // Then page back. ⭐ The origin is not 0 but the post-alignment start.
                    // Exact expectations:
                    //   - no bound hit (alignedStart + 5·step <= maxStart) → back to alignedStart exactly;
                    //   - bound hit → landing is max(maxStart - 5·step, 0) (normal clamp, not a bug).
                    for _ in 0..<step { vm.pageRoundsBackward() }
                    let hitClamp = alignedStart + step * size > vm.roundWindowMaxStart
                    let expected = hitClamp
                        ? max(vm.roundWindowMaxStart - step * size, 0)
                        : alignedStart
                    XCTAssertEqual(vm.roundWindowStart, expected,
                                   "count=\(count) focused=\(focused) step=\(step): " +
                                   "round-trip landing unexpected (start \(alignedStart), bound \(vm.roundWindowMaxStart))")
                }
            }
        }
    }

    /// `roundChipBar`'s doc comment once claimed "the first round of the paged-to
    /// window automatically becomes the focused round" — exactly the behavior this
    /// change **removed**. A comment contradicting the code is worse than none.
    func testRoundChipBarDocCommentDoesNotClaimPagingChangesFocus() throws {
        let src = try sourceFile("FixturesView.swift")
        let doc = try XCTUnwrap(
            qaSlice(src, from: "\"This round\" mode's horizontal round switch", to: "func roundChipBar"),
            "roundChipBar's doc comment not found"
        )
        for stale in ["automatically becomes the focused round", "automatically becomes"] {
            XCTAssertEqual(count(of: stale, in: doc), 0,
                           "roundChipBar's doc comment still describes the removed 'paging changes focus' behavior: " + stale)
        }
    }

    // MARK: - QA: two Today-page changes (4 per column / live minutes)

    /// Table-driven coverage of every `formatLiveClock` branch (pure function).
    func testFormatLiveClockCoversAllBranches() {
        let cases: [(elapsed: Int, halftime: Bool, expected: String)] = [
            // First half (≤45): actual minutes
            (0, false, "0'"), (1, false, "1'"), (19, false, "19'"),
            (44, false, "44'"), (45, false, "45'"),
            // Halftime window 46–60 (status not yet HALFTIME) → clamp to 45'
            (46, false, "45'"), (50, false, "45'"), (60, false, "45'"),
            // Second half 61–105: minus the 15-minute break
            (61, false, "46'"), (75, false, "60'"), (90, false, "75'"), (105, false, "90'"),
            // Stoppage / very long → clamp to 90+'
            (106, false, "90+'"), (200, false, "90+'"),
            // Halftime: fixed 45' regardless of elapsed minutes
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

    /// Off-by-one at segment boundaries: each adjacent pair lands in the right segment.
    func testFormatLiveClockSegmentBoundariesAreExact() {
        let boundaries: [(elapsed: Int, expected: String, note: String)] = [
            (45,  "45'",  "end of first half"),
            (46,  "45'",  "halftime window → clamped"),
            (60,  "45'",  "end of halftime window"),
            (61,  "46'",  "second half starts → minus 15"),
            (105, "90'",  "end of second half"),
            (106, "90+'", "stoppage → clamped"),
        ]
        for b in boundaries {
            XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: b.elapsed, isHalftime: false),
                           b.expected, "boundary \(b.elapsed) (\(b.note))")
        }
    }

    /// Clock skew / premature IN_PLAY must never produce negative minutes.
    /// `elapsedMinutes` is now a pure function taking `now` (truly testable, see
    /// `testElapsedMinutesPureFunction`); this pins the declaration's structure so it
    /// can't regress into secretly reading `Date()`.
    func testElapsedMinutesClampsFutureKickoffToZero() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "elapsedMinutes not found"
        )
        XCTAssertTrue(decl.contains("max(0,"),
                      "elapsedMinutes must clamp negatives to 0 (clock skew must not go negative)")
        XCTAssertTrue(decl.contains("guard let kickoff else { return nil }") ||
                      decl.contains("guard let kickoff else {return nil}"),
                      "an unparseable kickoff must return nil for statusLine's fallback")
        XCTAssertTrue(decl.contains("floor("), "minutes should floor")
    }

    /// When kickoff parsing fails, statusLine's live branch must fall back to the
    /// "live" copy — no crash, no empty string.
    func testStatusLineFallsBackToLiveTextWhenKickoffMissing() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func statusLine", to: "func statusBadge"),
            "statusLine not found"
        )
        XCTAssertTrue(fn.contains("guard let elapsed = Self.elapsedMinutes(kickoff: kickoff, now: now) else { return UIString.live.text(lang) }"),
                      "without elapsed minutes the live branch must fall back to the live copy")
        XCTAssertTrue(fn.contains("Self.formatLiveClock(elapsed: elapsed"),
                      "the live branch should call the pure formatLiveClock")
        XCTAssertTrue(fn.contains("isHalftime: match.status == \"HALFTIME\""),
                      "halftime status must be passed to formatLiveClock")
        XCTAssertFalse(fn.contains("formatLiveClock(elapsed: elapsedMinutes!"),
                      "never force-unwrap elapsedMinutes")
    }

    /// The non-live branches (finished / upcoming) must be untouched.
    func testStatusLineNonLiveBranchesUntouched() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func statusLine", to: "func statusBadge"),
            "statusLine not found"
        )
        XCTAssertTrue(fn.contains("if TodayFilter.isFinished(match) { return UIString.statusFinished.text(lang) }"),
                      "finished should still return the finished copy")
        XCTAssertTrue(fn.contains("guard let kickoff else { return UIString.tbd.text(lang) }"),
                      "upcoming without a kickoff time should still fall back to TBD")
        XCTAssertTrue(fn.contains("df.dateFormat = lang == .english ? \"MMM d\" : \"M月d日\""),
                      "upcoming with a kickoff time should still return the date")
        // Order: live → finished → upcoming; the live check must come first
        guard let live = fn.range(of: "TodayFilter.isLive(match, now: now)"),
              let finished = fn.range(of: "TodayFilter.isFinished(match)") else {
            return XCTFail("statusLine is missing status branches")
        }
        XCTAssertLessThan(live.lowerBound, finished.lowerBound, "the live branch must come first")
    }

    // MARK: - Live minutes: pure function + TimelineView decoupling (fixes "frozen minutes")

    /// `elapsedMinutes(kickoff:now:)` all branches: with `now` explicit, time →
    /// minutes is fully unit-testable (the old version secretly read `Date()` and
    /// could only be checked by source scanning).
    func testElapsedMinutesPureFunction() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func mins(_ seconds: TimeInterval) throws -> Int {
            try XCTUnwrap(FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                           now: kickoff.addingTimeInterval(seconds)),
                          "elapsedMinutes must not be nil")
        }

        XCTAssertNil(FeaturedMatchCard.elapsedMinutes(kickoff: nil, now: kickoff),
                     "no kickoff time → nil")

        XCTAssertEqual(try mins(0), 0, "exactly at kickoff → 0'")
        XCTAssertEqual(try mins(-30), 0, "now before kickoff → clamp to 0, never negative")
        XCTAssertEqual(try mins(-3600), 0, "an hour of clock skew → still clamped to 0")
        XCTAssertEqual(try mins(59.9), 0, "59.9s hasn't crossed a minute → 0'")
        XCTAssertEqual(try mins(60.0), 1, "60.0s crosses exactly → 1'")
        XCTAssertEqual(try mins(60.5), 1, "60.5s still floors → 1'")
        XCTAssertEqual(try mins(16 * 60), 16, "the reported scenario: 16 minutes → 16'")
        XCTAssertEqual(try mins(6000), 100, "a long gap (100 minutes) → 100'")
    }

    /// The whole "time → display text" chain is pure: elapsedMinutes(now) composed
    /// with formatLiveClock asserts text directly.
    func testLiveMinuteTextChainIsPure() throws {
        let kickoff = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        func text(atSeconds seconds: TimeInterval, isHalftime: Bool = false) throws -> String {
            let elapsed = try XCTUnwrap(
                FeaturedMatchCard.elapsedMinutes(kickoff: kickoff,
                                                 now: kickoff.addingTimeInterval(seconds)))
            return FeaturedMatchCard.formatLiveClock(elapsed: elapsed, isHalftime: isHalftime)
        }
        XCTAssertEqual(try text(atSeconds: 4 * 60), "4'")
        XCTAssertEqual(try text(atSeconds: 16 * 60), "16'", "the user-reported frozen scenario")
        XCTAssertEqual(try text(atSeconds: 0), "0'")
        XCTAssertEqual(try text(atSeconds: 50 * 60, isHalftime: true), "45'", "halftime fixed at 45'")
    }

    /// Live minutes must hang off `TimelineView(.periodic(by: 1))` (a redraw source
    /// independent of data refreshes), otherwise SwiftUI skips the card body when
    /// `match` doesn't change and the minutes freeze.
    func testFeaturedCardLiveMinuteWrappedInTimelineView() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(qaSlice(code, from: "struct FeaturedMatchCard: View {"),
                                 "FeaturedMatchCard not found")
        XCTAssertEqual(count(of: "TimelineView(", in: card), 1,
                       "exactly one TimelineView for the live minutes")
        XCTAssertTrue(card.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "the TimelineView must be 1-second periodic to cross minute boundaries")

        // The TimelineView wraps only that one Text (in centerBlock's live branch), not the whole card
        let center = try XCTUnwrap(qaSlice(card, from: "func centerBlock",
                                           to: "func scoreRow"),
                                   "centerBlock not found")
        XCTAssertTrue(center.contains("TimelineView(.periodic(from: .now, by: 1))"),
                      "the TimelineView belongs only in centerBlock's live branch")
        XCTAssertTrue(center.contains("context.date"),
                      "the TimelineView closure should feed context.date as now into the status line")
        XCTAssertTrue(center.contains("Text(statusLine(lang: lang, now: Date()))"),
                      "the non-live branch still evaluates Date() once — no per-second redraws")
    }

    /// `elapsedMinutes` must not read `Date()` internally — the time source must be
    /// the explicit `now` parameter (the root fix for this bug).
    func testElapsedMinutesHasNoImplicitDateRead() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "static func elapsedMinutes", to: "static func formatLiveClock"),
            "elapsedMinutes not found"
        )
        XCTAssertFalse(decl.contains("Date()"),
                       "elapsedMinutes must not read Date() internally — callers (TimelineView) pass now")
        XCTAssertTrue(decl.contains("now: Date"), "elapsedMinutes should take now explicitly")
    }
}

extension EPLViewerTests {
    // MARK: - Featured card live-minute notation

    /// Guards `FeaturedMatchCard.formatLiveClock`'s branches.
    /// This is the user-requested contract "live → show minutes played (19')";
    /// the engineer deliberately made it a pure function without `Date()` so every
    /// branch is unit-testable. Branch rules: see `formatLiveClock` in TodayView.swift.
    func testFormatLiveClockBranches() throws {
        // Halftime: fixed 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 50, isHalftime: true), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: true), "45'")

        // First half (≤45): actual minutes
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 0, isHalftime: false), "0'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 19, isHalftime: false), "19'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 45, isHalftime: false), "45'")

        // Halftime window (46–60, status not yet HALFTIME): clamp to 45'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 46, isHalftime: false), "45'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 60, isHalftime: false), "45'")

        // Second half (61–105): actual minutes minus 15 (61→46', 90→75', 105→90')
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 61, isHalftime: false), "46'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 90, isHalftime: false), "75'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 105, isHalftime: false), "90'")

        // Stoppage / very long (>105): clamp to 90+'
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 106, isHalftime: false), "90+'")
        XCTAssertEqual(FeaturedMatchCard.formatLiveClock(elapsed: 120, isHalftime: false), "90+'")
    }

    // MARK: - Featured card center content (centerContent)

    /// A team distinguishable only by id (for when the makeMatch series isn't enough).
    func ccTeam(_ id: Int) -> Team {
        Team(id: id, name: "T\(id)", shortName: "T\(id)", crest: nil,
             venue: nil, founded: nil, coach: nil, squad: nil)
    }

    /// Build a match; nil homeScore/awayScore means "no score" (score = nil).
    /// Note makeMatch / makeMatchTeams always have nil scores — this helper covers
    /// score-related branches.
    func ccMatch(id: Int = 1,
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

    /// Core regression: **live without a score** → `.pendingLiveScore` (it used to
    /// degrade to `.kickoff`, showing the kickoff time above and live minutes below —
    /// self-contradictory).
    func testCenterContentLiveWithoutScoreIsPendingLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay), .pendingLiveScore,
                       "IN_PLAY with no published score must show 0-0, not the kickoff time")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: nil, awayScore: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime), .pendingLiveScore,
                       "HALFTIME without a score likewise shows 0-0")
    }

    /// Live **with a score** → `.score` with isLive == true (score precedes live).
    func testCenterContentLiveWithScoreReturnsLiveScore() throws {
        let inPlay = ccMatch(status: "IN_PLAY", homeScore: 1, awayScore: 0)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: inPlay),
                       .score(home: 1, away: 0, isLive: true),
                       "live with a score shows the real score (never degrade to 0-0)")

        let halfTime = ccMatch(status: "HALFTIME", homeScore: 2, awayScore: 1)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: halfTime),
                       .score(home: 2, away: 1, isLive: true),
                       "halftime is also live; show the real score")
    }

    /// Upcoming (SCHEDULED) with a kickoff time → `.kickoff` (unchanged behavior).
    func testCenterContentScheduledReturnsKickoff() throws {
        let m = ccMatch(kickoff: "2026-09-12T14:00:00Z", status: "SCHEDULED")
        let expected = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m), .kickoff(expected),
                       "upcoming with a kickoff time shows the kickoff time")
    }

    /// Finished with a score → `.score` with isLive == false.
    func testCenterContentFinishedWithScoreReturnsNonLiveScore() throws {
        let m = ccMatch(status: "FINISHED", homeScore: 2, awayScore: 2)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m),
                       .score(home: 2, away: 2, isLive: false),
                       "finished shows the final score without live semantics")
    }

    /// Not live, no kickoff, no score → `.tbd`.
    func testCenterContentNonLiveNoKickoffNoScoreReturnsTbd() throws {
        let scheduled = ccMatch(kickoff: nil, status: "SCHEDULED")
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: scheduled), .tbd,
                       "no score and no kickoff → TBD")

        let noStatus = ccMatch(kickoff: nil, status: nil)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: noStatus), .tbd,
                       "missing status and no kickoff / score → TBD")
    }

    // MARK: - "Upcoming → live" transition alignment (display and scheduler share the window)

    /// Core regression: after kickoff but before the source flips `status` (FPL lags
    /// ~8 minutes), a SCHEDULED match inside the "kickoff → +3h" window is treated as
    /// **live** by the display (0 - 0 + ⚽), not degraded to "upcoming / kickoff time".
    /// This is the fix for "the scheduler is already polling while the UI still says
    /// upcoming".
    func testCenterContentScheduledButInKickoffWindowIsPendingLiveScore() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))
        // 2 minutes after kickoff, score unpublished (source lag)
        let now = kickoff.addingTimeInterval(2 * 60)
        XCTAssertEqual(FeaturedMatchCard.centerContent(for: m, now: now), .pendingLiveScore,
                       "an in-window SCHEDULED match (no score) shows 0-0 live, not the kickoff time")
    }

    /// `TodayFilter.isLive(_:now:)` dual-signal equivalence: status OR kickoff window,
    /// aligned with `AutoRefreshScheduler`.
    func testTodayFilterIsLiveWindowAlignedWithScheduler() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let kickoff = try XCTUnwrap(parseKickoffDate(kickoffStr))

        // 1) Status signal always true (now-independent)
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "IN_PLAY")), "IN_PLAY should be live")
        XCTAssertTrue(TodayFilter.isLive(ccMatch(status: "HALFTIME")), "HALFTIME should be live")

        // 2) Window signal: true inside
        let inWindow = kickoff.addingTimeInterval(2 * 60)
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: inWindow),
                      "after kickoff, inside the 3h window should be live")

        // 3) Before kickoff: not live
        let beforeKickoff = kickoff.addingTimeInterval(-60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: beforeKickoff),
                       "before kickoff should not be live")

        // 4) Four hours after kickoff (outside the 3h window): no longer live
        let afterWindow = kickoff.addingTimeInterval(4 * 60 * 60)
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: afterWindow),
                       "outside the 3h window should not be live")

        // 5) Finished beats the window: even inside it, FINISHED is not live
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "FINISHED"), now: inWindow),
                       "finished wins over the time window")
    }

    /// Regression: postponed/canceled matches aren't being played, yet their original
    /// kickoff also lands inside the 3h window — the window fallback must not mark
    /// them live (⚽ 0-0 instead of "postponed/canceled").
    func testIsLiveExcludesPostponedAndCanceledEvenInWindow() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(30 * 60)

        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "POSTPONED"), now: now),
                       "an in-window POSTPONED match must not be live")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELED"), now: now),
                       "an in-window CANCELED match must not be live")
        XCTAssertFalse(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "CANCELLED"), now: now),
                       "an in-window CANCELLED match must not be live")

        // A same-slot SCHEDULED match is still live via the window (don't neuter the fallback)
        XCTAssertTrue(TodayFilter.isLive(ccMatch(kickoff: kickoffStr, status: "SCHEDULED"), now: now),
                      "a normal match with stale status stays live via the time window")
    }

    /// Grouping regression: an in-window SCHEDULED match lands in the "live" group,
    /// not "upcoming" (the basis for Today/fixtures header counts and columns).
    func testGroupedScheduledInWindowCountedAsLiveNotUpcoming() throws {
        let kickoffStr = "2026-09-19T14:00:00Z"
        let m = ccMatch(kickoff: kickoffStr, status: "SCHEDULED")
        let now = try XCTUnwrap(parseKickoffDate(kickoffStr)).addingTimeInterval(2 * 60)
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let today = TodayFilter.todayMatches(from: [m], now: now, tz: tz)
        let live = today.filter { TodayFilter.isLive($0, now: now) }
        let upcoming = today.filter { TodayFilter.isUpcoming($0, now: now) }

        XCTAssertEqual(live.count, 1, "an in-window SCHEDULED match counts as live")
        XCTAssertEqual(upcoming.count, 0, "an in-window SCHEDULED match must not also count as upcoming")
    }
}
