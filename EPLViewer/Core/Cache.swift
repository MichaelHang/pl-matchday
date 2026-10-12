import Foundation

// MARK: - 缓存层（内存 + 磁盘，TTL）

// MARK: - 缓存层（on-disk JSON with TTL）

/// 缓存 TTL 配置（不同数据使用不同过期时长）
enum CacheTTL {
    /// 赛程/比分：懒刷新 TTL（仅约束「切 tab / 启动」等被动取数的新鲜度）。
    /// Match 内含实时比分，已结束比赛的比分会随赛后更新；
    ///   但 TTL 只决定「被动取数多久算陈旧」，手动刷新会先清缓存强制拿最新，
    ///   因此这里给一个浏览友好的 5 分钟——平时不频繁打扰网络，
    ///   想立刻看结果时点右上角刷新即可（绕过此 TTL）。
    static let fixtures: TimeInterval = 60 * 5
    /// FPL bootstrap：携带球队/射手/助攻/伤停数据，每场比赛后才会更新，缓存 2 小时
    static let bootstrap: TimeInterval = 60 * 60 * 2
    /// 积分榜：懒刷新 TTL（同 fixtures，5 分钟）。手动刷新同样绕过。
    static let standings: TimeInterval = 60 * 5
    /// 赛果：按日刷新即可，缓存 5 分钟
    static let scoreboard: TimeInterval = 60 * 5

    /// 纯函数：判断缓存是否在 TTL 内（便于单测）
    static func isValid(mtime: Date, ttl: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(mtime) < ttl
    }
}

/// 进程内内存缓存（actor 保证线程安全）
///
/// 磁盘缓存（CacheStore）解决「跨 App 启动」的持久化，但每次取数都要
/// 读文件 + JSONDecoder 全量解码 —— 切一次 tab 就把 bootstrap 解两遍
/// （currentGameweek + gameweeks），既慢又白耗电。
/// 这里补一层内存缓存：同一生命周期内只解码一次，之后直接返回内存对象。
///
/// ⚠️ 手动刷新 / 清缓存时必须一并清空（见 DataRepository.clearCache），
/// 否则清完磁盘仍会命中内存里的旧数据。
actor MemoryStore {
    static let shared = MemoryStore()

    private var bootstrap: FPLBootstrap?
    private var fixtures: [Match]?

    func cachedBootstrap() -> FPLBootstrap? { bootstrap }
    func cacheBootstrap(_ value: FPLBootstrap) { bootstrap = value }

    func cachedFixtures() -> [Match]? { fixtures }
    func cacheFixtures(_ value: [Match]) { fixtures = value }

    /// 清空全部内存缓存（手动刷新 / 设置里清缓存时调用）
    func clear() {
        bootstrap = nil
        fixtures = nil
    }

    /// 只清赛程（比赛期间自动刷新轮询用），保留 bootstrap
    func clearFixtures() { fixtures = nil }
}

/// 简易落盘缓存（actor 保证线程安全）
actor CacheStore {
    static let shared = CacheStore()

    private let cacheDir: URL

    /// - Parameter directory: 缓存目录；nil 用默认（App Support/EPLViewer/cache）。
    ///   测试注入临时目录，避免污染真实缓存。
    init(directory: URL? = nil) {
        if let directory {
            cacheDir = directory
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            cacheDir = support.appendingPathComponent("EPLViewer/cache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
    }

    private func url(for key: String) -> URL {
        cacheDir.appendingPathComponent(sanitize(key) + ".json")
    }

    /// 文件名安全化
    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: "?", with: "_")
           .replacingOccurrences(of: "&", with: "_")
    }

    /// 读取缓存（带 TTL 判断）
    func get<T: Decodable>(_ key: String, ttl: TimeInterval) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u),
              let attrs = try? FileManager.default.attributesOfItem(atPath: u.path),
              let mtime = attrs[.modificationDate] as? Date,
              CacheTTL.isValid(mtime: mtime, ttl: ttl)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 读取缓存，**忽略 TTL**（stale-if-error 兜底）。
    ///
    /// 用途：网络失败 / 超时、且 TTL 内缓存也没有时，回退到上次成功落盘的数据 ——
    /// 内容真实但可能过期，好过空白或假样例。解码失败（文件损坏）返回 nil。
    func getStale<T: Decodable>(_ key: String) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// 写入缓存
    func set<T: Encodable>(_ key: String, value: T) {
        let u = url(for: key)
        let enc = JSONEncoder()
        if let data = try? enc.encode(value) {
            try? data.write(to: u, options: .atomic)
        }
    }

    /// 清除所有缓存
    func clear() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true
        )
    }

    /// 只删某个 key（比赛期间自动刷新只失效赛程缓存用），不动其它缓存
    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }
}
