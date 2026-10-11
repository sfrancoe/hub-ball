# Remote featured opening — Scott-only foundation 127

Version 1.1 build 127 selects its opening from the unlisted public endpoint
`https://api.autumnlane.io/api/data/stories/featured-v1.json`. The legacy host
serves the same route. Only Scott receives this binary; the public data is not
an access-controlled service. Builds 125 and 126 ignore this pointer. Their
launch behavior and the shared Stories catalog remain unchanged.

The current selection is Cleveland's approved “Wow!” inning grid. Its payload
is byte-identical to build 126; no copy, colors, typography, chronology, or
animation changed. Older Stories remain available through their existing paths.

## Contract and launch

`FeaturedStoryStore.swift` validates schema 1, enablement, publication/date
window (at most seven days), minimum installed build, and the existing renderer
capability. An inline `StoryEntry` specifies the exact story ID, SHA-256 revision,
and minimum renderer. Its path is derived, never supplied by content. The
downloaded document is pinned for the entire presentation, so the same ID can
receive revised commentary without accidentally opening its bundled version.

Finite bundled renderers are guess/reveal, trajectory line/step/bar (including
the capability-3 sequencing), and capability-4 inning/out grid. No remote HTML,
JavaScript, formulas, arbitrary media, native bridges, or dependencies are loaded.
The approved HTTPS origins are fixed. Redirects are refused. Provenance links
are validated HTTPS and open only on a user's explicit source-link action.

The update check and featured preparation run together with two-second deadlines.
An eligible update notice appears first. Dismissal or return from its TestFlight
handoff proceeds to the prepared automatic story. Chart completion or Dismiss
returns to Postseason. Guess/reveal stories retain their explicit Dismiss control.
Late responses never reopen a finished launch, and foreground transitions never
reoffer a dismissed story. A new cold launch checks the current pointer.

One atomic cache slot in Caches/HubBall/Featured is limited to 750 KiB, including
the manifest and base64-encoded payload. Every restoration validates the pointer,
payload hash, renderer and dates. Saved content lasts at most 24 hours from fetch,
and never beyond the pointer's expiry. Valid disable, expiry or unsupported-build
decisions revoke it. A malformed response, bad hash or failed network keeps only
a compatible unexpired verified slot. No usable content means Postseason; there
is no permanent dated Cleveland fallback. Cache eviction is safe.

## Preview, publish, restore

1. Create/review a payload using the existing renderer validators. Keep original
   reporting concise; cite source URLs and retrieval dates. Use verified public
   baseball facts and original copy/graphics; do not copy article text, logos,
   broadcast clips or licensed photographs into the feed. A new rendering
   capability still requires another native build.
2. Create a schema-1 pointer with reviewed dates, minimum build, and inline entry.
   Validate/stage locally:

   ```sh
   python3 scripts/featured_story.py --manifest reviewed-featured.json \
     --payload reviewed-payload.json --output dist/featured-preview/data
   python3 scripts/featured_story.py --validate dist/featured-preview/data
   ```

3. Preview on simulator with the Debug-only `HUB_FEATURED_ROOT` override using an
   approved local HTTP fixture. Release always uses the fixed public endpoint.
4. Publish the immutable `data/stories/<id>/<sha>.json` before or atomically with
   `data/stories/featured-v1.json`. Use a scoped fast-forward commit against fresh
   production main, preserving concurrent feed refreshes. Never push the private
   native main history wholesale. Do not overwrite an existing immutable payload.
5. Verify both existing origins, no-store pointer headers, hash, schema and native
   rendering. For this private preview, do not change catalog-v1.json, Family,
   review submissions, or releases/testflight-v1.json.
6. Restore by publishing a fresh pointer to the earlier reviewed immutable
   document, within a current valid window. This is a content publication,
   not a Netlify deploy restore. Disable with enabled=false and entry=null.

`app-data.mjs` reads GitHub main at runtime, bounds pointers to 16 KiB and payloads
to 512 KiB, checks SHA paths, and gives pointers both browser and CDN `no-store`. The mutable raw-GitHub fetch
uses a server-generated freshness parameter and explicit no-cache request. The
GitHub branch origin can still propagate later than a local Git push; publishing
must wait for actual values on both hosted endpoints before announcing a change.
The live acceptance watcher allows ten minutes for upstream convergence.
The one-time route/header change deploys through existing Netlify Git CD. Subsequent
data-only pointer changes use the existing build-ignore policy and need neither a
website rebuild nor a TestFlight upload. Immutable payload routes cache for a year.

## Verification and distribution

Native: `FeaturedStoryTests`, `PostseasonLaunchTests`, `BetaUpdateTests`, story/cache
and trajectory suites. Gateway: `test_featured_gateway.mjs`, `test_story_gateway.mjs`,
`test_beta_gateway.mjs`. Python: featured pointer validator/stager plus existing
story, trajectory, Cleveland, release and atlas tests. UI: `FeaturedStoryUITests`
on iPhone/iPad covers notice ordering, automatic remote grid, cache/bad-hash,
disabled/expired/unsupported/slow responses, cold-launch renderer changes,
foreground/dismissal, reduced motion, replay and largest text.

The live acceptance test `testLivePublishedSwapWithoutReinstall` runs one continuous
XCTest session: launch A, change only the published pointer to existing public
trajectory B, relaunch the same installed app, restore A, relaunch again. Record
the installed executable hash before/after, public Git SHAs, endpoint values, and
screenshots. A simulator proof does not establish installation or playback on a
physical TestFlight phone. Ask Scott to install 127, open Cleveland, and coordinate
a later live pointer switch plus force-close/reopen if he wants that device proof.

The TestFlight release remains private to the verified sole-member Hub Ball Internal
group. Do not submit external beta review, add Family, or advance the global update
target. The proposed six-hour update-notice maintenance job remains unauthorized.
See ignored `dist/remote-opening` and the workspace handoff for exact release and
live-swap receipts; never commit generated build evidence.
