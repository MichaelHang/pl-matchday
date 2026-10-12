import Foundation
import SwiftUI

// MARK: - 调试期球员中文名覆盖层
//
// 开发者在 DEBUG 面板里可视化编辑球员的中文名；覆盖层持久化到
// `~/Library/Application Support/<bundleId>/playerNameOverrides.json`，
// 永不写进仓库。纯函数 `PlayerNameMap.zh(for:)` 通过 `PlayerNameStore.current`
// 同步读取最新覆盖，从而不需要任何 actor / 异步跳转。

/// 覆盖层数据：覆盖 `PlayerNameMap.zhById` / `zhByName` 的开发者自定义中文名。
/// 主键维度 `byId`（FPL element id）优先级最高，次级维度 `byName`（web_name）。
struct PlayerNameOverrides: Codable, Equatable {
    /// 按 FPL element id 覆盖（主键维度，跨赛季/转会稳定，优先级最高）
    var byId: [Int: String] = [:]
    /// 按 web_name 覆盖（二级维度，碰撞时以最后一个为准）
    var byName: [String: String] = [:]
}

/// 覆盖层存储。
///
/// - 普通 Swift 对象（不挂任何 global actor），保证单测可以直接同步调用。
/// - 每次 mutation 都会更新静态快照 `current`，供纯解析函数同步读取。
/// - `ObservableObject` 让 DEBUG 面板的行视图能观察 `overrides` 变化（覆盖徽标等）。
final class PlayerNameStore: ObservableObject {
    /// 同步快照：每次 mutation 更新，供纯函数 `PlayerNameMap.zh(for:)` 同步读取覆盖层。
    /// 非隔离静态变量，测试里可直接赋值/复位（App 实际只在主线程访问，故用 `nonisolated(unsafe)`）。
    nonisolated(unsafe) static var current: PlayerNameOverrides = .init()

    /// 单例；首次访问即加载磁盘上已有的覆盖层（文件不存在则保持默认空值）。
    nonisolated(unsafe) static let shared = PlayerNameStore()

    /// 当前内存中的覆盖层（等价于 `current`，供 SwiftUI 观察）。
    @Published var overrides = PlayerNameOverrides()

    /// 覆盖层 JSON 落盘路径。
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let bundleId = Bundle.main.bundleIdentifier ?? "com.eplviewer.app"
        let dir = support.appendingPathComponent(bundleId, isDirectory: true)
        self.fileURL = dir.appendingPathComponent("playerNameOverrides.json", isDirectory: false)
        load()
    }

    /// 若文件存在则解码进 `overrides` 并刷新静态快照；否则保持默认。
    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(PlayerNameOverrides.self, from: data) else { return }
        overrides = decoded
        PlayerNameStore.current = decoded
    }

    /// 创建目录（如需）并把 `overrides` 编码写盘。
    func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 用一份完整覆盖层替换并落盘（供全局保存按钮）。
    func commit(_ overrides: PlayerNameOverrides) {
        self.overrides = overrides
        PlayerNameStore.current = overrides
        save()
    }

    /// 按 id 设置覆盖：空名视为删除该覆盖。
    func set(id: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides.byId.removeValue(forKey: id)
        } else {
            overrides.byId[id] = trimmed
        }
        PlayerNameStore.current = overrides
        save()
    }

    /// 按 web_name 设置覆盖：空名视为删除该覆盖。
    func set(webName: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            overrides.byName.removeValue(forKey: webName)
        } else {
            overrides.byName[webName] = trimmed
        }
        PlayerNameStore.current = overrides
        save()
    }

    /// 删除某 id 的覆盖。
    func reset(id: Int) {
        overrides.byId.removeValue(forKey: id)
        PlayerNameStore.current = overrides
        save()
    }

    /// 删除某 web_name 的覆盖。
    func reset(webName: String) {
        overrides.byName.removeValue(forKey: webName)
        PlayerNameStore.current = overrides
        save()
    }
}
