# Hub Ball — Project Handoff

Updated October 9, 2026 from the canonical checkout at
`/Users/sfrancoe/Projects/Hub Ball`. Read [AGENTS.md](AGENTS.md) before making changes.

## Product and source

Hub Ball is a native SwiftUI baseball companion for all 30 MLB teams, backed by
generated JSON feeds and Netlify Functions. The repository also contains the original
Boston baseball website and canvas stories. The repository is
`https://github.com/sfrancoe/red-sox`; `main` is the only release and device-installation
source. The old MLB Apps / Red-Sox checkout is archived.

The active app identity is `com.sfrancoe.HubBall`. The legacy Boston Baseball Hub
identity and retired standalone Yankees app are documented in
[docs/PRODUCTS.md](docs/PRODUCTS.md). Yankees content is part of Hub Ball.

`config/hub-ball-release.json` currently declares version 1.1, build 125. Always read
the manifest and run `python3 scripts/check_hub_ball_release.py` before answering a
release question or installing on a device. A successful simulator build does not
declare or publish a release. Build changes require updating both Xcode configurations
and the manifest together. Device installation goes through
`scripts/install_hub_ball.sh`.

## Native features and architecture

`MainTab` in `ios/Hub Ball/Hub Ball/AppTabView.swift` defines Home, Game Recaps,
Standings, Schedule, Newspapers, X Posts, Players, Pitching, Leaders and Stories.
Team capabilities control available pages. Team selection, onboarding, settings and
saved page ordering are implemented in the native app.

League-wide features include the playoff bracket, postseason history, news and
scorecards, plus the story library. Story playback includes the Boston Game 108
story, the MLB 300-hitter story and validated trajectory stories. The home-run chase
has a Debug inspection entry point. Build 121 also bundles three private October 9
story previews and the private October 10 “Separated by One” launch story; these are separate from the shared remote catalog. Build 125 makes Postseason the initial underlying page, checks for an eligible update first (two-second maximum launch gate), and starts the story after Dismiss or a quiet failed/disabled check. Launch-only completion returns to Postseason after six foreground seconds of final payoff (fifteen for accessibility text/VoiceOver), with replay resetting the hold and manual library navigation preserved. It keeps whole-integer run-count presentation and the optional broad-release notice to “New version of Hub Ball,” with Dismiss and Open TestFlight to update. Its three-file server bootstrap is deployed; the shared manifest remains disabled (see [update notice](docs/testflight-update-notice.md)). Its launch chart autoplays once per process after onboarding; see [private release notes](docs/stories/separated-private-release.md). See
[docs/stories/private-october9-preview.md](docs/stories/private-october9-preview.md).

`TeamSession` owns the selected team's stores and preserves them across tab changes.
`AppModel` owns league-wide stores, player/scorecard reuse and lazy audio state.
`RefreshScheduler` manages visibility-based polling, with 20-second intervals for
live games and 60 seconds otherwise. It pauses in the background and refreshes on
foreground when the last success is more than 30 seconds old. Views report visibility
instead of starting polling loops.

Networking uses injectable `APIClient` and `Endpoint`, typed `APIError`, shared HTTP
caching and endpoint logging. Force refreshes bypass HTTP and game caches.
Independent sections retain their last good data after another section fails.
Persistent feed snapshots use bounded Caches-directory files.

The native app uses Swift 6, SwiftUI, Observation, Foundation and AVFoundation.
UI and observable stores stay on MainActor. Parsing/model types are explicitly
`nonisolated` and `Sendable`; CPU-heavy asynchronous work runs off MainActor.
Audio playback requires the user's Play gesture.

## Backend and data

`HUB_API_ORIGIN` is embedded in Info.plist from Xcode build settings. Debug and Release
use `https://api.autumnlane.io`, with `red-sox.netlify.app` retained as the fallback
and for older installed binaries. `AppBackend` uses `/data/<team>/...` in Debug and
`/api/data/<team>/...` in Release; Boston builds still request root paths, which the
`app-data.mjs` gateway serves from `data/redsox/`. Debug fixtures
override function routes with `HUB_API_ROOT` and static feeds with `HUB_DATA_ROOT`.

| Function | Route and responsibility |
|---|---|
| `app-data.mjs` | `/api/data/*` and `/data/*`: allowlisted generated feeds and validated story documents |
| `mlb-data.mjs` | `/api/mlb/*`: team-aware schedule, game, standings and related MLB projections |
| `postseason.mjs` | `/api/postseason`: postseason bracket and game state |
| `hr-chase.mjs` | `/api/hr-chase`: home-run chase data |
| `x-posts.mjs` | `/api/x-posts`: team-specific social feeds |
| `x-discovery.mjs` | `/api/x-discovery`: capped discovery with durable daily reservations |

`netlify/functions/team-registry.mjs` shares team configuration;
`netlify/lib/game-narrative.mjs` generates game narratives. Backend dependencies are
limited to the approved `@netlify/blobs` package; install them with `npm ci`.
X discovery reserves every paid call using strongly consistent Blobs before making
the request, consumes failed reservations and fails closed on storage failure.
Never make paid X calls during testing.

Python fetch scripts use the standard library and write generated `data/*.json`.
GitHub Actions workflows in `.github/workflows/` refresh team data, newspapers,
social feeds, leaderboards and postseason history on their configured schedules;
separate checks validate story payloads. Every team refreshes through the shared
registry fetchers: `scripts/fetch_team_data.py` (schedule, recap, standings,
pitching), `scripts/fetch_team_leaders.py` and `scripts/fetch_team_news.py`, run by
the `refresh-mlb-team-*.yml` workflows. A news source is fetched through Bing News
unless its registry entry has an `adapter`, which reads the publisher's page or feed
directly (parsers in `scripts/news_adapters.py`); an adapter's `source_name` is the
masthead the app shows. Boston's only own scripts are `fetch_seasons.py` (Four Roads /
Game 108 story data at the data root) and `fetch_x_posts.py` (its curated X list,
written to `data/redsox/`). Do not add
team-named fetch scripts or workflows; `scripts/test_no_team_specific_fetchers.py`
enforces this. Pitching publication has season, pacing and freeze controls described
in [docs/pitching-refresh.md](docs/pitching-refresh.md).

`config/mlb-teams.json` is the source for the 30-team registry. After changing it,
run `python3 scripts/generate_team_registry.py`; do not hand-edit generated registries
or feeds. Newspaper headlines and descriptions retain their source wording.

## Website and deployment

The website uses plain ES modules and canvas, self-hosted fonts and no frontend
dependencies or bundler. `src/chart.js` and `src/audio.js` are shared story engines.
`bash scripts/build_site.sh` assembles `_site/`; Netlify publishes that directory and
auto-deploys from `main`. A push or merged PR to `main` can therefore ship production
changes. `_site/` and `dist/` are generated and must not be committed.

The project atlas is generated from tracked source by `scripts/build_atlas.py` into
`docs/atlas/hub-ball-atlas.html` and published at `/atlas/`. Rebuild it after structural
changes and run `python3 scripts/test_build_atlas.py` to validate its graph.

Test browser code over HTTP. `file://` cannot support its module imports and feed
requests. Four Roads remains Boston-only. Its fetcher verifies the 57–51 record after
108 games across all four seasons; run `python3 scripts/story_facts.py` after refreshing
season data and correct copy when facts change. `stories/war-room/` is an unlisted
mockup with frozen WAR values and invented movement deltas.

## Verification

Open `ios/Hub Ball/Hub Ball.xcodeproj`, scheme **Hub Ball**. The app target is
**Hub Ball** and the native Swift Testing target is **HubBallTests**.

```bash
xcodebuild -project 'ios/Hub Ball/Hub Ball.xcodeproj' -scheme 'Hub Ball' \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
python3 scripts/test_hub_ball.py
node scripts/test_mlb_data.mjs
node scripts/test_app_data.mjs
node scripts/test_postseason.mjs
node scripts/test_x_posts.mjs
node scripts/test_x_discovery.mjs
node scripts/test_hr_chase_function.mjs
node scripts/test_story_gateway.mjs
```

The native runner builds the real targets, starts an isolated HTTP fixture and sets
`HUB_UNIT_TESTS` to suppress normal app network loads. It accepts `--device` and
`--suite` for targeted runs. Existing shell wrappers delegate to it. UI checks use
`scripts/test_large_text_ui.sh`; generated projects and evidence stay under `dist/`.
`scripts/ui_test_proxy.py` blocks paid discovery and forwards only supported routes.

For web regression checks, build the site, serve `_site/` with
`python3 -m http.server 8765 --directory _site`, then run
`node scripts/test_schedule.mjs` and
`node --experimental-vm-modules scripts/test_recent_game.mjs`.
Browser interaction must be verified separately from compilation or Node tests.
