import SwiftUI

// MARK: - Global app state

/// Global observable state (Observation framework `@Observable`).
/// `@MainActor` keeps every access on the main actor, avoiding cross-actor data
/// races; `.environment()` / `@Environment` resolve fine under the macOS 26 SDK.
@MainActor
@Observable
final class AppState {
    /// Eagerly loads the player-name override layer at startup (reads any existing
    /// disk overrides). Optional, but safer.
    init() {
        let _ = PlayerNameStore.shared
        #if DEBUG
        // QA convenience: launch with `-section fixtures` (UserDefaults argument
        // domain) to land directly on a section, e.g. for screenshots.
        if let s = UserDefaults.standard.string(forKey: "section"),
           let section = AppSection(rawValue: s) {
            selected = section
        }
        // QA convenience: `-force_stale 1` pins the offline badge for visual checks.
        if UserDefaults.standard.bool(forKey: "force_stale") {
            source = .stale
        }
        #endif
    }

    /// Main sections.
    enum AppSection: String, CaseIterable, Identifiable {
        // Order = sidebar order: Today → Fixtures → Standings → …
        case today, fixtures, standings, leaders, injuries, settings
        var id: String { rawValue }

        func title(_ lang: AppLanguage) -> String {
            switch self {
            case .today:     return UIString.today.text(lang)
            case .standings: return UIString.standings.text(lang)
            case .fixtures:  return UIString.fixtures.text(lang)
            case .leaders:   return UIString.leaders.text(lang)
            case .injuries:  return UIString.injuries.text(lang)
            case .settings:  return UIString.settings.text(lang)
            }
        }

        var systemImage: String {
            switch self {
            case .today:     return "clock.badge.checkmark"
            case .standings: return "tablecells"
            case .fixtures:  return "calendar"
            case .leaders:   return "soccerball"
            case .injuries:  return "bandage"
            case .settings:  return "gearshape"
            }
        }
    }

    /// Default landing section: Today (the day's overview; the first thing you see).
    var selected: AppSection = .today
    /// Current season (hardcoded 2026-27; no season-switching UI by design).
    var season: String { SeasonStore.currentSeason }
    /// Interface language (persisted; Chinese by default, switching is immediate and
    /// does not refetch data).
    var language: AppLanguage =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "epl_language") ?? "") ?? .chinese {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "epl_language")
        }
    }
    var source: DataSource = .sample
    /// 60 s auto-refresh switch (persisted; off by default).
    /// `Bool` is read/written directly; the key follows the existing
    /// `epl_language` / `epl_timezone` naming.
    var autoRefresh: Bool =
        UserDefaults.standard.bool(forKey: "epl_autorefresh") {
        didSet {
            UserDefaults.standard.set(autoRefresh, forKey: "epl_autorefresh")
        }
    }
    /// "Auto-refresh during matches" switch (persisted; **on by default**).
    /// Independent of `autoRefresh`: when the global switch is on, this one is
    /// disabled in the UI (60 s everywhere makes it moot); when the global switch is
    /// off and this one is on → poll at 60 s only while a match is live, otherwise
    /// **sleep until shortly before the next kickoff** (see `AutoRefreshScheduler`).
    ///
    /// ⚠️ **On by default**: fresh installs and users who never touched the toggle
    /// start checked. The tri-state read (`object(forKey:) == nil`) is mandatory —
    /// `bool(forKey:)` returns false both for "key absent" and "explicitly off",
    /// which would either force always-off or flip the user's off back to on across
    /// launches. Once the user moves the toggle, `didSet` persists the real value
    /// and defaults no longer apply.
    var autoRefreshDuringMatches: Bool =
        AppState.persistedBool(forKey: "epl_autorefresh_matches", defaultWhenAbsent: true) {
        didSet {
            UserDefaults.standard.set(autoRefreshDuringMatches, forKey: "epl_autorefresh_matches")
        }
    }

    /// Reads a persisted Bool, distinguishing "key absent" from "stored false"
    /// (see `autoRefreshDuringMatches`). Static members don't participate in
    /// `@Observable` observation (only instance stored properties are rewritten by
    /// the macro), so this is safe.
    private static func persistedBool(forKey key: String, defaultWhenAbsent: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultWhenAbsent }
        return UserDefaults.standard.bool(forKey: key)
    }
    var isLoading: Bool = false
    /// Display time zone for fixtures (persisted; Beijing by default, immediate switch).
    var timeZone: DisplayTimeZone =
        DisplayTimeZone(rawValue: UserDefaults.standard.string(forKey: "epl_timezone") ?? "") ?? .shanghai {
        didSet {
            UserDefaults.standard.set(timeZone.rawValue, forKey: "epl_timezone")
        }
    }
    /// Refresh counter: incrementing it re-triggers every view's `.task(id:)` refetch.
    var refreshNonce: Int = 0
    /// 60 s auto-refresh timer (polls `refresh()` for live scores during matches).
    /// `@ObservationIgnored` keeps the Observation framework from tracking the Timer.
    @ObservationIgnored
    private var refreshTimer: Timer?

    /// The schedule state last reported by a view (live match? next kickoff?).
    /// Recomputed **against the current time** by `reportLiveSchedule(from:)` /
    /// `refreshTick()`; drives `configureAutoRefresh()`.
    var liveSchedule = RefreshSchedule(hasLiveMatch: false, nextKickoff: nil)
    /// The latest known full fixture list. The timer recomputes the schedule from it
    /// plus the current time on every wake — the schedule depends on `now`, so the
    /// stored `liveSchedule` alone is not enough (see `refreshTick`). Arrays are COW
    /// value types; this only holds a reference, no extra copying.
    var lastKnownMatches: [Match] = []

    /// Manual refresh: default "full" — clears every local cache, bumps
    /// `refreshNonce`, so all views refetch over the network, unconstrained by the
    /// lazy CacheTTL window (passive fetches like tab switches keep the 5 min window).
    ///
    /// `scoresOnly: true` is for the live-match polling timer: invalidates only the
    /// **fixtures** cache (the scores source) and keeps bootstrap / standings etc.,
    /// so each 60 s tick doesn't re-download the whole FPL bootstrap. UI freshness
    /// is unchanged (scores come from fixtures only); per-minute network cost drops
    /// from 3 payloads to 1.
    func refresh(scoresOnly: Bool = false) async {
        // Record this nonce bump's origin: views read it once at `.task(id:)` start —
        // background polling refreshes silently (no overlay), manual refresh keeps
        // the overlay. Main-actor only, no races.
        lastRefreshSource = scoresOnly ? .background : .manual
        if scoresOnly {
            await DataRepository.invalidateFixtures()
        } else {
            await DataRepository.clearCache()
        }
        refreshNonce &+= 1
    }

    /// Refresh origin: decides whether this reload shows the full-screen overlay.
    /// - initial: cold launch / first entry into a section (nonce unchanged) → overlay;
    /// - manual: user tapped refresh / cleared cache → overlay (explicit wait expected);
    /// - background: matchday 60 s polling (scoresOnly) → **silent** refresh, scores
    ///   update in place — a flashing overlay every 60 s is very disruptive otherwise.
    enum RefreshSource { case initial, manual, background }
    @ObservationIgnored private(set) var lastRefreshSource: RefreshSource = .initial

    /// Rebuilds the auto-refresh timer. The interval comes from
    /// `AutoRefreshScheduler.refreshInterval(...)`:
    /// - global `autoRefresh == true` → fixed 60 s;
    /// - otherwise "during matches" on + a live match → 60 s;
    /// - otherwise sleep until 15 min before the next kickoff; with no schedule, fall
    ///   back to `maxIdleSleep`;
    /// - "during matches" off → no timer.
    /// Called by SettingsView's Toggle `.onChange`, ContentView's `.task`, and
    /// `reportLiveSchedule(from:)`.
    @MainActor
    func configureAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        let interval = AutoRefreshScheduler.refreshInterval(
            autoRefresh: autoRefresh,
            duringMatches: autoRefreshDuringMatches,
            schedule: liveSchedule,
            now: Date()
        )
        guard let interval else { return }
        // Each tick does two things: refresh data + **recompute the interval against
        // the current time** (see `refreshTick()`). The recompute must happen inside
        // the tick — see its doc comment (it's the crux of this feature).
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Timer wake: refresh data → **recompute schedule & interval against now** → rebuild the timer.
    ///
    /// ⚠️ The recompute must be **unconditional** (not the "only rebuild when content
    /// changed" debounce of `reportLiveSchedule`), for two independently-discovered
    /// reasons (each bit us once):
    ///
    /// 1. **The interval shrinks monotonically with `now`, but the schedule content
    ///    may not change.** Waking "15 min before kickoff" finds the exact same
    ///    schedule (`hasLiveMatch` still false, same `nextKickoff`) → a content-based
    ///    debounce would early-return → keep sleeping the old 6300 s and **sleep
    ///    through the entire match** (waking 90 min after kickoff).
    /// 2. **`hasLiveMatch` is derived from the kickoff-time window and only advances
    ///    when recomputed.** `RefreshSchedule.hasLiveMatch` is a stored Bool that
    ///    **never flips by itself**. Parked on a tab that doesn't report schedules
    ///    (standings / settings / leaders / injuries), `liveSchedule` freezes; without
    ///    a recompute the app would poll at 60 s **forever** after all matches ended
    ///    (clear cache + refetch + spinners), wasting network and battery.
    ///
    /// Recomputing from a possibly stale `lastKnownMatches` is safe and **intentional**:
    /// `untilWake = nextKickoff − now − kickoffLeadTime` is **monotonically
    /// non-increasing** in `now` ⇒ the recomputed interval never grows longer than the
    /// previous one (floored by `liveInterval`, so it never degenerates into
    /// 0/negative rapid-fire) — you may wake early, never oversleep.
    private func refreshTick() async {
        // Live polling: refresh fixtures only (the scores source); don't clear the
        // whole bootstrap / standings (see refresh(scoresOnly:)).
        await refresh(scoresOnly: true)
        liveSchedule = AutoRefreshScheduler.schedule(matches: lastKnownMatches, now: Date())
        configureAutoRefresh()
    }

    /// Views report the **latest fixtures** after fetching; AppState computes the
    /// schedule against the current time itself and no-ops when unchanged (debounce).
    ///
    /// ⚠️ Passes `matches`, not a ready `RefreshSchedule`: the schedule depends on
    /// `now`, so AppState must compute it here to share one logic path with
    /// `refreshTick()`'s recompute (otherwise the "sleep until kickoff" evolution
    /// would only advance when a view happens to report).
    ///
    /// ⚠️ The debounce covers only the "view report" path; timer wakes evolve via
    /// `refreshTick()`, which recomputes **unconditionally** and is unaffected by
    /// this early return (two independent reasons in `refreshTick`'s doc comment).
    /// Note: `AppState` is already a `@MainActor` class (class-level attribute), so
    /// the explicit `@MainActor` here is redundant but harmless.
    @MainActor
    func reportLiveSchedule(from matches: [Match]) {
        lastKnownMatches = matches
        let s = AutoRefreshScheduler.schedule(matches: matches, now: Date())
        guard s != liveSchedule else { return }
        liveSchedule = s
        configureAutoRefresh()
    }
}
