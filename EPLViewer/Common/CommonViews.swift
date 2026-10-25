import SwiftUI
import AppKit

// MARK: - Shared views

/// Loading view.
/// Note: never stack .glassEffect() on a self-sizing container like a VStack.
///   Under the macOS 26 SDK it inflates the whole subtree into a giant oval (once
///   produced a "big circle flashing when entering a section" bug). For glass, use
///   .background(.ultraThinMaterial) — looks fine and never inflates the container.
struct LoadingView: View {
    @Environment(AppState.self) private var appState
    var body: some View {
        VStack(spacing: 12) {
            // Brand-green spinner — PL's signature accent, otherwise unused
            ProgressView()
                .controlSize(.large)
                .tint(Color.eplGreen)
                .frame(width: 40, height: 40)
            Text(UIString.loading.text(appState.language))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

/// Empty-state view.
/// `retryLabel` / `retryAction`: optional refresh button for empty states that may
/// stem from missing data (offline / first launch) — wire them to `appState.refresh`.
struct EmptyStateView: View {
    let label: String
    var retryLabel: String? = nil
    var retryAction: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
            if let retryLabel, let retryAction {
                Button {
                    retryAction()
                } label: {
                    Label(retryLabel, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Error view.
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

// MARK: - Crest image (with on-disk cache)

/// Crest cache: downloaded once, persisted to Application Support/EPLViewer/logos/,
/// then loaded from disk — no re-downloads on refresh, works offline too.
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

    /// URL → safe file name (alphanumerics only).
    private func fileName(_ urlString: String) -> String {
        urlString.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    /// Crest binary (memory → disk → network download + persist).
    /// Returns Data (Sendable); the caller builds the NSImage on the main thread.
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
            // Tight-timeout session: crests are nice-to-have and must never slow the list.
            let (data, _) = try await APIClient.imageSession.data(from: url)
            // Verify it really is an image so error pages never get cached.
            guard NSImage(data: data) != nil else { return nil }
            memory.setObject(data as NSData, forKey: name as NSString)
            try? data.write(to: file, options: .atomic)
            return data
        } catch {
            return nil
        }
    }
}

/// Crest image: disk cache first, then download and persist.
struct CrestImage: View {
    let urlString: String?
    /// Render size (pt). Defaults to 20 (list rows); larger scenes (the featured
    /// match card) pass an explicit value. ⚠️ The size must live here: wrapping this
    /// view in an outer .frame() only centers the fixed-size child, it can't scale up.
    var size: CGFloat = CrestImage.renderedSize
    @State private var image: NSImage?

    /// Default crest size for list rows (some NSImages are portrait and would blow
    /// up the row height through scaledToFit without a fixed frame).
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
        .frame(width: size, height: size)
        .clipped()  // hard clip: even if the child overflows, only size×size shows
        .task(id: urlString) {
            guard let urlString else { image = nil; return }
            guard let data = await LogoCache.shared.imageData(for: urlString) else { return }
            image = NSImage(data: data)
        }
    }
}

// MARK: - Color helpers & brand colors

extension Color {
    /// Construct from a hex string (#RRGGBB or #RRGGBBAA).
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

    /// PL brand purple.
    static let eplPurple = Color(hex: "#37003C")
    /// PL brand green (for data-source accents).
    static let eplGreen = Color(hex: "#00FF85")

    /// Subtle surface fill for cards / pills / table backgrounds.
    /// `Color.primary.opacity(0.04)` is nearly invisible on the dark-mode canvas
    /// (4% white over black); 0.10 matches the system grouped-background contrast
    /// while staying just as subtle in light mode.
    static let eplSurface = Color.primary.opacity(0.10)
    /// Stronger surface fill for the active/selected pill or chip state.
    static let eplSurfaceStrong = Color.primary.opacity(0.20)
    /// Hairline stroke for card borders (was 0.08 — same dark-mode visibility issue).
    static let eplHairline = Color.primary.opacity(0.14)
}
