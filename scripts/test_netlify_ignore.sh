#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email test@example.com
git -C "$FIXTURE" config user.name "Netlify ignore test"
git -C "$FIXTURE" config diff.renames true
mkdir -p "$FIXTURE/scripts"
cp "$ROOT/scripts/netlify_ignore.sh" "$FIXTURE/scripts/netlify_ignore.sh"
chmod +x "$FIXTURE/scripts/netlify_ignore.sh"
git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm base
BASE=$(git -C "$FIXTURE" rev-parse HEAD)

commit_file() {
  local path=$1
  mkdir -p "$FIXTURE/$(dirname "$path")"
  printf '%s\n' "$path $(git -C "$FIXTURE" rev-list --count HEAD)" >"$FIXTURE/$path"
  git -C "$FIXTURE" add "$path"
  git -C "$FIXTURE" commit -qm "$path"
  git -C "$FIXTURE" rev-parse HEAD
}

expect_result() {
  local expected=$1
  local cached=$2
  local commit=$3
  local label=$4
  local actual
  set +e
  (cd "$FIXTURE" && CACHED_COMMIT_REF="$cached" COMMIT_REF="$commit" bash scripts/netlify_ignore.sh) >/dev/null
  actual=$?
  set -e
  if [[ "$actual" -ne "$expected" ]]; then
    printf 'FAIL: %s (expected %s, got %s)\n' "$label" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'ok: %s\n' "$label"
}

DATA=$(commit_file data/team/standings.json)
expect_result 0 "$BASE" "$DATA" "data-only skips"
mkdir -p "$FIXTURE/data/archive"
git -C "$FIXTURE" mv data/team/standings.json data/archive/standings.json
git -C "$FIXTURE" commit -qm "rename generated data"
DATA_RENAMED=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 0 "$DATA" "$DATA_RENAMED" "data rename skips"
git -C "$FIXTURE" rm -q data/archive/standings.json
git -C "$FIXTURE" commit -qm "delete generated data"
DATA_DELETED=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 0 "$DATA_RENAMED" "$DATA_DELETED" "data deletion skips"
IOS=$(commit_file ios/Hub/App.swift)
expect_result 0 "$DATA_DELETED" "$IOS" "iOS-only skips"
DOCS=$(commit_file docs/backend.md)
expect_result 0 "$IOS" "$DOCS" "docs-only skips"
ATLAS_TEMPLATE=$(commit_file docs/atlas/template.html)
expect_result 0 "$DOCS" "$ATLAS_TEMPLATE" "atlas template skips"
ATLAS=$(commit_file docs/atlas/hub-ball-atlas.html)
expect_result 1 "$ATLAS_TEMPLATE" "$ATLAS" "published atlas builds"
BACKEND=$(commit_file netlify/functions/app-data.mjs)
expect_result 1 "$ATLAS" "$BACKEND" "backend builds"
REGISTRY=$(commit_file netlify/functions/team-registry.mjs)
expect_result 1 "$BACKEND" "$REGISTRY" "generated registry builds"
REGISTRY_SOURCE=$(commit_file config/mlb-teams.json)
expect_result 1 "$REGISTRY" "$REGISTRY_SOURCE" "registry source builds"
BUILD_SCRIPT=$(commit_file scripts/build_site.sh)
expect_result 1 "$REGISTRY_SOURCE" "$BUILD_SCRIPT" "build script builds"
PUBLIC=$(commit_file privacy/index.html)
expect_result 1 "$BUILD_SCRIPT" "$PUBLIC" "retained public asset builds"

MIXED_BASE=$(git -C "$FIXTURE" rev-parse HEAD)
MIXED_DATA=$(commit_file data/team/schedule.json)
MIXED_PUBLIC=$(commit_file src/site.css)
expect_result 1 "$MIXED_BASE" "$MIXED_PUBLIC" "mixed changes build"
expect_result 1 "$PUBLIC" "$MIXED_PUBLIC" "multi-commit comparison finds later deployed changes"

git -C "$FIXTURE" rm -q privacy/index.html
git -C "$FIXTURE" commit -qm "delete public file"
DELETED=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 1 "$MIXED_PUBLIC" "$DELETED" "public deletion builds"

mkdir -p "$FIXTURE/assets"
git -C "$FIXTURE" mv src/site.css assets/site.css
git -C "$FIXTURE" commit -qm "rename public file"
RENAMED=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 1 "$DELETED" "$RENAMED" "public rename builds"

mkdir -p "$FIXTURE/docs"
git -C "$FIXTURE" mv assets/site.css docs/removed.js
git -C "$FIXTURE" commit -qm "move public asset into docs"
PUBLIC_TO_DOCS=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 1 "$RENAMED" "$PUBLIC_TO_DOCS" "public asset moved into docs builds"

FUNCTION=$(commit_file netlify/functions/retired.mjs)
git -C "$FIXTURE" mv netlify/functions/retired.mjs docs/retired.mjs
git -C "$FIXTURE" commit -qm "move function into docs"
FUNCTION_TO_DOCS=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 1 "$FUNCTION" "$FUNCTION_TO_DOCS" "function moved into docs builds"

IGNORED=$(commit_file docs/promoted.js)
mkdir -p "$FIXTURE/src"
git -C "$FIXTURE" mv docs/promoted.js src/promoted.js
git -C "$FIXTURE" commit -qm "move docs file into public source"
IGNORED_TO_PUBLIC=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 1 "$IGNORED" "$IGNORED_TO_PUBLIC" "ignored file moved into public source builds"

IGNORED_MOVE=$(commit_file data/team/archive.json)
mkdir -p "$FIXTURE/docs/archive"
git -C "$FIXTURE" mv data/team/archive.json docs/archive/archive.json
git -C "$FIXTURE" commit -qm "move file between ignored directories"
IGNORED_TO_IGNORED=$(git -C "$FIXTURE" rev-parse HEAD)
expect_result 0 "$IGNORED_MOVE" "$IGNORED_TO_IGNORED" "move within ignored directories skips"

expect_result 1 missing "$IGNORED_TO_IGNORED" "missing cached ref builds"
expect_result 1 "$IGNORED_TO_IGNORED" invalid "invalid target ref builds"
expect_result 1 "" "$IGNORED_TO_IGNORED" "empty cached ref builds"
expect_result 1 "$IGNORED_TO_IGNORED" "$IGNORED_TO_IGNORED" "cache-less build with equal refs builds"

printf 'netlify ignore checks passed\n'
