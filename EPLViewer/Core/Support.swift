import Foundation

// MARK: - 通用支撑（赛季常量 / 时间预算）

// MARK: - 赛季常量

/// 当前赛季常量
/// App 当前只 focus 在 2026-27 赛季（ESPN 的 season=2026，跨年赛季）。
/// 历史赛季相关能力（多赛季切换、缓存 TTL 按赛季隔离）暂不实现。
/// 后续要支持时，在 DataRepository 各 fetch 方法入参加 season 即可扩展。
enum SeasonStore {
    static let currentSeason: String = "2026"

    /// 跨年赛季的显示标签，如 "2026-2027"（英超 8 月开打、次年 5 月收官）。
    /// UI 标题（侧边栏 / 详情页）用这个字符串显示完整赛季名。
    static var seasonLabel: String {
        let start = Int(currentSeason) ?? 2026
        return "\(start)-\(start + 1)"
    }
}

/// 给任意 async 取数加时间预算，超预算即放弃并返回 nil。
///
/// 存在的意义：UI 的「首屏渲染」不该被锦上添花的数据拖死。
/// 比如赛季进度依赖 FPL bootstrap，而该接口在国内实测会慢到几十秒；
/// 与其让用户干等转圈，不如先出比赛列表，进度信息拿不到就算了。
///
/// - 注意：超预算后底层任务会被 cancel，但已经发出去的请求仍会在后台跑完，
///   结果只是被丢弃（不会写坏缓存，因为写入发生在任务内部、取消后即失效）。
/// - Parameter operation: 允许返回 nil（数据源拿不到时的正常结果），
///   所以泛型 T 是**非可选**的结果类型，避免 `T??` 双重可选把调用方绕晕。
func withTimeBudget<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        // 谁先完成用谁：正常返回取第一个（可能是数据，也可能是超时哨兵）
        let first = await group.next()
        group.cancelAll()
        return first ?? nil
    }
}
