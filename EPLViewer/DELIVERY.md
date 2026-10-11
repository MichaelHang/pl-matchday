# EPL Viewer —— 英超信息查看 macOS App（交付总览 v2）

> 交付时间：2026-08-23 ｜ 团队：software-epl-app（主理人齐活林）
> 工作流：产品经理(许清楚) → 架构师(高见远) → 工程师(寇豆码) → QA(严过关)
> 运行要求：**macOS 26 (Tahoe) + Xcode 26（Swift 6.0）**，因使用 Liquid Glass API

## TL;DR（v2 重要更新）
一款 SwiftUI 原生 macOS App，采用 **Liquid Glass** 视觉，提供英超「**积分榜 / 赛程 / 球队与球员 / 射手榜 / 助攻榜 / 伤停榜**」六大板块。数据层**重做**：去掉 football-data.org API Key 依赖，改用 **ESPN 公开端点（积分榜/赛程/赛果/球队） + FPL 公开端点（球员累计进球/助攻/伤停）**，均无需 API Key；**按你的分级策略**缓存：赛程按整季长缓存、积分榜 60s、赛果 5min、FPL bootstrap 2h。**离线/网络异常时自动回退到内置示例 JSON**，顶部徽标明确标识「在线/示例数据」。**App 本身零 Python、零 API Key 依赖**。

## 交付物位置
- 工程根目录：`/Users/hangbo/Code/Github/PremierLeague/EPLViewer/`
- 架构设计文档：`/Users/hangbo/Code/Github/PremierLeague/docs/`（system_design.md / class-diagram.mermaid / sequence-diagram.mermaid，v1 版本；v2 数据层重构后核心文件已更新，文档待同步）

## 数据源对比（v1 → v2）
| 项目 | v1 | v2 |
|---|---|---|
| 实时数据源 | football-data.org（需 API Key、限频 10/min、只给单赛季） | **ESPN 公开端点 + FPL 公开端点（均无 Key）** |
| 球队球员 | football-data.org `/teams/{id}` | FPL `bootstrap-static`（含全量球员 + 进球/助攻/伤停状态） |
| 射手榜 | football-data.org `/scorers` | FPL bootstrap 派生 |
| 助攻榜 | 无 | **FPL bootstrap 派生（新增）** |
| 伤停榜 | 无 | **FPL bootstrap 派生（新增）** |
| 缓存 | 无 | **按数据分级 TTL（赛程 30d / bootstrap 2h / 积分榜 60s / 赛果 5min）** |
| 设置面板 | API Key 输入框 | 已删除，改为「清空本地缓存」 |

## 文件清单（v2 共 20 个文件 + 1 文档）
```
EPLViewer/
├── Package.swift                              # SwiftPM, macOS .v26, executableTarget+resources
├── DELIVERY.md                                # 本文件
├── Sources/EPLViewer/
│   ├── EPLViewerApp.swift                     # @main, AppState(7 个 AppSection), Settings(去 Key,加缓存清理)
│   ├── Models.swift                           # 内部模型 + Assist + Injury + InjuriesResponse
│   ├── Services.swift                         # ★ 重写: SeasonStore / CacheStore(actor) / CacheTTL / ESPNProvider / FPLProvider /
│   │                                          #          FPLTranslator / ESPNTranslator / StatusTranslator /
│   │                                          #          LocalDataLoader / DataRepository(回退+缓存)
│   ├── Sidebar.swift                          # Liquid Glass 左侧导航（自动联动 6 板块）
│   ├── TopBar.swift                           # ToolbarContent（来源徽标改为"在线/示例数据"）
│   ├── StandingsView.swift                    # 积分榜 Table + 升降级区高亮
│   ├── FixturesView.swift                     # 赛程分组 + 未赛/已赛筛选
│   ├── TeamsScorersViews.swift                # 球队网格+详情 / 射手榜(前三奖牌)
│   ├── AssistsAndInjuriesViews.swift          # ★ 新增: AssistsView(前三奖牌) + InjuriesView(状态标签+出场概率)
│   ├── CommonViews.swift                      # Loading/Empty/Error/CrestImage/Color hex/eplPurple/eplGreen
│   └── Resources/
│       ├── standings.json   matches.json      # 内置示例（football-data.org 格式，作离线兜底）
│       ├── teams.json       scorers.json
│       └── injuries.json                     # ★ 新增: 伤停示例数据（4 条，含 status/news/出场概率）
└── Tests/EPLViewerTests/EPLViewerTests.swift  # 14 项测试（解码/排序/回退/缓存TTL/FPL派生/ESPN翻译/状态映射）
```

## 如何运行
```bash
cd /Users/hangbo/Code/Github/PremierLeague/EPLViewer
swift run     # 首次启动会自动拉取公开数据（无需 Key）
swift test    # 跑 14 项单元测试
# 或 xed . 用 Xcode 打开 → Run
```
**首次启动**：因 `bootstrap-static` 体积较大（~1MB JSON），会稍微慢 1-2s。后续启动命中本地缓存，秒开。

## 数据获取流程（v2）
1. **App 启动** → 用户进入任一板块 → 视图 `.task(id: refreshNonce)` 触发
2. **DataRepository** 检查 `CacheStore` 是否有未过期的缓存
   - **命中** → 直接用缓存数据（`.live`）
   - **未命中** → 调对应 Provider 拉取（ESPN / FPL）
3. **拉取成功** → 写入 `CacheStore`（落盘到 `~/Library/Application Support/EPLViewer/cache/`，不同数据不同 TTL）
4. **拉取失败**（断网/超时/429/无本地缓存） → 回退到 `LocalDataLoader` 读内置 JSON（`.sample`）
5. **TopBar 徽标**实时显示当前板块的数据来源（live → 亮绿圆点「在线」；sample → 橙色圆点「示例数据」）

## 缓存策略（你的分级方案）
| 数据 | Provider | TTL | 说明 |
|---|---|---|---|
| 完整赛程 | ESPN `/schedule?season=YYYY` | **30 天** | 整赛季基本不变，按赛季长缓存 |
| 积分榜 | ESPN `/standings` | **60 秒** | 变化频繁，短 TTL |
| 赛果 | ESPN `/scoreboard` | **5 分钟** | 按天刷新 |
| FPL bootstrap | FPL `/bootstrap-static` | **2 小时** | 含全量球员+积分，仅每场后更新 |
| 球队 | 派生自 bootstrap | 同 bootstrap | 1 次 bootstrap → 6 板块全部受益 |
| 射手榜/助攻榜/伤停榜 | 派生自 bootstrap | 同 bootstrap | 本地 sort/filter，零额外请求 |
| 各队球员名单 | 派生自 bootstrap | 同 bootstrap | TeamDetailView 直接读 Team.squad |

## 已知限制（诚实记录）
1. **沙箱无 swift 工具链，未实际编译**。需 macOS 26 + Xcode 26 用 `swift test` / `swift run` 验证编译。
2. **球队 ID 在 live 模式下跨源不一致**：积分榜用 ESPN id，球队列表/球员用 FPL id。Views 按 name+crest 展示，**不影响使用**；跨源点击跳转（如点积分榜某队→球队详情）未做，留 v3。
3. **FPL bootstrap 不含球员号码/国籍**（FPL 端点就没给），live 模式下球队详情的「号码/国籍」列为 `—`；offline 兜底数据完整。
4. **首次启动有 1-2s 拉取 bootstrap 的延迟**（~1MB JSON），之后秒开（命中 2h 缓存）。
5. **FPL `events` 字段**（gameweeks）已解码但暂未使用（赛程信息已通过 ESPN 获取）；保留以便未来做"当前轮次"高亮。

## 验证说明
- **必须 macOS 26 + Xcode 26** 验证（Liquid Glass API 依赖 26 SDK）。
- 测试覆盖：内联 JSON 解码（standings/matches/teams/scorers/injuries）、回退决策、缓存 TTL、射手/助攻稳定排序、FPL bootstrap 解码与派生（scorers/assists/injuries/teams+crest+squad）、ESPN 原生解码与翻译（含状态映射）。
- **建议优先级验证**：
  1. 编译通过（`swift build` / Xcode Run）
  2. 跑 14 项测试（`swift test`）
  3. 启动后看 SourceBadge 是否为「在线」（亮绿）
  4. 飞行模式启动 → 自动回退到「示例数据」（橙色）
  5. 设置 → 「清空本地缓存」→ 再回到主界面 → 重新拉取
