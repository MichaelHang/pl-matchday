import XCTest
@testable import EPLViewer

// Fixtures page: layout / round window / snapshot cache.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    // MARK: - Fixtures page (screenshot-style layout)

    /// focusedRound decides which round `displayed` shows, regardless of mode.
    func testFixturesFocusedRoundDrivesDisplayed() throws {
        let vm = FixturesViewModel()
        vm.focusedRound = 5
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 5),
            makeMatch(id: 2, kickoff: "2025-09-12T11:00:00Z", status: "FINISHED", matchday: 12),
        ]
        XCTAssertEqual(vm.displayed.map(\.id), [1])

        // User taps "Round N" in the season overview → focusedRound is rewritten
        vm.focusedRound = 12
        XCTAssertEqual(vm.displayed.map(\.id), [2])
    }

    /// Date-grouped fixtures layout: each section holds that day's matches, ascending by kickoff.
    func testFixturesGroupedSectionsByLocalDate() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let vm = FixturesViewModel()
        vm.focusedRound = 1
        vm.matches = [
            // Three matches on Aug 29 Beijing
            makeMatch(id: 1, kickoff: "2025-08-29T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-29T14:00:00Z", status: "FINISHED", matchday: 1),
            // One match on Sep 1 Beijing
            makeMatch(id: 3, kickoff: "2025-09-01T03:00:00Z", status: "FINISHED", matchday: 1),
        ]
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].matches.map(\.id), [1, 2], "ascending kickoffs within a day")
        XCTAssertEqual(sections[1].matches.map(\.id), [3])
    }

    /// Season-overview snapshots: one per round, at most 3 previews, status from currentRound.
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
        XCTAssertEqual(snaps[0].previews.count, 2, "round 1 has 2 matches")
        XCTAssertEqual(snaps[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(snaps[2].previews.map(\.id), [5])
    }

    /// Season overview: rounds with more than 3 matches preview only the first 3.
    func testFixturesRoundSnapshotsPreviewLimitIsThree() throws {
        let vm = FixturesViewModel()
        vm.matches = (1...8).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T1\(i):00:00Z", status: "FINISHED", matchday: 1)
        }
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 1, totalRounds: 38, playedRounds: 0, remainingRounds: 38,
            fraction: 0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps[0].previews.count, 3, "each overview card caps at 3 matches")
    }

    /// Season overview: future rounds without data → unknown status.
    func testFixturesRoundSnapshotsFutureWithoutDataIsUnknown() throws {
        let vm = FixturesViewModel()
        let snaps = vm.roundSnapshots(seasonProgress: SeasonProgress(
            currentRound: 5, totalRounds: 38, playedRounds: 4, remainingRounds: 34,
            fraction: 4.0 / 38.0, seasonYear: 2025
        ))
        XCTAssertEqual(snaps.count, 38)
        // Round 5 = current; rounds 6-38 = future without data → unknown
        XCTAssertEqual(snaps[4].progress, .current)
        XCTAssertEqual(snaps[5].progress, .unknown)
        XCTAssertTrue(snaps[5].previews.isEmpty, "unknown rounds have no previews")
    }

    /// Indexes rebuild automatically on matches assignment: availableRounds syncs,
    /// roundStart returns the round's earliest kickoff.
    ///
    /// This guards the performance regression: each of 38 round chips needs
    /// roundStart, and if anyone reverts to "scan all matches every call" this test
    /// still passes but the UI would hang. So roundStart must only read the
    /// precomputed dictionary (O(1)).
    func testFixturesIndexesRebuiltOnMatchesAssignment() throws {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1), // earliest
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        XCTAssertEqual(vm.availableRounds, [1, 2], "assignment syncs the round list")

        let earliest = try XCTUnwrap(parseKickoffDate("2025-08-21T11:00:00Z"))
        XCTAssertEqual(vm.roundStart(1), earliest, "roundStart returns the round's earliest kickoff")
        XCTAssertNil(vm.roundStart(9), "rounds without data return nil")

        // Grouping reads the precomputed bucket, also kickoff-ascending
        vm.focusedRound = 1
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let sections = vm.groupedSections(tz: tz)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].matches.map(\.id), [2, 1])
    }

    /// `displayed` must read the precomputed bucket, never a 380-match filter.
    func testFixturesDisplayedReadsPrebuiltBucket() {
        let vm = FixturesViewModel()
        vm.matches = [
            makeMatch(id: 1, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
        ]
        vm.focusedRound = 1
        XCTAssertEqual(vm.displayed.map(\.id), [2, 1], "buckets are kickoff-ascending")
        vm.focusedRound = 2
        XCTAssertEqual(vm.displayed.map(\.id), [3])
        vm.focusedRound = 99
        XCTAssertTrue(vm.displayed.isEmpty, "rounds without data return empty, no crash")
    }

    // MARK: - Layout-trap regression guards

    /// Two traps on the fixtures page both pin the main thread during SwiftUI layout
    /// ("endless spinner + frozen UI"):
    ///   1. LazyVStack nesting LazyVGrid — lazy containers propose undefined widths,
    ///      so the grid can't solve its column count;
    ///   2. GridItem(.adaptive(maximum: .infinity)) — unbounded column width makes the
    ///      column math diverge.
    /// Scanning the source keeps these traps from coming back.
    func testFixturesViewHasNoLayoutDeadlockTraps() throws {
        let src = try sourceFile("FixturesView.swift")
        // Scan code only: strip // comments first, otherwise the comments explaining
        // "why not LazyVStack" would false-positive.
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertFalse(codeOnly.contains("LazyVStack"),
                       "LazyVStack is banned on the fixtures page: nested lazy containers deadlock LazyVGrid size negotiation")
        XCTAssertFalse(codeOnly.contains("maximum: .infinity"),
                       "GridItem's maximum must be a concrete value, never .infinity")
    }

    /// Two guard rails for the round chip bar, both mandatory:
    ///   1. LazyHStack — a plain HStack would build a view per round; hundreds of
    ///      rounds would size thousands of chips at once, pinning the main thread.
    ///   2. Keep .frame(height: 32) — the fix for "a horizontal ScrollView inside a
    ///      vertical one negotiates sizes forever"; removing it regresses the hang,
    ///      and it's also what lets LazyHStack measure itself.
    /// Comments are stripped before matching, or explanatory comments false-positive.
    func testRoundChipBarUsesLazyHStack() throws {
        let src = try sourceFile("FixturesView.swift")
        let codeOnly = src.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
        XCTAssertTrue(codeOnly.contains("LazyHStack"),
                      "the round chip bar must use LazyHStack, otherwise many rounds render everything and stall the main thread")
        XCTAssertTrue(codeOnly.contains(".frame(height: 32)"),
                      "the horizontal chip bar's fixed height must stay: removing it regresses the layout deadlock")
    }

    /// `roundSnapshots` runs on the SwiftUI body evaluation path and must cache:
    /// unchanged inputs return the previous result (no recompute); changed inputs
    /// must recompute.
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

        // First call: empty cache → must recompute
        let first = vm.roundSnapshots(seasonProgress: progress)
        let computesAfterFirst = vm.roundSnapshotsComputeCount
        XCTAssertEqual(computesAfterFirst, 1, "the first call should compute exactly once")

        // Second call: identical inputs → cache hit, no recompute
        let second = vm.roundSnapshots(seasonProgress: progress)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst,
                       "unchanged inputs should hit the cache without recomputing")
        XCTAssertEqual(fingerprint(second), fingerprint(first), "the cached result matches the first")

        // Change seasonProgress (a key input) → must recompute with updated content
        let moved = SeasonProgress(
            currentRound: 3, totalRounds: 3,
            playedRounds: 2, remainingRounds: 1,
            fraction: 2.0 / 3.0, seasonYear: 2025
        )
        let third = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 1,
                       "changing seasonProgress must recompute")
        XCTAssertEqual(third[1].progress, .past, "after the round advances, round 2 goes current → past")
        XCTAssertEqual(third[2].progress, .current)

        // Now change matches (via didSet rebuilding indexes) → cache must invalidate
        vm.matches = [makeMatch(id: 99, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3)]
        let afterRematch = vm.roundSnapshots(seasonProgress: moved)
        XCTAssertEqual(vm.roundSnapshotsComputeCount, computesAfterFirst + 2,
                       "changing matches must recompute")
        XCTAssertEqual(afterRematch[2].previews.map(\.id), [99], "snapshot content should reflect the new data")
        XCTAssertTrue(afterRematch[0].previews.isEmpty, "old round-1 data is gone")
    }

    // MARK: - Round window (fixed-size chip-bar pagination)

    /// Build `count` rounds (one match each), just to fill availableRounds.
    func makeRounds(_ count: Int) -> [Match] {
        (1...count).map { i in
            makeMatch(id: i, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: i)
        }
    }

    // MARK: - Initial focus (load() focuses only on the first data load; refreshes must not reset browsing)

    /// Bucket makeRounds' output by round (the matchesByRound shape).
    func roundsByRound(_ count: Int) -> (byRound: [Int: [Match]], rounds: [Int]) {
        var byRound: [Int: [Match]] = [:]
        for m in makeRounds(count) { byRound[m.matchday ?? 0, default: []].append(m) }
        return (byRound, Array(1...count))
    }

    /// Current round has data → focus it.
    func testInitialFocusRoundPrefersCurrentRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 7,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            7, "current round with data → focus it")
    }

    /// Current round has no fixtures yet (FPL advanced but fixtures unpublished) →
    /// fall back to the first round with data.
    func testInitialFocusRoundFallsBackToFirstAvailableRound() {
        let (byRound, rounds) = roundsByRound(10)
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 11,
                                                availableRounds: rounds,
                                                matchesByRound: byRound),
            1, "current round without data → focus the first round with data")
    }

    /// No fixtures at all → keep the passed currentRound (load() wouldn't even call
    /// this with no rounds).
    func testInitialFocusRoundWithNoDataKeepsCurrentRound() {
        XCTAssertEqual(
            FixturesViewModel.initialFocusRound(currentRound: 5,
                                                availableRounds: [],
                                                matchesByRound: [:]),
            5, "no round data at all → keep the current round")
    }

    /// Focusing a middle round → the window **centers** on it (2 before, 2 after).
    func testRoundWindowCentersOnFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.roundWindowStart = 0            // push the window left manually to really test alignment
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "MD20 centered → MD18–MD22")
        XCTAssertEqual(vm.roundWindowStart, 17)
    }

    /// Focusing near the start (round 1 / 2) → window **left-aligned**, start never negative.
    func testRoundWindowAlignsLeftNearStart() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // Round 1: idx 0 - 2 = -2 → clamps to 0
        vm.roundWindowStart = 20
        vm.focusedRound = 1
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0, "the start must not go negative")

        // Round 2: idx 1 - 2 = -1 → also clamps to 0
        vm.roundWindowStart = 20
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// Focusing near the end (second-to-last / last round) → **right-aligned**, never past the bound.
    func testRoundWindowAlignsRightNearEnd() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)

        // Second to last (MD37): idx 36 - 2 = 34 → clamps to 33
        vm.roundWindowStart = 0
        vm.focusedRound = 37
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33, "with 38 rounds the bound is 33")

        // Last round (MD38): idx 37 - 2 = 35 → also clamps to 33
        vm.roundWindowStart = 0
        vm.focusedRound = 38
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.roundWindowStart, 33)
    }

    /// Fewer rounds than a window → show everything, bound 0 (both arrows hidden).
    func testRoundWindowShowsAllWhenFewerThanWindowSize() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(3)
        vm.roundWindowStart = 99            // even an out-of-bounds start gets clamped back
        vm.focusedRound = 2
        vm.alignWindowToFocusedRound()
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3], "only 3 rounds → show all")
        XCTAssertEqual(vm.roundWindowStart, 0)
        XCTAssertEqual(vm.roundWindowMaxStart, 0, "less than a window → bound 0, arrows hidden")
    }

    /// Paging bounds: right stops at the bound, left stops at 0 without going negative.
    func testRoundWindowPagingStopsAtBounds() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1

        // Page all the way right
        for _ in 0..<20 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.roundWindowStart, 33, "bound for 38 rounds = 38 - 5")
        XCTAssertEqual(vm.visibleRounds, [34, 35, 36, 37, 38])
        XCTAssertEqual(vm.focusedRound, 1, "paging moves only the window, not the selected round")

        // Further right paging never overflows
        vm.pageRoundsForward()
        XCTAssertEqual(vm.roundWindowStart, 33)
        XCTAssertEqual(vm.roundWindowMaxStart, 33)

        // Page all the way left
        for _ in 0..<20 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, 0, "the start never goes negative")
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5])
        XCTAssertEqual(vm.focusedRound, 1, "paging moves only the window; the selection never changes")

        // Further left paging never goes negative
        vm.pageRoundsBackward()
        XCTAssertEqual(vm.roundWindowStart, 0)
    }

    /// After paging right the focus is exactly what it was: the window moved,
    /// focusedRound didn't — so no chip in the new window is highlighted (the
    /// "focus stays put" behavior the user asked for).
    func testPagingPreservesFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        XCTAssertEqual(vm.roundWindowStart, 17, "initial centered window MD18–MD22")

        vm.pageRoundsForward()
        XCTAssertEqual(vm.focusedRound, 20, "after paging right the focus is still 20")
        XCTAssertNotEqual(vm.roundWindowStart, 17, "the window start did move")
        XCTAssertEqual(vm.visibleRounds, [23, 24, 25, 26, 27])
        XCTAssertFalse(vm.visibleRounds.contains(20), "the new window excludes 20 → no highlighted chip")
    }

    /// N right pages followed by N left pages: the window start returns, focusedRound
    /// never changed, and the focus lands back inside visibleRounds (MD20 re-highlights).
    func testPagingRoundTripRestoresWindowAndFocus() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        let originalStart = vm.roundWindowStart
        XCTAssertEqual(originalStart, 17)

        // 3 right pages (17→22→27→32, below the bound 33, keeping the round trip symmetric)
        for _ in 0..<3 { vm.pageRoundsForward() }
        XCTAssertEqual(vm.focusedRound, 20, "the focus stays constant while paging right")

        // 3 left pages: the window returns, the focus never changed, MD20 re-highlights
        for _ in 0..<3 { vm.pageRoundsBackward() }
        XCTAssertEqual(vm.roundWindowStart, originalStart, "a paging round trip restores the window")
        XCTAssertEqual(vm.focusedRound, 20, "the focus never changed")
        XCTAssertEqual(vm.visibleRounds, [18, 19, 20, 21, 22], "back at the original window, MD20 highlights again")
        XCTAssertTrue(vm.visibleRounds.contains(20))
    }

    /// After paging away, visibleRounds doesn't contain focusedRound: rendering
    /// doesn't crash and the highlight test `r == focusedRound` is false for every
    /// chip in the window (no highlight — expected, not a bug).
    func testPagingAwayFromFocusRendersNoSelection() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 20
        vm.pageRoundsForward()                 // window MD23–MD27, focus still 20
        XCTAssertFalse(vm.visibleRounds.contains(20))

        // Simulate the chip bar's highlight test: no chip in the window should highlight
        let anyHighlighted = vm.visibleRounds.contains { $0 == vm.focusedRound }
        XCTAssertFalse(anyHighlighted, "no chip highlighted — as expected")

        // Invariants hold even when paged away
        XCTAssertLessThanOrEqual(vm.visibleRounds.count, FixturesViewModel.roundWindowSize)
        XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0)
        XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart)
    }

    /// Jumping to MD30 from the season overview (window at the far left): the window
    /// must re-align automatically and include MD30.
    func testRoundWindowAlignsToFarAwayFocusedRound() {
        let vm = FixturesViewModel()
        vm.matches = makeRounds(38)
        vm.focusedRound = 1
        XCTAssertEqual(vm.visibleRounds, [1, 2, 3, 4, 5], "start at the far left")

        // Simulate "tap the MD30 card in the overview" — only focusedRound changes;
        // the didSet aligns the window automatically
        vm.focusedRound = 30
        XCTAssertTrue(vm.visibleRounds.contains(30), "after alignment the window must contain focusedRound")
        XCTAssertEqual(vm.visibleRounds, [28, 29, 30, 31, 32])

        // Already in the window → shouldn't move (otherwise the focus landing back in
        // the window would re-center it and bounce back and forth)
        let before = vm.roundWindowStart
        vm.focusedRound = 29
        XCTAssertEqual(vm.roundWindowStart, before, "focus still inside the window → the window stays put")
    }

    /// Invariant: at any data size, under any operation sequence, the window never
    /// leaves bounds or exceeds its size.
    func testRoundWindowInvariantsHoldAcrossDataSizes() {
        let size = FixturesViewModel.roundWindowSize
        // Covers: empty / 1 round / less than a window / exactly one / one extra / 38 / 200
        for count in [0, 1, 3, 5, 6, 12, 38, 200] {
            let vm = FixturesViewModel()
            vm.matches = count == 0 ? [] : makeRounds(count)
            // Covers: out-of-bounds small / middle / out-of-bounds large
            for focused in [1, 2, 3, 5, count / 2 + 1, count - 1, count, 999] {
                vm.roundWindowStart = 0
                vm.focusedRound = focused
                vm.alignWindowToFocusedRound()

                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size,
                                         "rounds \(count) / focus \(focused): window must not exceed \(size)")
                XCTAssertGreaterThanOrEqual(vm.roundWindowStart, 0,
                                            "rounds \(count) / focus \(focused): start must not go negative")
                XCTAssertLessThanOrEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                                         "rounds \(count) / focus \(focused): start must not pass the bound")

                // Page fully right, re-check the invariants
                for _ in 0..<(count + 1) { vm.pageRoundsForward() }
                XCTAssertLessThanOrEqual(vm.visibleRounds.count, size)
                XCTAssertEqual(vm.roundWindowStart, vm.roundWindowMaxStart,
                               "paging right forever should stop at the bound")
                XCTAssertEqual(vm.visibleRounds,
                               Array(vm.availableRounds.suffix(min(size, count))),
                               "the rightmost window should be the last \(min(size, count)) rounds")
            }
        }
    }

    /// Compress snapshots into a comparable fingerprint: round + status + preview ids.
    /// (Arrays of tuples can't be XCTAssertEqual'd directly, so stringify.)
    func fingerprint(_ snaps: [RoundSnapshot]) -> String {
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

    // MARK: - QA: snapshot cache correctness

    // Why not the engineer's own `roundSnapshotsComputeCount`: that counter only
    // proves whether a recompute happened — it says nothing about **what a cache hit
    // returns**. The real risk is "should have invalidated but didn't", serving a
    // stale snapshot — user-visible data corruption. So everything below is checked
    // against an independent oracle: recompute the expected snapshots straight from
    // vm.matches and compare on every call. Any missed invalidation shows up here.

    /// Independent oracle: no VM caches/indexes; recomputes expected snapshots from
    /// `vm.matches` raw data. Output format identical to `fingerprint(_:)` for direct
    /// comparison.
    func oracleSnapshots(for vm: FixturesViewModel, progress: SeasonProgress?) -> String {
        let cur = progress?.currentRound ?? vm.currentRound
        let maxRound = progress?.totalRounds ?? (vm.availableRounds.sorted().last ?? 38)
        // The production implementation traps via `1...maxRound` when maxRound < 1.
        // The oracle doesn't replay the crash; it returns a sentinel so the assertion
        // produces a readable failure.
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

    func progressName(_ p: RoundProgress) -> String {
        switch p {
        case .past:    return "past"
        case .current: return "current"
        case .future:  return "future"
        case .unknown: return "unknown"
        }
    }

    /// Five-match sample: round 1 ×2, round 2 ×2, round 3 ×1.
    func sampleMatches() -> [Match] {
        [
            makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 2, kickoff: "2025-08-21T14:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 3, kickoff: "2025-08-28T11:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 4, kickoff: "2025-08-28T14:00:00Z", status: "FINISHED", matchday: 2),
            makeMatch(id: 5, kickoff: "2025-09-04T11:00:00Z", status: "FINISHED", matchday: 3),
        ]
    }

    /// Two `SeasonProgress` values equal in content but separately constructed: the
    /// cache key compares via Equatable, so it must respect **value equality**, not
    /// object identity (structs have none anyway; this covers implementations that
    /// store Optional<SeasonProgress> in the key without comparing it properly).
    func testRoundSnapshotsCacheTreatsEqualSeasonProgressValuesAsSameInput() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let a = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        let b = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)
        XCTAssertEqual(a, b, "precondition: the two seasonProgress values must be equal")

        let r1 = vm.roundSnapshots(seasonProgress: a)
        let r2 = vm.roundSnapshots(seasonProgress: b)
        XCTAssertEqual(fingerprint(r1), oracleSnapshots(for: vm, progress: a))
        XCTAssertEqual(fingerprint(r2), fingerprint(r1),
                       "equal-but-distinct seasonProgress values must produce identical snapshots")
        XCTAssertEqual(fingerprint(r2), oracleSnapshots(for: vm, progress: b))

        // Changing only snapshot-irrelevant fields (playedRounds / fraction) → the key
        // differs → recompute, but the content shouldn't change (currentRound and
        // totalRounds untouched)
        let c = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 2,
                               remainingRounds: 1, fraction: 2.0 / 3.0, seasonYear: 2025)
        XCTAssertNotEqual(a, c, "precondition: the two seasonProgress values must differ")
        let r3 = vm.roundSnapshots(seasonProgress: c)
        XCTAssertEqual(fingerprint(r3), oracleSnapshots(for: vm, progress: c))
        XCTAssertEqual(fingerprint(r3), fingerprint(r1),
                       "with currentRound / totalRounds unchanged, snapshot content must not change")
    }

    /// Toggling `seasonProgress` between nil and non-nil is the branch where key
    /// comparison is easiest to get wrong (with Optionals in ==, nil must equal nil
    /// and nil must not equal .some).
    func testRoundSnapshotsNilProgressToggleNeverReturnsStaleSnapshot() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()                 // availableRounds = [1, 2, 3]

        let nilFirst = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(nilFirst.count, 3, "with nil, totalRounds falls back to availableRounds.last")
        XCTAssertEqual(fingerprint(nilFirst), oracleSnapshots(for: vm, progress: nil))
        let nilSecond = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(nilSecond), fingerprint(nilFirst), "two consecutive nil calls must agree")

        let p = SeasonProgress(currentRound: 3, totalRounds: 5, playedRounds: 2,
                               remainingRounds: 3, fraction: 0.4, seasonYear: 2025)
        let nonNil = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(nonNil.count, 5)
        XCTAssertEqual(fingerprint(nonNil), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(nonNil), fingerprint(nilFirst),
                          "precondition: nil and non-nil results must differ, or this test can't detect staleness")

        // Back to nil — the previous non-nil cache must not leak
        let backToNil = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(backToNil), fingerprint(nilFirst),
                       "returning to nil must restore the nil result, not the previous non-nil cache")
        XCTAssertEqual(fingerprint(backToNil), oracleSnapshots(for: vm, progress: nil))

        // And back to non-nil — the nil cache must not leak either
        let again = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(again), fingerprint(nonNil),
                       "returning to non-nil must not serve the nil cache")
        XCTAssertEqual(fingerprint(again), oracleSnapshots(for: vm, progress: p))
    }

    /// Changing only `currentRound` (matches and seasonProgress untouched) must
    /// invalidate the cache. Note seasonProgress must be nil here: with a non-nil
    /// progress, cur comes from seasonProgress.currentRound and vm.currentRound
    /// doesn't affect the output at all — the invalidation path wouldn't be exercised.
    func testRoundSnapshotsInvalidatesWhenOnlyCurrentRoundChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        vm.currentRound = 1

        let before = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(before[0].progress, .current, "precondition: the current round is 1")
        XCTAssertEqual(fingerprint(before), oracleSnapshots(for: vm, progress: nil))

        vm.currentRound = 3                          // change this one input only
        let after = vm.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(fingerprint(after), oracleSnapshots(for: vm, progress: nil))
        XCTAssertNotEqual(fingerprint(after), fingerprint(before))
        XCTAssertEqual(after[0].progress, .past, "changing currentRound must invalidate: round 1 becomes past")
        XCTAssertEqual(after[1].progress, .past)
        XCTAssertEqual(after[2].progress, .current)

        // Restoring the original value must restore the original result — the cache
        // can't be a one-shot invalidate-once switch
        vm.currentRound = 1
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)), fingerprint(before),
                       "restoring currentRound should restore the first result")
    }

    /// Degenerate round sets: 1 round / 0 rounds (empty matches) / sparse [7, 3, 19] /
    /// very many (1000 rounds).
    func testRoundSnapshotsHandlesDegenerateRoundSets() {
        // 1) A single round
        let one = FixturesViewModel()
        one.matches = [makeMatch(id: 1, kickoff: "2025-08-21T11:00:00Z", status: "FINISHED", matchday: 1)]
        let oneSnaps = one.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(oneSnaps.count, 1)
        XCTAssertEqual(fingerprint(oneSnaps), oracleSnapshots(for: one, progress: nil))
        XCTAssertEqual(oneSnaps[0].progress, .current)
        XCTAssertEqual(oneSnaps[0].previews.map(\.id), [1])

        // 2) Empty matches → empty availableRounds → the 38 fallback; no crash, no OOB
        let empty = FixturesViewModel()
        let emptySnaps = empty.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(emptySnaps.count, 38)
        XCTAssertEqual(fingerprint(emptySnaps), oracleSnapshots(for: empty, progress: nil))
        XCTAssertTrue(emptySnaps.allSatisfy { $0.previews.isEmpty }, "all placeholders without data")

        // 3) Sparse, non-contiguous round numbers
        let sparse = FixturesViewModel()
        sparse.matches = [
            makeMatch(id: 7, kickoff: "2025-10-01T11:00:00Z", status: "SCHEDULED", matchday: 7),
            makeMatch(id: 3, kickoff: "2025-09-01T11:00:00Z", status: "FINISHED", matchday: 3),
            makeMatch(id: 19, kickoff: "2025-12-01T11:00:00Z", status: "SCHEDULED", matchday: 19),
        ]
        XCTAssertEqual(sparse.availableRounds, [3, 7, 19], "round numbers should be ascending")
        let sparseSnaps = sparse.roundSnapshots(seasonProgress: nil)
        XCTAssertEqual(sparseSnaps.count, 19, "total rounds comes from availableRounds.last")
        XCTAssertEqual(fingerprint(sparseSnaps), oracleSnapshots(for: sparse, progress: nil))
        XCTAssertEqual(sparseSnaps.map(\.round), Array(1...19),
                       "rounds must fill 1...max contiguously, never skip with the data's holes")
        XCTAssertEqual(sparseSnaps[2].previews.map(\.id), [3])
        XCTAssertEqual(sparseSnaps[6].previews.map(\.id), [7])
        XCTAssertEqual(sparseSnaps[18].previews.map(\.id), [19])
        XCTAssertTrue(sparseSnaps[0].previews.isEmpty, "round 1 without data → an empty placeholder, never another round's data")

        // 4) Very many rounds: the stress case for "render everything at once"; 1000 rounds must not crash
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

    /// New `matches` content with unchanged `seasonProgress` — only `indexGeneration`
    /// can invalidate this.
    func testRoundSnapshotsInvalidatesWhenMatchesContentChanges() {
        let vm = FixturesViewModel()
        vm.matches = sampleMatches()
        let p = SeasonProgress(currentRound: 2, totalRounds: 3, playedRounds: 1,
                               remainingRounds: 2, fraction: 1.0 / 3.0, seasonYear: 2025)

        let first = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(first[0].previews.map(\.id), [1, 2])
        XCTAssertEqual(fingerprint(first), oracleSnapshots(for: vm, progress: p))

        // A completely different set of matches; seasonProgress untouched
        vm.matches = [
            makeMatch(id: 71, kickoff: "2025-08-21T09:00:00Z", status: "FINISHED", matchday: 1),
            makeMatch(id: 72, kickoff: "2025-09-04T09:00:00Z", status: "FINISHED", matchday: 3),
        ]
        let second = vm.roundSnapshots(seasonProgress: p)
        XCTAssertEqual(fingerprint(second), oracleSnapshots(for: vm, progress: p))
        XCTAssertNotEqual(fingerprint(second), fingerprint(first))
        XCTAssertEqual(second[0].previews.map(\.id), [71], "snapshots must follow the new data, never the old cache")
        XCTAssertEqual(second[2].previews.map(\.id), [72])

        // Same content reassigned (indexGeneration bumps) → still oracle-consistent
        vm.matches = vm.matches
        XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                       oracleSnapshots(for: vm, progress: p))
    }

    /// Cross-product of input mutations, checked against the oracle at every step,
    /// catching "should have invalidated but didn't".
    ///
    /// ⚠️ Version one of this test was a **false pass**: it reassigned
    /// `vm.seasonProgress` / `vm.matches` in a loop, and those didSet hooks
    /// unconditionally cleared the cache — so no matter what SnapshotCacheKey
    /// compared, everything recomputed and the test stayed green forever.
    /// The key is the **only line of defense** in exactly one scenario: **the function
    /// argument differs from the stored properties** (no didSet fires; only the key
    /// comparison can save you). Hence round one never writes the properties.
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

        // —— Round one: the key is the only defense. No more vm.seasonProgress /
        //    vm.matches writes from here on. ——
        vm.seasonProgress = progresses[1]
        for pass in 0..<2 {
            for (i, p) in progresses.enumerated() {
                for (j, q) in progresses.enumerated() {
                    _ = vm.roundSnapshots(seasonProgress: p)
                    XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: q)),
                                   oracleSnapshots(for: vm, progress: q),
                                   "pass\(pass): after switching the argument #\(i) → #\(j) a stale snapshot was served — " +
                                   "is seasonProgress missing from SnapshotCacheKey?")
                }
            }
            vm.currentRound = 4
            XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: nil)),
                           oracleSnapshots(for: vm, progress: nil),
                           "pass\(pass): after changing only currentRound a stale snapshot was served — " +
                           "both the didSet and the key failed at once")
            vm.currentRound = 2
        }

        // —— Round two: change matches content (the indexGeneration path) ——
        for k in 0..<3 {
            vm.matches = sampleMatches() + [
                makeMatch(id: 900 + k, kickoff: "2025-09-11T11:00:00Z",
                          status: "FINISHED", matchday: 2),
            ]
            for (i, p) in progresses.enumerated() {
                XCTAssertEqual(fingerprint(vm.roundSnapshots(seasonProgress: p)),
                               oracleSnapshots(for: vm, progress: p),
                               "stale snapshot after match change \(k) / argument #\(i)")
            }
        }
    }

    // MARK: - QA: lazy containers & layout red lines

    /// Statically scan the source for the lazy structure (stricter than "contains
    /// LazyHStack"): the LazyHStack must be the horizontal ScrollView's **first direct
    /// child** — anything in between could be "lazy inside lazy", the layout-deadlock
    /// red line.
    func testRoundChipBarLazyHStackIsDirectChildOfHorizontalScrollView() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        XCTAssertEqual(count(of: "ScrollView(.horizontal", in: code), 1,
                       "expected exactly one horizontal ScrollView (the chip bar); if the structure changes, update this guard")

        guard let sv = code.range(of: "ScrollView(.horizontal") else {
            return XCTFail("horizontal ScrollView not found")
        }
        guard let brace = code[sv.upperBound...].firstIndex(of: "{") else {
            return XCTFail("no content block after the horizontal ScrollView")
        }
        var i = code.index(after: brace)
        while i < code.endIndex, code[i].isWhitespace { i = code.index(after: i) }
        let firstToken = code[i...]
        XCTAssertTrue(firstToken.hasPrefix("LazyHStack"),
                      "the horizontal ScrollView's first direct child must be LazyHStack, nothing else (" +
                      "lazy inside lazy deadlocks layout; reverting to HStack builds every view at once). " +
                      "Actual prefix: \(firstToken.prefix(40))")

        guard let fn = code.range(of: "func roundChipBar") else {
            return XCTFail("roundChipBar not found")
        }
        // hasPrefix("LazyHStack") above already rules out a plain HStack regression
        // (contains("HStack(spacing: 8)") can't be used — LazyHStack contains that substring)
        XCTAssertTrue(code[fn.lowerBound...].contains(".frame(height: 32)"),
                      "roundChipBar's horizontal ScrollView must keep .frame(height: 32)")
        XCTAssertTrue(code[fn.lowerBound...].contains("roundPageButton"),
                      "both paging buttons should reuse roundPageButton for identical styling and a11y copy")
        // Fixed window: the chip bar renders only the window's rounds, never all of availableRounds
        XCTAssertTrue(code[fn.lowerBound...].contains("vm.visibleRounds"),
                      "the chip bar must render vm.visibleRounds (the fixed window); " +
                      "ForEach(vm.availableRounds) would scale rendering linearly with total rounds")
    }

    /// Project-wide hard red lines: nested lazy containers / unbounded GridItem /
    /// URLSession.shared / hardcoded .help strings.
    func testSourcesHaveNoLayoutOrNetworkRedLines() throws {
        let violations = try allSourceFiles().flatMap { f -> [String] in
            let code = codeOnly(f.text)
            var v: [String] = []
            if code.contains("LazyVStack") {
                v.append("\(f.name): LazyVStack found (nested lazy containers deadlock layout negotiation)")
            }
            if code.contains("maximum: .infinity") {
                v.append("\(f.name): GridItem's maximum must not be .infinity")
            }
            if code.contains("URLSession.shared") {
                v.append("\(f.name): URLSession.shared is banned (its 7-day resource timeout makes await never return)")
            }
            if code.contains(".help(\"") {
                v.append("\(f.name): .help( contains a hardcoded string literal; it must go through UIString")
            }
            return v
        }
        XCTAssertEqual(violations, [], "hard-constraint red lines violated:\n" + violations.joined(separator: "\n"))
    }

    /// Character-by-character brace-depth scan detecting any lazy container inside
    /// another lazy container. Stronger than contains("LazyVStack"): catches renamed
    /// lazy containers too.
    func testNoLazyContainerNestedInsideAnotherLazyContainer() throws {
        for f in try allSourceFiles() {
            let v = lazyNestingViolations(codeOnly(f.text))
            XCTAssertEqual(v, [], "\(f.name) has nested lazy containers: \(v.joined(separator: "; "))")
        }
    }

    /// A horizontal ScrollView inside a vertical one must have a definite height,
    /// otherwise infinite size negotiation deadlocks the main thread.
    func testHorizontalScrollViewsAreHeightConstrained() throws {
        for f in try allSourceFiles() {
            let code = codeOnly(f.text)
            var search = code.startIndex
            while let r = code.range(of: "ScrollView(.horizontal", range: search..<code.endIndex) {
                // A long window is needed: the horizontal ScrollView's content block
                // (LazyHStack + chips) is itself over a thousand characters.
                let windowEnd = code.index(r.upperBound, offsetBy: 3000, limitedBy: code.endIndex)
                    ?? code.endIndex
                XCTAssertTrue(code[r.upperBound..<windowEnd].contains(".frame(height:"),
                              "\(f.name): the horizontal ScrollView lacks .frame(height:) — " +
                              "nested in a vertical one it negotiates sizes with its parent forever")
                search = r.upperBound
            }
        }
    }
}
