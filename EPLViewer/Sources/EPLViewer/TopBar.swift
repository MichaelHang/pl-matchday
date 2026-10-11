import SwiftUI

/// 顶部工具栏内容（仅保留手动刷新按钮）
/// 说明：之前这里有三个 ToolbarItem — 刷新 / 数据来源徽标 / 设置入口。
///   - 数据来源徽标（"在线" / "示例数据"）已移除，避免干扰主信息；
///     真实回退场景下对应列表会为空，本身就是信号。
///   - 设置入口已从工具栏移除，保留在左侧栏（"设置" 项）。
struct TopBar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        @Bindable var appState = appState

        ToolbarItem {
            Button {
                Task { await appState.refresh() }
            } label: {
                Label(UIString.refresh.text(appState.language), systemImage: "arrow.clockwise")
            }
            .disabled(appState.isLoading)
        }
    }
}
