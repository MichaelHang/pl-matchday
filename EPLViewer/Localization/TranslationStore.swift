import Foundation

// MARK: - Translation resource loader
//
// Player/team name tables live as JSON resources under
// `EPLViewer/Localization/Resources/`:
//   - `PlayerNames-<locale>.json`  {"byId": {..}, "byName": {..}}
//   - `TeamNames-<locale>.json`    {"byShort": {..}}
//
// To add a language, add a resource file (e.g. `TeamNames-zh-Hant.json`); the
// display side picks the locale from AppLanguage. The Chinese UI loads `zh-Hans`
// for now; English shows the FPL names directly and loads no table.
// A load failure (missing/corrupt file) returns nil and callers fall back to an
// empty table → English names — functionality is unaffected.

/// Anchor for locating the resource bundle: resolves to the main app bundle both
/// in the app and in unit tests (TEST_HOST injects the host app), which is more
/// reliable than `Bundle.main` across hosts.
private final class TranslationBundleAnchor {}

enum TranslationStore {
    /// Read `<baseName>-<locale>.json` and decode it; nil when missing or corrupt.
    static func load<T: Decodable>(_ baseName: String, locale: String) -> T? {
        let bundle = Bundle(for: TranslationBundleAnchor.self)
        guard let url = bundle.url(forResource: "\(baseName)-\(locale)", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
