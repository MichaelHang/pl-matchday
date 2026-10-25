# EPLViewer — System Design

> Current as of 2026-10-13. The README covers user-facing basics and build steps;
> this document describes the architecture, data pipeline and the reasoning behind
> the load-bearing decisions. Diagrams: `class-diagram.mermaid`, `sequence-diagram.mermaid`.

---

## 1. Platform & Stack

- macOS 26 native app, SwiftUI + Observation (`@Observable`), Swift 6.
- Zero third-party dependencies — URLSession async/await, no packages.
- Single Xcode target (`EPLViewer`) + unit-test target (`EPLViewerTests`, TEST_HOST).
- No API keys. Sources: Fantasy Premier League public endpoints (primary) and ESPN
  public API (fallback), both key-less.

## 2. Directory Layout

```
EPLViewer/
├── App/            Entry & global shell: @main, AppState, ContentView,
│                   SettingsView, Sidebar, TopBar
├── Core/           Data layer:
│   ├── Models.swift          domain models (Match/Team/StandingRow/…)
│   ├── Networking.swift      APIClient + ESPNProvider + FPLProvider + wire models
│   ├── Cache.swift           MemoryStore (session) + CacheStore (disk, TTL)
│   ├── Translators.swift     wire → domain translators, standings aggregation,
│   │                         enrichment, stableID (FNV-1a)
│   ├── DataRepository.swift  the single fetch entry point + fallback chain
│   └── Support.swift         SeasonStore + withTimeBudget
├── Features/       TodayView / FixturesView / StandingsView /
│                   LeadersAndInjuriesViews (view + view model per section)
├── Localization/   TranslationStore + PlayerNames + TeamNames +
│   └── Resources/  PlayerNames-zh-Hans.json, TeamNames-zh-Hans.json
└── Common/         CommonViews (state views / CrestImage / LogoCache) + UIStrings
```

Dependency direction: `Features → Core`, `App → all`, leaf stores touch no UI.

## 3. Data Pipeline

### 3.1 Sources & priority

| Data | Primary | Fallback | Notes |
|---|---|---|---|
| Fixtures & scores | FPL `/api/fixtures/` | ESPN site scoreboard | FPL carries gameweek + official crests |
| Standings | ESPN v3 `records` | aggregate from played fixtures | ESPN fills `records` late; aggregation is the workhorse early season |
| Players / scorers / assists / injuries | FPL `bootstrap-static` | — | derived locally by `FPLTranslator` |

### 3.2 Fetch chain (per `DataRepository.matches()`; standings/bootstrap analogous)

```
memory (session) → disk (within TTL) → network (20 s budget)
  → disk stale (ignore TTL) → in-process last-known-good → empty
```

- **MemoryStore** — session cache, decoded once per launch; the live-match poll
  clears it to force a network attempt.
- **CacheStore** — atomic JSON files in Application Support, TTL-checked via mtime
  (`CacheTTL`: fixtures 5 min, bootstrap 2 h, standings 5 min).
- **Stale-if-error** — on network failure the disk cache is served ignoring TTL,
  tagged `DataSource.stale`.
- **Last-known-good** — `MemoryStore` slots written on every *successful* fetch and
  deliberately immune to `clear()` / `clearFixtures()`. A failed refresh therefore
  degrades to the previous data and can never wipe a populated page blank (the
  match-day blank-screen regression). `DataSource` vocabulary: `.live` / `.stale` /
  `.sample` (empty placeholder; no bundled fake data).
- Every tier transition is intentional — see the inline comments; the sequence is
  also drawn in `sequence-diagram.mermaid`.

### 3.3 Standings aggregation & enrichment

- `StandingsAggregator.aggregate(matches:)` tallies W/D/L/Pts/GF/GA from finished
  fixtures (an ESPN v3 event-walking variant, `aggregate(daysBack:)`, exists for when
  the fixtures source is unavailable).
- `StandingsEnricher` fills home/away splits and the last-5 form per team.
- Sorting is deterministic everywhere: points → GD → GF, then ESPN rank (v3) or
  teamId (aggregated) as the final tiebreak — tied rows never swap between renders.

## 4. Auto-refresh Scheduler

`AutoRefreshScheduler` (pure functions) is the single interval decision point:

| Condition | Interval |
|---|---|
| Global auto-refresh on | 60 s |
| "During matches" on + live match | 60 s |
| No live match | sleep until 15 min before next kickoff |
| No schedule | 6 h self-check |
| "During matches" off | no timer |

- Live detection = status signal (IN_PLAY/HALFTIME) OR kickoff window
  (`kickoff … kickoff+3h`), postponed/canceled excluded — one definition shared by
  the display (`TodayFilter.isLive`) and the scheduler.
- Every timer wake **recomputes** the schedule/interval against the current time
  (content-based debouncing would sleep through matches — documented in
  `AppState.refreshTick`).
- The poll refreshes fixtures only (`refresh(scoresOnly: true)`); bootstrap and
  standings are not re-downloaded every 60 s.
- A failed poll/refetch never blanks the UI — see §3.2 last-known-good.

## 5. Feature Logic Highlights

- **Today** — featured-match selection with six priority rules (live → ≤3.5 h window
  (earliest slot, rank-sum marquee tiebreak) → today's finished → today's upcoming →
  round's next → round finished (cross-slot marquee)); live minutes rendered as
  `19' / 45' / 90+'` via pure functions + a 1-second `TimelineView`.
- **Fixtures** — fixed-size round window (5 chips) with paging that never moves the
  focused round; season-overview snapshots cached by input (`indexGeneration` +
  currentRound + seasonProgress); season progress bar (played/total rounds).
- **Standings** — 4 tabs (overall/home/away/form); zone colors derive from the
  overall position only; form chips sized to keep tab heights aligned.
- **Injuries** — transfer departures (status "u" + transfer news: "joined" / "on
  loan" / "departed" / "free agent") are filtered out; the board shows real
  availability only.
- **UI guard rails** — no lazy container inside another lazy container, horizontal
  ScrollViews always height-constrained, `GridItem.maximum` never `.infinity`,
  `URLSession.shared` banned (7-day resource timeout), no hardcoded user-facing
  Chinese outside UIStrings — several of these are enforced by source-text tests.

## 6. Localization

- Name tables live as JSON resources keyed by FPL ids/codes
  (`PlayerNames-zh-Hans.json`: 667 ids + 220 web_names; `TeamNames-zh-Hans.json`: 21
  clubs), loaded once by `TranslationStore` (bundle-anchored; failure → empty table →
  English names).
- A DEBUG override panel persists runtime corrections to
  `~/Library/Application Support/<bundle id>/playerNameOverrides.json`.
- New language = add a locale file (e.g. `TeamNames-zh-Hant.json`) and select the
  locale on the display side; UI copy itself lives in `UIStrings` (zh/en pairs).

## 7. Testing

208 unit tests in `EPLViewerTests/`, split by domain
(`TodayTests` / `FixturesTests` / `StandingsTests` / `SchedulerTests` /
`LocalizationTests` / `GuardTests` + the base fixture/helper file). All domain files
are extensions of the same `EPLViewerTests` class; shared helpers/seeds live in the
base file.

- **Source-text guard tests** assert on literal implementation details (corner
  radii, font sizes, `LazyHStack` placement, navigation titles, banned APIs). When
  changing an implementation on purpose, update the assertion — keep the guard.
- Guard infrastructure locates sources by recursive file-name search
  (`locateSource`), so adding subdirectories needs no test changes; renaming or
  splitting source files does.
- QA launch arguments (DEBUG only, via the UserDefaults argument domain):
  `-section <name>` (land on a section), `-fixtures_mode season` (season overview),
  `-force_stale 1` (pin the offline badge), `-epl_snapshot <name>` (write a window
  capture to `/tmp/epl-<name>.png` and exit).

## 8. Intentional Decisions & Known Limitations

- The standings card fills the detail area; on very tall windows a blank tail
  remains below row 20 (chosen over a content-hugging card).
- `EmptyStateView` offers a retry button, but the fetch chain already prefers
  last-known-good — retry matters mainly on first launch offline.
- `DataRepository.teams()/team(id:)` are kept without callers (future team-detail
  feature).
- Error banners are unreachable by design: fetch failures degrade to stale data or
  empty states instead of error screens.
