import Foundation

// MARK: - 译名资源加载器
//
// 球员/球队译名表已外部化为 `Sources/EPLViewer/Resources/` 下的 JSON 资源:
//   - `PlayerNames-<locale>.json`  {"byId": {..}, "byName": {..}}
//   - `TeamNames-<locale>.json`    {"byShort": {..}}
//
// 本地化扩展方式:新增语言 = 新增一个资源文件(如 `TeamNames-zh-Hant.json`),
// 由显示侧按 AppLanguage 选择 locale 加载;当前中文界面固定加载 `zh-Hans`,
// 英文界面直接显示 FPL 原名、不加载任何译名表。
// 加载失败(文件缺失/损坏)返回 nil,调用方回退空表 → 显示英文原名,不影响功能。

/// 用于定位资源 bundle 的锚点:App 运行时与单元测试(TEST_HOST 注入主程序)都会
/// 解析到主 App bundle,比 `Bundle.main` 在不同宿主下更可靠。
private final class TranslationBundleAnchor {}

enum TranslationStore {
    /// 读取 `<baseName>-<locale>.json` 并解码;文件缺失或损坏返回 nil。
    static func load<T: Decodable>(_ baseName: String, locale: String) -> T? {
        let bundle = Bundle(for: TranslationBundleAnchor.self)
        guard let url = bundle.url(forResource: "\(baseName)-\(locale)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
