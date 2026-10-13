import SwiftUI

// MARK: - Today: time & filtering logic (pure logic, unit-testable)

/// A match with its parsed kickoff time, for time-based filtering / sorting.
struct TimedMatch {
    let match: Match
    let kickoff: Date
}

/// Parse kickoff times and sort ascending (matches with unparseable times are dropped).
func timedMatches(_ matches: [Match]) -> [TimedMatch] {
    matches
        .compactMap { m -> TimedMatch? in
            guard let d = parseKickoffDate(m.utcDate) else { return nil }
            return TimedMatch(match: m, kickoff: d)
        }
        .sorted { $0.kickoff < $1.kickoff }
}

enum TodayFilter {
    /// Live (halftime included) — dual signal:
    /// 1. status is `IN_PLAY` / `HALFTIME`; **or**
    /// 2. inside the "kickoff → kickoff + matchWindow" window and not judged finished.
    ///
    /// The time window covers source-status lag (FPL flips `status` / publishes scores
    /// ~8 minutes after kickoff), keeping one definition with
    /// `AutoRefreshScheduler.schedule` — otherwise the scheduler is already polling a
    /// "live" match while the UI still shows "upcoming".
    static func isLive(_ m: Match, now: Date = Date()) -> Bool {
        if m.status == "IN_PLAY" || m.status == "HALFTIME" { return true }
        // Postponed/canceled matches aren't being played, yet their original kickoff
        // time lands in the window below — they must be excluded explicitly, or the
        // match reads as "live" for 3 h after kickoff (⚽ 0-0 on the card, and
        // MatchCard's postponed/canceled branch would become unreachable).
        if m.status == "POSTPONED" || m.status == "CANCELED" || m.status == "CANCELLED" { return false }
        guard let kickoff = parseKickoffDate(m.utcDate) else { return false }
        return kickoff <= now
            && now < kickoff.addingTimeInterval(AutoRefreshScheduler.matchWindow)
            && !isFinished(m)
    }
    /// Finished.
    static func isFinished(_ m: Match) -> Bool { m.status == "FINISHED" }
    /// Upcoming (includes postponed/canceled — neither live nor finished).
    static func isUpcoming(_ m: Match, now: Date = Date()) -> Bool { !isLive(m, now: now) && !isFinished(m) }

    /// Whether `date` and `reference` fall on the same day in `tz`.
    static func isSameDay(_ date: Date, as reference: Date, in tz: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.isDate(date, inSameDayAs: reference)
    }

    /// All matches "today" in `tz`, ascending by kickoff.
    ///
    /// Rules (all mandatory):
    /// 1. **Live matches always count as today** — a cross-midnight match (e.g. 23:30
    ///    Beijing kickoff running past 1 a.m.) kicked off "yesterday" in the selected
    ///    time zone but is being played right now; it must be shown.
    /// 2. Everything else is filtered by "kickoff date == today in the selected zone".
    static func todayMatches(from matches: [Match], now: Date = Date(), tz: TimeZone) -> [Match] {
        timedMatches(matches)
            .filter { isLive($0.match) || isSameDay($0.kickoff, as: now, in: tz) }
            .map(\.match)
    }

    /// Next match not yet kicked off (strictly after `now`).
    static func nextMatch(from matches: [Match], now: Date = Date()) -> Match? {
        timedMatches(matches).first { $0.kickoff > now }?.match
    }
}

// MARK: - Auto-refresh scheduling (pure logic, unit-testable)

/// Scheduling state for auto-refresh (plain data, easy to test and compare).
struct RefreshSchedule: Equatable {
    /// Whether a match is currently live (time-window test, see `AutoRefreshScheduler.schedule`).
    var hasLiveMatch: Bool
    /// Next unplayed kickoff; nil = nothing left in the known schedule.
    var nextKickoff: Date?
}

/// Timer scheduler for "auto-refresh during matches" — pure functions: no network,
/// no hidden `Date()` reads (`now` is passed explicitly).
///
/// Design goal: with no live match, stop fixed polling and **sleep until shortly
/// before the next kickoff** (wake `kickoffLeadTime` early), effectively zero polling
/// while idle; `maxIdleSleep` guards against schedule gaps so the app never sleeps
/// forever.
enum AutoRefreshScheduler {
    /// Refresh interval while a match is live.
    static let liveInterval: TimeInterval = 60
    /// How long before kickoff to wake up early (never miss kickoff itself).
    static let kickoffLeadTime: TimeInterval = 15 * 60
    /// Max idle sleep: with no inferable kickoff, self-check at least this often.
    static let maxIdleSleep: TimeInterval = 6 * 60 * 60
    /// Maximum span of a match from kickoff (for the "still live?" window test).
    static let matchWindow: TimeInterval = 3 * 60 * 60

    /// Compute the schedule state from fixtures + `now`.
    ///
    /// - `hasLiveMatch`: any match where `TodayFilter.isLive` holds — the status
    ///   signal (IN_PLAY / HALFTIME) or the `kickoff <= now < kickoff + matchWindow`
    ///   window; postponed/canceled are excluded explicitly. The window covers
    ///   source lag rather than trusting `status` alone (FPL scores stayed null for
    ///   ~8 minutes after kickoff once). Reusing `TodayFilter.isLive` keeps display
    ///   and scheduler on one definition.
    /// - `nextKickoff`: the earliest kickoff strictly after `now`; nil if none.
    /// - Matches with unparseable `utcDate` are skipped, never crash.
    nonisolated static func schedule(matches: [Match], now: Date) -> RefreshSchedule {
        var hasLiveMatch = false
        var nextKickoff: Date?

        for m in matches {
            guard let kickoff = parseKickoffDate(m.utcDate) else { continue }

            // Live: exactly the `TodayFilter.isLive` definition (status first + window
            // fallback). Reusing isLive instead of re-writing the window condition:
            // postponed/canceled matches also fall inside the window, and excluding
            // only FINISHED would have the scheduler poll a non-match for 3 hours.
            if TodayFilter.isLive(m, now: now) {
                hasLiveMatch = true
            }

            // Next: earliest kickoff strictly after now
            if kickoff > now, kickoff < (nextKickoff ?? .distantFuture) {
                nextKickoff = kickoff
            }
        }
        return RefreshSchedule(hasLiveMatch: hasLiveMatch, nextKickoff: nextKickoff)
    }

    /// Timer interval in seconds; nil = no timer. **The single decision entry point.**
    ///
    /// Decision table:
    /// - `autoRefresh == true` → fixed `liveInterval` (global 60 s makes this moot);
    /// - `duringMatches == false` → nil (no timer);
    /// - live match → `liveInterval`;
    /// - otherwise sleep until `kickoffLeadTime` before the next kickoff; already
    ///   inside the pre-kickoff window (or closer) → `liveInterval`;
    ///   no next match / too far away → `maxIdleSleep`.
    nonisolated static func refreshInterval(autoRefresh: Bool,
                                            duringMatches: Bool,
                                            schedule: RefreshSchedule,
                                            now: Date) -> TimeInterval? {
        if autoRefresh { return liveInterval }
        guard duringMatches else { return nil }
        if schedule.hasLiveMatch { return liveInterval }

        guard let next = schedule.nextKickoff else { return maxIdleSleep }
        let untilWake = next.timeIntervalSince(now) - kickoffLeadTime
        if untilWake <= liveInterval { return liveInterval }
        return min(untilWake, maxIdleSleep)
    }
}

// MARK: - Featured match selection

/// Pick logic for the featured-match card — the Today page's visual focal point.
/// The first matching rule wins (rules 2 / 4 / 5 all take the earliest kickoff slot
/// first, then break ties within the same slot by the smallest rank sum):
/// 1. a match currently being played;
/// 2. a match kicking off within 3.5 hours — earliest slot, marquee pairing on ties;
/// 3. today's finished matches (the most recent one);
/// 4. today's next unplayed match — earliest slot, marquee pairing on ties;
/// 5. the current round's next unplayed match (may cross days) — same as 2 / 4;
/// 6. the round is over — pick the finished result with the smallest rank sum;
///    without rankings, fall back to the round's earliest kickoff.
enum TodayFeatured {
    /// How close to kickoff counts as "about to start".
    static let upcomingWindow: TimeInterval = 3.5 * 60 * 60

    static func pick(from matches: [Match],
                     currentRound: Int,
                     now: Date = Date(),
                     tz: TimeZone,
                     positions: [Int: Int] = [:]) -> Match? {
        let timed = timedMatches(matches)

        // 1) Live (earliest kickoff when several, for stability)
        if let live = timed.first(where: { TodayFilter.isLive($0.match, now: now) }) { return live.match }

        // 2) Within 3.5 h → take the earliest-slot batch first, break same-slot ties by
        //    smallest rank sum.
        //    ⚠️ Preconditions: `timed` is kickoff-**ascending** (see `timedMatches`) and
        //    `filter` preserves order, so `chooseByRanking`'s `candidates.first?.kickoff`
        //    is the earliest time in the window — same semantics as the old
        //    `first(where:)`. With no rankings (empty positions) all rankKeys are equal
        //    → `min(by:)` stably returns the earliest match, unchanged behavior.
        let soonCandidates = timed.filter {
            $0.kickoff > now && $0.kickoff.timeIntervalSince(now) <= upcomingWindow
        }
        if let chosen = chooseByRanking(soonCandidates, positions: positions) { return chosen.match }

        // 3) Finished today → the most recent one
        let finishedToday = timed.filter {
            TodayFilter.isFinished($0.match) && TodayFilter.isSameDay($0.kickoff, as: now, in: tz)
        }
        if let last = finishedToday.last { return last.match }

        // 4) Today's next unplayed → same earliest-slot rule with rank tiebreak.
        //    (Candidate set identical to the old implementation, word for word; only
        //    "take the first" became `chooseByRanking`.)
        let todayUpcoming = timed.filter {
            TodayFilter.isUpcoming($0.match, now: now) && TodayFilter.isSameDay($0.kickoff, as: now, in: tz)
        }
        if let chosen = chooseByRanking(todayUpcoming, positions: positions) { return chosen.match }

        // 5) Current round's next unplayed (may cross days) → same two-tier rule
        let roundUpcoming = timed.filter {
            $0.match.matchday == currentRound && TodayFilter.isUpcoming($0.match, now: now)
        }
        if let chosen = chooseByRanking(roundUpcoming, positions: positions) {
            return chosen.match
        }

        // 6) Round over → pick the finished result with the smallest rank sum across
        //    the whole round.
        //
        // ⚠️ Cannot reuse chooseByRanking: it narrows to the earliest kickoff slot
        // before comparing ranks, which degenerates to "earliest kickoff" once the
        // whole round is finished — exactly the bug this fixes (after round 3 the card
        // showed the early Liverpool game when the user wanted Arsenal vs Chelsea).
        // With the round over, kickoff order is meaningless, so compare ranks across
        // all time slots directly.
        //
        // Without rankings all rankKeys are equal and `min(by:)` stably returns the
        // first → still the earliest kickoff, backwards compatible.
        let roundMatches = timed.filter { $0.match.matchday == currentRound }
        return roundMatches.min(by: {
            rankKey($0.match, positions: positions) < rankKey($1.match, positions: positions)
        })?.match
    }

    /// Pick the featured match from candidates (shared by rules 2 / 4 / 5).
    /// Two-tier ordering:
    /// 1. by kickoff first — only the earliest same-time batch qualifies; matches at
    ///    other times never outrank earlier ones (a lone earliest match wins outright,
    ///    even if a "bigger" pairing starts later);
    /// 2. within the same slot, smallest sum of the two ranks wins; on equal sums the
    ///    better (lower) best-rank wins.
    /// Ranks come from `positions` (teamId → rank); unknown ranks sink via
    /// `Int.max / 2`. `timed` is kickoff-ascending and `min(by:)` is stable.
    private static func chooseByRanking(_ candidates: [TimedMatch], positions: [Int: Int]) -> TimedMatch? {
        guard let earliest = candidates.first?.kickoff else { return nil }
        // Only the same kickoff slot is compared by rank
        let sameSlot = candidates.filter { $0.kickoff == earliest }
        return sameSlot.min(by: { rankKey($0.match, positions: positions) < rankKey($1.match, positions: positions) })
    }

    private static func rankKey(_ m: Match, positions: [Int: Int]) -> (sum: Int, best: Int) {
        // ⚠️ Sentinel is `Int.max / 2`, not `Int.max`: with both ranks unknown,
        // `hp + ap` would be `Int.max + Int.max`, overflowing and trapping in debug
        // builds (SIGTRAP / signal 5 — a crashing test process). Half the bound sums
        // to at most `Int.max`, no overflow.
        let unknown = Int.max / 2
        let hp = positions[m.homeTeam.id] ?? unknown
        let ap = positions[m.awayTeam.id] ?? unknown
        return (hp + ap, min(hp, ap))
    }
}

/// Today's matches grouped by status.
struct TodayGroups {
    let live: [Match]
    /// Upcoming (includes postponed/canceled — neither live nor finished).
    let upcoming: [Match]
    let finished: [Match]

    var total: Int { live.count + upcoming.count + finished.count }
    var isEmpty: Bool { total == 0 }
}

/// What feeds the first column (decides its title).
///
/// The first column merges "live & recent": live matches first, today's finished
/// ones after — users want both at a glance instead of choosing one.
enum TodayLiveSource: Equatable {
    /// Live matches exist (the list holds live + today's finished)
    case liveAndRecent
    /// No live matches; only today's finished remain
    case recent
}

/// Content of the bottom row's two columns.
struct TodayColumns {
    /// Column 1: live & recent (live first, finished after; featured match excluded).
    let live: [Match]
    let liveSource: TodayLiveSource
    /// Column 2: today's upcoming fixtures (featured match excluded).
    ///
    /// Deliberately **no round fallback** (next match of this round / next round):
    /// while the current round is still 2, spilling round 3 fixtures would look like
    /// the round already flipped. Layout undecided — "today" only for now, empty
    /// shows "no data".
    let upcoming: [Match]
}

// MARK: - ViewModel

/// Today view model (@Observable).
@Observable
final class TodayViewModel {
    var matches: [Match] = []
    var source: DataSource = .sample
    var error: AppError?
    /// Current round.
    var currentRound: Int = 1
    /// Current standings positions (teamId → rank) so the featured card can prefer
    /// marquee pairings for "next match of the round". Fetched via
    /// DataRepository.standings() (cached, three-tier fallback, per-tier timeouts
    /// inside) — no outer budget here, so a slow tier 1 can't cancel the
    /// millisecond-tier 2 aggregation.
    var positions: [Int: Int] = [:]

    @MainActor
    func load() async {
        // Concurrent fetches: fixtures (first screen), current round and standings
        // positions are independent; firing together shortens the window where the
        // featured card shows "earliest kickoff" before jumping to the marquee pick.
        // (standings() reuses the cached fixtures internally; no extra network hits.)
        async let matchesResult: ([Match], DataSource) = DataRepository.matches()
        async let roundResult: Int? = withTimeBudget(seconds: 8) {
            await DataRepository.currentGameweek()
        }
        // ⚠️ No outer 8 s budget here on purpose:
        // standings() already has per-tier timeouts (tier 1 network 15 s/30 s, tier 2
        // reuses cached fixtures) and switches tiers itself. An outer 8 s cap would
        // cancel the whole call while tier 1 is slow, so the millisecond-tier 2
        // aggregation would never run — positions stay empty and the featured card
        // degrades to "earliest kickoff".
        async let standingsResult: ([StandingRow], DataSource)? = try? await DataRepository.standings()

        // First-screen render point: show fixtures the moment they arrive; the rest
        // fills in asynchronously.
        let (data, src) = await matchesResult
        matches = data
        source = src
        error = nil

        // currentRound only feeds the featured pick — nice to have: past the 8 s
        // budget it falls back to inferring the round from fixtures, never blocking
        // the first screen above.
        let round = await roundResult
        currentRound = round ?? CurrentRoundInference.infer(from: matches) ?? 1

        // Missing ranks (timeout / no data) simply degrade the featured formula to
        // "earliest kickoff"; no error.
        if let rows = (await standingsResult)?.0, !rows.isEmpty {
            positions = Self.buildPositions(from: rows)
        }
    }

    /// Aggregate standings rows into a "teamId → rank" dictionary.
    ///
    /// `uniquingKeysWith:` instead of `uniqueKeysWithValues:`: dirty data or
    /// home/away leftovers can put the same team in twice, and the latter traps on
    /// duplicate keys. Duplicates keep the **first** occurrence.
    static func buildPositions(from rows: [StandingRow]) -> [Int: Int] {
        Dictionary(rows.map { ($0.team.id, $0.position) }, uniquingKeysWith: { first, _ in first })
    }

    /// Today's matches grouped by status (header counts and status mix).
    func grouped(tz: TimeZone, now: Date = Date()) -> TodayGroups {
        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        return TodayGroups(
            live: today.filter { TodayFilter.isLive($0, now: now) },
            upcoming: today.filter { TodayFilter.isUpcoming($0, now: now) },
            finished: today.filter(TodayFilter.isFinished)
        )
    }

    /// The featured match (large card).
    func featured(tz: TimeZone, now: Date = Date()) -> Match? {
        TodayFeatured.pick(from: matches, currentRound: currentRound, now: now, tz: tz, positions: positions)
    }

    /// The bottom row's two columns.
    ///
    /// Both columns **exclude the featured match** — it's already the focal point;
    /// listing it again is pure duplication.
    ///
    /// Column 1 merges live + today's finished (live first, finished most-recent
    /// first); column 2 takes **today's upcoming only**, no round fallback (see
    /// `TodayColumns.upcoming`).
    func columns(tz: TimeZone, now: Date = Date()) -> TodayColumns {
        let today = TodayFilter.todayMatches(from: matches, now: now, tz: tz)
        let featuredID = featured(tz: tz, now: now)?.id
        let notFeatured: (Match) -> Bool = { $0.id != featuredID }

        // Column 1: live first (earliest kickoff first) + today's finished after (most recent first)
        let liveOnly = today.filter { TodayFilter.isLive($0, now: now) }.filter(notFeatured)
        let finishedToday = today.filter(TodayFilter.isFinished)
            .filter(notFeatured)
            .reversed() // "recent": just-finished first
        let first = liveOnly + finishedToday
        let firstSource: TodayLiveSource = liveOnly.isEmpty ? .recent : .liveAndRecent

        // Column 2: today's upcoming (timedMatches is kickoff-ascending)
        let second = today.filter { TodayFilter.isUpcoming($0, now: now) }.filter(notFeatured)

        return TodayColumns(live: first, liveSource: firstSource, upcoming: second)
    }
}

// MARK: - View

/// Today page layout (four rows top to bottom):
/// 1. large title "Today · Aug 31";
/// 2. subtitle "Round 2 · 10 matches · 0 live";
/// 3. featured match card (the page's focal point);
/// 4. two equal columns:
///    - column 1: live & recent (live first, finished after; title degrades to
///      "Recent" with no live matches);
///    - column 2: today's fixtures (no round fallback; empty shows "no data");
///    both exclude the featured match.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = TodayViewModel()

    private var timeZone: TimeZone {
        TimeZone(identifier: appState.timeZone.identifier) ?? .current
    }

    var body: some View {
        let lang = appState.language

        Group {
            if vm.matches.isEmpty {
                EmptyStateView(label: UIString.noFixtures.text(lang))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let featured = vm.featured(tz: timeZone) {
                            FeaturedMatchCard(match: featured)
                        }
                        columnsView(vm.columns(tz: timeZone))
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(UIString.today.text(lang))
        .task(id: appState.refreshNonce) {
            // Background polling refreshes silently: no full-screen overlay (a flash
            // every 60 s on matchdays is very disruptive); first load / manual refresh
            // keep it. isLoading still resets unconditionally so the overlay can never
            // stick under odd timings.
            if appState.lastRefreshSource != .background { appState.isLoading = true }
            await vm.load()
            appState.source = vm.source
            appState.isLoading = false
            // Report "live match? / next kickoff?" to AppState so the auto-refresh
            // timer can switch between 60 s polling and sleeping until kickoff.
            appState.reportLiveSchedule(from: vm.matches)
        }
        .overlay { if appState.isLoading { LoadingView() } }
    }

    // MARK: Rows 1 & 2: large title + subtitle

    private var header: some View {
        let lang = appState.language
        let groups = vm.grouped(tz: timeZone)
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: UIString.todayTitleFormat.text(lang), todayDateText))
                .font(.largeTitle)
                .bold()
            Text(String(format: UIString.todaySubtitleFormat.text(lang),
                        vm.currentRound, groups.total, groups.live.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Date only: Chinese "8月31日" / English "Aug 31".
    private var todayDateText: String {
        let lang = appState.language
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = lang == .english ? "MMM d" : "M月d日"
        return df.string(from: Date())
    }

    // MARK: Row 4: two equal columns

    /// Bottom row: always two small cards (left/right), with or without data.
    /// Empty content shows a "no data" placeholder so the page never shows one lonely
    /// large card between rounds. The "View all →" link jumps to the fixtures section.
    private func columnsView(_ cols: TodayColumns) -> some View {
        let lang = appState.language
        return HStack(alignment: .top, spacing: 16) {
            columnCard(
                title: cols.liveSource == .liveAndRecent
                    ? UIString.colLiveAndRecent.text(lang)
                    : UIString.colRecent.text(lang),
                matches: cols.live
            )
            columnCard(
                title: UIString.colTodayUpcoming.text(lang),
                matches: cols.upcoming
            )
        }
    }

    /// One column card: title + "view all" link + match list or empty placeholder.
    private func columnCard(title: String, matches: [Match]) -> some View {
        let lang = appState.language
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    appState.selected = .fixtures
                } label: {
                    HStack(spacing: 4) {
                        Text(UIString.viewAll.text(lang))
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if matches.isEmpty {
                Text(UIString.noData.text(lang))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    // Max 4 matches per column: both columns share columnCard, one
                    // change covers both. The rest go through "View all →" to the
                    // fixtures page — two long lists would make Today scroll forever.
                    ForEach(Array(matches.prefix(4))) { match in
                        // Today page: teams flanking the edges (home left, away right),
                        // distinct from the fixtures page's "hug the score" layout.
                        MatchCard(match: match, teamsFlankSides: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Featured match card

/// Featured card corner radius.
///
/// Without an explicit shape, .glassEffect() on macOS 26 picks a container-derived
/// corner radius (26 pt and up) — far too round for a content card. Specified here:
/// - Apple's radius grows with container size, but content cards don't need
///   sheet/modal radii;
/// - 12 pt matches the macOS window corner (~10 pt) in scale, reading as "card";
/// - pinned on purpose rather than inheriting defaults — every value should be a
///   defensible choice.
private let featuredCardCornerRadius: CGFloat = 12

/// Extra inset between the team blocks and the card's left/right edges.
/// The card already has 22 pt padding, but the team blocks are
/// `maxWidth: .infinity` — crests/names would sit 22 pt from the edge, visually
/// "glued" to it. +40 pt gives the content breathing room from the glass while the
/// score/time stay centered and the teams don't crowd the middle.
private let featuredCardSideInset: CGFloat = 40

/// The card's pinned gradient (deep magenta → bright pink, left→right), independent
/// of the macOS accent color. The "accent color × Liquid Glass" purple looked cool
/// enough that the user chose to freeze this card's colors — hence a constant that
/// never reads AppState.
private let featuredCardGradient = LinearGradient(
    colors: [
        Color(red: 0.45, green: 0.05, blue: 0.35),   // deep magenta (left)
        Color(red: 0.92, green: 0.20, blue: 0.55),   // bright pink (right)
    ],
    startPoint: .leading,
    endPoint: .trailing
)

/// Row 3 of the Today page: the featured match card, the page's focal point.
struct FeaturedMatchCard: View {
    @Environment(AppState.self) private var appState
    let match: Match

    private var timeZone: TimeZone {
        TimeZone(identifier: appState.timeZone.identifier) ?? .current
    }

    private var kickoff: Date? { parseKickoffDate(match.utcDate) }

    /// Minutes elapsed since kickoff (floored) — a **pure function**; `now` is passed in.
    ///
    /// Clamped at 0 so a pre-match IN_PLAY status or clock skew can't produce
    /// negatives. Returns nil when kickoff is unparseable.
    ///
    /// ⚠️ Deliberately does **not** read `Date()` inside the property: the live path
    /// feeds `context.date` from `TimelineView(.periodic(by: 1))` in `centerBlock`.
    /// That keeps the whole "time → text" chain unit-testable and avoids SwiftUI
    /// skipping this card's body (frozen minutes) when `match` doesn't change.
    nonisolated static func elapsedMinutes(kickoff: Date?, now: Date) -> Int? {
        guard let kickoff else { return nil }
        return max(0, Int(floor(now.timeIntervalSince(kickoff) / 60)))
    }

    /// Render elapsed minutes in football notation (19' / 45' / 90+').
    ///
    /// A pure function (no `Date()`) so every branch is testable. Rules:
    /// - halftime (HALFTIME) → fixed 45'
    /// - first half (≤45) → actual minutes
    /// - halftime window (46–60, status not yet HALFTIME) → clamp to 45'
    /// - second half (61–105) → actual minutes minus the 15-minute break
    /// - stoppage / very long (>105) → clamp to 90+'
    ///
    /// - Parameters:
    ///   - elapsed: minutes since kickoff (caller guarantees ≥ 0)
    ///   - isHalftime: whether the match is at halftime
    nonisolated static func formatLiveClock(elapsed: Int, isHalftime: Bool) -> String {
        if isHalftime { return "45'" }
        if elapsed <= 45 { return "\(elapsed)'" }
        if elapsed <= 60 { return "45'" }
        if elapsed <= 105 { return "\(elapsed - 15)'" }
        return "90+'"
    }

    /// What the card's center slot should show — a pure function (no network / clock)
    /// so each branch is testable.
    ///
    /// Decision order (**order must not change**):
    /// 1. a score (`score?.fullTime?.home` and `.away` both non-nil) → `.score`;
    /// 2. else if live (`TodayFilter.isLive`) → `.pendingLiveScore` — FPL fixtures
    ///    return no score for ~8 minutes after kickoff; show `0 - 0`, **never**
    ///    degrade to the kickoff time;
    /// 3. else a parseable kickoff → `.kickoff`;
    /// 4. none of the above → `.tbd`.
    ///
    /// ⚠️ Order must be strictly "score → live → kickoff": lifting the live check
    /// first would misclassify "live with a score" as `.pendingLiveScore` (0-0).
    enum CenterContent: Equatable {
        /// A score; `isLive` decides whether ⚽ precedes it (live)
        case score(home: Int, away: Int, isLive: Bool)
        /// Live but the source hasn't published a score yet (FPL lag ~8 min) → UI shows 0 - 0
        case pendingLiveScore
        /// Not kicked off → show kickoff time
        case kickoff(Date)
        /// No score and no kickoff → "TBD"
        case tbd
    }

    /// See `CenterContent`'s ordering notes. `nonisolated` matches `formatLiveClock`
    /// for direct unit-test access.
    nonisolated static func centerContent(for match: Match, now: Date = Date()) -> CenterContent {
        if let home = match.score?.fullTime?.home, let away = match.score?.fullTime?.away {
            return .score(home: home, away: away, isLive: TodayFilter.isLive(match, now: now))
        }
        if TodayFilter.isLive(match, now: now) { return .pendingLiveScore }
        if let kickoff = parseKickoffDate(match.utcDate) { return .kickoff(kickoff) }
        return .tbd
    }

    var body: some View {
        let lang = appState.language
        VStack(spacing: 18) {
            // Top: round + status badge (left), Spacer fills the right
            HStack(spacing: 8) {
                if let md = match.matchday {
                    Text(String(format: UIString.roundN.text(lang), md))
                        .font(.footnote)
                        .foregroundStyle(.white)
                }
                statusBadge(lang: lang)
                Spacer()
            }

            // Middle: home (left) | score / time (center) | away (right).
            // Each team block takes half the width, hugging its outer edge, so
            // crests/names don't crowd the score. (List-row MatchCards do the
            // opposite on purpose — names hug the score for a straight score column.)
            HStack(spacing: 0) {
                teamBlock(match.homeTeam, lang: lang, alignment: .leading)
                Spacer(minLength: 24)
                centerBlock(lang: lang)
                Spacer(minLength: 24)
                teamBlock(match.awayTeam, lang: lang, alignment: .trailing)
            }
            .padding(.horizontal, featuredCardSideInset)
        }
        .padding(22)
        // Force dark semantics on the card subtree: .primary/.secondary resolve to
        // white/light gray. Otherwise light-mode text renders near-black on the pinned
        // magenta gradient (WCAG contrast a mere 1.71:1).
        .environment(\.colorScheme, .dark)
        // Pinned gradient background (never follows the accent color); corner radius
        // shared via featuredCardCornerRadius. A faint black overlay softens the pink
        // end so the white text (44 pt score / small round & status rows) reads on
        // both ends without losing the pop.
        .background(
            RoundedRectangle(cornerRadius: featuredCardCornerRadius)
                .fill(featuredCardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: featuredCardCornerRadius)
                        .fill(Color.black.opacity(0.12))
                )
        )
    }

    private func teamBlock(_ team: Team, lang: AppLanguage, alignment: HorizontalAlignment) -> some View {
        VStack(spacing: 10) {
            // The featured card is the focal point: crest at 56 pt (CrestImage's 20 pt
            // default is for list rows).
            CrestImage(urlString: team.crest, size: 56)
            Text(team.displayName(chinese: lang == .chinese))
                .font(.title3)
                .bold()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    /// Center: big score when present (⚽ when live), big time when upcoming.
    /// "Live but no score yet" (source lag) shows 0 - 0 rather than contradictorily
    /// degrading to the kickoff time.
    private func centerBlock(lang: AppLanguage) -> some View {
        let now = Date()
        return VStack(spacing: 6) {
            switch Self.centerContent(for: match, now: now) {
            case let .score(home, away, isLive):
                scoreRow(home: home, away: away, isLive: isLive)
            case .pendingLiveScore:
                // Live, source hasn't published a score → 0 - 0, styled exactly like a live score
                scoreRow(home: 0, away: 0, isLive: true)
            case let .kickoff(date):
                Text(timeText(date, lang: lang))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            case .tbd:
                Text(UIString.tbd.text(lang))
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            // Live minutes (e.g. 19') are what users track in real time: bigger, bold,
            // pure white. The finished/upcoming line below stays footnote + .white.
            if TodayFilter.isLive(match, now: now) {
                // ⚠️ `TimelineView(.periodic(by: 1))` gives the minutes a redraw source
                // independent of data refreshes: while no goal is scored `match` doesn't
                // change and SwiftUI skips this card's body, freezing `Date()`-derived
                // minutes at the last evaluated minute. The timeline re-evaluates its
                // closure automatically, so minutes always advance. Only this one `Text`
                // is wrapped — the rest of the card has no need for per-second redraws.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(statusLine(lang: lang, now: context.date))
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            } else {
                Text(statusLine(lang: lang, now: Date()))
                    .font(.footnote)
                    .foregroundStyle(.white)
            }
        }
    }

    /// Score row (⚽ when live). Shared by `.score` and `.pendingLiveScore` so both
    /// look identical.
    private func scoreRow(home: Int, away: Int, isLive: Bool) -> some View {
        HStack(spacing: 8) {
            if isLive {
                Image(systemName: "soccerball")
                    .foregroundStyle(.red)
                    .font(.title3)
            }
            Text("\(home) - \(away)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    /// Small line under the score/time: live → minutes (19'); finished → finished;
    /// upcoming → date.
    ///
    /// `now` comes from the caller — the live path uses `TimelineView`'s
    /// `context.date`; otherwise `Date()`.
    private func statusLine(lang: AppLanguage, now: Date) -> String {
        if TodayFilter.isLive(match, now: now) {
            // No kickoff time → no minutes; fall back to the "live" label
            guard let elapsed = Self.elapsedMinutes(kickoff: kickoff, now: now) else { return UIString.live.text(lang) }
            return Self.formatLiveClock(elapsed: elapsed,
                                        isHalftime: match.status == "HALFTIME")
        }
        if TodayFilter.isFinished(match) { return UIString.statusFinished.text(lang) }
        guard let kickoff else { return UIString.tbd.text(lang) }
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = lang == .english ? "MMM d" : "M月d日"
        return df.string(from: kickoff)
    }

    private func statusBadge(lang: AppLanguage) -> some View {
        let text: String
        let color: Color
        if TodayFilter.isLive(match, now: Date()) {
            text = UIString.live.text(lang)
            color = .red
        } else if TodayFilter.isFinished(match) {
            text = UIString.statusFinished.text(lang)
            color = .white
        } else if match.status == "POSTPONED"
                    || match.status == "CANCELED"
                    || match.status == "CANCELLED" {
            text = match.status == "POSTPONED" ? UIString.postponed.text(lang) : UIString.canceled.text(lang)
            color = .white
        } else {
            text = UIString.statusUpcoming.text(lang)
            color = .white
        }
        return Text(text)
            .font(.caption)
            .bold()
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func timeText(_ date: Date, lang: AppLanguage) -> String {
        let df = DateFormatter()
        df.timeZone = timeZone
        df.locale = lang == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }
}
