# Product map and release policy

Hub Ball is the only active app identity. Use the names below consistently in
code, documentation, App Store Connect, TestFlight, release notes, and conversation.

| Canonical name | Status | Bundle ID | Working source |
|---|---|---|---|
| **Hub Ball** | Active product | `com.sfrancoe.HubBall` | `main` → `ios/Hub Ball/` |
| **Boston Baseball Hub** | Retired (removed from App Store Connect, Oct 12, 2026) | `com.sfrancoe.Red-Sox-Records` | Git history only |

## Hub Ball

Hub Ball is the current multi-team app. All feature development, TestFlight builds,
App Store metadata, screenshots, device installations, and release work belong here.
Team names describe content selected inside Hub Ball; they do not identify separate
applications.

The `main` branch is the sole release and device-installation source. The declared
release is stored in `config/hub-ball-release.json`. Update that manifest and both Xcode
build configurations together whenever the build changes. Run
`python3 scripts/check_hub_ball_release.py` before packaging, and install through
`scripts/install_hub_ball.sh` instead of invoking `xcodebuild` from an arbitrary
worktree.

## Boston Baseball Hub

Boston Baseball Hub was the original Boston-only app, bundle ID
`com.sfrancoe.Red-Sox-Records`. It never shipped to the App Store and is fully
retired: the App Store Connect record was removed on October 12, 2026, and it
receives no further builds or fixes. Its multi-team successor is Hub Ball.

Its source exists only in Git history, starting at `d1dec8b2b Add native Red Sox
Records iOS app`; the `codex/archive-pre-consolidation-20260908` branch preserves
the pre-consolidation workspace.

Apple does not allow the bundle ID `com.sfrancoe.Red-Sox-Records` to be reused or
deleted, so leave its App ID in Certificates, Identifiers & Profiles as is.

## Retired standalone Yankees app

The former `NY Baseball Hub` / `Yankees Hub` iOS project is retired. Yankees data,
fetchers, tests, and API routing remain because the Yankees are supported within Hub
Ball.

Complete these account-level steps manually in App Store Connect and Apple Developer:

1. ~~Rename the old Boston app record to **Boston Baseball Hub**.~~ Done; the record
   was later removed entirely (Oct 12, 2026).
2. Confirm `com.sfrancoe.HubBall` is the only record named **Hub Ball**.
3. Retire the standalone Yankees record and obsolete provisioning assets when Apple
   permits it; do not remove Yankees team support from Hub Ball.
4. Expire obsolete beta builds and label remaining groups with canonical product names.

