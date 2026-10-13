import XCTest
@testable import EPLViewer

// Auto-refresh: persistence / scheduler / cache invalidation.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    // MARK: - autoRefresh persistence (UserDefaults)

    /// `autoRefresh` should persist to UserDefaults (key `epl_autorefresh`): writes
    /// read back consistently.
    @MainActor
    func testAutoRefreshPersistsToUserDefaults() throws {
        let key = "epl_autorefresh"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            // Restore, so this machine's app defaults / other tests aren't polluted
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        let state = AppState()
        XCTAssertFalse(state.autoRefresh, "defaults to false when nothing was written")

        state.autoRefresh = true
        XCTAssertTrue(defaults.bool(forKey: key), "turning it on writes back to UserDefaults")
        XCTAssertTrue(AppState().autoRefresh, "a new instance restores true from UserDefaults")

        state.autoRefresh = false
        XCTAssertFalse(defaults.bool(forKey: key), "turning it off writes back false")
        XCTAssertFalse(AppState().autoRefresh, "a new instance restores false")
    }

    /// Defaults to off when the key was never written (`UserDefaults.bool` defaults to false).
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
        XCTAssertFalse(AppState().autoRefresh, "false by default when the key is absent")
    }

    /// When `autoRefresh == true` is restored from UserDefaults, the Toggle's
    /// `.onChange` never fires — the root view must configure the timer once on
    /// appear, otherwise "the UI says on but no timer exists".
    func testRootViewConfiguresAutoRefreshOnAppear() throws {
        let code = codeOnly(try sourceFile("ContentView.swift"))
        XCTAssertTrue(code.contains(".task { appState.configureAutoRefresh() }"),
                      "ContentView should call configureAutoRefresh() on appear to restore the persisted on state")
    }

    /// The `autoRefresh` declaration should read UserDefaults (Bool directly), write
    /// back in didSet, with the key matching the existing naming scheme.
    func testAutoRefreshDeclarationUsesUserDefaults() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))
        let decl = try XCTUnwrap(
            qaSlice(code, from: "var autoRefresh: Bool", to: "var isLoading"),
            "autoRefresh declaration not found"
        )
        XCTAssertTrue(decl.contains("UserDefaults.standard.bool(forKey: \"epl_autorefresh\")"),
                      "autoRefresh should read from UserDefaults (Bool directly, no rawValue)")
        XCTAssertTrue(decl.contains("UserDefaults.standard.set(autoRefresh, forKey: \"epl_autorefresh\")"),
                      "didSet should write autoRefresh back to UserDefaults")
        XCTAssertFalse(decl.contains(".rawValue"), "Bool reads/writes need no rawValue")
    }

    // MARK: - "Auto-refresh during matches" scheduler (AutoRefreshScheduler, pure functions)

    /// Scheduler constants locked (contract table must be updated in sync).
    func testAutoRefreshSchedulerConstants() throws {
        XCTAssertEqual(AutoRefreshScheduler.liveInterval, 60, "60s while a match is live")
        XCTAssertEqual(AutoRefreshScheduler.kickoffLeadTime, 15 * 60, "wake 15 minutes before kickoff")
        XCTAssertEqual(AutoRefreshScheduler.maxIdleSleep, 6 * 60 * 60, "max idle sleep 6h")
        XCTAssertEqual(AutoRefreshScheduler.matchWindow, 3 * 60 * 60, "max match span 3h")
    }

    /// The `refreshInterval` decision table — row by row (the behavioral contract,
    /// the single interval entry point).
    func testRefreshIntervalDecisionTable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T12:00:00Z"))

        // Row 1: global autoRefresh=true → always 60 (regardless of duringMatches / schedule)
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "global on → 60s")
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: true, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "global on → 60s (regardless of anything else)")

        // Row 2: global off + during-matches off → nil (no timer)
        XCTAssertNil(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: false,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: now.addingTimeInterval(600)), now: now),
            "both off → no timer")

        // Row 3: global off + during-matches on + a live match → 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: true, nextKickoff: nil), now: now),
            AutoRefreshScheduler.liveInterval, "live match → 60s")

        // Row 4: no live match, next kickoff +2h → sleep until 15 min before = 2h - 15min = 6300s
        //   ⚠️ The team requirements table says 6900 here; but 6900 = 2h − 5min, inconsistent
        //   with kickoffLeadTime (=15min). Per the constant semantics (wake 15 min before
        //   kickoff) it should be 6300; this test pins 6300.
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(2 * 3600)), now: now),
            2 * 3600 - 15 * 60, "sleep until 15 minutes before the next kickoff (6300s)")

        // Row 5: next kickoff +10min (already inside the pre-kickoff window) → 60
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(10 * 60)), now: now),
            AutoRefreshScheduler.liveInterval, "inside the pre-kickoff window → 60s")

        // Row 6: next kickoff +3 days → clamp to maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: now.addingTimeInterval(3 * 24 * 3600)), now: now),
            AutoRefreshScheduler.maxIdleSleep, "too far away → clamp to 6h")

        // Row 7: no next match → maxIdleSleep
        XCTAssertEqual(AutoRefreshScheduler.refreshInterval(
            autoRefresh: false, duringMatches: true,
            schedule: RefreshSchedule(hasLiveMatch: false, nextKickoff: nil), now: now),
            AutoRefreshScheduler.maxIdleSleep, "no schedule → 6h fallback")
    }

    /// 30 minutes after kickoff, not finished → the time window says live; no future
    /// matches → nextKickoff = nil.
    func testScheduleDetectsLiveMatchByKickoffWindow() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let live = makeMatchTeams(id: 1, home: 1, away: 2,
                                  kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY")
        let s = AutoRefreshScheduler.schedule(matches: [live], now: now)
        XCTAssertTrue(s.hasLiveMatch, "30 minutes after kickoff, not finished → live")
        XCTAssertNil(s.nextKickoff, "no matches later than now")
    }

    /// The source status hasn't flipped (still SCHEDULED) but kickoff passed within
    /// the window → still live (FPL once lagged ~8 minutes on status/scores).
    func testScheduleKickoffWindowIgnoresStaleStatus() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:55:00Z", status: "SCHEDULED")
        XCTAssertTrue(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                      "just kicked off, status stale → the time window decides live")
    }

    /// Regression: postponed/canceled matches must not trigger 60 s live polling even
    /// though their original kickoff falls inside the window (otherwise one postponed
    /// match would have the scheduler spin for 3 hours).
    func testScheduleIgnoresPostponedAndCanceledMatches() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let postponed = makeMatchTeams(id: 1, home: 1, away: 2,
                                       kickoff: "2026-09-12T13:55:00Z", status: "POSTPONED")
        let canceled = makeMatchTeams(id: 2, home: 3, away: 4,
                                      kickoff: "2026-09-12T13:55:00Z", status: "CANCELED")
        let s = AutoRefreshScheduler.schedule(matches: [postponed, canceled], now: now)
        XCTAssertFalse(s.hasLiveMatch, "postponed/canceled are not live")
    }

    /// Finished and outside the 3h window → not live.
    func testScheduleFinishedOutsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T10:00:00Z", status: "FINISHED")
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "finished and outside the window → not live")
    }

    /// ⚠️ Fills a real coverage gap: FINISHED but **still inside the 3h window** must
    /// read "not live". The existing `testScheduleFinishedOutsideWindowIsNotLive` uses
    /// a kickoff 4h back (already outside), so the `!TodayFilter.isFinished(m)`
    /// condition **was actually uncovered** (removing it kept everything green —
    /// proven by mutation N1 in independent QA). This case plugs that hole.
    func testScheduleFinishedInsideWindowIsNotLive() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let m = makeMatchTeams(id: 1, home: 1, away: 2,
                               kickoff: "2026-09-12T13:00:00Z", status: "FINISHED") // 1h ago, still inside the 3h window
        XCTAssertFalse(AutoRefreshScheduler.schedule(matches: [m], now: now).hasLiveMatch,
                       "a finished match must read not-live even while still inside the time window")
    }

    /// Structural guards: timer repeats, the view-report debounce, and both report
    /// sites. (None of these had coverage before — mutations N4 / N6 / N7 deleted
    /// them and everything stayed green.)
    func testLiveScheduleWiringGuards() throws {
        let app = codeOnly(try sourceFile("AppState.swift"))

        // N4: the timer must repeat — "sleep until pre-kickoff" sleeps one long
        //     interval and relies on the tick recompute to finish the job; a
        //     one-shot timer would wake once and never be rebuilt.
        let cfg = try XCTUnwrap(
            qaSlice(app, from: "func configureAutoRefresh()", to: "func refreshTick"),
            "configureAutoRefresh not found"
        )
        XCTAssertTrue(cfg.contains("repeats: true"),
                      "the timer must repeat:true; a one-shot means nobody rebuilds it after a long sleep")

        // N6: the debounce + remembering the latest fixtures (the latter is what lets
        // refreshTick recompute the schedule)
        XCTAssertTrue(app.contains("guard s != liveSchedule else { return }"),
                      "reportLiveSchedule must keep its debounce, or every view report rebuilds the timer")
        XCTAssertTrue(app.contains("lastKnownMatches = matches"),
                      "reportLiveSchedule must remember the latest fixtures so refreshTick can recompute against the latest now")

        // N7: both pages that load fixtures must report (missing one risks sleeping
        // through matches while parked on that page)
        XCTAssertTrue(codeOnly(try sourceFile("TodayView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "TodayView must report the schedule")
        XCTAssertTrue(codeOnly(try sourceFile("FixturesView.swift")).contains("reportLiveSchedule(from: vm.matches)"),
                      "FixturesView must report the schedule")
    }

    /// Future matches aren't live; `nextKickoff` takes the earliest future kickoff.
    func testScheduleFutureMatchNotLiveAndReportsNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T16:00:00Z", status: "SCHEDULED"),
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T15:00:00Z", status: "SCHEDULED"), // earliest
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertFalse(s.hasLiveMatch, "future matches aren't live")
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T15:00:00Z")),
                       "nextKickoff should be the earliest future kickoff")
    }

    /// Live and future matches coexist → both must be reported.
    func testScheduleReportsBothLiveAndNextKickoff() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let matches = [
            makeMatchTeams(id: 1, home: 1, away: 2, kickoff: "2026-09-12T13:30:00Z", status: "IN_PLAY"),  // live
            makeMatchTeams(id: 2, home: 3, away: 4, kickoff: "2026-09-12T17:00:00Z", status: "SCHEDULED"), // future
        ]
        let s = AutoRefreshScheduler.schedule(matches: matches, now: now)
        XCTAssertTrue(s.hasLiveMatch)
        XCTAssertEqual(s.nextKickoff, try XCTUnwrap(parseKickoffDate("2026-09-12T17:00:00Z")))
    }

    /// Empty array / unparseable `utcDate` → no crash; false/nil.
    func testScheduleEmptyAndUnparseable() throws {
        let now = try XCTUnwrap(parseKickoffDate("2026-09-12T14:00:00Z"))
        let empty = AutoRefreshScheduler.schedule(matches: [], now: now)
        XCTAssertFalse(empty.hasLiveMatch)
        XCTAssertNil(empty.nextKickoff)

        let bad = makeMatchTeams(id: 9, home: 1, away: 2, kickoff: "not-a-date", status: "SCHEDULED")
        let s = AutoRefreshScheduler.schedule(matches: [bad], now: now)
        XCTAssertFalse(s.hasLiveMatch, "an unparseable utcDate should be skipped")
        XCTAssertNil(s.nextKickoff)
    }

    /// `configureAutoRefresh` must go through the `refreshInterval` decision, never a
    /// hardcoded 60 s.
    func testConfigureAutoRefreshUsesSchedulerNotHardcoded60() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))
        let fn = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "func reportLiveSchedule"),
            "configureAutoRefresh not found"
        )
        XCTAssertTrue(fn.contains("AutoRefreshScheduler.refreshInterval("),
                      "the interval decision must go through refreshInterval, not hardcoding")
        XCTAssertFalse(fn.contains("withTimeInterval: 60"),
                       "no hardcoded 60 s interval")
        XCTAssertTrue(fn.contains("withTimeInterval: interval"),
                      "refreshInterval's result should be passed to the timer")
    }

    /// 🚨 Guard rail: the timer must **recompute the interval** on every wake, or it
    /// sleeps through whole matches. Scenario: waking "15 min before kickoff" sees
    /// the exact same schedule (hasLiveMatch still false, same nextKickoff) →
    /// reportLiveSchedule debounces and doesn't rebuild; only the tick's own recompute
    /// switches the interval to 60 s. Deleting `configureAutoRefresh()` from
    /// `refreshTick` must turn this test red.
    func testRefreshTickRecomputesIntervalOnEveryWake() throws {
        let code = codeOnly(try sourceFile("AppState.swift"))

        // 1) refreshTick's body must "refresh first, then recompute the interval"
        let tick = try XCTUnwrap(
            qaSlice(code, from: "func refreshTick", to: "func reportLiveSchedule"),
            "refreshTick not found"
        )
        XCTAssertTrue(tick.contains("await refresh(scoresOnly: true)"),
                      "refreshTick must refresh data first, with live polling invalidating fixtures only (scoresOnly), never the whole bootstrap")
        XCTAssertTrue(tick.contains("configureAutoRefresh()"),
                      "refreshTick must recompute the interval (configureAutoRefresh), or it sleeps through matches")
        // ⚠️ Key: the schedule must be **recomputed against the latest now** — using
        // the stored liveSchedule alone can't work. hasLiveMatch is a stored Bool that
        // never flips by itself; only recomputing the kickoff window in the tick turns
        // it false after the match ends. Otherwise, parked on a tab that doesn't report
        // (standings/settings/leaders/injuries), liveSchedule freezes → permanent 60 s
        // polling after all matches end.
        XCTAssertTrue(tick.contains("AutoRefreshScheduler.schedule("),
                      "refreshTick must recompute the schedule against the latest now, or parked tabs poll at 60 s forever")

        // 2) The timer's fire closure must call refreshTick(), not just refresh()
        let cfg = try XCTUnwrap(
            qaSlice(code, from: "func configureAutoRefresh()", to: "func refreshTick"),
            "configureAutoRefresh not found"
        )
        XCTAssertTrue(cfg.contains("await self?.refreshTick()"),
                      "the fire closure should call refreshTick(), recomputing the interval on every wake")
        XCTAssertFalse(cfg.contains("await self?.refresh()"),
                       "the fire closure must not call refresh() directly (it should call refreshTick())")

        // 3) No leftover "never re-configure inside the tick" counter-instruction
        //    (so nobody copies it back as a contract)
        let raw = try sourceFile("AppState.swift")
        XCTAssertFalse(raw.contains("绝不在 tick 里重新 configure"),
                       "the wrong-reason comment must stay deleted so nobody reinstates it as a contract")
    }

    // MARK: - "Auto-refresh during matches" persistence + copy

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
        XCTAssertTrue(state.autoRefreshDuringMatches, "unwritten (fresh install / never touched) → on by default")

        state.autoRefreshDuringMatches = true
        XCTAssertTrue(defaults.bool(forKey: key), "turning it on writes back to UserDefaults")
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "a new instance restores true from UserDefaults")

        state.autoRefreshDuringMatches = false
        XCTAssertFalse(defaults.bool(forKey: key), "turning it off writes back false")
        // ⚠️ Key regression: after the user explicitly turns it off, a new instance
        // must still read false — never flipped back by the default-on. This guards
        // the tri-state read (object(forKey:) == nil); degrading to bool(forKey:)
        // would make the default-on unimplementable or flip off back to on across
        // launches.
        XCTAssertFalse(AppState().autoRefreshDuringMatches,
                       "after an explicit off, a new instance must stay false (the default must not flip it back)")
    }

    /// Missing key (fresh install / never touched) → **true by default** (the user
    /// asked for "checked out of the box").
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
        XCTAssertTrue(AppState().autoRefreshDuringMatches, "missing key → on by default")
    }

    /// The copy must exist in both languages; hardcoded Chinese is banned.
    func testAutoRefreshDuringMatchesStringsBilingual() throws {
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.chinese), "比赛期间自动刷新")
        XCTAssertEqual(UIString.autoRefreshDuringMatches.text(.english), "Auto-refresh during matches")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.chinese), "已开启全局自动刷新，此项无需设置")
        XCTAssertEqual(UIString.autoRefreshDuringMatchesHint.text(.english),
                       "Global auto-refresh is on; this setting is not needed")
    }

    /// With the global auto-refresh on, the "during matches" toggle must be disabled
    /// with the explanatory footnote.
    func testSettingsDisablesDuringMatchesToggleWhenGlobalOn() throws {
        let code = codeOnly(try sourceFile("SettingsView.swift"))
        XCTAssertTrue(code.contains(".disabled(appState.autoRefresh)"),
                      "with global auto-refresh on, the during-matches toggle should be disabled")
        XCTAssertTrue(code.contains("UIString.autoRefreshDuringMatchesHint.text(appState.language)"),
                      "the 'not needed' footnote should show")
    }

    /// Max 4 matches per column: confirm it applies only to the two columns and the
    /// "View all →" entry is intact.
    func testColumnCardCapsAtFourAndViewAllIntact() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))

        // columnCard has exactly two call sites (left/right columns); no other call
        // site got truncated along with them
        XCTAssertEqual(count(of: "columnCard(", in: code), 3,
                       "expected 1 definition + 2 calls of columnCard; a new call site needs a truncation review")
        XCTAssertEqual(count(of: "ForEach(Array(matches.prefix(4)))", in: code), 1,
                       "the truncation should live in exactly one place inside columnCard")

        // "View all →" still present and still jumps to the fixtures page — truncated
        // matches need somewhere to go
        XCTAssertEqual(count(of: "UIString.viewAll", in: code), 1,
                       "the column card's 'View all →' must not be lost")
        XCTAssertTrue(code.contains("appState.selected = .fixtures"),
                      "'View all →' must still jump to the fixtures page")

        // The truncation must not affect the view model's data (columns beyond 4 keep
        // their data; only rendering is capped)
        XCTAssertTrue(code.contains("ForEach(Array(matches.prefix(4))) { match in"),
                      "the ForEach's match binding should stay")
    }

    /// With the card forcing `.dark`, `.primary` is pure white (clears the bar), but
    /// `.secondary` under macOS dark is a **translucent** secondaryLabelColor
    /// (≈60% white) that **dims along with the background**: on the pinned
    /// magenta→pink gradient it measured only 2.31–2.51:1 (< the 3.0 large-text bar),
    /// visibly gray. Quantified in the companion test
    /// `testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient` (opaque white clears it).
    /// Hence the fix: all small text on the featured card uses opaque `.white`.
    /// This guards "no `.secondary` inside FeaturedMatchCard" — reverting to
    /// `.secondary` would collapse the contrast back to gray.
    func testFeaturedCardSecondaryTextMeetsReadabilityBar() throws {
        let code = codeOnly(try sourceFile("TodayView.swift"))
        let card = try XCTUnwrap(
            qaSlice(code, from: "struct FeaturedMatchCard"),
            "FeaturedMatchCard definition not found"
        )
        XCTAssertEqual(count(of: ".secondary", in: card), 0,
            "small text on the featured card (FeaturedMatchCard) must use opaque .white, never .secondary — " +
            "on the magenta→pink gradient .secondary measures only 2.31:1, below 3.0:1, visibly gray.")
    }

    /// Reference group: proves the "opaque white text" fix actually clears the bar
    /// (giving the engineer a concrete direction).
    func testOpaqueWhiteTextWouldMeetReadabilityBarOnGradient() throws {
        let src = try sourceFile("TodayView.swift")
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
                                        "opaque white text should clear the bar at gradient stop \(i)")
        }
    }
}

extension EPLViewerTests {
    /// The live-match 60 s poll must clear only the fixtures cache, never a full
    /// clearCache() (which would wipe the whole FPL bootstrap / standings and
    /// re-download megabytes every 60 s). Guard: after invalidateFixtures(), the
    /// in-memory fixtures are gone and bootstrap survives.
    func testInvalidateFixturesClearsFixturesKeepsBootstrap() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "the matchesJSON fixture should decode into fixtures")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        await DataRepository.invalidateFixtures()

        // Fixtures invalidated
        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "invalidateFixtures must clear the in-memory fixtures cache")
        // Bootstrap survives — a misused full clearCache() would make this nil
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "invalidateFixtures must not clear the bootstrap (or every 60 s re-downloads it)")
    }

    /// End-to-end guard: AppState.refresh(scoresOnly:) (the timer path) must not wipe
    /// every cache. Pre-fill memory fixtures + bootstrap; after a scoresOnly refresh
    /// the fixtures are gone but bootstrap survives (proving full clearCache wasn't
    /// used, or bootstrap would be gone too).
    /// Note: CacheStore disk IO is intercepted in this sandbox, so the memory layer
    /// carries the equivalent assertions.
    @MainActor
    func testRefreshScoresOnlyDoesNotWipeAllCaches() async {
        let matches = (try? makeDecoder().decode(MatchesResponse.self,
                                                 from: Data(matchesJSON.utf8)).matches) ?? []
        XCTAssertFalse(matches.isEmpty, "the matchesJSON fixture should decode into fixtures")
        let bootstrap = FPLBootstrap(teams: [], elements: [], element_types: [], events: nil)

        await MemoryStore.shared.cacheBootstrap(bootstrap)
        await MemoryStore.shared.cacheFixtures(matches)

        let appState = AppState()
        await appState.refresh(scoresOnly: true)

        let fixturesAfter: [Match]? = await MemoryStore.shared.cachedFixtures()
        XCTAssertNil(fixturesAfter,
                     "a scoresOnly refresh must invalidate the fixtures cache")
        let bootstrapAfter = await MemoryStore.shared.cachedBootstrap()
        XCTAssertNotNil(bootstrapAfter,
                        "a scoresOnly refresh must not clear the bootstrap (or every 60 s re-downloads it)")
    }
}
