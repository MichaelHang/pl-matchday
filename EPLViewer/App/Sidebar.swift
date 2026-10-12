import SwiftUI

/// 左侧 Liquid Glass 导航栏
struct Sidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        List(AppState.AppSection.allCases, selection: $appState.selected) { section in
            Label(section.title(appState.language), systemImage: section.systemImage)
                .tag(section)
                .padding(.vertical, 4)
        }
        .listStyle(.sidebar)
        .navigationTitle(String(format: UIString.appTitle.text(appState.language),
                                SeasonStore.seasonLabel))
        // 注意：不要在 List 这种自拉伸容器上叠 .glassEffect()。
        //   macOS 26 SDK 下会把整棵子树撑成椭圆玻璃，曾出现"侧边栏一个巨大圆圈"的视觉 bug。
        //   列表行的玻璃感由 .listStyle(.sidebar) 自带的材质提供，已经足够。
    }
}
