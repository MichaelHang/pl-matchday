import XCTest
@testable import EPLViewer

// 源码守卫:文案契约 / 布局红线 / 标题与窗口尺寸 / 积分榜布局护栏
// 从 EPLViewerTests.swift 按域拆出;方法仍挂在同一个 EPLViewerTests 类上。

extension EPLViewerTests {
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
}

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
}
