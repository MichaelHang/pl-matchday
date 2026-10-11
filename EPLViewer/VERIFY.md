# EPL Viewer — 本地编译运行验证报告（v2.1）

> 验证时间：2026-08-23 15:05 ｜ 验证环境：macOS 26.5.2 + Xcode 26.6 + Swift 6.3.3

> ⚠️ 工程形态已变更（2026-09-30）：移除 `Package.swift` 与 `project.yml`，转为纯 Xcode 工程。下文历史命令中的 `swift build/test` 仅作当时记录，当前请改用 `xcodebuild`（见文末「你本机使用方式」）。

## ✅ 编译通过
```bash
swift build --disable-sandbox --package-path /Users/hangbo/Code/Github/PremierLeague/EPLViewer
# Build complete! (0.15s)
```

**修复的编译错误**（静态审查漏掉的真实问题）：
1. `Package.swift` `.macOS(.v26)` 需要 swift-tools 6.2 → 改为字符串 `.macOS("26.0")`
2. ESPN/FPL 原生类型只声明 `Decodable`，但要写入 `CacheStore` → 改为 `Codable`
3. `DataRepository` 5 处 `try? ... ?? []` 写法错（`try?` 把整个表达式包成 Optional）→ 改为 `(try? ...) ?? []`
4. Swift 6 actor 隔离：5 个 ViewModel 的 `load()` 需要 `@MainActor`（@Observable 类默认 MainActor，但 `load()` 是 async）
5. `AppState` 在 `Task { await appState.clearCacheAndRefresh() }` 中跨 actor 传递 → 标记 `@MainActor`
6. `StandingsView` 的 `TableRow.background(_:)` 在 macOS 26 SDK 不可用 → **重写为 List + listRowBackground 方案**（保留升降级区着色功能）
7. `SettingsView` 的 `.glassBackgroundEffect()` 不存在 → 改为 `.glassEffect()`

## ✅ 测试全部通过（17/17）
```bash
swift test --disable-sandbox --package-path /Users/hangbo/Code/Github/PremierLeague/EPLViewer
```
```
testAssistStableSort ............... passed
testCacheTTLIsValid ................ passed
testESPNScoreboardTranslation ..... passed
testESPNStandingsTranslation ...... passed
testExample ........................ passed
testFPLAssistsDerivation ........... passed
testFPLBootstrapDecoding ........... passed
testFPLInjuriesDerivation .......... passed
testFPLTeamsDerivation ............. passed
testInjuriesDecoding ............... passed
testMatchesDecoding ................ passed
testScorersDecoding ................ passed
testScorerStableSort ............... passed
testShouldFallback ................. passed
testStandingsDecoding .............. passed
testStatusTranslator ............... passed
testTeamsDecoding .................. passed
Test Suite 'All tests' passed
```

**修复的测试错误**：
- 积分榜 JSON 最后一行手误（`playedGames:9` 应为 `won:9`）→ 修正
- `StatusTranslator` 缺 `STATUS_SCHEDULED → SCHEDULED` 分支 → 补全
- FPL/ESPN native 解码用了 `convertFromSnakeCase` 但 Swift 字段就是 snake_case → 新增 `makeNativeDecoder()` 辅助方法

## ✅ App 启动验证
```bash
swift build -c release --disable-sandbox --package-path /Users/hangbo/Code/Github/PremierLeague/EPLViewer
# Build complete! (8.32s)
/Users/hangbo/Code/Github/PremierLeague/EPLViewer/.build/arm64-apple-macosx/release/EPLViewer &
# PID=25302，启动后稳定运行（lsof 看到访问 dyld / SystemAppearance 等系统框架）
```

## 二进制位置
- Debug: `/Users/hangbo/Code/Github/PremierLeague/EPLViewer/.build/arm64-apple-macosx/debug/EPLViewer`
- Release: `/Users/hangbo/Code/Github/PremierLeague/EPLViewer/.build/arm64-apple-macosx/release/EPLViewer`

## 你本机使用方式（纯 Xcode 工程，已移除 Package.swift / project.yml）

```bash
cd /Users/hangbo/Code/Github/PremierLeague/EPLViewer
xed .                                  # 用 Xcode 打开工程
xcodebuild -scheme EPLViewer -configuration Debug test    # 跑全部单元测试
xcodebuild -scheme EPLViewer -configuration Release build  # 编译发布版
./build-app.sh                         # 打 EPLViewer.app Bundle
```

## v2.1 → v2 的增量改动
- 修正静态审查漏掉的 7 处编译错误
- 修正 3 处测试错误（手误/缺分支/解码器策略）
- 重写 StandingsView 用 List 替代 Table（更可靠，保留升降级区高亮）
- 无功能性破坏，纯修复