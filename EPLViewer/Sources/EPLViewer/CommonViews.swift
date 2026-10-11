import SwiftUI
import AppKit

// MARK: - 通用视图

/// 加载中视图
/// 注意：不要在 VStack 自拉伸容器上叠 .glassEffect()。
///   macOS 26 SDK 下会把整棵子树撑成巨大椭圆，曾出现"进入主板块瞬间闪一下大圆"的视觉 bug。
///   玻璃质感改用 .background(.ultraThinMaterial)，已经够看，且不会撑大容器。
struct LoadingView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 40, height: 40)
            Text(UIString.loading.text(appState.language))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// 空状态视图
struct EmptyStateView: View {
    let label: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 错误视图
struct ErrorView: View {
    @Environment(AppState.self) private var appState
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text(UIString.loadFailed.text(appState.language))
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 队徽图片（带本地磁盘缓存）

/// 队徽本地缓存：首次从 URL 下载后落盘到 Application Support/EPLViewer/logos/，
/// 之后直接从本地文件加载，避免每次刷新都重新下载（也支持离线后展示）。
actor LogoCache {
    static let shared = LogoCache()

    private let dir: URL
    private let memory = NSCache<NSString, NSData>()

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        dir = support.appendingPathComponent("EPLViewer/logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// 把 URL 转成安全的文件名（只保留字母数字）
    private func fileName(_ urlString: String) -> String {
        urlString.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    /// 返回队徽的 PNG/JPG 二进制（优先内存 → 磁盘 → 网络下载并落盘）
    /// 返回 Data（Sendable），由调用方在主线程构造 NSImage
    func imageData(for urlString: String) async -> Data? {
        let name = fileName(urlString)
        if let cached = memory.object(forKey: name as NSString) { return cached as Data }
        let file = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path),
           let data = try? Data(contentsOf: file) {
            memory.setObject(data as NSData, forKey: name as NSString)
            return data
        }
        guard let url = URL(string: urlString) else { return nil }
        do {
            // 用收紧过超时的会话：队徽是锦上添花，绝不能拖慢列表渲染
            let (data, _) = try await APIClient.imageSession.data(from: url)
            // 校验确实是图片，避免把错误页缓存下来
            guard NSImage(data: data) != nil else { return nil }
            memory.setObject(data as NSData, forKey: name as NSString)
            try? data.write(to: file, options: .atomic)
            return data
        } catch {
            return nil
        }
    }
}

/// 队徽图片：优先从本地缓存读取，未命中再下载并落盘。
struct CrestImage: View {
    let urlString: String?
    @State private var image: NSImage?

    /// 统一队徽渲染尺寸（避免某些 NSImage 是竖长比例时被 scaledToFit 撑破外层 frame、把整行 HStack 撑高）
    static let renderedSize: CGFloat = 20

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shield")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: Self.renderedSize, height: Self.renderedSize)  // 双保险：建议 + 内部 frame
        .clipped()  // 强制裁剪：哪怕子 Image 撑破 frame 也只显示 20×20 范围
        .task(id: urlString) {
            guard let urlString else { image = nil; return }
            guard let data = await LogoCache.shared.imageData(for: urlString) else { return }
            image = NSImage(data: data)
        }
    }
}

// MARK: - 颜色扩展与品牌色

extension Color {
    /// 从十六进制字符串构造颜色（支持 #RRGGBB 与 #RRGGBBAA）
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// 英超品牌色：深紫
    static let eplPurple = Color(hex: "#37003C")
    /// 英超品牌色：亮绿（用于数据来源强调）
    static let eplGreen = Color(hex: "#00FF85")
}
