#!/usr/bin/env bash
# Netlify exits without building when this command returns 0. Return 1 whenever
# the comparison is uncertain or a deployed file changed.
set -u

cached_ref=${CACHED_COMMIT_REF:-}
commit_ref=${COMMIT_REF:-}

build() {
  printf 'Netlify build required: %s\n' "$1"
  exit 1
}

if [[ -z "$cached_ref" || -z "$commit_ref" ]]; then
  build "missing CACHED_COMMIT_REF or COMMIT_REF"
fi

if ! git rev-parse --verify --quiet "${cached_ref}^{commit}" >/dev/null; then
  build "cached commit is unavailable or invalid"
fi

if ! git rev-parse --verify --quiet "${commit_ref}^{commit}" >/dev/null; then
  build "target commit is unavailable or invalid"
fi

# Netlify sets CACHED_COMMIT_REF to COMMIT_REF when a build runs without cache
# (first build, cleared cache, or a renamed repository), so there is no deployed
# commit to compare against.
if [[ "$(git rev-parse "${cached_ref}^{commit}")" == "$(git rev-parse "${commit_ref}^{commit}")" ]]; then
  build "no previously deployed commit to compare against"
fi

changed_paths=$(mktemp)
trap 'rm -f "$changed_paths"' EXIT
# Treat renames as a deletion plus an addition so both the old and new paths
# are classified. Otherwise a deployed file moved into an ignored directory
# can leave its obsolete deployed copy live.
if ! git diff --no-renames --name-only --diff-filter=ACDMRTUXB "$cached_ref" "$commit_ref" -- >"$changed_paths"; then
  build "Git could not compare the deployed and target commits"
fi

if [[ ! -s "$changed_paths" ]]; then
  printf 'Netlify build skipped: no deployed files changed\n'
  exit 0
fi

while IFS= read -r path; do
  case "$path" in
    # The generated atlas is published at /atlas/, unlike the rest of docs/.
    docs/atlas/hub-ball-atlas.html)
      build "$path changed"
      ;;
    # These files are consumed from GitHub at runtime or are not part of the
    # Netlify release. A commit containing only these paths can safely skip.
    data/*|ios/*|app-store/*|docs/*|.github/*|README.md|AGENTS.md|CLAUDE.md|PROJECT_HANDOFF.md)
      ;;
    scripts/*)
      case "$path" in
        scripts/build_site.sh|scripts/netlify_ignore.sh|scripts/generate_team_registry.py)
          build "$path changed"
          ;;
      esac
      ;;
    config/mlb-teams.json)
      build "$path changed"
      ;;
    *)
      # Public pages/assets, Netlify functions/config, and future unclassified
      # paths build by default so a new dependency cannot be skipped silently.
      build "$path changed"
      ;;
  esac
done <"$changed_paths"

printf 'Netlify build skipped: only generated data, native app, docs, or automation files changed\n'
exit 0
