# Hub Ball architecture and scale review

Reviewed September 19, 2026. Review only: no application code, configuration, data, commits, or deployments changed.

## Executive verdict

**NOT READY for 1 million installs or a dependable paid launch.**
1. Commercial rights and service guarantees for core data are unverified.
2. Full-game downloads, unprotected upstream work, and fragile refresh/failure handling make delivery expensive and unreliable.
3. Monitoring, release gates, and subscription entitlements are insufficient or absent.
The SwiftUI app, shared team registry, and CDN approach can be retained; a wholesale rewrite is unnecessary.

## Scope and evidence

The supplied MLB Apps workspace is archived. Primary review: **/Users/sfrancoe/Projects/Hub Ball**, local HEAD **fefe47eb44eaff6e4c7655029c416e266873a5f0**, version 1.0/build 61. Its existing uncommitted ScheduleView.swift change was preserved. All repository-relative paths below mean this canonical checkout unless labeled archived or remote.

I read both checkouts' AGENTS.md and CLAUDE.md, archived PROJECT_HANDOFF.md and docs/netlify-cost-reduction-review-followup.md, canonical ios/IPAD_REVIEW.md, product/backend/release documentation, then implementation. No HUB_BALL_EXPANSION_REVIEW.md was found. The handoff's four-team assessment is historical: the current registry contains 30 teams with generated Swift/JavaScript views.

Read-only GitHub inspection found remote main at **51f9cb5df673b511c0045bb62f99d647ff39c225**, declaring build **60**. Comparing remote tree blob hashes found differences in the release manifest, Xcode project, three views, bundled players, Boston refresh workflow, and fetch_team_news.py. I inspected relevant differences. All seven function modules and the networking/store code central to this review matched remote. **UNVERIFIED:** exact source revisions of the distributed TestFlight binary and Netlify deployment. Local main is not proof of either.

Links cite reviewed files/lines or functions. Effort: **S** approximately 1–2 engineering days; **M** 3–10 days; **L** multiple weeks. Licensing and App Review lead times are separate.

For compact citations, bare Swift filenames resolve under ios/Hub Ball/Hub Ball/, bare .mjs filenames under netlify/functions/, bare fetch/test/build script filenames under scripts/, and project.pbxproj under ios/Hub Ball/Hub Ball.xcodeproj/. These names identify the reviewed canonical files, not the archived copies.

## Findings

| ID | Area | Severity | Evidence | Impact | Recommended fix | Effort |
|---|---|---|---|---|---|---|
| F01 | Commercial data / legal | Critical | netlify/functions/mlb-data.mjs:3,197–205; scripts/fetch_team_data.py:22–44; scripts/fetch_players.py:37–38; [MLB notice](https://gdx.mlb.com/components/copyright.txt). Preflight only scans client sources/bundled players for hostnames (scripts/app_store_preflight.py:193–209). | **UNVERIFIED:** commercial redistribution permission, quotas, and SLA. Core functionality still depends on MLB through the proxy, notwithstanding preflight's passing “Production data sources” result. FanGraphs, Baseball Reference, newspapers, and X have separate rights questions. | Obtain written rights covering distribution, caching, transformations, historical data, and the paid tier, or use a licensed provider. Maintain a source/rights register and check backend dependencies in preflight. A proxy does not confer rights. | L |
| F02 | Security / cost abuse | Critical if X credentials enabled | [x-discovery.mjs:97–132][discovery]: public GET, server bearer token, paid search per invocation, no application quota/auth. [app-data.mjs:30–32][appdata] accepts arbitrary 1–10 digit career IDs. [mlb-data.mjs:25,60–99][mlb] permits unbounded date ranges/numeric game IDs. | **UNVERIFIED:** production X key and external firewall settings. Outsiders can consume provider quota and potentially increase charges. Unknown query parameters fragment caches; arbitrary IDs/date windows amplify other upstreams. A CDN is not a spending boundary. | Replace user-triggered paid searches with a scheduled, budget-limited collector and durable results. Add an emergency disable control, edge rate limits, normalized semantic query keys, real calendar/date-span validation, and allowed game/career IDs. Never put a shared API secret in the app. | M |
| F03 | Live delivery / cost | High | [RecentGameView.swift:45–56][recentview]; [RecentGameStore.swift:46–55][recentstore]; [MLBGameClient.swift:16–69][client]; [ScheduleStore.swift:17–37][schedule]; [mlb-data.mjs:201–228][mlb]. | Every 20-second live refresh requests generated schedule, discovery schedule, and the complete game feed. Initial entry also downloads three finals. Finals get the same five-second CDN TTL as live games. Every game miss additionally fetches editorial content the native converter discards (client line 125). Measured feed: 860 KB decoded / 144 KB gzip. | Serve compact normalized game snapshots keyed by game, reusable by both teams. Fetch once per game, discover less often, reuse schedules, cache finals longer with a correction policy, and decouple editorial refreshes. Measure bytes/session and actual CDN hits. | M |
| F04 | Pipeline / CI isolation | High | [refresh-mlb-team-data.yml:11–36][datajob]; [refresh-mlb-team-news.yml:11–35][newsjob]; scripts/fetch_team_data.py:464–489; [remote news fetcher][remotenews]; [failed production run][newsfailure]. | All 21 refresh workflows share one concurrency group. Protecting the running job does not provide an unlimited pending queue. One transport/XML failure aborts the expansion-news batch before publication. This happened September 19 at the first team's source. | Isolate team/source failures, validate successful outputs, retain failed sources' last-good data, publish success/failure status, and alert. Separate fetching from publication; consolidate schedules and use deliberate queueing. Before 100k, move frequent feed publication out of Git. | M–L |
| F05 | Stale data / offline / partial failure | High | [RecentGameStore.swift:49–70][recentstore]; [HomeStore.swift:49–60][home]; [HeadlinesStore.swift:29–49][headlines]; [StandingsStore.swift:35–50][standings]; [x-posts.mjs:289–300][xposts]. | Game Center silently retains an old game on refresh failure, but has no durable cold-launch game fallback. One failed Home/headline/league dependency prevents publishing otherwise successful results. X fallback permits a week of stale CDN serving, without the app interpreting its fallback header. | Persist bounded last-good data with source-update/check times and expiry. Show successful sections independently. Clearly mark frozen scores, report errors without hiding content, and define maximum stale age by source. | M |
| F06 | Season correctness | High | MLBGameClient.swift:19,30,45–53; netlify/functions/mlb-data.mjs:70–76; scripts/fetch_team_data.py:23–27,119–124. | Live discovery explicitly requests regular-season games and only looks back 14 days. Upcoming schedules stop at regular-season end. Postseason games are excluded from these paths; offseason Game Center can become empty. | Define regular/postseason/exhibition behavior and season transitions. Test playoffs, doubleheaders, delays, suspended/resumed games, and no-games periods. Keep postseason out of regular-season historical totals. | M |
| F07 | Privacy / preflight | High | [PrivacyInfo.xcprivacy:5–12][privacy]; AppTabView.swift:48–50 and TeamSettingsView.swift:23–24 use AppStorage; MarketsView.swift:89,101 uses UserDefaults directly. [Preflight:147–159][preflight] only checks plist readability. | Empty required-reason API declarations conflict with preference storage. A green preflight misses this. **UNVERIFIED:** archive privacy report and App Store Connect disclosures. Future diagnostics/payments change the disclosure basis. | Audit the signed archive, declare the applicable UserDefaults category/reason, reconcile policy/App Store labels/server logging, and add a semantic preflight check. | S |
| F08 | Paid tier | High before charging | AppTabView.swift:selectedTabContent; [app-data handler][appdata]; [mlb-data handler][mlb]. No StoreKit, transaction, entitlement, or subscription implementation found in reviewed Swift/functions inventory. | Paid access is not implemented. A client-only lock cannot protect public backend data; refunds/revocations require handling. There is no current payment breach because payments are absent. | Use verified StoreKit transactions, entitlement updates, restore/manage, expiry/refund/revocation handling, and explicit offline grace. Protected server content additionally needs server verification, idempotent App Store notifications, and authorization before delivery. | L |
| F09 | Operability / rollback | High | Error logging in app-data.mjs:88, mlb-data.mjs:235–255, x-posts.mjs:289–298; [backend documentation][backenddoc]; scripts/netlify_ignore.sh:40–59; AppBackend.swift:6. No telemetry/alert integrations found in reviewed app/functions/workflows. | Logs exist, but no repository-defined freshness alerts, synthetic live checks, crash-reporting integration, or game-night runbook. A Netlify code rollback still reads current GitHub main data: it cannot restore a previous data/schema version. Provider hostname binds installed clients to Netlify. **UNVERIFIED:** dashboard-only protections. | Add actionable freshness/error/latency/cache/budget alerts, crash diagnostics, and an owner runbook. Publish versioned data with a reversible manifest. Adopt an owned API domain before broad release; preserve existing routes. Rehearse code and data rollback separately. | M |
| F10 | iOS runtime / accessibility | Medium | project.pbxproj:286,320 defaults actor isolation to MainActor; [MLBGameClient.swift:62–74,224][client]; XPostsStore.swift:60; RecentGameView.swift:45–56,271–333; StandingsView.swift:38–49; XPostsView.swift:178–200. | Large JSON conversion is not explicitly moved off the default main actor. Live loops lack inactive-scene gating/jitter. Duplicate upstream IDs can trap Dictionary(uniqueKeysWithValues:). Dense tables use fixed small fonts/widths; images lack explicit downsampling. **UNVERIFIED:** actual hangs, crashes, battery/memory cost, or accessibility task success. | Shared networking/cache actor, deliberate off-main decoding, MainActor UI updates, active-scene polling, bounded backoff/jitter, safe deduplication, and downsampling. Test Dynamic Type, VoiceOver, contrast, Reduce Motion, and a three-hour device session. | M |
| F11 | Release verification | High | .github/workflows contains refresh jobs but no general push/PR validation workflow; scripts/test_mlb_data.mjs:6 mocks fetch; [scheme:26–32][scheme] has no explicit testables; scripts/test_chase_engine.sh:8–11 tests only chase logic; build_site.sh:5–9 copies files. | Tests exist, but merges can deploy without them. Passing unit tests does not establish CDN behavior, native resilience, or billing correctness. Preflight currently overstates privacy/source readiness. | Require registry checks, feed contracts, function tests, iOS build/store failure tests, and improved preflight on PRs. Add production smoke/freshness checks and record source SHA/data schema for each release. | M |
| F12 | NFL/NBA extensibility | Medium | [registry:2–8][registry]; [HubTeam.swift:45–90][hubteam]; scripts/team_registry.py:11–35; MLBGameClient.swift:213–310; mlb-data.mjs:10–23,72–76; AppTabView.swift:67–73. | Good MLB abstraction, not sport abstraction: MLB IDs, AL/NL, innings, pitching, WAR, and navigation are baseball-specific. Most capability flags do not control tab availability. Adding NFL/NBA entries alone is insufficient. | Add sport/provider identity, sport adapters, and capability-driven navigation when implementing the second sport. Share selection, schedule shell, news, caching, billing; keep sport-specific game/stat models and views. | M–L |

### Foundations worth keeping

The @Observable/MainActor stores and per-store in-flight guards are sensible (RecentGameStore.swift:37–44). Team changes rebuild team-specific state through .id(team.id), and completed games are reused within the current Game Center store (AppTabView.swift:77–83; RecentGameStore.swift:51–56). Improve shared caching and store lifetimes rather than replace SwiftUI.

The authoritative registry is **config/mlb-teams.json**, not literally teams.json. scripts/generate_team_registry.py:14–17 generates HubTeam.swift and team-registry.mjs. Generic fetchers cover 26 expansion teams; four legacy families remain (scripts/team_registry.py:12,34–35). All 30 local datasets and generated registry views passed existing checks.

The gateways already use HTTPS, path/team allowlists, timeouts, game/team checks, and durable CDN directives (app-data.mjs:11–32,45–64,80–84; mlb-data.mjs:188–199,220–232). No embedded API credential was found in reviewed client source; X_BEARER_TOKEN is server-side. There is no npm/pip/Swift-package dependency tree in the inspected app. This reduces dependency exposure, but does not prove vulnerability-free runtime or history. **UNVERIFIED:** full-history/binary secret scan, deployed runtime patches, account security. Actions use movable checkout@v4/setup-python@v5 tags; pin trusted revisions and review updates.

The previous build-ignore rename defect is fixed: scripts/netlify_ignore.sh:28–31 uses --no-renames. Data-only commits intentionally skip deployments. Do not charge the cost model for a deploy on every data commit.

## Architecture and source-to-screen flow

    config/mlb-teams.json
       → Python registry / generated Swift HubTeam / generated JS registry

    Sources → scheduled GitHub Actions → Python transforms → JSON commits on main
       → Netlify app-data reads GitHub Raw → durable CDN → iOS stores → SwiftUI

    Live game/schedule/standings → Netlify mlb-data → MLB API
       → durable CDN → MLBGameClient/HomeStore/StandingsStore → SwiftUI

    X tab → x-posts → syndication HTML + MLB roster; fallback: GitHub snapshot
          → x-discovery → paid recent search for four teams → native merge

**Live games do not travel through GitHub Actions.** Git/cron govern supporting snapshots and news. Installs increase delivery demand; teams, sources, and refresh frequency increase ingestion work.

| Surface | Implementation and flow |
|---|---|
| Home | HomeStore.load fetches generated recent game/schedule, live standings, and discovery + newest game: five successful-path requests. HomeView.swift:38,85 loads on entry/pull, without a periodic live timer. |
| Game Center | RecentGameStore.refresh → MLBGameClient.gameDescriptors/game → /api/mlb/schedule and /api/mlb/game; ScheduleStore.load fetches generated schedule for broadcasts. |
| Schedule / pitching / history / leaders | fetch_team_data.py:464–489, fetch_team_leaders.py:253–269, legacy equivalents, fetch_league_leaders.py → generated JSON → app-data → respective native stores. |
| News | Globe HTML metadata (fetch_globe_news.py:24–60), Herald WordPress API (fetch_herald_news.py:18–35), legacy RSS adapters, expansion Bing RSS search (fetch_team_news.py:61–93) → JSON → HeadlinesStore. Registry: 64 team/source entries, mean 2.13/team. |
| X | x-posts.mjs:275–283 parses internal __NEXT_DATA__. Expansion teams filter one MLB clubs list to the official handle. fetch_team_x_posts.py:193–203 already fetches that list once per batch. XPostsStore.load still requests both curated/discovery for all teams; 26 discovery configurations are absent. |
| Players | fetch_players.py combines Wikimedia, Chadwick, Retrosheet, and MLB enrichment (lines 37–38) → per-team players/per-player careers → PlayersStore. Only Boston has its bundled roster fallback (PlayersStore.swift:117–124). Older “open sources only” documentation is incomplete. |
| Stories / markets | hr-chase.mjs:32–45,65–84 retrieves Judge totals; HomeRunChaseStore.swift:11–36 retains built-in totals on failure. redsox-markets.mjs:128–143 contacts Kalshi/Polymarket and tolerates one failed source. These are baseball-specific ancillary paths. |
| Web / deploy | build_site.sh:5–9 copies public files into _site. netlify.toml:4–7 sets build/ignore rules. app-data.mjs:96 handles both /data/* and /api/data/*. Native, backend, and data release states are separate. |

## Caching, freshness, and outages

| Resource | Configuration | Assessment |
|---|---|---|
| Generated JSON | Client max-age 60 + SWR 300 seconds; durable CDN 300 + SWR 3,600 (app-data.mjs:81–82). | Reasonable slow-data starting point. GitHub Raw also returned max-age 300, adding another possible lag. Cache expiry does not prove ingestion ran. |
| Live game/discovery | Client and CDN 5 + SWR 15 seconds (mlb-data.mjs:223–228). | Client polls every 20 seconds live/60 otherwise. Five-second end-to-end freshness is not guaranteed. Finals get unnecessarily short TTLs. |
| Standings | 30 + SWR 30; saved fallback marked stale with 15-second TTL (mlb-data.mjs:226–245). | Useful fallback. Native Standings fetches both leagues every minute (StandingsStore.swift:40–42). Share league snapshots instead of favorite-team computation. |
| Curated X | 300 + SWR 3,600; fallback 3,600 + SWR 604,800 (x-posts.mjs:6–9,292–295). | Brief outages covered, but stale content can outlive credible freshness/removal expectations. Native store ignores fallback headers. |
| Paid X discovery | CDN 86,400 + SWR 3,600 (x-discovery.mjs:119–121). | A daily selection, not continuously updated rankings. Genuine CDN hits do not invoke X. |
| Native | Live client ignores local cache; most other stores force revalidation. Game cache is memory-only. Boston players/some stories have bundled fallbacks. | No consistent cold-start/offline contract. Persist a labeled last-good game. First-ever offline launch can offer setup/help, not current scores. |

Headlines and X do **not** automatically poll on a native timer (HeadlinesView.swift:62; XPostsView.swift:30). Their load model below uses entries/manual refreshes. Home likewise needs an explicit freshness policy if presented as live.

No cross-request application coalescer was found in function handlers, nor a shared native request repository. Per-store isLoading prevents duplication only within that instance. Durable CDN caching is valuable; it is not proof that exactly one worldwide request refreshes a cold key.

Netlify includes query parameters in function cache keys by default. Code does not constrain them to semantic parameters; probes returned Netlify-Vary: query. Normalize inputs and use a consistent restricted variation policy. [Netlify cache behavior](https://docs.netlify.com/build/caching/caching-overview/).

### Production observations

Around 06:51–06:56 UTC September 19, non-metered GETs returned 200 for both Boston standings route shapes, Dodgers standings, Globe news, live schedule, and one completed game. Boston standings/GitHub Raw had matching timestamps and byte counts. This is representative availability, not all-team production certification.

Game 822923: **859,522 decoded bytes / 143,559 transferred with gzip**. The 14-day schedule was approximately 18.6 KB decoded / 2.1 KB gzip. Local generated schedules compressed to about 0.8–0.9 KB. These are sample sizes, not season maxima. The game payload's copyright field explicitly links to MLB's notice.

Some live probes reported durable-cache bypass; repeated others reported edge misses/stored responses. **UNVERIFIED:** hit ratio, coalescing, and why bypass occurred. This small sample does not prove either a broken CDN or adequate caching. Verify using production telemetry and actual URLSession requests.

The [failed news job][newsfailure] ended 06:39:21 UTC with malformed XML while processing Baltimore. Remote code catches empty valid searches, unlike local code, but still aborts on transport/XML failures. The finding remains current. Conversely, old generated_at timestamps alone do not prove failed refresh: writers deliberately preserve unchanged content (fetch_team_data.py:70–80). Add a separate successful-check heartbeat.

## Scale model

### Assumptions

All behavioral assumptions are **UNVERIFIED against analytics**:

- Tiers mean **installs**, not concurrent users. DAU = requested **15%**.
- Peak foreground concurrency = **20% of DAU**, or **3% of installs**: 300 / 3,000 / 30,000. Up to 15 simultaneous MLB games; team popularity is uneven.
- Peak mix: 70% Game Center following live games, 10% Home, 10% news, 5% X, 5% standings.
- Game Center: three requests/20 seconds. Standings: two/minute. Home/news/X: one entry or manual refresh/five minutes, a behavior assumption rather than a coded timer.
- Monthly baseline: 30 in-season days, average 30 minutes Game Center use per DAU/day. Peak lasts only part of the day.
- Excludes bots, website visitors, third-party images, purchases, and mass retries.

### Peak client requests/second

| Request class | Formula for concurrent users C | 10k | 100k | 1M |
|---|---|---:|---:|---:|
| Live game feed | 0.70 × C / 20 | 10.5 | 105 | 1,050 |
| Live schedule discovery | Same | 10.5 | 105 | 1,050 |
| Generated schedule during game refresh | Same | 10.5 | 105 | 1,050 |
| News JSON | 0.10 × C × 2.133 / 300 | 0.21 | 2.13 | 21.33 |
| X curated + discovery | 0.05 × C × 2 / 300 | 0.10 | 1 | 10 |
| Standings, both leagues | 0.05 × C × 2 / 60 | 0.50 | 5 | 50 |
| Home, five requests | 0.10 × C × 5 / 300 | 0.50 | 5 | 50 |
| **Total** | | **32.81** | **328.13** | **3,281.33** |

At 1M, the X total is five curated and five discovery requests/second. Equal team distribution means only 0.67 discovery RPS targets the four supported teams; popular-team concentration could be higher. Unsupported requests return errors. CDN hits are neither function invocations nor paid API searches.

**Opening burst:** Game Center entry needs two schedules plus up to four games: six requests. Weighted across screens, approximately 5.11 requests/opening. If the peak cohort opens within one minute, that is **26 / 256 / 2,557 entry RPS**, possibly overlapping existing users. Do not double-count that cohort's own initial and steady-state loads.

**Stress case:** 60% of DAU simultaneously active gives 900 / 9,000 / 90,000 clients and approximately **98 / 984 / 9,844 sustained RPS**. A nationally televised game concentrates requests into a few keys: favorable with healthy shared caching, dangerous during a cold-cache stampede.

### Origin load and breaking points

An ideal shared cache with 30 hot team-specific game keys and five-second TTL needs approximately six refreshes/second; discovery schedules add six. Thirty favorite-team standings variants add one/second at 30-second TTL. Each game refresh also retrieves editorial content, making roughly **19 MLB upstream requests/second** before retries and finals. This is a high-occupancy estimate, not guaranteed request coalescing.

Rolling sessions can activate around 90 recent-final keys. At five-second TTL these add up to roughly **18 function refreshes / 36 MLB calls per second** under sustained demand. Cache reuse helps substantially, but finals/editorial requests are avoidable waste.

If cache delivery is bypassed, at the base 1M peak the game/discovery paths alone can make about **3,150 MLB calls/second**: 1,050 games × two upstreams + 1,050 discovery requests. Home, standings, rosters, retries are extra. **UNVERIFIED:** MLB's permitted rate; there is no defensible numerical throttle threshold/SLA in the repository.

A central collector refreshing 15 games every 10–20 seconds needs only **0.75–1.5 game-source requests/second**, plus small schedule/standings/editorial work. User count should not determine upstream collection frequency.

| Tier | Likely first problems | What this review does not establish |
|---|---|---|
| 10k | Source failure, silent stale UI, CI scheduling, or exposed paid endpoint. These already exist. Static delivery at 33 RPS is not inherently hard. | No evidence Netlify automatically hits a CPU limit at 10k users. |
| 100k | Bandwidth/mobile transfer waste, cache/upstream bursts, unreliable source maintenance, and inability to detect/recover a paid outage. | No measured function concurrency ceiling or contractual upstream quota. |
| 1M | Provider rights/guarantees, proven cache miss budget, affordable delivery, stale-safe recovery, subscriptions/support. Cache bypass at 3.3k–9.8k client RPS greatly amplifies upstream demand. | This is not a load test, SLA certification, or a hard user-count failure prediction. |

### Git and CI capacity

The 21 checked-in workflow schedules request approximately **1,419 starts/day**: 864 five-minute news jobs, 432 ten-minute news jobs, 48 expansion-news jobs, 60 two-hour data jobs, eight six-hour X jobs, and seven daily jobs. That is **42,570 requested starts/month**, not observed completions. Evidence: each on.schedule in .github/workflows/refresh-*.yml; representative [data][datajob] and [news][newsjob] workflows.

One serial group has an average service budget of **61 seconds/run** before requested work exceeds a day. Twenty seconds/run consumes 33% of the day; 60 seconds consumes 99%; two minutes consumes 197%. Overlapping cron entries and occasional 20–45 minute jobs can displace pending work even with low average utilization.

GitHub's default is one running/one pending run per concurrency group; additional pending runs replace previous ones unless explicit queueing is configured. This repository sets no queue option. Scheduled jobs can also be delayed/dropped by GitHub. Thus cancel-in-progress:false is not a reliable FIFO queue. [Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency), [scheduled-event limitations](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows).

Installs do **not** multiply this ingestion workload. Thirty-team scheduling is already the problem. Sampled successful expansion-data runs took tens of seconds; the 40-minute timeout is not normal measured runtime.

Git growth is a longer-term maintenance concern. Illustratively, 20 KB changed JSON × every requested run would produce 0.85 GB/month of logical versions, or 85 MB if only 10% changed. Physical Git storage depends on delta compression; actual growth is **UNVERIFIED**. Moving live updates into Git would add 1,080 commits/day even for one league batch every 20 seconds during six hours. Keep live delivery outside Git and move frequent supporting feeds out before scale.

## Monthly cost model

### Workload

Approximately **318 JSON requests/DAU/day**:

- Ninety Game Center refresh cycles including entry: 273 requests, including three extra finals.
- Two Home loads: 10; four news loads: 8.53 average; four X loads: eight; four two-league standings loads: eight; other JSON: ten.

Monthly totals: **14.31M / 143.1M / 1.431B requests**. Never multiply peak RPS by an entire month.

Assume **15 MB compressed JSON/DAU/day**, informed by the measured game: approximately 90 × (150 KB game + 3 KB discovery + 3 KB generated schedule), three extra finals, and other screens. This yields **675 GB / 6.75 TB / 67.5 TB monthly**. Third-party images add device traffic but currently are fetched outside Netlify (XPostsView.swift:187–200,234–246).

### Pricing and estimates

Published Netlify rates: Pro starts at $20 with 3,000 credits; extra packs $10/1,500; bandwidth 20 credits/GB, requests two/10k, compute ten/GB-hour, production deploys 15 each. Marginal equivalents: **$0.1333/GB, $1.333/M requests, $0.0667/GB-hour**. [Netlify pricing](https://www.netlify.com/pricing/).

**UNVERIFIED:** actual account/legacy plan, discounts, regional settings, telemetry, invoice rounding, and recharge configuration. Compute scenario: **10% of requests invoke a function**, 1 GB memory, 250 ms mean duration; remaining requests hit CDN. This is a sensitivity assumption, not a measured uniform miss rate. Allow 20 production deploys/month. [Function defaults](https://docs.netlify.com/build/functions/configuration/).

| Monthly item | 10k installs | 100k installs | 1M installs |
|---|---:|---:|---:|
| DAU | 1,500 | 15,000 | 150,000 |
| CDN/web requests | 14.31M | 143.1M | 1.431B |
| JSON bandwidth | 675 GB | 6,750 GB | 67,500 GB |
| Function invocations, 10% miss scenario | 1.431M | 14.31M | 143.1M |
| Compute | 99.4 GB-hours | 993.8 GB-hours | 9,937.5 GB-hours |
| Bandwidth dollar equivalent | $90 | $900 | $9,000 |
| Requests dollar equivalent | $19.08 | $190.80 | $1,908 |
| Compute dollar equivalent | $6.63 | $66.25 | $662.50 |
| Twenty deploys dollar equivalent | $2 | $2 | $2 |
| **Estimated Netlify bill, plan and pack rounding included** | **$120** | **$1,160** | **$11,580** |
| Standard GitHub Actions, current public repo | $0 | $0 | $0 |
| Four-team daily X discovery, if configured and one fill/team/day | up to ~$28.80 | up to ~$28.80 | up to ~$28.80 |
| Commercial sports/news data licenses | **UNVERIFIED: quote required** | **UNVERIFIED: quote required** | **UNVERIFIED: quote required** |

Reproducible formula: credits = 20 × GB + 2 × requests/10,000 + 10 × invocations × memory_GB × seconds/3,600 + 15 × deploys. Pro estimate = $20 + $10 × ceil(max(0, credits − 3,000)/1,500). Component dollar equivalents explain usage; do not add another full plan allowance to them.

GitHub API confirmed the repo is public; standard public-repo hosted runners are free. If made private, an illustrative 42,570 one-minute Linux runs minus 2,000 included minutes at $0.006/minute is about $243, plus plan/storage charges. Actual billing/run time differs. [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

### Sensitivities and omitted expenses

- At 1M, half/double the assumed bytes changes bandwidth expense to **$4,500/$18,000**. Three hours watching instead of 30 minutes multiplies live transfer by six: approximately 84 MB compressed/session at these payload assumptions. CDN caching cannot remove bytes each device must receive.
- At 1M/250 ms/1 GB, compute is approximately **$66 at 1% misses, $663 at 10%, $6,625 at 100%**. One-second duration multiplies these by four. Timeout/error conditions can be worse; provider throttling may occur before theoretical billing totals.
- An optimized example of **110 requests and 1 MB/DAU/day** at 1M gives 495M requests and 4.5 TB/month, about **$1,260 request+bandwidth usage**. Approximately **$1,300–$1,600 infrastructure/month** is a reasonable engineering target including modest collector/storage/compute, not a quote or achieved result. Analogous delivery usage is ~$13/$126 at 10k/100k before base/operational fees. This requires small/conditional updates and reuse, not just a host migration.
- Reserve an additional planning allowance of roughly **$25–$100 / $100–$300 / $200–$1,000** for diagnostics, alerting, independent probes, and operational services as adopted. These are allowances, not verified vendor quotes; avoid double-counting collector/storage if included above. Support labor and commercial data contracts are excluded and could dominate.
- Data commits are intentionally not deployments. If ignores stopped working, another 1,000 production deploys would add about $100 marginal credits. Actual skip events were not audited here.
- Subscription fees are separate revenue deductions: model **15–30% Apple commission** depending on agreement, eligibility, subscriber tenure and storefront. Hypothetical 2% paid conversion of 1M installs at $5/month means $100,000 gross and $15,000–$30,000 commission sensitivity before tax/refunds. **UNVERIFIED:** actual eligibility/economics. [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/).

### X economics and rate limits

The code requests **16 posts**, not 100, with author expansion (x-discovery.mjs:1–5,85–93). Published rates are $0.005/post and $0.010/user; resources are generally deduplicated within a UTC day, described as a soft guarantee. One daily fill for four teams with 16 distinct authors gives 4 × 30 × 16 × $0.015 = **$28.80**; 30 teams gives **$216/month**. More refreshes cost by additional billable resources, not users × requests × 16. [X pricing/deduplication](https://docs.x.com/x-api/getting-started/pricing).

A richer hypothetical collection of 500 distinct posts and 100 authors/team/day across 30 teams costs approximately **$3,150/month** before overlap/other endpoints. This should stay approximately constant across install tiers because collection is shared. Public syndication has no API invoice in this code, but is not a contracted free feed. **UNVERIFIED:** actual billing agreement, author-expansion charges, and commercial permissions.

Published recent-search quota: **450 requests/15 minutes per app** (0.5 RPS averaged); pay-per-use caps post reads at 3M/month. Deduplication may reduce charges without preventing quota exhaustion. New result sets, midnight resets, query fragmentation and deploy invalidation still matter. [Rate limits](https://docs.x.com/x-api/fundamentals/rate-limits), [monthly cap](https://docs.x.com/x-api/getting-started/pricing). No metered production discovery request was made during this review.

## Third parties, App Store, and iOS readiness

**MLB:** no supported production quota, SLA, or commercial agreement was available. The observed API payload links to a notice restricting use absent authorization. Secure appropriate rights or a licensed feed before commercial distribution. Free endpoints and an unofficial disclaimer are not permission. [MLB notice](https://gdx.mlb.com/components/copyright.txt).

**News:** expansion coverage depends on Bing indexing rather than publisher-supported feeds. Source filters use host substring membership (fetch_team_news.py:73–77); validate exact host/subdomain boundaries, types, timestamps and per-source success. Redesigns, paywalls, empty indexes and malformed RSS must affect only that source. Keep excerpts within actual rights and link to publishers. The XML incident demonstrates fragility, not a hypothetical takedown.

**X:** custom cards use plain Text for entities and the visible wide-layout timestamp (XPostsView.swift:172–180), while x-posts parses syndication internals. No removal/update workflow for stored content/Git history was demonstrated. Review X's display and content compliance obligations, including linked entities/timestamps and prompt updates/removals, or choose authorized embeds/links. API payment alone does not authorize every presentation. [Display rules](https://docs.x.com/developer-terms/display-requirements), [content compliance](https://docs.x.com/developer-terms/policy).

**Bundle ID:** com.sfrancoe.HubBall matches the local release manifest and Xcode configurations, and is sport-neutral. Apple locks the App Store Connect bundle ID **after a build is uploaded**, not just public release. Do not plan to rename it later. Legacy Boston identity is separate. **UNVERIFIED:** App Store Connect record/ownership. [Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).

**Branding:** inspected AppIcon-1024-v5.png is an HB monogram/diamond, not an obvious MLB logo. No separate club-logo asset set was found in the native catalog. Team names/colors and remote social media still require scoped rights/branding review (config/mlb-teams.json; XPostsView.swift:187,235). **UNVERIFIED:** clearance, image/publisher permissions and store screenshots. Do not assume all team-name references are unlawful, or that TestFlight establishes clearance. [App Review §5.2](https://developer.apple.com/app-store/review/guidelines/).

**Privacy/support:** policy says no third-party analytics and explains network/image requests (privacy/index.html:28–56). Adding diagnostics/subscriptions requires deliberate retention/access/disclosure choices. Required-reason declarations are separate from collected-data labels. Public support is also incomplete: metadata points support_url to the root website; privacy/index.html:69–71 directs questions to TestFlight. Provide a public support channel. [Required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

**Subscriptions:** validate purchase, restore, pending/interrupted purchase, renewal, grace/billing retry, expiration, refund, revocation, offline use and device changes. Provide price/period/renewal information, privacy/EULA and management access. Pure on-device premium features can use verified StoreKit without mandatory new accounts; protected server content needs server enforcement. [Apple subscription guidance](https://developer.apple.com/app-store/subscriptions/).

**iOS testing:** some good accessibility work exists—game selector labels and a Reduce Motion-aware live indicator (RecentGameView.swift:84,629–646); story views stop on inactive scenes (NinePitchesView.swift:65–67). Coverage is uneven, not absent. Fixed-size stat tables and source-fed images require real device/accessibility testing. No current crash rate, energy profile, memory leak, or measured main-thread hitch is claimed.

## Necessary target architecture

    Approved/licensed sources
      → small collectors, bounded retries, per-source isolation
      → validate/normalize once per game, league, publication
      → object storage: current + immutable versions + reversible manifest
      → CDN on an owned API domain
      → shared native networking/disk cache → SwiftUI stores/screens

    StoreKit → verified entitlement → small private service if backend access is paid
    All stages → freshness/error/cache/budget metrics → owner alerts/runbook

1. **Keep SwiftUI and the registry.** Consolidate legacy fetchers as touched. Use versioned normalized contracts rather than expose arbitrary upstream shapes.
2. **Collect independently of viewers.** One collector per game at the agreed 10–20 second cadence, schedules every few minutes, standings per league, news per source, X under a global budget. A lease/single writer prevents duplicate workers. A small worker or managed scheduler suffices; no Kubernetes or per-user sockets are needed for this cadence.
3. **Separate data from code releases.** Object storage with validated immutable versions and an atomic current manifest preserves last-good output and supports rollback. Keep GitHub Actions for tests/deploys/slow batches. A relational database is unnecessary for shared score snapshots.
4. **Deliver small responses.** One game serves both fan bases; highlight favorite team in iOS. Separate state, box score history and editorial content. Use validators, appropriate TTLs, bounded stale-if-error behavior and explicit source time. Verify failure behavior, not just healthy headers. Keep Netlify if measured cost/behavior meets the budget; changing vendors is a later commercial choice.
5. **Common native data repository.** Coalesce identical requests, reuse finals/schedules, persist bounded last-good data, decode off-main, pause inactive polling, and use backoff/jitter. Preserve partial content with explicit staleness.
6. **Protect expensive/private paths.** Global source budgets and edge rate limits even for public scores. Validate entitlements before serving protected data; avoid caching one user's private response for others.
7. **Make failure visible and reversible.** Monitor source/check age, collector errors, p95 latency, schema failures, cache hits, bytes/session, origin fetches, concurrency, credits and crash-free sessions. A proposed live target is p95 source-to-screen ≤30 seconds, stale warning after 60 seconds; confirm provider cadence/rights make it achievable. Test code and manifest rollback independently.

## Roadmap

### Before public launch

1. Settle data rights, freshness/postseason promises, paid scope and X strategy (F01, F06, F08). Defer any feature whose rights/reliability cannot support the promise.
2. Close public paid-source exposure, establish spend caps/validation, and correct privacy declarations using the signed-archive report (F02, F07).
3. Isolate source failures; preserve partial results; add visible stale/recovery states and durable last-good data (F04–F05).
4. Stop unnecessary schedule/editorial/final downloads; gate polling by active scene and measure a three-hour session (F03, F10).
5. Require PR checks, reconcile release SHA/build, add crash visibility/freshness/budget alerts and working public support, and rehearse a short game-night runbook (F09, F11).
6. If charging at launch, complete subscription lifecycle tests and server enforcement for protected content first (F08). Validate basic accessibility and postseason behavior on supported iPhone/iPad devices.

**Exit evidence:** source permissions, archive/privacy review, source-failure regression tests, demonstrated stale/recovery UI, device-session results, a received alert, exercised rollback, and exact source-to-distributed-build mapping.

### Before 100k

1. Move frequent snapshots/news off Git into validated object storage with reversible manifests.
2. Normalize game payloads; centralize collection; finish shared native networking/caching.
3. Test approximately 1,000 client RPS against owned staging fixture origins, including cold keys, openings, source outages, invalid IDs and slow responses. Do not load-test MLB/X or production accidentally.
4. Verify identity/freshness for all 30 teams in production and schema compatibility with the oldest supported app. Measure actual unit costs, bytes, cache hits and crash-free sessions.

**Exit evidence:** bounded source requests as user count grows, recovery from collector failure, correctly labeled stale data, no cross-team responses, and cost within the owner-approved budget.

### Before 1M

1. Obtain provider quota/SLA commitments and hosting concurrency/support confirmation. Negotiate transfer pricing after reducing unnecessary traffic.
2. Prove approximately **10,000 sustained client RPS** and a concentrated opening burst in production-like staging. Include cache expiration, throttling, retries and collector restart; test at least twice measured expected origin load separately.
3. Run a full game-duration soak and rollback drill. Confirm credit exhaustion cannot silently disable all core feeds and that a responsible person receives alerts.
4. Validate subscription/abuse behavior at projected paid volume, staff support, and retain privacy/rights records. Add sport adapters when NFL/NBA implementation is funded.

**Exit evidence:** measured service/recovery objectives, independent source-age monitoring, bounded upstream spend under stress, and a named game-night responder.

### How the owner would know at 7pm

The target alert names the game/team, last successful check, data age, and failing layer. Inspect that status page; disable only an optional failing source when appropriate; keep last-good scores labeled stale. Roll back the manifest for bad data or function deployment for bad code, escalate licensed-source outages, and publish brief status. Add a regression after the incident. The current repository does not demonstrate this loop (F09).

## Owner decisions

- What does “live” promise, and what delay/stale behavior is acceptable to paid users?
- Which sources/features merit a commercial license, and which should be dropped without permission or reliability?
- What is premium: on-device tools, exclusive content, protected live data? Are accounts, cross-platform access, or family sharing required?
- What monthly infrastructure/license budget and spending caps are acceptable? Can optional feeds stop while scores continue?
- Who responds on game nights, and is experienced engineering/support help funded?
- Which device/accessibility/postseason standards are part of the launch promise?
- When will NFL/NBA be funded, and which contracts/providers cover them?

## Verification and limitations

Passed: node scripts/test_app_data.mjs; node scripts/test_mlb_data.mjs; node scripts/test_x_posts.mjs; node scripts/test_x_discovery.mjs; python3 -B scripts/test_team_registry.py; python3 -B scripts/test_all_team_data.py. MLB tests exercised a simulated 502 standings fallback; X tests did not call metered production discovery.

Preflight with --skip-build reported **15 passes, five warnings, zero failures, two skips**. This is the script's result, not App Store readiness: F01/F07 identify concrete blind spots. No build/install/archive/deploy/commit, source refresh, dependency installation or paid API call was performed.

**UNVERIFIED / not exercised:**

- Netlify actual plan/invoices, secrets, external firewall/alerts, deployed SHA, concurrency allowance, cache-hit telemetry and rollback. Source files/GETs do not expose dashboard-only settings.
- Exact TestFlight artifact, App Store Connect labels/subscriptions, signed privacy report, branding/content contracts. These require account/artifact/legal evidence.
- MLB production quotas/prices; X account-specific limits/billing. Public documentation is not an account contract.
- Full-history/binary secret scanning, penetration/load testing, runtime CVE audit and hostile-source injection. No comprehensive security certification.
- Simulator/device execution, actual URLSession cache behavior, energy/memory profiling, VoiceOver/Dynamic Type tasks, long-session stability and crash rates.
- All-team production correctness, sustained capacity, traffic mix/session lengths, canceled-run frequency and causes of sampled CDN bypass.
- Total business operating cost. Estimates exclude contracted sports/news rights, support labor, tax/refunds, unrelated workloads and substantial website/media traffic. Treating those unknowns as zero would be misleading.

[appdata]: </Users/sfrancoe/Projects/Hub Ball/netlify/functions/app-data.mjs:67>
[mlb]: </Users/sfrancoe/Projects/Hub Ball/netlify/functions/mlb-data.mjs:188>
[discovery]: </Users/sfrancoe/Projects/Hub Ball/netlify/functions/x-discovery.mjs:97>
[xposts]: </Users/sfrancoe/Projects/Hub Ball/netlify/functions/x-posts.mjs:268>
[client]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/MLBGameClient.swift:62>
[recentview]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/RecentGameView.swift:45>
[recentstore]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/RecentGameStore.swift:37>
[schedule]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/ScheduleStore.swift:17>
[home]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/HomeStore.swift:43>
[headlines]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/HeadlinesStore.swift:29>
[standings]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/StandingsStore.swift:35>
[privacy]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/PrivacyInfo.xcprivacy:5>
[preflight]: </Users/sfrancoe/Projects/Hub Ball/scripts/app_store_preflight.py:147>
[datajob]: </Users/sfrancoe/Projects/Hub Ball/.github/workflows/refresh-mlb-team-data.yml:11>
[newsjob]: </Users/sfrancoe/Projects/Hub Ball/.github/workflows/refresh-mlb-team-news.yml:11>
[registry]: </Users/sfrancoe/Projects/Hub Ball/config/mlb-teams.json:2>
[hubteam]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball/HubTeam.swift:45>
[scheme]: </Users/sfrancoe/Projects/Hub Ball/ios/Hub Ball/Hub Ball.xcodeproj/xcshareddata/xcschemes/Hub Ball.xcscheme:26>
[backenddoc]: </Users/sfrancoe/Projects/Hub Ball/docs/app-backend.md:5>
[remotenews]: https://github.com/sfrancoe/red-sox/blob/51f9cb5df673b511c0045bb62f99d647ff39c225/scripts/fetch_team_news.py#L103
[newsfailure]: https://github.com/sfrancoe/red-sox/actions/runs/35427180344
