# Hub Ball

Hub Ball is a multi-team iOS baseball companion backed by this dependency-free static
site and its visual stories. The current site remains centered on Boston Red Sox box
scores and uses plain ES modules and `<canvas>`, with game logs pulled from the free
[MLB Stats API](https://statsapi.mlb.com/).

The native iOS app includes an App Store readiness check. Run
`python3 scripts/app_store_preflight.py` before TestFlight; add `--network` to
verify live non-metered feeds. See `app-store/README.md` for the remaining human
review items.

## Product map

Hub Ball is the only active app identity:

| Name | Status | Bundle ID | Source |
|---|---|---|---|
| **Hub Ball** | Active; all new work goes here | `com.sfrancoe.HubBall` | `main` → `ios/Hub Ball/` |
| **Boston Baseball Hub** | Retired Oct 12, 2026 (App Store Connect record removed) | `com.sfrancoe.Red-Sox-Records` | Git history only |

The New York Yankees are a supported team inside Hub Ball, not a separate app.
The former standalone Yankees iOS project has been retired. See
[`docs/PRODUCTS.md`](docs/PRODUCTS.md) for naming and retirement rules.

`main` is the only installation and release source. To install the declared current
build on a paired device, use:

```bash
bash scripts/install_hub_ball.sh --device <device-identifier>
```

The installer refuses a dirty source tree, a non-`main` branch, a manifest mismatch,
or a lower build than another worktree.

Open `ios/Hub Ball/Hub Ball.xcodeproj` in Xcode, or run an unsigned simulator build:

```bash
xcodebuild -project "ios/Hub Ball/Hub Ball.xcodeproj" -scheme "Hub Ball" \
  -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build
```

## Stories

| Story | What it shows |
|---|---|
| **Four Roads, One Record** (`stories/four-roads/`) | Four straight seasons (2023-26) reached the identical record after 108 games, then split toward four completely different endings. |

The **Newspaper Headlines** tab tracks Red Sox headlines and short descriptions
from The Boston Globe and Boston Herald in parallel desktop columns and mobile
tabs. Every item links to the original article.

The **Standings** tab shows all three American League divisions and the Wild
Card race, with Boston highlighted throughout.

## Run it locally

ES modules and `fetch()` both need a real HTTP origin, so `file://` will not work:

```bash
bash scripts/build_site.sh
cd _site && python3 -m http.server 8765
# open http://localhost:8765
```

## Refresh the data

```bash
python3 scripts/fetch_team_data.py --team redsox   # schedule, recap, standings, pitching
python3 scripts/fetch_team_leaders.py --team redsox # season paths and leaders
python3 scripts/fetch_team_news.py --team redsox    # newspaper headlines
python3 scripts/fetch_seasons.py                    # Four Roads / Game 108 story data
```

Every team's feeds are generated into `data/<team>/` by the shared registry
fetchers; only the Four Roads story data (`data/seasons.json`, `data/meta.json`)
sits at the root. Standard library only — no dependencies to install. GitHub
Actions refreshes on the `refresh-mlb-team-*.yml` schedules and commits only when
content changes; Netlify redeploys on that commit.

## Deploy

Netlify builds with `bash scripts/build_site.sh` and publishes `_site/`, which
contains only the public files — `scripts/`, docs, and CI config stay out of the
served site.

## Layout

```
index.html              landing page
src/                    shared chart + audio engine, styles
stories/<slug>/         one folder per story
data/                   generated JSON — do not hand-edit
assets/fonts/           self-hosted woff2
scripts/                fetch, build, package
```

## Project atlas

[`docs/atlas/hub-ball-atlas.html`](docs/atlas/hub-ball-atlas.html) is an interactive 3D
map of this repository. Open it in a browser (it works offline from `file://`): spheres
are sized by lines of code, open into groups and files when clicked, and are linked by
the imports, API calls, data writes, workflow runs and tests between them. The site
serves it at https://red-sox.netlify.app/atlas/, linked from the **Atlas** tab. Rebuild it after structural changes:

```bash
python3 scripts/build_atlas.py        # rewrite docs/atlas/hub-ball-atlas.html
python3 scripts/test_build_atlas.py   # validate the graph
```

The **Refresh project atlas** workflow rebuilds it every Monday and can be run by hand
from the Actions tab. Edit the viewer in `docs/atlas/template.html`; connections the scanners cannot see
(fetcher outputs, app endpoints) are listed in `scripts/build_atlas.py`.

## A note on accuracy

Every game in `data/` comes from the MLB Stats API. The fetch script also
re-checks the claim the first story is built on — the same 57-51 record after 108
games, four years running — and records the result in `data/meta.json` as
`premise_holds`. If that ever goes false, the story text needs rewriting rather
than the check being ignored.

Above the Forecast's pitching refresh is pinned to an explicitly configured season,
with weekly October updates and a winter freeze. See
[the pitching refresh controls](docs/pitching-refresh.md) before any manual refresh
or season transition.
