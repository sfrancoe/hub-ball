# Hosted Hub Ball Lab X refresh

This is an explicitly packaged, credential-free runtime for the four-sport Lab.
It is isolated from the production app and production refresh scripts.
Source: scripts/nba_x and the reviewed registries in Scott's Lab checkout.
manifest.json records every packaged source file and SHA-256.

The workflow on main runs at minute 37 of odd UTC hours, year-round, using a
standard GitHub-hosted Ubuntu runner. It writes only Lab feeds/rosters and
data/lab-x-status.json on lab-data/nba-x. The app's existing URLs do not change.
Missing/changed and oldest feeds go first. HTTP 429 stops the run without retry;
completed snapshots publish and the rest retain their last-good data. The audit
fails if a feed is invalid, empty, missing or older than 12 hours. The two-hour
schedule is subject to GitHub queue delays and X quotas, not a freshness guarantee.

BALLDONTLIE_API_KEY is an encrypted secret in the lab-x-refresh environment,
restricted to main. The job uses the short-lived GITHUB_TOKEN to publish to its
own repository; no personal GitHub token or X API credential is required.

The default manual dispatch verifies all 124 cached feeds, BDL access and data
publication without requesting X. Uncheck verify_only only for an intentionally
authorized normal run after any upstream cooldown. Normal scheduled runs refresh.
The initial cutover guard prevents an early retry before 2026-11-11 21:34 UTC.

To update this runtime, run scripts/package_lab_x_runtime.py against this
directory from the Lab source checkout, review manifest.json and all changes,
run the packaged tests, then merge only the hosting files. Do not merge the Lab
app branch to main. Use [skip netlify] in the PR title and merge commit message.

Tests: python3 -m unittest discover -s .github/lab-x/scripts/nba_x -p 'test_*.py'
Audit: python3 .github/lab-x/scripts/nba_x/audit.py --published --output /tmp/lab-x-audit.json

Rollback: disable the hosted workflow first; only then re-enable the previous
Mac LaunchAgent. Never run both scheduled writers at once.
