import Foundation

// MARK: - Season constants & time budget

/// Current-season constants.
/// The app only targets the 2026-27 season (ESPN `season=2026`, a cross-year season).
/// Historical-season features (multi-season switching, per-season cache isolation) are
/// out of scope for now; to add them later, thread a `season` parameter through the
/// DataRepository fetch methods.
enum SeasonStore {
    static let currentSeason: String = "2026"

    /// Display label for the cross-year season, e.g. "2026-2027"
    /// (the PL runs August through May). Used by UI titles (sidebar / detail pages)
    /// to show the full season name.
    static var seasonLabel: String {
        let start = Int(currentSeason) ?? 2026
        return "\(start)-\(start + 1)"
    }
}

/// Wraps any async fetch in a time budget; gives up and returns nil when exceeded.
///
/// Why this exists: first-screen rendering must never be held hostage by
/// nice-to-have data. Season progress, for example, depends on the FPL bootstrap,
/// which in practice can hang for tens of seconds — better to show the match list
/// first and skip the progress info than to leave the user staring at a spinner.
///
/// - Note: once over budget the underlying task is cancelled, but a request already
///   in flight still finishes in the background; its result is simply discarded
///   (cache writes happen inside the task and are invalidated by cancellation,
///   so nothing gets corrupted).
/// - Parameter operation: may return nil (a normal outcome when the data source is
///   unreachable), hence the generic T is a **non-optional** result type — avoids
///   confusing callers with a `T??` double optional.
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
        // First finisher wins: the first result may be data or the timeout sentinel.
        let first = await group.next()
        group.cancelAll()
        return first ?? nil
    }
}
