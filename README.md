# EPLViewer - 英超联赛信息查看 App

一款 macOS 26 原生 SwiftUI App（Liquid Glass 视觉），混合数据源查看英超赛季信息。

## 功能板块

- **积分榜**：实时排名，升降级区高亮（ESPN v3，记录缺失时从赛程实时聚合）
- **赛程**：整季赛程一次拉取（FPL fixtures，ESPN scoreboard 兜底）
- **球队与球员**：8+ 球队详情，含完整 squad（FPL bootstrap）
- **射手榜 / 助攻榜**：进球/助攻排行（FPL 派生）
- **伤停榜**：伤情状态、可出战概率（FPL 派生）

## 数据源

| 数据 | 来源 | 缓存 TTL |
|---|---|---|
| 完整赛程 / 比分 | FPL fixtures（ESPN scoreboard 兜底） | 5 分钟（手动刷新绕过） |
| FPL bootstrap（球队/球员/射手/助攻/伤停） | Fantasy Premier League 公开端点 | 2 小时 |
| 积分榜 / 当日赛果 | ESPN v3 | 各 5 分钟 |

零 API Key、零 Python 依赖。断网自动回退**上次缓存的数据**（stale-if-error，忽略缓存 TTL）；全新安装且从未成功联网时显示空状态，不内置任何假数据。

---

## 开发与构建

### 方式 1：直接用 Xcode 26 打开（推荐）

```bash
open /Users/hangbo/Code/Github/PremierLeague/EPLViewer.xcodeproj
# Xcode 里 Cmd+R 运行（Cmd+U 跑测试）
```

> Xcode 26 GUI 在 macOS 26 下用原生进程环境编译，**Liquid Glass、`@Observable`、Observation 宏全部原生支持**，不会有 sandbox 下子进程派生问题。

### 方式 2：用命令行 xcodebuild

```bash
cd /Users/hangbo/Code/Github/PremierLeague/EPLViewer
xcodebuild -scheme EPLViewer -configuration Debug build       # 编译
xcodebuild -scheme EPLViewer -configuration Debug test        # 跑单元测试
xcodebuild -scheme EPLViewer -configuration Release build     # 发布编译
```
> 工程已是**纯 Xcode 工程**（`EPLViewer.xcodeproj`），不再有 `Package.swift` / `project.yml` / XcodeGen。

### 方式 3：打 .app 包后用 Finder 启动

```bash
cd /Users/hangbo/Code/Github/PremierLeague/EPLViewer
./build-app.sh                # 用 xcodebuild 编译 release 并打 build/EPLViewer.app
open build/EPLViewer.app      # 在 Finder 双击也可
```

---

## 工程结构

```
.                                 # 仓库根 = 项目根
├── EPLViewer.xcodeproj           # Xcode 工程（真源，手工维护，纳入版本管理）
├── EPLViewer/                    # 主 target 源码
│   ├── App/                      # 入口与全局壳：@main / AppState / ContentView / SettingsView / Sidebar / TopBar
│   ├── Core/                     # 数据层：Models / Networking（ESPN+FPL 客户端）/ Cache / Translators / DataRepository / Support
│   ├── Features/                 # 板块视图：Today / Fixtures / Standings / LeadersAndInjuries
│   ├── Localization/             # 译名：TranslationStore + PlayerNames + TeamNames + Resources/*.json
│   └── Common/                   # CommonViews（三态视图 / CrestImage / 品牌色）+ UIStrings
├── EPLViewerTests/               # 200+ 项单元测试（按域拆分：Today / Fixtures / Standings / Scheduler / Localization / Guard）
├── Tools/                        # player_names_editor.py（译名辅助工具）
├── docs/                         # 设计文档（history/ 内为历史交付快照）
└── build-app.sh                  # 用 xcodebuild 打 .app Bundle
```

## 维护说明（纯 Xcode 工程）

- **新增 / 移动源文件**：在 Xcode 中拖入或移除即可（会自动写入 `EPLViewer.xcodeproj/project.pbxproj`）；纯命令行场景可手改 pbxproj 的 `PBXBuildFile` / `PBXFileReference` / `PBXSourcesBuildPhase` 三段。
- **不再有** `Package.swift`、`project.yml`，也没有 XcodeGen 生成步骤。`EPLViewer.xcodeproj` 即为唯一真源，增删文件后无需再跑任何生成命令。

## 已知限制

- **首次安装且断网**：没有任何本地数据可显示（不内置假样例），联网成功一次后即有缓存兜底
- **数据 ID 跨源**：积分榜（ESPN）与球员数据（FPL）用不同 id 体系
- **首次启动延迟**：拉一次 FPL bootstrap（~1MB），之后 2 小时缓存
