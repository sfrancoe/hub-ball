#!/bin/bash
# Operate only on a dedicated clean checkout of lab-data/nba-x.
set -u
LAB_REPO="${HUB_NBA_LAB_REPO:-/Users/sfrancoe/Projects/Hub Ball NBA Prototype}"
DATA_REPO="${HUB_NBA_DATA_REPO:-$HOME/HubBall-NBA-X-Data}"
if [ ! -d "$DATA_REPO/.git" ] && [ ! -f "$DATA_REPO/.git" ]; then
  echo "Missing dedicated data checkout: $DATA_REPO" >&2; exit 1
fi
if [ "$(git -C "$DATA_REPO" branch --show-current)" != lab-data/nba-x ] || [ -n "$(git -C "$DATA_REPO" status --porcelain)" ]; then
  echo "Data checkout must be clean and on lab-data/nba-x" >&2; exit 1
fi
git -C "$DATA_REPO" pull --ff-only || exit 1
export HUB_LAB_ALLOW_UNOFFICIAL_X=1
# One queue across all configured teams prevents an earlier league from using
# every run's quota. Missing/changed feeds go first, then the oldest snapshots.
# All four leagues remain eligible year-round, including offseason news.
python3 "$LAB_REPO/scripts/nba_x/build.py" --sport all --all --data-dir "$DATA_REPO/data"
fetch_status=$?
git -C "$DATA_REPO" add -- data/nba/ || exit 1
if [ -d "$DATA_REPO/data/mlb" ]; then
  git -C "$DATA_REPO" add -- data/mlb/ || exit 1
fi
if [ -d "$DATA_REPO/data/nfl" ]; then
  git -C "$DATA_REPO" add -- data/nfl/ || exit 1
fi
if [ -d "$DATA_REPO/data/nhl" ]; then
  git -C "$DATA_REPO" add -- data/nhl/ || exit 1
fi
if ! git -C "$DATA_REPO" diff --cached --quiet; then
  git -C "$DATA_REPO" commit -m 'Refresh Lab X snapshots' || exit 1
fi
# Retry an earlier failed push even when this refresh produced no new changes.
if [ "$(git -C "$DATA_REPO" rev-list --count '@{upstream}..HEAD')" -gt 0 ]; then
  git -C "$DATA_REPO" push origin lab-data/nba-x || exit 1
fi
exit "$fetch_status"
