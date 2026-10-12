import SwiftUI

import SwiftUI

// MARK: - App 入口

@main
struct EPLViewerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                // 最小高度按「积分榜完整显示 20 队」估算：表头 + 20 行 ≈ 600，
                // 加上导航栏 toolbar(~52) 与列表内边距，取 675 留出余量。
                // 不再为 ScrollView 兜底而撑得更大（之前 680 → 240 那次改太极端了）。
                .frame(minWidth: 900, minHeight: 675)
        }
    }
}

// MARK: - 界面语言
/// 全局界面语言定义见 UIStrings.swift（AppLanguage 枚举 + UIString 集中文案表）
