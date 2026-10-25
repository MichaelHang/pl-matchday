# EPLViewer — Premier League Companion App

A native SwiftUI app for macOS 26 (Liquid Glass look) that follows the Premier League season through a hybrid of public data sources.

## Features

- **Standings** — live table with European / relegation zone highlighting (ESPN v3; falls back to on-the-fly aggregation from played fixtures while ESPN's records are empty)
- **Fixtures** — full-season schedule in one pull (FPL fixtures, ESPN scoreboard as fallback)
- **Players** — top scorers & top assists (derived from FPL)
- **Injuries** — status, news and chance of playing next round (derived from FPL)

## Data Sources

| Data | Source | Cache TTL |
|---|---|---|
| Fixtures & scores | FPL fixtures (ESPN scoreboard fallback) | 5 min |
| FPL bootstrap (players / scorers / assists / injuries) | Fantasy Premier League public endpoint | 2 h |
| Standings | ESPN v3 | 5 min |

No API key, no Python dependency. Offline (or on timeout) the app falls back to **the last successfully cached data** (stale-if-error, TTL ignored). A fresh install that has never reached the network shows empty states — no bundled fake data.

## Development

### Option 1: Open in Xcode 26 (recommended)

```bash
open /Users/hangbo/Code/Github/PremierLeague/EPLViewer.xcodeproj
# Cmd+R to run, Cmd+U to test
```

### Option 2: Command line

```bash
cd /Users/hangbo/Code/Github/PremierLeague
xcodebuild -scheme EPLViewer -configuration Debug build       # build
xcodebuild -scheme EPLViewer -configuration Debug test        # unit tests
xcodebuild -scheme EPLViewer -configuration Release build     # release build
```

### Option 3: Build a .app bundle

```bash
./build-app.sh             # release build + bundle at build/EPLViewer.app
open build/EPLViewer.app
```

## Project Layout

```
.                                 # repo root = project root
├── EPLViewer.xcodeproj           # Xcode project (hand-maintained, single source of truth)
├── EPLViewer/                    # app target sources
│   ├── App/                      # entry & global shell: @main / AppState / ContentView / SettingsView / Sidebar / TopBar
│   ├── Core/                     # data layer: Models / Networking (ESPN+FPL clients) / Cache / Translators / DataRepository / Support
│   ├── Features/                 # feature views: Today / Fixtures / Standings / LeadersAndInjuries
│   ├── Localization/             # translations: TranslationStore + PlayerNames + TeamNames + Resources/*.json
│   └── Common/                   # CommonViews (state views / CrestImage / brand colors) + UIStrings
├── EPLViewerTests/               # 200+ unit tests, split by domain (Today / Fixtures / Standings / Scheduler / Localization / Guard)
├── docs/                         # design docs + diagrams (mermaid)
└── build-app.sh                  # xcodebuild release + .app bundle
```

## Maintenance Notes

- **Adding / moving source files**: drag in or remove via Xcode (writes to `EPLViewer.xcodeproj/project.pbxproj` automatically). From the command line, edit the `PBXBuildFile` / `PBXFileReference` / build-phase sections of the pbxproj by hand.
- There is **no** `Package.swift`, `project.yml` or XcodeGen step — `EPLViewer.xcodeproj` is the single source of truth.
- **Player / team name tables** live in `EPLViewer/Localization/Resources/*.json`; add a translation by editing the JSON (or by using the in-app DEBUG override manager). To support a new language, add another locale file (e.g. `TeamNames-zh-Hant.json`).
- The test suite includes **source-text guard tests** that assert on literal implementation details; when changing an implementation on purpose, update the corresponding assertion (keep the guard, don't delete it).

## Known Limitations

- **Offline on first install**: nothing to show (no bundled sample data); after one successful fetch the cache takes over as the offline fallback.
- **Cross-source IDs**: standings (ESPN) and player data (FPL) use different id spaces.
- **First-launch latency**: one FPL bootstrap fetch (~1 MB), cached for 2 hours afterwards.
