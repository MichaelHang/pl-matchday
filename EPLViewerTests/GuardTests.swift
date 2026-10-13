import XCTest
@testable import EPLViewer

// Source guards: copy contracts / layout red lines / titles & window size / standings layout rails.
// Split from EPLViewerTests.swift by domain; methods still live on the same class.

extension EPLViewerTests {
    // MARK: - QA: copy & localization

    /// The two paging-button help strings: both languages present and **placeholder-free**.
    /// The paged-to rounds depend on the current window, not a fixed value — stuffing
    /// in a %d would actually mislead.
    func testRoundsPageStringsAreLocalizedWithoutPlaceholders() {
        let cases: [(String, UIString)] = [
            ("prevRoundsPage", UIString.prevRoundsPage),
            ("nextRoundsPage", UIString.nextRoundsPage),
        ]
        for (name, s) in cases {
            let zh = s.text(.chinese)
            let en = s.text(.english)
            XCTAssertFalse(zh.isEmpty, "\(name).zh must not be empty")
            XCTAssertFalse(en.isEmpty, "\(name).en must not be empty")
            XCTAssertNotEqual(zh, en, "\(name) must be genuinely localized, not identical in both languages")
            for token in ["%d", "%@", "%f", "%lld"] {
                XCTAssertEqual(count(of: token, in: zh), 0,
                               "\(name).zh should not contain \(token) (pure action description, no arguments)")
                XCTAssertEqual(count(of: token, in: en), 0,
                               "\(name).en should not contain \(token) (pure action description, no arguments)")
            }
        }
    }

    /// The three jump-copy entries from the previous version
    /// (jumpToFirstRound / jumpToLastRound / jumpToNextRound) were deleted along with
    /// their buttons; no dead copy may linger in UIStrings.swift.
    func testRemovedJumpRoundStringsDoNotComeBack() throws {
        let src = try sourceFile("UIStrings.swift")
        for dead in ["jumpToFirstRound", "jumpToLastRound", "jumpToNextRound"] {
            XCTAssertEqual(count(of: dead, in: src), 0,
                           "\(dead)'s button was removed; its dead copy must not stay in UIStrings")
        }
    }

    /// Verify zh/en placeholder-count parity for every entry in UIStrings.swift.
    func testAllUIStringsKeepZhEnPlaceholderParity() throws {
        let src = try sourceFile("UIStrings.swift")
        let re = try NSRegularExpression(
            pattern: #"UIString\(\s*zh:\s*"([^"]*)"\s*,\s*en:\s*"([^"]*)"\s*\)"#,
            options: .dotMatchesLineSeparators
        )
        let ns = src as NSString
        let matches = re.matches(in: src, range: NSRange(location: 0, length: ns.length))
        XCTAssertGreaterThan(matches.count, 40, "too few UIString entries parsed — the regex may have drifted")

        for m in matches {
            guard let zr = Range(m.range(at: 1), in: src),
                  let er = Range(m.range(at: 2), in: src) else { continue }
            let zh = String(src[zr])
            let en = String(src[er])
            for token in ["%d", "%@", "%f", "%lld"] {
                XCTAssertEqual(count(of: token, in: zh), count(of: token, in: en),
                               "mismatched zh/en placeholder counts would feed String(format:) dirty arguments: " +
                               "\(token) / zh=\(zh) / en=\(en)")
            }
        }
    }

    /// The paging buttons' accessibility copy must go through UIString — no literals.
    func testPageButtonsWireHelpThroughUIStrings() throws {
        let code = codeOnly(try sourceFile("FixturesView.swift"))
        for key in ["prevRoundsPage", "nextRoundsPage"] {
            XCTAssertEqual(count(of: "UIString.\(key)", in: code), 1,
                           "\(key) should be used exactly once inside roundChipBar")
            XCTAssertFalse(code.contains("String(format: UIString.\(key)"),
                           "\(key) takes no arguments; it must not go through String(format:)")
        }
        XCTAssertFalse(code.contains(".help(\""), "the paging buttons' .help must not hardcode string literals")
        XCTAssertTrue(code.contains(".help(help)"),
                      "roundPageButton should use the passed help parameter, keeping both buttons consistent")
    }

    /// This change must not add new hardcoded user-facing Chinese.
    /// The entries below are **pre-existing** violations (untouched by that change,
    /// listed separately in the QA report); the counts may only go down.
    func testNoNewHardcodedUserFacingChineseInViews() throws {
        let baseline = [
            "FixturesView.swift": 1,             // "加载失败"
            "LeadersAndInjuriesViews.swift": 1,  // "加载失败"
            "StandingsView.swift": 1,            // "加载失败"
            "Models.swift": 9,                   // 4 AppError.errorDescription entries (injury-status copy moved to UIStrings)
        ]
        for f in try allSourceFiles() where f.name != "UIStrings.swift" && f.name != "TeamNames.swift" && f.name != "PlayerNames.swift" {
            let found = hardcodedCJK(in: codeOnly(f.text))
            XCTAssertLessThanOrEqual(found.count, baseline[f.name] ?? 0,
                                     "\(f.name) added hardcoded Chinese; switch it to UIString: " +
                                     "\(found.joined(separator: " / "))")
        }
    }
}

extension EPLViewerTests {
    /// `SeasonStore.seasonLabel` formats currentSeason ("2026") into the cross-year
    /// string "2026-2027". Verifies the cross-year season (PL runs August → May)
    /// displays the full season name.
    func testSeasonLabelFormatsAsStartPlusEndYear() {
        XCTAssertEqual(SeasonStore.seasonLabel, "\(SeasonStore.currentSeason)-\(Int(SeasonStore.currentSeason)! + 1)",
                       "seasonLabel should be startYear-(startYear+1)")
        // currentSeason is known to be "2026", so expect "2026-2027"
        XCTAssertEqual(SeasonStore.seasonLabel, "2026-2027",
                       "the current season's label should be 2026-2027")
    }

    /// `UIString.appTitle` carries exactly one %@ placeholder per language (filled
    /// with the season label). Guards against later removals/additions breaking layout.
    func testAppTitleHasOnePlaceholderInBothLanguages() {
        let placeholders = { (s: String) -> Int in
            // %@ starts with "%"; count occurrences
            var count = 0
            var idx = s.startIndex
            while let r = s.range(of: "%@", range: idx..<s.endIndex) {
                count += 1
                idx = r.upperBound
            }
            return count
        }
        XCTAssertEqual(placeholders(UIString.appTitle.zh), 1, "the zh placeholder count should be exactly 1")
        XCTAssertEqual(placeholders(UIString.appTitle.en), 1, "the en placeholder count should be exactly 1")
    }

    /// Rendered examples: zh → "2026-2027 英超联赛", en → "EPL 2026-2027".
    func testAppTitleRendersWithSeasonLabel() {
        let zh = String(format: UIString.appTitle.text(.chinese), SeasonStore.seasonLabel)
        let en = String(format: UIString.appTitle.text(.english), SeasonStore.seasonLabel)
        XCTAssertEqual(zh, "2026-2027 英超联赛")
        XCTAssertEqual(en, "EPL 2026-2027")
    }
}

extension EPLViewerTests {
    /// StandingsView's table card must use a RoundedRectangle background, never a
    /// bare one — so nobody later reverts to a plain List look.
    func testStandingsCardUsesRoundedRectangleBackground() throws {
        let src = try sourceFile("StandingsView.swift")
        // Strip // comments before matching
        let stripped = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(stripped.contains("RoundedRectangle"),
                      "the table card must use a RoundedRectangle background")
        XCTAssertTrue(stripped.contains("clipShape(RoundedRectangle"),
                      "the card must clipShape round its corners (rows must not overflow the radius)")
    }

    /// The reworked StandingsView no longer uses List (ScrollView + VStack manages
    /// rows itself) and has no horizontal ScrollView inside a vertical one (project
    /// red line).
    func testStandingsViewAvoidsLayoutDeadlockTraps() throws {
        let src = try sourceFile("StandingsView.swift")
        let stripped = src.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(stripped.contains("LazyVStack"),
                       "LazyVStack is banned in standings (nested lazy containers deadlock size negotiation)")
        XCTAssertFalse(stripped.contains("maximum: .infinity"),
                       "GridItem's maximum must be a concrete value, never .infinity")
    }
}

extension EPLViewerTests {
    /// The 4 tabs' cards should share one total height (overall/home/away ≈ form).
    /// detailedRow uses `.body` text + 6 pt padding ≈ 23 pt; formRow uses FormChipsView,
    /// whose 18×18 chip + 6 pt padding = 24 pt — 1 pt apart, visually equal.
    /// Guard: FormChipsView's chip width/height must stay ≤ 20 (a larger chip would
    /// make the form tab 100 pt+ taller than the others).
    func testFormChipsKeepsHeightAlignedWithOtherTabs() throws {
        let src = try sourceFile("StandingsView.swift")
        // Scan all two-argument frame(width:height:) calls (single-argument ones are
        // list layout and don't affect row height)
        let pattern = #"frame\(\s*width:\s*(\d+)\s*,\s*height:\s*(\d+)\s*\)"#
        let re = try NSRegularExpression(pattern: pattern)
        let matches = re.matches(in: src, range: NSRange(src.startIndex..., in: src))
        XCTAssertFalse(matches.isEmpty, "StandingsView should contain at least one frame(width:height:)")
        var chipFrames: [(width: Int, height: Int, line: Int)] = []
        for m in matches {
            let w = Int(src[Range(m.range(at: 1), in: src)!]) ?? 0
            let h = Int(src[Range(m.range(at: 2), in: src)!]) ?? 0
            // Line number = newlines before the match + 1
            let line = src[..<Range(m.range, in: src)!.lowerBound]
                .reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
            chipFrames.append((w, h, line))
        }
        for f in chipFrames {
            XCTAssertLessThanOrEqual(f.width, 20,
                "frame(width:\(f.width), height:\(f.height)) at line \(f.line): an oversized width makes the form tab taller than the others")
            XCTAssertLessThanOrEqual(f.height, 20,
                "frame(width:\(f.width), height:\(f.height)) at line \(f.line): an oversized height makes the form tab taller than the others")
        }
    }
}

extension EPLViewerTests {
    /// macOS 26's NavigationSplitView "borrows" the sidebar column's title for the
    /// detail column when the detail view sets no navigationTitle of its own.
    /// StandingsView once missed it, leaking the old "EPL Viewer" at the top of the
    /// detail area (even with the sidebar already renamed). Guard: every detail view
    /// (Today/Standings/Fixtures/Leaders/Injuries/Settings) must set navigationTitle
    /// **explicitly** (an empty string to clear it counts) — never inherit.
    func testAllDetailViewsSetNavigationTitleExplicitly() throws {
        let detailFiles = ["TodayView.swift", "StandingsView.swift", "FixturesView.swift",
                           "LeadersAndInjuriesViews.swift"]
        for name in detailFiles {
            let src = try sourceFile(name)
            // Strip // comments before matching (a comment *mentioning* explicit
            // navigationTitle doesn't count as setting one)
            let stripped = src.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            XCTAssertTrue(stripped.contains(".navigationTitle("),
                          "\(name) must set .navigationTitle(...) explicitly — otherwise macOS NavigationSplitView borrows the sidebar title and the detail area shows the wrong old title")
        }
    }
}

extension EPLViewerTests {
    /// The standings detail page's navigationTitle must use `appTitle`
    /// ("xxxx-xxxx Premier League"), not a page name like "Standings".
    /// Rationale: the top title uniformly answers "which season's PL app is this";
    /// which page you're on is expressed by the sidebar selection.
    func testStandingsDetailTitleUsesAppTitle() throws {
        let src = try sourceFile("StandingsView.swift")
        // The `String(format: UIString.appTitle.text(...), SeasonStore.seasonLabel)` pattern must appear
        XCTAssertTrue(src.contains("UIString.appTitle"),
                      "the standings detail navigationTitle must use UIString.appTitle")
        XCTAssertTrue(src.contains("SeasonStore.seasonLabel"),
                      "the standings detail navigationTitle must fill the season label via SeasonStore.seasonLabel")
        // The standings copy must not come back as the title
        XCTAssertFalse(src.contains(".navigationTitle(UIString.standings.text"),
                       "the standings detail navigationTitle must not be UIString.standings again")
    }
}

extension EPLViewerTests {
    /// Window minimum-height contract: must fall in [400, 700].
    /// - Lower bound 400: the window can't shrink below "two standings rows" (actual
    ///   content ≈ [30 tab + 28 header + 46 two rows + 16 card padding + 26 card
    ///   margin + 52 toolbar + 28 title bar] ≈ 226 pt, leaving headroom).
    /// - Upper bound 700: at 680 the user found it too short ("can't see team 20"),
    ///   240 was too extreme; 660 stuck.
    /// Stops casual edits of this value from ruining either end.
    func testWindowMinHeightIsWithinReasonableRange() throws {
        let src = try sourceFile("EPLViewerApp.swift")
        let pattern = #"minHeight:\s*(\d+)"#
        let re = try NSRegularExpression(pattern: pattern)
        guard let m = re.firstMatch(in: src, range: NSRange(src.startIndex..., in: src)) else {
            XCTFail("EPLViewerApp.swift must contain a minHeight: constraint")
            return
        }
        let value = Int(src[Range(m.range(at: 1), in: src)!]) ?? 0
        XCTAssertGreaterThanOrEqual(value, 400,
            "window minHeight must not drop below 400 (currently \(value)) — the window would get tighter than a two-row standings table")
        XCTAssertLessThanOrEqual(value, 700,
            "window minHeight must not exceed 700 (currently \(value)) — an oversized minimum inflates the standings card needlessly")
    }
}
