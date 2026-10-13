import SwiftUI

// MARK: - Modes

/// Fixtures page view mode.
/// - `.thisRound` single-round detail (default; lands on `focusedRound`)
/// - `.season` season overview (grid of round cards; tapping opens that round)
enum FixturesMode: Equatable {
    case thisRound
    case season
}

/// A round's progress within the season (colors the overview card dot).
enum RoundProgress {
    /// Played
    case past
    /// Current round (live or upcoming)
    case current
    /// Future rounds
    case future
    /// No data for this round yet (not in availableRounds; next round's fixtures unpublished)
    case unknown
}

// MARK: - Season progress / round snapshots

/// Season progress summary (top progress bar).
struct SeasonProgress: Equatable {
    /// Current round (is_current > is_next > latest finished)
    let currentRound: Int
    /// Total rounds (last FPL event; defaults to 38 when FPL is unavailable)
    let totalRounds: Int
    /// Played rounds (count of bootstrap.events with finished=true)
    let playedRounds: Int
    /// Remaining rounds
    let remainingRounds: Int
    /// Played fraction 0..1
    let fraction: Double
    /// Year of the first round's deadline_time (falls back to the current year)
    let seasonYear: Int
}

/// A round's "snapshot" — used by the season-overview cards.
struct RoundSnapshot: Identifiable {
    let round: Int
    let startDate: Date?
    let progress: RoundProgress
    let previews: [Match]
    var id: Int { round }
}

// MARK: - ViewModel

/// Fixtures view model (@Observable).
@Observable
final class FixturesViewModel {
    /// The full match set. Assignment automatically rebuilds the indexes so the
    /// "per-round buckets / per-round earliest kickoff" indexes always match the
    /// data (manual assignment and test injection included).
    var matches: [Match] = [] {
        didSet {
            rebuildIndexes()
            availableRounds = matchesByRound.keys.sorted()
        }
    }
    var source: DataSource = .sample
    var error: AppError?
    /// Mode: this round / season overview.
    var mode: FixturesMode = .thisRound
    /// The round being viewed — shown in "this round" mode; tapping an overview card
    /// rewrites it and switches back to `.thisRound`. Changing it (initial focus, or
    /// jumping from an overview card) aligns the round window to it; when already in
    /// the window it stays put so tapping a chip never makes the window jump.
    /// ⚠️ Paging does **not** touch focusedRound, so paging never triggers this.
    var focusedRound: Int = 1 {
        didSet { alignWindowToFocusedRound() }
    }
    /// Whether the "initial focus on the current round" already happened.
    /// ⚠️ `load()` reruns on every manual refresh and every 60 s matchday poll;
    /// focusing must happen only on the **first** data load — otherwise the round
    /// the user is browsing gets yanked back to the current round by every refresh.
    @ObservationIgnored private var didFocusInitialRound = false
    /// The real "current" round (from FPL is_current/is_next), used for initial
    /// focusing and progress copy. It feeds `roundSnapshots`' past/current/future
    /// decision, so changing it invalidates the snapshot cache.
    var currentRound: Int = 1 {
        didSet { invalidateSnapshotCache() }
    }
    /// Rounds that have matches (ascending, from FPL fixtures).
    /// A length change can push the window start out of bounds → clamp immediately.
    var availableRounds: [Int] = [] {
        didSet { clampWindowStart() }
    }
    /// Season progress (season-overview header; filled on first load). A direct input
    /// of `roundSnapshots`, so changing it invalidates the snapshot cache.
    var seasonProgress: SeasonProgress? {
        didSet { invalidateSnapshotCache() }
    }

    // MARK: Round window (fixed-size chip-bar pagination)
    //
    // The chip bar doesn't list every round at once: 38 rounds is fine, but rounds
    // growing into the hundreds would bog down layout. A fixed-size window with
    // paging renders at most `roundWindowSize` chips — render cost is independent
    // of the total round count.

    /// Window size: how many rounds the chip bar shows at once.
    static let roundWindowSize = 5
    /// The window's start index into `availableRounds`.
    /// Lives in the ViewModel (not a View `@State`) for testability; it is an
    /// **observed** property — paging must redraw the UI.
    var roundWindowStart: Int = 0

    // MARK: Precomputed indexes
    //
    // ⚠️ Each of the 38 round chips needs its round's earliest kickoff; scanning all
    // 380 matches per chip is 38 × 380 = 14,440 parses — on the SwiftUI body
    // evaluation path, rerun by every redraw, freezing the main thread. So the
    // indexes are built in one pass at load time.

    /// Earliest kickoff per round (UTC) — feeds the chip date suffix and grouping.
    private(set) var roundStartUTC: [Int: Date] = [:]
    /// Matches bucketed by round (buckets sorted by kickoff ascending).
    private(set) var matchesByRound: [Int: [Match]] = [:]

    // MARK: Season-overview snapshot cache
    //
    // ⚠️ `roundSnapshots(seasonProgress:)` is called on the SwiftUI body evaluation
    // path; every redraw would iterate all rounds and build a ≤3-preview snapshot
    // each — O(rounds × previews). 38 rounds is imperceptible, but hundreds of rounds
    // would saturate the main thread. Cache by input: unchanged inputs return the
    // previous result directly.

    /// Snapshot cache key — covers every input that can change the result.
    private struct SnapshotCacheKey: Equatable {
        /// Index version (bumped each time `matches` rebuilds the indexes)
        let indexGeneration: Int
        /// Current round: decides past / current / future state
        let currentRound: Int
        /// Season progress: decides total rounds and current round (nil falls back to `currentRound`)
        let seasonProgress: SeasonProgress?
    }

    /// Index version. Replaces "fingerprint all matches" with an O(1) change test.
    /// `roundStartUTC` / `matchesByRound` / `availableRounds` all derive from
    /// `matches`, so one version covers them all.
    ///
    /// ⚠️ `@ObservationIgnored`: the body never reads it; it shouldn't join the
    /// @Observable dependency tracking.
    @ObservationIgnored private var indexGeneration: Int = 0
    /// Last computed snapshots.
    @ObservationIgnored private var snapshotCache: [RoundSnapshot]?
    /// The input key that produced `snapshotCache`.
    @ObservationIgnored private var snapshotCacheKey: SnapshotCacheKey?
    /// Number of cache **misses** (actual recomputations). Only used by tests
    /// asserting "the second call didn't recompute"; not used by the UI.
    @ObservationIgnored private(set) var roundSnapshotsComputeCount: Int = 0

    /// Invalidate the snapshot cache. Index rebuilds / current-round changes /
    /// season-progress changes all land here.
    ///
    /// `SnapshotCacheKey` is the real gate (a key mismatch recomputes anyway);
    /// clearing explicitly is just a cheap extra safety net.
    private func invalidateSnapshotCache() {
        snapshotCache = nil
        snapshotCacheKey = nil
    }

    @MainActor
    func load() async {
        let (data, src) = await DataRepository.matches()
        matches = data // didSet rebuilds the indexes and refreshes availableRounds
        source = src
        error = nil
        // Fetch events once for both "current round" and "season progress" —
        // these used to be two calls (currentGameweek + gameweeks), decoding the
        // same bootstrap twice.
        //
        // ⚠️ And it needs a time budget: the FPL bootstrap has been observed hanging
        // for tens of seconds, while "current round / progress" is nice-to-have. Fall
        // back to local inference — never let this hold the first screen, or the
        // fixtures page would spin forever.
        let events = await withTimeBudget(seconds: 8) { await DataRepository.gameweeks() }
        currentRound = events.flatMap { DataRepository.deriveCurrentRound($0) }
            ?? inferCurrentRoundFromMatches()
            ?? 1
        // Focus the current round only on the **first** data load (falling back to the
        // first round with data when it has none); later refreshes never touch
        // focusedRound — an O(1) lookup on the precomputed index instead of an O(n)
        // scan over 380 matches.
        if !didFocusInitialRound, !availableRounds.isEmpty {
            didFocusInitialRound = true
            focusedRound = Self.initialFocusRound(
                currentRound: currentRound,
                availableRounds: availableRounds,
                matchesByRound: matchesByRound
            )
        }
        await loadSeasonProgress(events: events)
    }

    /// Which round to focus when fixtures first arrive (pure function, testable):
    /// current round with data → current round; otherwise the first round with data;
    /// nothing at all → current round.
    static func initialFocusRound(currentRound: Int,
                                  availableRounds: [Int],
                                  matchesByRound: [Int: [Match]]) -> Int {
        if matchesByRound[currentRound] != nil { return currentRound }
        return availableRounds.first ?? currentRound
    }

    /// Read season progress from FPL events (played / total / current round / year).
    /// On failure falls back to 38 rounds at 0% so the UI still renders something.
    /// - Parameter events: fetched once by `load()` and passed in; no refetch here.
    @MainActor
    func loadSeasonProgress(events: [FPLGameweek]? = nil) async {
        let resolvedEvents: [FPLGameweek]?
        if let events {
            resolvedEvents = events
        } else {
            resolvedEvents = await DataRepository.gameweeks()
        }
        guard let events = resolvedEvents else {
            let total = max(38, availableRounds.last ?? 38)
            seasonProgress = SeasonProgress(
                currentRound: currentRound,
                totalRounds: total,
                playedRounds: 0,
                remainingRounds: total,
                fraction: 0,
                seasonYear: Calendar.current.component(.year, from: Date())
            )
            return
        }
        let total = events.map(\.id).max() ?? 38
        let played = events.filter { ($0.finished ?? false) == true }.count
        let current = events.first(where: { ($0.is_current ?? false) == true })?.id
            ?? events.first(where: { ($0.is_next ?? false) == true })?.id
            ?? events.filter({ ($0.finished ?? false) == true }).map(\.id).max()
            ?? total
        let remaining = max(0, total - played)
        let frac = total > 0 ? Double(played) / Double(total) : 0
        let year = events
            .compactMap { $0.deadline_time }
            .compactMap(parseKickoffDate)
            .map { Calendar.current.component(.year, from: $0) }
            .first ?? Calendar.current.component(.year, from: Date())
        seasonProgress = SeasonProgress(
            currentRound: current,
            totalRounds: total,
            playedRounds: played,
            remainingRounds: remaining,
            fraction: frac,
            seasonYear: year
        )
    }

    /// Matches for the current mode + round, ascending by kickoff.
    /// Reads the precomputed bucket directly — O(1), no filter+sort over 380 matches.
    var displayed: [Match] {
        matchesByRound[focusedRound] ?? []
    }

    // MARK: - Index building

    /// Fallback when FPL events are unavailable: infer the current round locally from
    /// fixtures. Rules in `CurrentRoundInference` (shared by fixtures & today pages).
    /// (internal, not private: unit tests cover this fallback path)
    func inferCurrentRoundFromMatches() -> Int? {
        CurrentRoundInference.infer(from: matches)
    }

    /// Build both indexes in one pass: per-round buckets + earliest kickoff per round.
    /// All lookups afterwards are O(1) bucket reads, never full scans.
    private func rebuildIndexes() {
        // New indexes → derived snapshots are invalidated too
        indexGeneration += 1
        invalidateSnapshotCache()
        var byRound: [Int: [Match]] = [:]
        var earliest: [Int: Date] = [:]
        for m in matches {
            guard let r = m.matchday else { continue }
            byRound[r, default: []].append(m)
            if let d = parseKickoffDate(m.utcDate) {
                if let cur = earliest[r] {
                    if d < cur { earliest[r] = d }
                } else {
                    earliest[r] = d
                }
            }
        }
        // Sort each bucket by kickoff ascending (ISO8601 string order == time order)
        for (r, list) in byRound {
            byRound[r] = list.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") }
        }
        matchesByRound = byRound
        roundStartUTC = earliest
    }

    // MARK: - Round metadata

    /// A round's earliest kickoff (UTC) → the chip/card date label. O(1) index
    /// lookup; time-zone conversion is the formatter's job, not this one's.
    func roundStart(_ round: Int) -> Date? {
        roundStartUTC[round]
    }

    // MARK: - Round window (chip-bar pagination)

    /// Legal upper bound for the window start.
    /// 0 when fewer rounds than a window — the arrows should be hidden then.
    var roundWindowMaxStart: Int {
        max(0, availableRounds.count - FixturesViewModel.roundWindowSize)
    }

    /// Visible round numbers (at most `roundWindowSize`). The start is clamped into
    /// range before slicing, so no state can index out of bounds.
    var visibleRounds: [Int] {
        let start = min(max(roundWindowStart, 0), roundWindowMaxStart)
        guard start < availableRounds.count else { return [] }
        let end = min(start + FixturesViewModel.roundWindowSize, availableRounds.count)
        return Array(availableRounds[start..<end])
    }

    /// Clamp `roundWindowStart` back into `[0, roundWindowMaxStart]`.
    /// Safety net when a refresh shrinks `availableRounds`.
    func clampWindowStart() {
        roundWindowStart = min(max(roundWindowStart, 0), roundWindowMaxStart)
    }

    /// Re-position the window so it contains `focusedRound`.
    ///
    /// Alignment rules (over the ordered `availableRounds`):
    /// - middle: center on `focusedRound`, 2 before / 2 after (size 5 → offset 5 / 2 = 2)
    /// - near edges: start clamps to 0 / the bound, i.e. left/right alignment
    /// - total rounds ≤ window size: start at 0 (everything visible, nothing to align)
    ///
    /// Two cases deliberately **stay put**:
    /// - `focusedRound` already inside the window (including after paging — the user
    ///   moved the viewport without changing rounds) → keep the viewport stable;
    /// - `focusedRound` not in `availableRounds` (no data for that round) → nothing
    ///   to align to.
    func alignWindowToFocusedRound() {
        let size = FixturesViewModel.roundWindowSize
        if availableRounds.count <= size {
            roundWindowStart = 0
            return
        }
        guard !visibleRounds.contains(focusedRound),
              let idx = availableRounds.firstIndex(of: focusedRound)
        else { return }
        // count > size always holds here, so maxStart > 0 and the clamp can't go out of bounds
        let maxStart = availableRounds.count - size
        roundWindowStart = min(max(idx - size / 2, 0), maxStart)
    }

    /// Page one window left (earlier rounds).
    /// **Moves only the window, never `focusedRound`** — the selected round stays
    /// highlighted and on screen. The window is purely a viewport; only tapping a
    /// chip changes the selected round.
    func pageRoundsBackward() {
        roundWindowStart = max(roundWindowStart - FixturesViewModel.roundWindowSize, 0)
        clampWindowStart()
    }

    /// Page one window right (later rounds). Same: window only, not `focusedRound`.
    func pageRoundsForward() {
        roundWindowStart = roundWindowStart + FixturesViewModel.roundWindowSize
        clampWindowStart()
    }

    // MARK: - Grouping by (round, date)

    /// Date-grouped sections; one section per local day, ascending kickoffs within.
    func groupedSections(tz: TimeZone) -> [FixturesSection] {
        let list = matchesByRound[focusedRound] ?? []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var buckets: [Date: [Match]] = [:]
        for m in list {
            guard let d = parseKickoffDate(m.utcDate) else { continue }
            let local = cal.startOfDay(for: d)
            buckets[local, default: []].append(m)
        }
        return buckets
            .map { (date, items) in
                FixturesSection(date: date,
                                matches: items.sorted { ($0.utcDate ?? "") < ($1.utcDate ?? "") })
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Season-overview snapshots

    /// One snapshot per round for the overview grid; at most 3 previews per card
    /// (first 3 by kickoff). Reads only the precomputed indexes, never full scans.
    ///
    /// Cached by input: when `matches` (via `indexGeneration`) / `currentRound` /
    /// `seasonProgress` are all unchanged, the previous result is returned directly so
    /// body redraws don't pay O(rounds × previews) every time.
    func roundSnapshots(seasonProgress: SeasonProgress?) -> [RoundSnapshot] {
        let key = SnapshotCacheKey(
            indexGeneration: indexGeneration,
            currentRound: currentRound,
            seasonProgress: seasonProgress
        )
        if let cached = snapshotCache, snapshotCacheKey == key {
            return cached
        }
        let cur = seasonProgress?.currentRound ?? currentRound
        let set = Set(availableRounds)
        let max = seasonProgress?.totalRounds ?? (availableRounds.last ?? 38)
        var result: [RoundSnapshot] = []
        result.reserveCapacity(max)
        for r in 1...max {
            let progress: RoundProgress
            if r < cur {
                progress = .past
            } else if r == cur {
                progress = .current
            } else {
                progress = .future
            }
            // Read the precomputed bucket directly; no 38 × 380 rescans
            let items = matchesByRound[r] ?? []
            // Rounds without data this season still get an empty (placeholder) snapshot
            result.append(RoundSnapshot(
                round: r,
                startDate: roundStartUTC[r],
                progress: set.contains(r) ? progress : (progress == .future ? .unknown : progress),
                previews: Array(items.prefix(3))
            ))
        }
        roundSnapshotsComputeCount += 1
        snapshotCache = result
        snapshotCacheKey = key
        return result
    }
}

/// One section = a local date with its matches.
struct FixturesSection: Identifiable {
    var date: Date
    var matches: [Match]
    var id: Date { date }
}

// MARK: - Date utilities

// ⚠️ Performance-critical zone: these run on the SwiftUI body evaluation path, and
// the fixtures page renders 380 matches + 38 round chips at once. Constructing a
// DateFormatter / ISO8601DateFormatter per call stalls the main thread (their
// construction is expensive), so everything goes through the shared pool.

/// Formatter cache pool.
///
/// Under Swift 6 strict concurrency a global mutable `var` is rejected
/// (MutableGlobalVariable), so it lives in this singleton; guarded by an NSLock and
/// annotated `@unchecked Sendable`.
private final class FormatterPool: @unchecked Sendable {
    static let shared = FormatterPool()

    private let lock = NSLock()
    private var cache: [String: DateFormatter] = [:]

    let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Reuse DateFormatter instances keyed by time zone + language + format.
    func formatter(tz: TimeZone, localeID: String, format: String) -> DateFormatter {
        let key = "\(tz.identifier)|\(localeID)|\(format)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let f = DateFormatter()
        f.timeZone = tz
        f.locale = Locale(identifier: localeID)
        f.dateFormat = format
        cache[key] = f
        return f
    }
}

/// Short date "Aug 29 / 8月29日".
private func formatShortDate(_ d: Date, tz: TimeZone, lang: AppLanguage) -> String {
    let df = FormatterPool.shared.formatter(
        tz: tz,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "MMM d" : "M月d日")
    return df.string(from: d)
}

/// Section header "Sat, Aug 29 / 8月29日 星期六".
private func formatDateHeader(_ d: Date, tz: TimeZone, lang: AppLanguage) -> String {
    let df = FormatterPool.shared.formatter(
        tz: tz,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "EEE · MMM d" : "M月d日 EEEE")
    return df.string(from: d)
}

// MARK: - View

/// Fixtures.
/// - `.thisRound`: focused on the current round (default) or a round entered from the
///   overview; all matches grouped by date.
/// - `.season`: overview card grid; tapping a card returns to `.thisRound` for details.
struct FixturesView: View {
    @Environment(AppState.self) private var appState

    @State private var vm = FixturesViewModel()

    /// Brand pink — season-overview progress bar and the "current round" accent
    /// (kept out of TodayView on purpose; the color carries progress semantics only).
    private let accentPink = Color(red: 1.00, green: 0.231, blue: 0.498)

    var body: some View {
        @Bindable var appState = appState
        let lang = appState.language
        let tz = TimeZone(identifier: appState.timeZone.identifier) ?? .current

        VStack(spacing: 0) {
            if vm.error != nil {
                ErrorView(message: vm.error?.localizedDescription ?? "加载失败")
            } else if vm.matches.isEmpty {
                EmptyStateView(label: UIString.noFixtures.text(lang))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch vm.mode {
                        case .thisRound:
                            thisRoundSection(lang: lang, tz: tz)
                        case .season:
                            seasonOverviewSection(lang: lang, tz: tz)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("")
        .task(id: appState.refreshNonce) {
            // Background polling refreshes silently: no full-screen overlay (a flash
            // every 60 s on matchdays is very disruptive); first load / manual refresh
            // keep it. isLoading still resets unconditionally so the overlay can never
            // stick under odd timings.
            if appState.lastRefreshSource != .background { appState.isLoading = true }
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
            // The fixtures page also shows live matches; report the schedule via the
            // same entry point as TodayView.
            appState.reportLiveSchedule(from: vm.matches)
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: This-round detail

    @ViewBuilder
    private func thisRoundSection(lang: AppLanguage, tz: TimeZone) -> some View {
        Text(String(format: UIString.fixturesHeader.text(lang), vm.focusedRound))
            .font(.system(size: 28, weight: .bold))

        modeBar(lang: lang)

        if !vm.availableRounds.isEmpty {
            roundChipBar(lang: lang, tz: tz)
        }

        if vm.displayed.isEmpty {
            EmptyStateView(label: UIString.noRoundMatches.text(lang))
                .padding(.top, 32)
        } else {
            groupsSection(lang: lang, tz: tz)
        }
    }

    // MARK: Season overview

    @ViewBuilder
    private func seasonOverviewSection(lang: AppLanguage, tz: TimeZone) -> some View {
        let progress = vm.seasonProgress

        // Large title "2026 Season"
        Text(String(format: UIString.seasonHeader.text(lang),
                     progress?.seasonYear ?? Calendar.current.component(.year, from: Date())))
            .font(.system(size: 28, weight: .bold))

        // Round switch pills (kept alongside the season overview)
        modeBar(lang: lang)

        // Card grid
        let snapshots = vm.roundSnapshots(seasonProgress: progress)
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200, maximum: 260),
                               spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(snapshots) { snap in
                Button {
                    vm.focusedRound = snap.round
                    vm.mode = .thisRound
                } label: {
                    SeasonOverviewCard(
                        snapshot: snap,
                        lang: lang,
                        tz: tz,
                        accent: accentPink
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Mode switch pills

    @ViewBuilder
    private func modeBar(lang: AppLanguage) -> some View {
        HStack(spacing: 8) {
            modePill(label: UIString.modeThisRound.text(lang),
                     active: vm.mode == .thisRound) {
                vm.mode = .thisRound
            }
            modePill(label: UIString.modeSeason.text(lang),
                     active: vm.mode == .season) {
                vm.mode = .season
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func modePill(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(active
                        ? Color.primary.opacity(0.12)
                        : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Round chip bar

    /// "This round" mode's horizontal round switch: a **fixed window** — renders only
    /// `visibleRounds` (at most 5), each chip "MD N · Aug 29", focused chip highlighted.
    /// The arrows page by the window size (±5) and **move only the window, never
    /// `focusedRound`** — the selected round stays highlighted; only tapping a chip
    /// changes it.
    ///
    /// Window state lives in the ViewModel (`roundWindowStart`); this is pure
    /// rendering + action forwarding.
    @ViewBuilder
    private func roundChipBar(lang: AppLanguage, tz: TimeZone) -> some View {
        let rounds = vm.visibleRounds
        ScrollView(.horizontal, showsIndicators: false) {
            // ⚠️ Keep a LazyHStack rather than a plain HStack: the window is fixed at
            // 5 chips so lazy isn't a performance requirement today, but it is a guard
            // rail — `testRoundChipBarUsesLazyHStack` asserts it exists, and if the
            // window ever grows it won't regress to building hundreds of views at once.
            //
            // Safety: the outer container is a ScrollView (not a lazy container), so
            // this is not "lazy inside lazy"; the .frame(height: 32) below gives the
            // horizontal lazy container a definite height.
            LazyHStack(spacing: 8) {
                // Previous page (hidden when the window is already leftmost)
                if vm.roundWindowStart > 0 {
                    roundPageButton(systemName: "chevron.left",
                                    help: UIString.prevRoundsPage.text(lang)) {
                        vm.pageRoundsBackward()
                    }
                }

                ForEach(rounds, id: \.self) { r in
                    roundChip(
                        label: chipLabel(round: r, lang: lang, tz: tz),
                        active: r == vm.focusedRound
                    ) {
                        vm.focusedRound = r
                    }
                }

                // Next page (hidden when rightmost, or when everything already fits)
                if vm.roundWindowStart < vm.roundWindowMaxStart {
                    roundPageButton(systemName: "chevron.right",
                                    help: UIString.nextRoundsPage.text(lang)) {
                        vm.pageRoundsForward()
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        // ⚠️ A definite height is mandatory: a horizontal ScrollView nested in a
        // vertical one, without a height constraint, negotiates sizes with its parent
        // forever and deadlocks the main thread during layout. (It also gives the
        // LazyHStack above its definite height — removing it regresses both the hang
        // and lazy sizing.)
        .frame(height: 32)
    }

    /// Round paging buttons (`<` / `>`), one shared implementation for identical
    /// styling and accessibility copy.
    @ViewBuilder
    private func roundPageButton(systemName: String,
                                 help: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Chip label: "MD N · Aug 29".
    private func chipLabel(round: Int, lang: AppLanguage, tz: TimeZone) -> String {
        let date = vm.roundStart(round)
        let dateStr = date.map { formatShortDate($0, tz: tz, lang: lang) } ?? "—"
        return String(format: UIString.roundChipFormat.text(lang), round, dateStr)
    }

    @ViewBuilder
    private func roundChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? Color.primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule().fill(active
                        ? Color.primary.opacity(0.18)
                        : Color.primary.opacity(0.04))
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Round matches grouped by date

    @ViewBuilder
    private func groupsSection(lang: AppLanguage, tz: TimeZone) -> some View {
        let sections = vm.groupedSections(tz: tz)
        // ⚠️ This must be a plain VStack, not LazyVStack: a lazy container proposes an
        // undefined width to children, and a LazyVGrid needs a definite width to solve
        // columns → rows → height. Stacking them makes size negotiation ping-pong and
        // pins the main thread at 100% — "data loaded but the UI spins forever".
        // A round has at most 10 matches in 4-5 groups; rendering everything is free.
        VStack(alignment: .leading, spacing: 22) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(formatDateHeader(section.date, tz: tz, lang: lang))
                        .font(.headline)
                        .padding(.leading, 2)

                    // ⚠️ maximum must be a concrete value, never .infinity: an unbounded
                    // max makes .adaptive's column math diverge too.
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240, maximum: 320),
                                           spacing: 12, alignment: .top)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(section.matches) { match in
                            MatchGridCard(match: match)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Season overview card

/// One round's preview card in the season overview:
/// - top-left "Round N"
/// - top-right status dot (past=green / current=brand pink / future=gray / unknown=gray)
/// - second row start date
/// - then up to 3 match previews ([crest] vs [crest] — score)
struct SeasonOverviewCard: View {
    @Environment(AppState.self) private var appState
    let snapshot: RoundSnapshot
    let lang: AppLanguage
    let tz: TimeZone
    let accent: Color

    var body: some View {
        let isCurrent = snapshot.progress == .current
        VStack(alignment: .leading, spacing: 6) {
            // Top row: round + status dot
            HStack {
                Text(String(format: UIString.roundN.text(lang), snapshot.round))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                statusDot
            }
            // Second row: start date
            if let s = snapshot.startDate {
                Text(formatShortDate(s, tz: tz, lang: lang))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Preview area (up to 3 matches)
            VStack(spacing: 4) {
                if snapshot.previews.isEmpty {
                    Text(UIString.noData.text(lang))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 6)
                } else {
                    ForEach(snapshot.previews) { m in
                        previewRow(m)
                        if m.id != snapshot.previews.last?.id {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isCurrent ? accent.opacity(0.6) : Color.primary.opacity(0.08),
                                      lineWidth: isCurrent ? 1.2 : 0.5)
                }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch snapshot.progress {
        case .past:     Circle().fill(Color.green.opacity(0.85)).frame(width: 8, height: 8)
        case .current:  Circle().fill(accent).frame(width: 8, height: 8)
        case .future:   Circle().fill(Color.primary.opacity(0.18)).frame(width: 8, height: 8)
        case .unknown:  Circle().fill(Color.primary.opacity(0.10)).frame(width: 8, height: 8)
        }
    }

    @ViewBuilder
    private func previewRow(_ m: Match) -> some View {
        HStack(spacing: 4) {
            CrestImage(urlString: m.homeTeam.crest)
                .frame(width: 16, height: 16)
            Text(UIString.seasonPreviewVs.text(lang))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            CrestImage(urlString: m.awayTeam.crest)
                .frame(width: 16, height: 16)
            Spacer(minLength: 4)
            if let h = m.score?.fullTime?.home, let a = m.score?.fullTime?.away {
                Text("\(h)-\(a)")
                    .font(.caption.monospacedDigit())
            } else {
                Text(formatKickoffShort(m.utcDate, tz: tz))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Match card (this-round detail)

/// Single match card (screenshot style: big time + home badge + two team rows).
struct MatchGridCard: View {
    @Environment(AppState.self) private var appState
    let match: Match

    var body: some View {
        let lang = appState.language
        let tz = TimeZone(identifier: appState.timeZone.identifier) ?? .current

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(formatKickoffShort(match.utcDate, tz: tz))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Text(UIString.homeBadge.text(lang))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            teamRow(
                crest: match.homeTeam.crest,
                name: match.homeTeam.displayName(chinese: appState.language == .chinese),
                score: homeScoreView(),
                isWinner: isHomeWinner
            )

            Divider()
                .padding(.vertical, 4)

            teamRow(
                crest: match.awayTeam.crest,
                name: match.awayTeam.displayName(chinese: appState.language == .chinese),
                score: awayScoreView(),
                isWinner: isAwayWinner
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private func teamRow(crest: String?, name: String, score: Text, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            CrestImage(urlString: crest)
                .frame(width: 20, height: 20)
            Text(name)
                .font(.system(size: 13, weight: isWinner ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            score
                .font(.system(size: 13, weight: isWinner ? .semibold : .regular))
                .monospacedDigit()
        }
    }

    private var isFinished: Bool {
        match.status == "FINISHED" ||
            match.score?.fullTime?.home != nil ||
            match.score?.fullTime?.away != nil
    }
    private var homeScore: Int? { match.score?.fullTime?.home }
    private var awayScore: Int? { match.score?.fullTime?.away }

    private var isHomeWinner: Bool {
        guard let h = homeScore, let a = awayScore, isFinished else { return false }
        return h > a
    }
    private var isAwayWinner: Bool {
        guard let h = homeScore, let a = awayScore, isFinished else { return false }
        return a > h
    }

    @ViewBuilder
    private func homeScoreView() -> Text {
        Text(displayScore(homeScore))
    }
    @ViewBuilder
    private func awayScoreView() -> Text {
        Text(displayScore(awayScore))
    }

    private func displayScore(_ s: Int?) -> String {
        guard let s else { return "" }
        return "\(s)"
    }
}

// MARK: - Legacy match card (home | score | away; shared by Today)
//   Kept as-is: used by the Today page and the featured card.

struct MatchCard: View {
    @Environment(AppState.self) private var appState
    let match: Match
    /// Teams flanking the edges (true) or hugging the center score (false, default).
    /// - `true`  = home at the left edge, away at the right edge — **Today page**
    ///   (user preference: the two teams split apart).
    /// - `false` = both hug the center score — **fixtures page** (keeps the score
    ///   column vertically aligned for scanning multiple cards).
    var teamsFlankSides: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                CrestImage(urlString: match.homeTeam.crest)
                    .frame(width: 24, height: 24)
                Text(match.homeTeam.displayName(chinese: appState.language == .chinese))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: teamsFlankSides ? .leading : .trailing)

            scoreText
                .frame(width: 104, alignment: .center)

            HStack(spacing: 6) {
                Text(match.awayTeam.displayName(chinese: appState.language == .chinese))
                    .lineLimit(1)
                CrestImage(urlString: match.awayTeam.crest)
                    .frame(width: 24, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: teamsFlankSides ? .trailing : .leading)
        }
        .padding(8)
        .glassEffect()
    }

    private var scoreText: some View {
        let lang = appState.language
        return Group {
            if let home = match.score?.fullTime?.home,
               let away = match.score?.fullTime?.away {
                HStack(spacing: 4) {
                    if TodayFilter.isLive(match, now: Date()) {
                        Image(systemName: "soccerball")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    Text("\(home) - \(away)").bold()
                }
            } else if TodayFilter.isLive(match, now: Date()) {
                HStack(spacing: 4) {
                    Image(systemName: "soccerball")
                        .foregroundStyle(.red)
                        .font(.footnote)
                    Text(match.status == "HALFTIME" ? UIString.halftime.text(lang) : UIString.live.text(lang))
                        .foregroundStyle(.red)
                }
            } else if match.status == "POSTPONED"
                        || match.status == "CANCELED"
                        || match.status == "CANCELLED" {
                Text(match.status == "POSTPONED" ? UIString.postponed.text(lang) : UIString.canceled.text(lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(formatKickoff(match.utcDate, tz: appState.timeZone, lang: lang))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Kickoff as "HH:mm" in the selected time zone.
private func formatKickoffShort(_ utcDate: String?, tz: TimeZone) -> String {
    guard let d = parseKickoffDate(utcDate) else { return "" }
    let df = FormatterPool.shared.formatter(tz: tz, localeID: "en_US", format: "HH:mm")
    return df.string(from: d)
}

// MARK: - Parsing & formatting (shared)

/// Parse an ISO8601 kickoff time.
func parseKickoffDate(_ utcDate: String?) -> Date? {
    guard let utcDate else { return nil }
    // Pooled static parsers: called per match on the body evaluation path.
    let pool = FormatterPool.shared
    return pool.isoBasic.date(from: utcDate) ?? pool.isoFractional.date(from: utcDate)
}

/// ISO8601 kickoff as "date time" text in the selected time zone.
func formatKickoff(_ utcDate: String?, tz: DisplayTimeZone, lang: AppLanguage) -> String {
    guard let d = parseKickoffDate(utcDate) else { return UIString.tbd.text(lang) }
    let df = FormatterPool.shared.formatter(
        tz: TimeZone(identifier: tz.identifier) ?? .current,
        localeID: lang == .english ? "en_US" : "zh_CN",
        format: lang == .english ? "MMM d HH:mm" : "M月d日 HH:mm")
    return df.string(from: d)
}
