# AGENTS.md — Hub Ball

Instructions for AI coding agents working in this repo. Read this before changing
anything. If you are Claude Code, `CLAUDE.md` covers the same ground in more detail.

---

## What this project is

Hub Ball is a native SwiftUI iPhone/iPad app covering all 30 MLB teams, backed by
Netlify Functions and generated JSON feeds. This repository also hosts the original
Boston baseball stories built with plain JavaScript and canvas. Accuracy and clear,
mobile-first presentation matter across both products.

The canonical checkout is `/Users/sfrancoe/Projects/Hub Ball`. The old
`/Users/sfrancoe/Projects/Red-Sox` checkout is archived and is not a release source.

Hosting is Netlify, auto-deploying from `main`. **A merged PR ships to production.**

For the current feature inventory, backend routes and handoff, read
[`PROJECT_HANDOFF.md`](PROJECT_HANDOFF.md). Keep that inventory aligned with
`MainTab` and the implemented full-screen features; deleted experiments are not
supported product surfaces. News headlines remain faithful to their sources.

---

## Stack

Native app: Swift 6, SwiftUI, Observation, Foundation and AVFoundation. Backend:
Netlify Functions (ES modules), with the approved `@netlify/blobs` dependency for X
call reservations and last-good feeds. Run `npm ci` for backend development. Web
stories remain plain ES modules and canvas with no framework or bundler; Python
fetch scripts use the standard library.

```
ios/Hub Ball/Hub Ball/       native app sources
ios/Hub Ball/HubBallTests/   native Swift Testing target and bundled fixtures
netlify/functions/          API routes and upstream adapters
netlify/lib/                team-aware game narrative generation
config/mlb-teams.json        source of the generated 30-team registry
index.html                  landing page — one card per story
src/chart.js                SHARED engine: canvas, animation, scrub, controls
src/audio.js                SHARED Web Audio engine (createAudio factory)
src/styles.css              story-page styles + @font-face
src/home.css                landing-page styles
stories/four-roads/         index.html + story.js (CONFIG: colors, labels, beats)
stories/war-room/           unlisted DESIGN MOCKUP — see rule 7
data/seasons.json           GENERATED — per-game arrays, keyed by year
data/meta.json              GENERATED — generated_at, source, premise check
scripts/fetch_seasons.py    MLB API + Baseball Reference → data/*.json
scripts/story_facts.py      prints real milestones so story copy can be fact-checked
scripts/build_site.sh       assembles _site/ for Netlify
scripts/build_single_file.py → dist/*.html, one portable file for sharing
assets/fonts/               Anton + Oswald woff2, self-hosted
```

Data flows one way: **Python writes `data/*.json` → the browser fetches it at runtime.**
`story.js` holds presentation config and wires it to `initStory` from `src/chart.js`.

---

## Rules

These are the mistakes agents actually make here. They are not style preferences.

**1. Do not add dependencies or a frontend build toolchain without approval.** The
approved exception is backend-only `@netlify/blobs`, locked in `package-lock.json`.
Do not add webpack, Vite, React, charting packages, CDN scripts or native packages.
The web stories' CSP blocks external scripts. Ask before introducing another package.

**2. Never hand-edit `data/seasons.json` or `data/meta.json`.** They are generated, and
the daily CI refresh overwrites them. To change data, change `scripts/fetch_seasons.py`.
`diff` and `seq` must always agree and be the same length — both are built from the same
walk, so editing one by hand desynchronizes them silently.

**3. Test over HTTP, never `file://`.** ES module imports and `fetch()` of the JSON both
require a real HTTP origin; `file://` fails with opaque CORS errors. Do not claim a
change works based on reading the code:

```bash
bash scripts/build_site.sh && (cd _site && python3 -m http.server 8765)
# → http://localhost:8765
```

If you have no browser available, say that you could not verify it rather than implying
you did.

**4. `initStory({ DATA, CONFIG, YEARS })` takes a destructured parameter.** A
`"use strict"` directive inside that function body is a **syntax error**. ES modules are
already strict. Do not add one.

**5. Leave the iOS audio unlock alone.** [`src/audio.js:199`](src/audio.js) plays a
1-sample silent buffer inside `start()`, which runs from the overlay's tap handler. It
looks like dead code. It is what makes sound work on iPhone. Likewise, do not add
autoplay — audio cannot start without a user gesture on iOS, and the big center Play
button exists to be both the call-to-action and that gesture.

**6. Accuracy is the product.** If real data contradicts a story's copy, **fix the copy**,
not the data. After any data refresh, run `python3 scripts/story_facts.py` and confirm the
narrative beats in `story.js` still match the real peaks, valleys, streaks and records.

**7. `stories/war-room/` is a mockup, not a finished story.** Its WAR values are real but
**frozen** into `story.js`, and the overnight movement deltas are **invented** so the UI
has something to show. It is unlisted on the landing page on purpose. Do not wire it up,
cite its numbers, or present it as live. Making it real means extending
`fetch_seasons.py` to emit `data/war.json` plus a dated history file.

**8. Prefer extending `src/chart.js` with options over forking it.** The engine is shared
across stories. One chart per page — it keeps state in module/function scope.

**9. Do not commit `_site/` or `dist/`.** Both are generated and gitignored.

**10. Ask before anything paid.** No paid APIs or services without checking first.

**11. `main` is the only Hub Ball release and device-installation source.** Never answer
"latest build" from the current checkout alone. Run
`python3 scripts/check_hub_ball_release.py`, which validates
`config/hub-ball-release.json`, the Xcode settings, Git cleanliness, and every registered
worktree. Install on a device only through `scripts/install_hub_ball.sh`. When bumping a
build, update both Xcode build configurations and the release manifest in the same
commit. A side branch may contain future work, but it is not a release until merged to
`main` and declared in the manifest.

---

## The premise check

The first story rests on one claim: **57-51 after 108 games, four seasons running.**
`fetch_seasons.py` re-verifies it on every run, prints `CONFIRMED` or `DOES NOT HOLD` in
the CI log, and records `premise_holds` in `meta.json`.

**If that flips to false, the story copy is wrong and must be rewritten.** Do not paper
over it, and do not adjust the checkpoint or the expected record to make it pass. The
graphic makes a factual claim; the check is what keeps it honest.

---

## Things that look wrong but are not

Before "simplifying" any of these, read the comment above them. Each cost real debugging.

- **Curve geometry is built once per resize, then truncated** (`buildSegs` +
  `splitBezier` in `src/chart.js`). Growing the line by re-fitting a spline each frame
  makes the tip wobble, because every knot's tangent depends on its neighbours. At 26
  games/sec that read as stutter. De Casteljau truncation of a fixed curve is the fix.
- **The scoreboard is memoized through a `shown{}` cache.** The render loop runs every
  frame but the text changes a few times a second; writing unconditionally caused a style
  recalc per frame.
- **The display series is smoothed, and game 108 is pinned.** `disp[108] = 6` forces the
  exact convergence point. The underlying `diff` array is untouched and stays exact.
- **Results are derived from the API's running `leagueRecord`, not a win flag.** If the
  record did not move, the game did not count. MLB marks postponed and cancelled games
  `Final` too; counting those is how you get a 167-game season.

---

## Conventions

**JavaScript** — 2-space indent, ES modules, no build step. `camelCase` for
functions/vars, `UPPER_CASE` for config constants.

**Python** — 4-space indent, type hints on signatures, stdlib only. Network calls retry
with backoff and fail loudly; a silent bad fetch is worse than a red build.

**Mobile first.** These get opened on phones and texted around.

---

## Adding a story

1. `mkdir stories/<slug>/` with `index.html` + `story.js`
2. `story.js` imports `initStory` from `../../src/chart.js` and supplies `CONFIG`
3. Add a `<li>` card to the root `index.html`
4. If it needs new data, extend `scripts/fetch_seasons.py` — never hand-write data files

## Adding a team to Hub Ball

Before installing a build that exposes a new team, publish its generated `data/<team>/`
files and Netlify function configuration to `main`, wait for the production deploy, and
verify representative production requests (including `/data/<team>/standings.json` and
`/api/x-posts?team=<team>`) return successful, team-specific payloads. A local data file
or passing local test does not make it available to a device build because the app reads
from `https://api.autumnlane.io`.

## Native app and backend development

Open `ios/Hub Ball/Hub Ball.xcodeproj`, scheme **Hub Ball**. The app target is **Hub
Ball** and the unit-test target is **HubBallTests**. A simulator build does not change
the release manifest or authorize a device installation.

```bash
xcodebuild -project 'ios/Hub Ball/Hub Ball.xcodeproj' -scheme 'Hub Ball' \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
python3 scripts/test_hub_ball.py
# Optional: --device <simulator-UUID>, --suite RecentGameStoreTests
bash scripts/test_recent_game_store.sh
bash scripts/test_schedule_store.sh
node scripts/test_mlb_data.mjs
node scripts/test_x_discovery.mjs
node scripts/test_postseason.mjs
```

The native test runner builds the real app/test targets, starts an isolated local HTTP
fixture, and runs Swift Testing in a simulator. Existing `test_*.sh` entrypoints are
thin suite wrappers. Tests belong in `HubBallTests`, use `@testable import Hub_Ball`,
and inject sessions/clients; do not reconstruct `swiftc` source-file lists. The
`HUB_UNIT_TESTS` launch environment suppresses normal app network loads. UI tests use
`scripts/test_large_text_ui.sh <simulator-UUID> <run-name> [method ...]`; its generated
project and evidence stay under ignored `dist/`.

`AppBackend` maps team data to `/data/<team>/...` in Debug and `/api/data/<team>/...`
in Release (Boston builds request root paths; `app-data.mjs` serves them from
`data/redsox/`), and functions to `/api/...?...team=...`.
`HUB_API_ORIGIN` is an Xcode build setting
embedded in Info.plist. Debug and Release use `https://api.autumnlane.io`, owned by
Scott and verified on Netlify with valid TLS and working data/API routes on 2026-10-06.
Keep `red-sox.netlify.app` available for already installed binaries and the configuration
fallback. Debug fixtures override function routes with `HUB_API_ROOT` and static
data with `HUB_DATA_ROOT`.

All store requests go through injectable `APIClient` and `Endpoint`, with typed
`APIError`, endpoint logging and shared HTTP caching. MLB feeds are projected on the
server, decoded into Sendable values, and coalesced by game ID before deriving each
team's perspective. Keep support for older unprojected feeds during rollout. Force
refreshes must bypass game and HTTP caches. Never make paid X calls in a test.

Swift 6 uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.
UI and observable stores stay on MainActor. Model/parsing types are explicitly
`nonisolated` and `Sendable`; CPU-heavy async work uses `@concurrent` or an isolated
worker actor. Cancellation is quiet, not a user-facing failure. Independent sections
retain their last good data when another section fails.

`TeamSession` owns per-team stores and survives tab switches; replace it only when
the selected team changes. `AppModel` owns league-wide stores and lazy audio state.
Views read these owners from the environment and report visibility to the scheduler.
Do not recreate stores in view initializers or add network polling loops to views.
`RefreshScheduler` uses 20 seconds for live games, 60 otherwise, pauses in background,
and refreshes on foreground only when the last success is over 30 seconds old.
Inactive transitions such as Control Center do not trigger refreshes. Story animation
uses SwiftUI timelines, independently of network polling.

Generate `HubTeam.swift` with `python3 scripts/generate_team_registry.py` after editing
`config/mlb-teams.json`; never hand-edit generated registries or feeds. Stores require
an explicit team. Backend data for every team comes from the shared registry fetchers
(`fetch_team_data.py`, `fetch_team_leaders.py`, `fetch_team_news.py`); never add
team-named `fetch_<team>_*.py` scripts or `refresh-<team>-*.yml` workflows. Every team's
feeds live in `data/<team>/`; only the Four Roads/Game 108 story data
(`data/seasons.json`, `data/meta.json`, built by `fetch_seasons.py`) sits at the root.
`legacy_root_data` now only means installed builds request that team's feeds at root
paths, which the gateway aliases. Direct publisher scraping is a per-source `adapter`
in `config/mlb-teams.json`, not a new script. Refresh workflows are started on time by
`netlify/functions/workflow-timer.mjs`; after editing a workflow's cron, regenerate its
table with `python3 scripts/generate_workflow_schedules.py`. The Four Roads/Game 108 story intentionally remains Boston-only.
Persistent feed snapshots belong in bounded Caches-directory files, not UserDefaults.
Audio preparation may run early, but playback still requires the user's Play gesture.

X discovery uses strongly consistent Netlify Blobs and immutable conditional daily
reservations before any paid request. Failed upstream calls still consume a reservation;
storage failure fails closed. Query validation and `Netlify-Vary` must match the endpoint
parameters. CDN caching alone is not a billing limit. Production upstream requests
identify as Hub Ball; personal retrieval fallback identities do not belong in shipped code.
