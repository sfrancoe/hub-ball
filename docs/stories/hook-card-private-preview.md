# Persistent hook cards and private screening previews (build 128)

Build 128 changes the opening policy for every compatible remote story: update
notice first, then a hook card with Dismiss and Play. No renderer is instantiated
until Play. `FeaturedStoryLaunch` stores acknowledged stable story IDs in the
`hubFeaturedAcknowledgedStoryIDs.v1` preference. Play records the choice before
playback; Dismiss and interactive sheet dismissal record it too. Relaunch,
foreground return, revised payload SHA and A→B→A rollback cannot reoffer an
acknowledged ID. Force-quitting an unanswered card can reoffer it. The history is
bounded to 1,024 IDs without eviction; a full history safely suppresses automatic
offers while leaving manual Stories access intact. Cache removal never clears it.

The exact verified `FeaturedStoryItem` is pinned through card and playback.
Launch dismissal/completion returns to Postseason; manual replay retains library
navigation. Existing six-second foreground completion holds remain fifteen seconds
for accessibility text/VoiceOver. Replay resets the hold, and background time and
source-sheet reading do not count. A visible launch offer closes at its pointer
expiry. Preparation retains the two-second gate and refuses late presentation.

## Reusable screening presentation

`chart-trajectory` version 1 gains optional `presentation`, requiring minimum
renderer capability **5**. Existing capabilities 1–4 and their legacy layouts are
unchanged. The finite `screening-room` style is compiled SwiftUI/Canvas, not remote
HTML, script, fonts, formulas or media. Required fields:

- `headline`, `subheadline`, UTC `hookExpiresAt`.
- `numberFormat`: `standard` or `innings`. Innings requires nonnegative bar values
  representing exact integer outs divided by three; .1/.2 baseball notation is
  never treated as decimal innings.
- `openingSeconds`, `sweepSeconds`: finite bounded timing within chart duration.
- `intervals`: at most six bounded `{start, end, label}` annotations inside the plot.

White heading, yellow supporting text, essential axes and Replay precede the chart;
no conclusion or source text appears beneath it. Data and sources remain available
through the toolbar info control and the accessible chart summary. Innings display
uses exact thirds without changing geometry/data. Bars grow sequentially; Reduce
Motion presents the complete chart. Large text has vertical reading and a wider
horizontally scrollable plot. After `hookExpiresAt`, manual playback uses the dated
story title rather than its expired relative-time headline.

## Scott-only data seed, with remote supersession

The approved Griffin preview is **data** in `featured-preview.json`, a generic
envelope `{manifest, payloadBase64}`. It uses the existing featured manifest,
StoryEntry, immutable SHA verification and renderer validators. Code contains no
Griffin ID or date. This resource is distributed only inside the authorized private
binary; no Griffin entry/pointer/payload is published to shared production feeds.

`FeaturedStoryPreview` verifies the envelope (≤750 KiB) and document (≤512 KiB).
Automatic eligibility is bounded by pointer dates, minimum build and 24 hours from
publication. The private seed is newer than the existing Cleveland selection, so
that older production pointer cannot replace it or return after its expiry. A
newer authoritative remote pointer supersedes the seed; successful validated content
or a valid disable/incompatibility decision permanently retires the seed preference.
Bad payloads, bad hashes and failed downloads do not retire it. A retired seed never
returns on offline cold launches. Its document remains available manually in the
private build's Stories library, with no automatic completion dismissal.

Package any reviewed compatible preview without story-specific Swift code:

```sh
python3 scripts/prepare_featured_preview.py --manifest reviewed-manifest.json \
  --payload reviewed-payload.json \
  --output 'ios/Hub Ball/Hub Ball/featured-preview.json'
```

This packages a private binary preview; it does not publish. Fixture roots suppress
automatic bundle seeding, and unit tests inject seeds/preferences explicitly.

## Current approved data and expiry

Private Sites version **13** was retrieved through Scott's connected account's
authorized read access. Its exact annual MLB values were checked against official
MLB year-by-year pitching data for person 656492, regular season, sport 1:
2020 **5 outs / 1⅔ innings**; 2021 **0**; 2022 **19 outs / 6⅓ innings**;
2023–25 **0 MLB innings**, explicitly marked **Japan**; 2026 **518 outs / 172⅔
innings**, 31 starts. Combined-season rows are counted once. Before 2026 totals
24 outs / eight innings. Japan innings and postseason innings are excluded.

The official October 12 schedule lists Griffin as Cleveland's probable starter
against Tampa Bay, game 849820, at **2026-10-13T00:00:00Z** (October 12, 8 pm ET).
Both the opening pointer and relative-time headline expire at that scheduled first
pitch. Recheck schedule before release; if an assignment changes, revise factual
copy/data rather than extending a stale claim.

## Later promotion and daily publication

Scott-only upload must stay in the sole-member Hub Ball Internal group. Do not
assign Family, submit external beta review, notify external testers or advertise
128 in `releases/testflight-v1.json` during this preview.

After separately authorized promotion of this exact binary, external users install
the bootstrap once. Subsequent compatible stories are content-only publications:
validate/stage the immutable payload, add the entry to the shared catalog for
manual access and publish a fresh `featured-v1.json` pointer with a publication
timestamp newer than this private seed. Require build 128 and capability 5 for this
screening layout. Use globally stable story IDs; change SHA revisions for corrections
without renaming the story. No further native release is needed for supported
charts, hook copy, intervals or data. New executable rendering capabilities still
require another native update.

Keep the current source baseline, publisher UTC fix and unrelated work. Never push
private native history wholesale: publish eventual data with scoped fast-forward
commits against fresh production main, preserving concurrent feed refreshes. Verify
actual content on both existing hosts before announcing activation. No new service,
dependency, paid API, hosting change or six-hour upkeep job is introduced.

Relevant suites: HookCardTests, FeaturedStoryTests, PostseasonLaunchTests,
BetaUpdateTests, trajectory/cache suites, HookCardUITests on iPhone/iPad;
`test_screening_story.py`, existing story/trajectory/publisher validators and
featured/story/beta gateway tests. Build evidence stays in ignored dist/ and the
workspace handoff. Physical TestFlight installation/VoiceOver use is not claimed.
