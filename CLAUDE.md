# CLAUDE.md — Hub Ball

## Project Overview

Hub Ball is a 30-team native SwiftUI iPhone/iPad app with a Netlify backend and
an accompanying collection of JavaScript baseball stories. Read **AGENTS.md** first:
it is the shared source for current native architecture, concurrency, build/test
commands, dependency policy and canonical release rules. The sections below retain
additional context for the original web stories.

[`PROJECT_HANDOFF.md`](PROJECT_HANDOFF.md) describes the current native features,
backend routes, data refreshes and verification workflow. Use the active app
navigation and current source as the feature inventory; preserve source wording in
news feeds.

**Primary developer:** Scott Francoe
**GitHub repo:** https://github.com/sfrancoe/hub-ball (public)
**Hosting:** Netlify (auto-deploys from `main`)
**Local path:** `/Users/sfrancoe/Projects/Hub Ball` (the Red-Sox checkout is archived)

---

## Tech Stack

- **Native app:** Swift 6 + SwiftUI, app target `Hub Ball`, test target `HubBallTests`.
- **Backend:** Netlify Functions with approved backend-only `@netlify/blobs`.
- **Web stories:** plain ES modules + `<canvas>`, no framework or bundler.
- **Data:** MLB Stats API (`statsapi.mlb.com`) — free, no key, no rate limit worth worrying about.
- **Fetch script:** Python 3, **standard library only** (so CI needs no `pip install`).
- **Hosting:** Netlify, publishing `_site/`.
- **Refresh:** GitHub Actions cron, daily at 11:00 UTC.

Native/web code remains dependency-free. `npm ci` installs the approved backend
package. Additional dependencies require approval.

---

## Project Structure

```
hub-ball/
├── index.html                  # landing page — one card per story
├── src/
│   ├── chart.js                # SHARED engine: canvas, animation, scrub, controls
│   ├── audio.js                # SHARED Web Audio engine (createAudio factory)
│   ├── styles.css              # story-page styles + @font-face
│   └── home.css                # landing-page styles
├── stories/
│   └── four-roads/
│       ├── index.html          # page shell + markup
│       └── story.js            # CONFIG (colors, arc labels, beats) + wiring
├── data/
│   ├── seasons.json            # GENERATED — do not hand-edit
│   └── meta.json               # GENERATED — generated_at, source, premise check
├── assets/fonts/               # Anton + Oswald woff2 (self-hosted, no CDN)
├── scripts/
│   ├── fetch_seasons.py        # MLB API → data/*.json
│   ├── build_site.sh           # assemble _site/ for Netlify
│   └── build_single_file.py    # → dist/*.html, one portable file for sharing
├── netlify.toml
└── .github/workflows/refresh-data.yml
```

---

## Development

```bash
# Serve locally — ES modules need http://, NOT file://
bash scripts/build_site.sh && (cd _site && python3 -m http.server 8765)
# → http://localhost:8765

# Refresh the data by hand
python3 scripts/fetch_seasons.py            # all default seasons
python3 scripts/fetch_seasons.py 2026       # just one

# Portable single-file build (for sharing / Claude artifacts)
python3 scripts/build_single_file.py
```

> **`file://` will not work.** ES module imports and `fetch()` of the JSON both need a
> real HTTP origin. Always go through the local server.

---

## Data Model

`data/seasons.json` is keyed by year. Each season:

| field | meaning |
|---|---|
| `diff` | array, games above/below .500 after each game |
| `seq` | string of `W`/`L`, one char per game |
| `record` | `"W-L"` at the last completed game |
| `end_game` | number of completed games (162 = final) |
| `in_progress` | `true` while the season is unfinished |
| `checkpoint_record` | `"W-L"` after game 108 |

`diff` and `seq` must always agree and be the same length — `fetch_seasons.py` builds
both from the same walk, so don't edit either by hand.

---

## The Premise Check

The whole first story rests on one claim: **57-51 after 108 games, four seasons running.**
`fetch_seasons.py` re-verifies this on every run and prints `CONFIRMED` or
`DOES NOT HOLD` in the CI log, and records `premise_holds` in `meta.json`.

**If that ever flips to false, the story copy is wrong and must be rewritten.** Don't
paper over it. The graphic makes a factual claim; the check is what keeps it honest.

---

## Adding a Story

1. `mkdir stories/<slug>/` with `index.html` + `story.js`
2. `story.js` imports `initStory` from `../../src/chart.js` and supplies `CONFIG`
3. Add a `<li>` card to the root `index.html`
4. If it needs new data, extend `scripts/fetch_seasons.py` — never hand-write data files

The engine in `src/` is shared. Prefer extending it with options over forking it.

---

## Conventions

### JavaScript
- 2-space indent, ES modules, no build step
- `camelCase` functions/vars, `UPPER_CASE` for config constants
- The chart engine keeps its state in module/function scope — one chart per page
- No frontend dependencies or CDN scripts (the CSP blocks them). Backend dependencies
  are limited to the approved Blobs package.

### Python
- 4-space indent, type hints on signatures, stdlib only
- Network calls retry with backoff and fail loudly — a silent bad fetch is worse than a red build

---

## Hard Constraints

1. **Never hand-edit `data/*.json`.** They are generated; the next CI run overwrites them.
2. **No paid APIs or services** without asking Scott first.
3. **Do not add a frontend build toolchain or additional dependencies without approval.**
   The existing backend Blobs dependency is the sole approved package exception.
4. **Accuracy is the product.** If real data contradicts a story's copy, fix the copy.
5. Do not commit `_site/` or `dist/` — both are generated and gitignored.

---

## Notes for Claude

- Audio cannot start without a user gesture on iOS. The big center Play button exists
  to be both the obvious call-to-action and that gesture — don't "helpfully" add autoplay.
- The play overlay primes WebAudio with a silent buffer inside the tap handler. That
  line looks pointless; it is what makes sound work on iPhone. Leave it.
- `initStory({DATA, CONFIG, YEARS})` takes a destructured parameter, so a `"use strict"`
  directive inside it is a syntax error. ES modules are strict already.
- Test in a real browser before claiming something works. `python3 -m http.server` plus
  Playwright catches the module/CORS/canvas failures that static reading misses.
- Mobile first here, unlike em-dashboard — these get opened on phones and texted around.

## Native architecture and verification

The current native build and test commands are in [AGENTS.md](AGENTS.md#native-app-and-backend-development).
`APIClient` owns networking/decoding; `AppBackend` resolves the configured API origin.
`TeamSession` preserves per-team stores across tabs, while `AppModel` owns league-wide
state. `RefreshScheduler` owns visible-screen polling; views do not poll. Swift 6 keeps
UI/stores on the default MainActor and Sendable decoding/model work off it. Run
`python3 scripts/test_hub_ball.py` to exercise the real Swift Testing target with local
fixtures. The shell harnesses delegate to this runner. Do not add standalone `swiftc`
file lists. Preserve explicit team arguments and regenerate the team registry from
`config/mlb-teams.json`.

Only canonical `main` is a release source. Before release/device installation, follow
AGENTS.md rule 11 and run `python3 scripts/check_hub_ball_release.py`; use the guarded
installation script. Work on a feature branch is not a released build.
