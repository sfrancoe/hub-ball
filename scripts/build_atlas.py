#!/usr/bin/env python3
"""Build docs/atlas/hub-ball-atlas.html, an interactive 3D map of this repository.

Every tracked file is measured (lines of code; generated data by bytes), grouped
into systems and feature groups, and linked by the connections detected between
them: Swift type references, JS/Python imports, workflow -> script runs, script ->
data writes, app -> API calls and test coverage. The graph is embedded into
docs/atlas/template.html so the output is one self-contained, offline HTML file.

    python3 scripts/build_atlas.py            # rebuild the atlas
    python3 scripts/build_atlas.py --json -   # print the graph JSON instead
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "docs" / "atlas" / "template.html"
OUTPUT = ROOT / "docs" / "atlas" / "hub-ball-atlas.html"
GITHUB_BLOB = "https://github.com/sfrancoe/hub-ball/blob/main/"
IOS = "ios/Hub Ball/Hub Ball/"
BINARY = {".png", ".jpg", ".jpeg", ".ttf", ".woff2", ".otf", ".ico", ".pdf"}
# JSON that is configuration rather than data counts as code lines.
CODE_JSON = ("config/", "package.json", "package-lock.json", "app-store/metadata.json", ".xcassets/")
# The generated page is excluded so rebuilding never measures itself.
EXCLUDED = {"docs/atlas/hub-ball-atlas.html"}

SYSTEMS = [
    ("ios", "iOS App", "The native SwiftUI iPhone/iPad app (Swift 6). Covers all 30 MLB teams: per-team "
     "stores live in TeamSession, league-wide state in AppModel, networking in APIClient, and "
     "RefreshScheduler drives polling for whatever screen is visible."),
    ("backend", "Netlify Backend", "Netlify Functions (ES modules) that sit between the app and upstream "
     "sources: proxying MLB Stats API calls, serving generated JSON under /api/data, and talking to X. "
     "Uses the one approved dependency, @netlify/blobs, for last-good caches and call reservations."),
    ("web", "Website & Stories", "The original dependency-free website: plain ES modules + <canvas>. "
     "Pages for recent game, schedule, standings, pitching, news and X posts, plus the animated "
     "'Four Roads, One Record' story built on the shared chart/audio engine."),
    ("pipeline", "Data Pipeline", "Python (standard library only) fetchers that pull from the MLB Stats "
     "API, Baseball Reference, FanGraphs and news feeds and write data/*.json. Also holds build, "
     "release and QA tooling plus the test suites."),
    ("actions", "GitHub Actions", "Scheduled workflows that run the Python fetchers (every 5 minutes for "
     "news up to daily for seasons) and commit refreshed data to main, which Netlify then deploys."),
    ("data", "Generated Data", "JSON produced by the pipeline and committed to the repo. Never hand-edited. "
     "Served to the website directly and to the app through /api/data. Sized here by kilobytes, not lines."),
    ("docs", "Docs & Config", "Agent instructions, product docs, design plans, AI review reports, App Store "
     "metadata and the config files (team registry, release manifest) that other parts are generated from."),
    ("external", "External Services", "Third-party sources the project reads from. Not part of the repo; "
     "shown so you can see where data enters the system."),
]

IOS_FEATURES = [
    ("Core & Networking", "App entry, tab shell, networking, backend addressing, refresh scheduling, team "
     "session and shared utilities.",
     ["HubBallApp", "ContentView", "AppTabView", "APIClient", "AppBackend", "RefreshScheduler", "TeamSession",
      "SnapshotFileCache", "SafeURL", "BaseballTime", "PlaybackClock", "AppTheme", "HubTeam", "MLBPayload",
      "MLBGameClient", "TeamSettingsView", "Info.plist", "PrivacyInfo"]),
    ("Home", "The Home tab.", ["HomeView", "HomeStore"]),
    ("Recent Game", "Box score / live game screen, its snapshot model and store.", ["RecentGame", "NinePitches"]),
    ("Schedule", "Team schedule screen.", ["Schedule"]),
    ("Standings", "Division and wild-card standings.", ["Standings"]),
    ("Pitching", "Pitching staff cards.", ["Pitching"]),
    ("Players", "Roster and baseball-card player profiles with career stats.", ["Players", "players.json"]),
    ("Leaders", "Season and league leaderboards.", ["SeasonLeaders", "LeagueLeaders"]),
    ("Postseason & October", "Playoff bracket, scorecards, history, news and the October hub.",
     ["Postseason", "PlayoffBracket", "October"]),
    ("News & Social", "Newspaper headlines and X (Twitter) post feeds.", ["Headlines", "NewsFeed", "XFeed", "XPosts"]),
    ("Stories", "Native visual stories: the Game 108 graph (with music), the vanishing .300 hitter, Brewers "
     "shutouts.", ["StoriesView", "Game108", "GraphMusicPlayer", "MLB300Hitter", "BrewersShutout",
                   "brewers-shutouts"]),
    ("Home Run Chase", "Live home-run chase tracker and chart.", ["HomeRunChase"]),
]

PIPELINE_GROUPS = [
    ("Red Sox Fetchers", "Original Boston-focused fetchers: seasons, schedule, box score, standings, pitching, "
     "Globe/Herald/RSS news and X posts."),
    ("Yankees Fetchers", "Yankees copies of the per-team fetchers, writing data/yankees/."),
    ("Mets Fetchers", "Mets copies of the per-team fetchers, writing data/mets/."),
    ("Rays Fetchers", "Rays copies of the per-team fetchers, writing data/rays/."),
    ("League-wide Fetchers", "Registry-driven fetchers that cover all 30 teams: team data, news, leaders, "
     "players, pitching, playoffs."),
    ("Shared Helpers", "Modules the fetchers import: HTTP refresh/retry, broadcast lookup, team registry."),
    ("Build, Release & QA", "Site assembly, single-file builds, release checks, device install, App Store "
     "preflight, UI-test tooling and this atlas."),
    ("Tests", "Python, Node and shell test suites for the pipeline, the Netlify functions and the native app."),
]
RED_SOX_FETCHERS = {"fetch_seasons.py", "fetch_x_posts.py", "story_facts.py"}
SHARED_HELPERS = {"http_refresh.py", "schedule_broadcasts.py", "team_registry.py", "generate_team_registry.py"}

WORKFLOW_GROUPS = [
    ("News Refreshers", "Every 5–30 minutes: newspaper, RSS, team and postseason news."),
    ("Game & Team Data", "Every 2 hours: schedule, box scores, standings for Boston, the Yankees/Mets/Rays and "
     "all 30 teams."),
    ("Seasons & Leaders", "Daily: per-game season history and leaderboards."),
    ("Players, Pitching & Playoffs", "Player careers, pitching refresh with staged publication, playoff history."),
    ("Social", "X post refreshers every 6 hours."),
    ("Validation", "CI checks run on pull requests."),
    ("Repository Upkeep", "Weekly rebuild of this project atlas."),
    ("Status Files", "Health ledgers the news workflows write so failing sources can alert."),
]

LEAGUE_DATA_DIRS = {"leaderboards": "Leaderboards", "postseason-history": "Postseason History",
                    "postseason-news": "Postseason News"}

GROUP_DESC = {name: desc for name, desc, _ in IOS_FEATURES}
GROUP_DESC.update(dict(PIPELINE_GROUPS))
GROUP_DESC.update(dict(WORKFLOW_GROUPS))
GROUP_DESC.update({
    "Unit Tests": "Swift Testing target with bundled fixtures; run via scripts/test_hub_ball.py.",
    "Large-Text UI Tests": "XCUITest suite that checks every screen at the largest accessibility text sizes.",
    "Xcode Project": "Project file, shared scheme and the iPad review notes.",
    "Fonts & Images": "Bundled Inter and Barlow Condensed fonts plus the asset catalog.",
    "API Functions": "One file per /api route. Each exports a handler and a config with its path.",
    "Shared Modules": "Code shared by the functions: the generated 30-team registry and game narrative writer.",
    "Deploy Config": "Netlify build/headers config and the npm lockfile for @netlify/blobs.",
    "Stories": "Animated canvas stories. Four Roads is live; War Room is an unlisted design mockup.",
    "Four Roads, One Record": "Four straight seasons hit 57-51 after 108 games, then split toward four "
                              "different endings.",
    "War Room (mockup)": "Unlisted design mockup. WAR values are frozen and movement deltas are invented — "
                         "not live.",
    "Shared JS Engine": "Plain ES modules: the canvas chart engine, Web Audio engine and per-page scripts.",
    "Styles": "Per-page CSS and the shared site shell.",
    "Fonts": "Self-hosted Anton and Oswald fonts (no CDN).",
    "Pages": "One HTML shell per website section. The root redirects to /recent-game/.",
    "Red Sox Feeds": "Boston's feeds at the root of data/: seasons, schedule, box score, standings, pitching, "
                     "news.",
    "Team Feeds": "One directory per club, written by the league-wide fetchers.",
    "League Feeds": "Cross-team feeds: leaderboards and postseason history/news.",
    "Player Careers": "One JSON file per player with career stats, used by the Players baseball cards.",
    "Leaderboards": "League leaderboards by season.",
    "Postseason History": "Playoff results history.",
    "Postseason News": "Postseason news headlines.",
    "Config": "Source-of-truth config: the 30-team registry, release manifest and pitching refresh plan.",
    "AI Review Reports": "Reports and ledgers from AI-assisted architecture and large-text accessibility reviews.",
    "App Store": "App Store metadata and archived app icons.",
    "Project Guides": "AGENTS.md, CLAUDE.md, README and the product map.",
    "Design & Plans": "Design plans, data-source research, approved design screenshots and this atlas.",
})

EXTERNALS = {
    "mlb": ("MLB Stats API", "statsapi.mlb.com — free, keyless source of schedules, box scores, rosters, "
            "standings and stats."),
    "bref": ("Baseball Reference", "Historical season records and leaderboards."),
    "fangraphs": ("FanGraphs", "Advanced pitching stats."),
    "globe": ("Boston Globe", "Red Sox headlines."),
    "herald": ("Boston Herald", "Red Sox headlines."),
    "rss": ("News RSS Feeds", "The Athletic, MassLive, NY Times and other team news feeds."),
    "x": ("X (Twitter)", "Post feeds via the X API and syndication lists."),
    "blobs": ("Netlify Blobs", "Key-value storage for X call reservations and last-good feeds."),
}
PYTHON_UPSTREAMS = [("statsapi.mlb.com", "ext:mlb"), ("baseball-reference.com", "ext:bref"),
                    ("fangraphs", "ext:fangraphs"), ("bostonglobe.com", "ext:globe"),
                    ("bostonherald.com", "ext:herald"), ("syndication.twitter.com", "ext:x"), ("api.x.com", "ext:x")]

# Connections that are not visible to the scanners: data written by each fetcher,
# routes the app and site call, and generator relationships documented in AGENTS.md.
D = "data/"
SCRIPT_WRITES = {
    "fetch_seasons.py": [D + "seasons.json", D + "meta.json", "data/brewers", IOS + "brewers-shutouts.json"],
    "fetch_x_posts.py": ["data/Team Feeds"],
    "fetch_hitter_story.py": [D + "mlb300-hitters.json"],
    "fetch_team_data.py": ["data/Team Feeds"],
    "fetch_team_news.py": ["data/Team Feeds", ".github/news-status/expansion.json"],
    "fetch_team_leaders.py": ["data/Team Feeds"],
    "fetch_team_x_posts.py": ["data/Team Feeds"],
    "fetch_players.py": ["data/Team Feeds", "data/Player Careers", IOS + "players.json"],
    "fetch_playoff_history.py": ["data/League Feeds/Postseason History"],
    "fetch_postseason_news.py": ["data/League Feeds/Postseason News"],
    "fetch_league_leaders.py": ["data/League Feeds/Leaderboards"],
    "pitching_publication.py": ["data/Team Feeds", D + "pitching.json"],
}
for _team in ("yankees", "mets", "rays"):
    for _kind in ("schedule", "recent_game", "standings", "seasons", "news", "pitching"):
        SCRIPT_WRITES[f"fetch_{_team}_{_kind}.py"] = [f"data/{_team}"]

APP_ENDPOINTS = [
    ("HeadlinesStore.swift", [D + "globe.json", D + "herald.json", D + "athletic.json", D + "masslive.json",
                              "data/Team Feeds"], "team news JSON"),
    ("HomeRunChaseStore.swift", ["netlify/functions/hr-chase.mjs"], "/api/hr-chase"),
    ("PlayersStore.swift", [D + "players.json", "data/Player Careers"], "players + careers"),
    ("Game108GraphStore.swift", [D + "seasons.json"], "seasons.json"),
    ("PitchingStore.swift", [D + "pitching.json", "data/Team Feeds"], "pitching.json"),
    ("ScheduleStore.swift", [D + "schedule.json", "data/Team Feeds"], "schedule.json"),
    ("SeasonLeadersStore.swift", [D + "seasons.json", D + "meta.json", "data/League Feeds/Leaderboards"],
     "seasons + leaderboards"),
    ("PostseasonHistory.swift", ["data/League Feeds/Postseason History"], "postseason-history/"),
    ("PostseasonNews.swift", ["data/League Feeds/Postseason News"], "postseason-news/"),
    ("PostseasonStore.swift", ["netlify/functions/postseason.mjs"], "/api/postseason"),
    ("PostseasonScorecardSheet.swift", ["netlify/functions/postseason.mjs"], "/api/postseason"),
    ("TeamSession.swift", ["netlify/functions/postseason.mjs"], "/api/postseason"),
    ("MLBGameClient.swift", ["netlify/functions/mlb-data.mjs"], "/api/mlb/schedule, /api/mlb/game"),
    ("StandingsStore.swift", ["netlify/functions/mlb-data.mjs"], "/api/mlb/standings"),
    ("XPostsStore.swift", ["netlify/functions/x-posts.mjs", "netlify/functions/x-discovery.mjs"],
     "/api/x-posts, /api/x-discovery"),
    ("AppBackend.swift", ["netlify/functions/app-data.mjs"], "/api/data/* (release builds)"),
]

KNOWN_EDGES = [
    ("src/standings.js", "netlify/functions/mlb-data.mjs", "calls", "/api/mlb/standings"),
    ("src/x-posts.js", "netlify/functions/x-posts.mjs", "calls", "/api/x-posts"),
    ("scripts/test_hub_ball.py", "ios/Hub Ball/HubBallTests/ArchitectureTests.swift", "tests",
     "runs Swift Testing target"),
    ("scripts/test_hub_ball.py", "ios/Hub Ball/Hub Ball.xcodeproj/project.pbxproj", "uses", "xcodebuild"),
    ("scripts/test_large_text_ui.sh", "ios/Hub Ball/LargeTextUITests/LargeTextUITests.swift", "tests", ""),
    ("scripts/prepare_large_text_ui_tests.py", "ios/Hub Ball/LargeTextUITests/LargeTextUITests.swift", "uses", ""),
    ("scripts/test_netlify_ignore.sh", "scripts/netlify_ignore.sh", "tests", ""),
    ("scripts/test_recent_game.mjs", "src/recent-game-feed.js", "tests", ""),
    ("scripts/test_schedule.mjs", "src/schedule.js", "tests", ""),
    ("scripts/generate_team_registry.py", IOS + "HubTeam.swift", "generates", "from config/mlb-teams.json"),
    ("scripts/generate_team_registry.py", "netlify/functions/team-registry.mjs", "generates",
     "from config/mlb-teams.json"),
    ("scripts/generate_team_registry.py", "config/mlb-teams.json", "reads", ""),
    ("scripts/team_registry.py", "config/mlb-teams.json", "reads", ""),
    ("scripts/fetch_hitter_story.py", IOS + "MLB300HitterData.swift", "generates", ""),
    ("scripts/fetch_hitter_story.py", IOS + "MLB300HitterPlayers.swift", "generates", ""),
    ("scripts/check_hub_ball_release.py", "config/hub-ball-release.json", "reads", "release manifest"),
    ("scripts/check_hub_ball_release.py", "ios/Hub Ball/Hub Ball.xcodeproj/project.pbxproj", "reads",
     "build numbers"),
    ("scripts/install_hub_ball.sh", "scripts/check_hub_ball_release.py", "uses", "guards install"),
    ("scripts/install_hub_ball.sh", "ios/Hub Ball/Hub Ball.xcodeproj/project.pbxproj", "uses", "xcodebuild"),
    ("scripts/app_store_preflight.py", "app-store/metadata.json", "reads", ""),
    ("scripts/refresh_pitching.py", "config/pitching-refresh.json", "reads", ""),
    ("scripts/story_facts.py", D + "seasons.json", "reads", ""),
    ("scripts/build_single_file.py", "stories/four-roads/story.js", "uses", "inlines story"),
    ("scripts/build_single_file.py", D + "seasons.json", "reads", ""),
    ("scripts/build_site.sh", "index.html", "uses", "copies into _site/"),
    ("scripts/build_site.sh", "src/chart.js", "uses", "copies into _site/"),
    ("scripts/build_site.sh", "stories/four-roads/index.html", "uses", "copies into _site/"),
    ("scripts/build_site.sh", "recent-game/index.html", "uses", "copies into _site/"),
    ("scripts/build_site.sh", "news/index.html", "uses", "copies into _site/"),
    ("scripts/build_site.sh", "data", "uses", "copies data/ into _site/"),
    ("scripts/build_atlas.py", "docs/atlas/template.html", "reads", "embeds the graph into this viewer"),
    ("netlify.toml", "scripts/build_site.sh", "runs", "build command"),
    ("netlify.toml", "scripts/netlify_ignore.sh", "runs", "ignore check"),
    ("package.json", "ext:blobs", "uses", "@netlify/blobs"),
    ("netlify/functions/app-data.mjs", "data", "serves", "/api/data/* → data/"),
]

CONFIG_DESC = {
    "mlb-teams.json": "Source of truth for the 30-team registry; generates HubTeam.swift and team-registry.mjs.",
    "hub-ball-release.json": "Release manifest: the declared current build that check_hub_ball_release.py validates.",
    "pitching-refresh.json": "Plan for the staged MLB pitching refresh.",
}


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=True).stdout


def measure(files: list[str]) -> dict[str, dict]:
    info: dict[str, dict] = {}
    for f in files:
        ext = PurePosixPath(f).suffix.lower()
        path = ROOT / f
        text = ""
        if ext not in BINARY:
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                text = ""
        lines = text.count("\n") + (0 if not text or text.endswith("\n") else 1)
        datafile = ext == ".json" and not any(
            (k in f) if k.endswith("/") else f == k for k in CODE_JSON)
        info[f] = {"bytes": path.stat().st_size, "lines": 0 if datafile else lines, "text": text, "ext": ext,
                   "datafile": datafile}
    return info


def ios_group(f: str) -> list[str]:
    name = PurePosixPath(f).name
    if "/HubBallTests/" in f:
        return ["Unit Tests"]
    if "/LargeTextUITests/" in f:
        return ["Large-Text UI Tests"]
    if ".xcodeproj/" in f or f == "ios/IPAD_REVIEW.md":
        return ["Xcode Project"]
    if "/Fonts/" in f or "Assets.xcassets" in f:
        return ["Fonts & Images"]
    for group, _, prefixes in IOS_FEATURES:
        if name.startswith(tuple(prefixes)):
            return [group]
    return ["Core & Networking"]


def pipeline_group(f: str) -> list[str]:
    name = PurePosixPath(f).name
    if f.startswith("scripts/fixtures/") or name.startswith("test_"):
        return ["Tests"]
    for team, group in (("yankees", "Yankees Fetchers"), ("mets", "Mets Fetchers"), ("rays", "Rays Fetchers")):
        if f"_{team}_" in name:
            return [group]
    if name in RED_SOX_FETCHERS:
        return ["Red Sox Fetchers"]
    if name in SHARED_HELPERS:
        return ["Shared Helpers"]
    if name.startswith(("fetch_", "refresh_", "pitching_publication", "news_publication", "news_source_status",
                        "probe_")):
        return ["League-wide Fetchers"]
    return ["Build, Release & QA"]


def workflow_group(f: str) -> list[str]:
    name = PurePosixPath(f).name
    if f.startswith(".github/news-status/"):
        return ["Status Files"]
    if "news" in name:
        return ["News Refreshers"]
    if "x-posts" in name:
        return ["Social"]
    if "validate" in name:
        return ["Validation"]
    if "atlas" in name:
        return ["Repository Upkeep"]
    if "leaders" in name or name == "refresh-data.yml":
        return ["Seasons & Leaders"]
    if any(k in name for k in ("players", "pitching", "playoff")):
        return ["Players, Pitching & Playoffs"]
    return ["Game & Team Data"]


def data_group(f: str) -> list[str]:
    """Data folders become aggregate leaves ('@leaf:') instead of one node per file."""
    parts = f.split("/")
    if len(parts) == 2:
        return ["Red Sox Feeds"]
    folder = parts[1]
    if folder == "player-careers":
        return ["@leaf:Player Careers"]
    if folder in LEAGUE_DATA_DIRS:
        return ["League Feeds", "@leaf:" + LEAGUE_DATA_DIRS[folder]]
    return ["Team Feeds", "@team:" + folder]


def classify(f: str) -> tuple[str, list[str]]:
    if f.startswith("ios/"):
        return "ios", ios_group(f)
    if f in ("netlify/functions/team-registry.mjs", "netlify/lib/game-narrative.mjs"):
        return "backend", ["Shared Modules"]
    if f.startswith("netlify/functions/"):
        return "backend", ["API Functions"]
    if f in ("netlify.toml", "package.json", "package-lock.json"):
        return "backend", ["Deploy Config"]
    if f.startswith("stories/four-roads/"):
        return "web", ["Stories", "Four Roads, One Record"]
    if f.startswith("stories/war-room/"):
        return "web", ["Stories", "War Room (mockup)"]
    if f.startswith("src/"):
        return "web", ["Shared JS Engine" if f.endswith(".js") else "Styles"]
    if f.startswith("assets/"):
        return "web", ["Fonts"]
    if f == "index.html" or (f.endswith("/index.html") and f.count("/") == 1):
        return "web", ["Pages"]
    if f.startswith("scripts/"):
        return "pipeline", pipeline_group(f)
    if f.startswith(".github/"):
        return "actions", workflow_group(f)
    if f.startswith("data/"):
        return "data", data_group(f)
    if f.startswith("config/") or f == ".gitignore":
        return "docs", ["Config"]
    if f.startswith("Ai/"):
        return "docs", ["AI Review Reports"]
    if f.startswith("app-store/"):
        return "docs", ["App Store"]
    if f in ("AGENTS.md", "CLAUDE.md", "README.md", "docs/PRODUCTS.md"):
        return "docs", ["Project Guides"]
    return "docs", ["Design & Plans"]


def leading_description(text: str, ext: str) -> str:
    """The file's own summary: a module docstring, heading, <title>, or leading comment."""
    if not text:
        return ""
    lines = text.splitlines()[:40]
    if ext == ".py":
        m = re.search(r'^\s*(?:#![^\n]*\n)?(?:#[^\n]*\n)*\s*(?:"""|\'\'\')\s*(.+?)(?:\n\s*\n|"""|\'\'\')',
                      text, re.S)
        return " ".join(m.group(1).split()) if m else ""
    if ext == ".md":
        heading = next((ln.lstrip("# ").strip() for ln in lines if ln.startswith("#")), "")
        para = next((ln.strip() for ln in lines
                     if ln.strip() and not ln.startswith(("#", "|", "-", "`", "<", ">", "!"))), "")
        return f"{heading} — {para}" if heading and para else heading or para
    if ext == ".html":
        m = re.search(r"<title>([^<]*)", text)
        return "Page: " + m.group(1).strip() if m else ""
    if ext in (".yml", ".yaml"):
        name = re.search(r"^name:\s*(.+)$", text, re.M)
        crons = re.findall(r"cron:\s*'([^']+)'", text)
        desc = name.group(1).strip().strip("'\"") if name else ""
        return desc + (f" (cron {', '.join(crons)} UTC)" if crons else "")
    if ext not in (".swift", ".js", ".mjs", ".css", ".sh", ".toml"):
        return ""
    out: list[str] = []
    for line in lines:
        s = line.strip()
        if s.startswith("#!") or (not s and not out):
            continue
        if s.startswith(("///", "//", "#", "/*", "*")):
            comment = re.sub(r"^(///|//|#|/\*+|\*/|\*)\s?", "", s).rstrip("*/ ").strip()
            if comment and not re.match(r"(import|set -|Created by|Copyright|swiftlint)", comment):
                out.append(comment)
                if len(" ".join(out)) > 180:
                    break
                continue
        if out or (s and not s.startswith(("import", "@", "use ", "'use", "set "))):
            break
    return " ".join(out)


def swift_role(name: str) -> str:
    if re.search(r"(View|Sheet|Chart)\.swift$", name):
        return "SwiftUI view"
    if name.endswith("Store.swift"):
        return "Observable store"
    if name.startswith("test_") or name.endswith("Tests.swift"):
        return "Swift test"
    return "Model / logic"


def strip_swift(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)


def fallback_description(f: str, item: dict, node: dict) -> str:
    kb = item["bytes"] / 1024
    text = item["text"]
    if item["datafile"]:
        where = (" bundled into the app." if f.startswith(IOS) else
                 " used as a test fixture." if "ixtures" in f else ".")
        return f"JSON data file ({kb:,.0f} KB){where}"
    if f.endswith((".mjs", ".js")):
        route = re.search(r"path:\s*(\[[^\]]*\]|'[^']*')", text)
        exports = re.findall(r"export\s+(?:async\s+)?(?:function|const|class)\s+(\w+)", text)
        parts = []
        if route:
            parts.append("Netlify function serving " + route.group(1).replace("'", ""))
        if exports:
            parts.append("exports " + ", ".join(exports[:6]))
        return ("; ".join(parts) or "JavaScript module") + "."
    if f.endswith(".css"):
        return "Styles for the " + PurePosixPath(f).stem.replace("-", " ") + " page."
    if f.endswith(".sh"):
        return "Shell script."
    if item["ext"] in BINARY:
        return f"Binary asset ({kb:,.0f} KB)."
    if f.endswith((".plist", ".xcprivacy")):
        return "Property list: app metadata / privacy manifest."
    if f.endswith(".pbxproj"):
        return "Xcode project definition: targets, build settings, build numbers."
    if f.startswith("config/"):
        return CONFIG_DESC.get(PurePosixPath(f).name, "Configuration file.")
    return ""


class Atlas:
    def __init__(self, files: list[str], info: dict[str, dict]) -> None:
        self.files = files
        self.info = info
        self.nodes: dict[str, dict] = {}
        self.file_node: dict[str, str] = {}
        self.edges: dict[tuple[str, str, str], dict] = defaultdict(lambda: {"w": 0, "labels": set()})
        self.swift_types: dict[str, str] = {}

    def add_node(self, nid: str, **fields: object) -> dict:
        if nid not in self.nodes:
            self.nodes[nid] = {"id": nid, "children": [], "lines": 0, "bytes": 0, "files": 0,
                               **{k: v for k, v in fields.items() if v is not None}}
        return self.nodes[nid]

    def edge(self, src: str, dst: str, kind: str, label: str = "", weight: int = 1) -> None:
        s = self.file_node.get(src, src)
        d = self.data_target(dst)
        if s == d or s not in self.nodes or d not in self.nodes:
            return
        entry = self.edges[(s, d, kind)]
        entry["w"] += weight
        if label:
            entry["labels"].add(label)

    def data_target(self, target: str) -> str:
        if target in self.file_node:
            return self.file_node[target]
        parts = target.split("/")
        if len(parts) == 2 and parts[0] == "data" and f"data/Team Feeds/{parts[1]}" in self.nodes:
            return f"data/Team Feeds/{parts[1]}"
        return target

    def build_hierarchy(self) -> None:
        for key, name, desc in SYSTEMS:
            self.add_node(key, name=name, kind="system", sys=key, parent=None, desc=desc)
        for f in self.files:
            system, groups = classify(f)
            parent, leaf = system, None
            for group in groups:
                if group.startswith("@team:"):
                    folder = group[6:]
                    pretty = folder.replace("bluejays", "blue jays").replace("whitesox", "white sox").title()
                    label, name, desc = folder, pretty, f"Generated feeds for the {pretty} (data/{folder}/)."
                    path, kind = f"data/{folder}/", "leafgroup"
                elif group.startswith("@leaf:"):
                    label = name = group[6:]
                    desc, path, kind = GROUP_DESC.get(label, ""), "/".join(f.split("/")[:2]) + "/", "leafgroup"
                else:
                    label = name = group
                    desc, path, kind = GROUP_DESC.get(label, ""), None, "group"
                gid = f"{parent}/{label}"
                self.add_node(gid, name=name, kind=kind, sys=system, parent=parent, desc=desc, path=path)
                if gid not in self.nodes[parent]["children"]:
                    self.nodes[parent]["children"].append(gid)
                parent = gid
                if kind == "leafgroup":
                    leaf = gid
            if leaf:
                self.file_node[f] = leaf
                self.nodes[leaf].setdefault("filelist", []).append(f)
                continue
            nid = "f:" + f
            self.add_node(nid, name=PurePosixPath(f).name, kind="file", sys=system, parent=parent, path=f,
                          ext=self.info[f]["ext"], url=GITHUB_BLOB + f.replace(" ", "%20"))
            self.nodes[parent]["children"].append(nid)
            self.file_node[f] = nid
        for key, (name, desc) in EXTERNALS.items():
            self.add_node("ext:" + key, name=name, kind="file", sys="external", parent="external", desc=desc,
                          ext="ext")
            self.nodes["external"]["children"].append("ext:" + key)

    def roll_up_sizes(self) -> None:
        for f, nid in self.file_node.items():
            item, node = self.info[f], self.nodes[nid]
            if item["ext"] in BINARY:
                node["binary"] = True
            if item["datafile"]:
                node["datafile"] = True
            cur: str | None = nid
            while cur:
                self.nodes[cur]["lines"] += item["lines"]
                self.nodes[cur]["bytes"] += item["bytes"]
                self.nodes[cur]["files"] += 1
                cur = self.nodes[cur].get("parent")

    def scan_swift(self) -> None:
        swift = [f for f in self.files if f.endswith(".swift")]
        stripped = {f: strip_swift(self.info[f]["text"]) for f in swift}
        for f in swift:
            for m in re.finditer(r"\b(?:class|struct|enum|actor|protocol|typealias)\s+([A-Z]\w+)", stripped[f]):
                self.swift_types.setdefault(m.group(1), f)
        for f in swift:
            refs: dict[str, set[str]] = defaultdict(set)
            counts: dict[str, int] = defaultdict(int)
            for token in re.findall(r"\b[A-Z]\w+\b", stripped[f]):
                target = self.swift_types.get(token)
                if target and target != f:
                    counts[target] += 1
                    refs[target].add(token)
            kind = "tests" if "/HubBallTests/" in f or "/LargeTextUITests/" in f else "uses"
            for target, count in counts.items():
                self.edge(f, target, kind, ", ".join(sorted(refs[target])[:6]), count)

    def resolve(self, base: str, ref: str) -> str | None:
        ref = ref.split("?")[0].split("#")[0]
        if not ref or ref.startswith(("http", "//", "data:", "mailto")):
            return None
        path = ref.lstrip("/") if ref.startswith("/") else os.path.normpath(os.path.join(os.path.dirname(base), ref))
        if path in self.info:
            return path
        if path + "/index.html" in self.info:
            return path + "/index.html"
        return None

    def scan_javascript(self) -> None:
        for f in self.files:
            if self.info[f]["ext"] not in (".js", ".mjs", ".html"):
                continue
            text = self.info[f]["text"]
            is_test = PurePosixPath(f).name.startswith("test_")
            pattern = (r"""(?:from\s+|import\s*\(\s*|src=|href=|fetch\(\s*|fetchJSON\(\s*|"""
                       r"""readFile\(\s*new URL\(\s*)['"]([^'"]+)['"]""")
            for m in re.finditer(pattern, text):
                target = self.resolve(f, m.group(1))
                if target:
                    self.edge(f, target, "tests" if is_test else "reads" if target.startswith("data/") else "uses")
            for m in re.finditer(r"""['"`](\.\./[^'"`]*data/[A-Za-z0-9_./-]+\.json)""", text):
                target = self.resolve(f, m.group(1))
                if target:
                    self.edge(f, target, "reads")
            for m in re.finditer(r"""['"`]((?:\.\./)+src/[A-Za-z0-9_.-]+\.js)""", text):
                target = self.resolve(f, m.group(1))
                if target:
                    self.edge(f, target, "tests" if is_test else "uses")
            lower = text.lower()
            for needle, ext, label in (("statsapi.mlb.com", "ext:mlb", "statsapi.mlb.com"),
                                       ("api.x.com", "ext:x", "X API"),
                                       ("@netlify/blobs", "ext:blobs", "@netlify/blobs")):
                if needle in lower:
                    self.edge(f, ext, "calls", label)

    def scan_python(self) -> None:
        modules = {PurePosixPath(f).stem: f for f in self.files if f.startswith("scripts/") and f.endswith(".py")}
        for stem, f in modules.items():
            text = self.info[f]["text"]
            is_test = stem.startswith("test_")
            for m in re.finditer(r"^\s*(?:from|import)\s+([a-z_]+)", text, re.M):
                target = modules.get(m.group(1))
                if target and target != f:
                    self.edge(f, target, "tests" if is_test else "uses")
            # This generator names every upstream in its own tables; it calls none of them.
            if is_test or f == "scripts/build_atlas.py":
                continue
            for needle, ext in PYTHON_UPSTREAMS:
                if needle in text:
                    self.edge(f, ext, "calls", needle)
            if re.search(r"https?://[^\s'\"]*(masslive|nytimes|theathletic|news\.google|/rss|/feed)", text):
                self.edge(f, "ext:rss", "calls", "RSS")
        for f in self.files:
            if f.startswith("scripts/test_") and f.endswith(".sh") and "test_hub_ball.py" in self.info[f]["text"]:
                self.edge(f, "scripts/test_hub_ball.py", "tests", "delegates")

    def scan_workflows(self) -> None:
        for f in self.files:
            if not f.startswith(".github/workflows/"):
                continue
            text = self.info[f]["text"]
            scripts = set(re.findall(r"scripts/([A-Za-z0-9_]+\.(?:py|sh|mjs))", text))
            scripts |= set(re.findall(r"-p '([A-Za-z0-9_]+\.py)'", text))
            for script in scripts:
                self.edge(f, "scripts/" + script, "runs")

    def add_known_edges(self) -> None:
        for script, targets in SCRIPT_WRITES.items():
            for target in targets:
                self.edge("scripts/" + script, target, "writes")
        for source, targets, label in APP_ENDPOINTS:
            for target in targets:
                self.edge(IOS + source, target, "calls" if target.startswith("netlify/") else "reads", label)
        for src, dst, kind, label in KNOWN_EDGES:
            self.edge(src, dst, kind, label)

    def describe(self) -> None:
        types_in: dict[str, list[str]] = defaultdict(list)
        for name, f in self.swift_types.items():
            types_in[f].append(name)
        for f, nid in self.file_node.items():
            node = self.nodes[nid]
            if node["kind"] != "file":
                continue
            item = self.info[f]
            desc = leading_description(item["text"], item["ext"])
            if f.endswith(".swift"):
                node["role"] = swift_role(node["name"])
                node["types"] = types_in.get(f, [])[:12]
                if not desc:
                    names = types_in.get(f, [])[:5]
                    desc = node["role"] + (" declaring " + ", ".join(names) if names else "") + "."
            desc = desc or fallback_description(f, item, node)
            node["desc"] = desc if len(desc) <= 260 else desc[:257].rsplit(" ", 1)[0] + "…"

    def build(self) -> dict:
        self.build_hierarchy()
        self.roll_up_sizes()
        self.scan_swift()
        self.scan_javascript()
        self.scan_python()
        self.scan_workflows()
        self.add_known_edges()
        self.describe()
        for node in self.nodes.values():
            if len(node.get("filelist", [])) > 40:
                node["filecount_hidden"] = len(node["filelist"]) - 40
                node["filelist"] = sorted(node["filelist"])[:40]
        return {
            "generated": git("log", "-1", "--format=%h %cI").strip(),
            "systems": [key for key, _, _ in SYSTEMS],
            "nodes": list(self.nodes.values()),
            "edges": [{"s": s, "t": t, "type": kind, "w": v["w"], "label": "; ".join(sorted(v["labels"]))[:160]}
                      for (s, t, kind), v in self.edges.items()],
        }


def build_graph() -> dict:
    files = [f for f in git("ls-files", "-z").split("\0") if f and f not in EXCLUDED and (ROOT / f).is_file()]
    return Atlas(files, measure(files)).build()


def render(graph: dict) -> str:
    payload = json.dumps(graph, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
    template = TEMPLATE.read_text(encoding="utf-8")
    if "__GRAPH__" not in template:
        raise SystemExit(f"{TEMPLATE} is missing the __GRAPH__ placeholder")
    return template.replace("__GRAPH__", payload)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--json", metavar="PATH", help="write the graph JSON to PATH ('-' for stdout) instead")
    args = parser.parse_args()
    graph = build_graph()
    if args.json:
        text = json.dumps(graph, indent=1, ensure_ascii=False)
        if args.json == "-":
            sys.stdout.write(text + "\n")
        else:
            Path(args.json).write_text(text + "\n", encoding="utf-8")
        return
    OUTPUT.write_text(render(graph), encoding="utf-8")
    systems = {n["id"]: n for n in graph["nodes"] if n["kind"] == "system"}
    code = sum(n["lines"] for n in systems.values())
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {code:,} lines of code, "
          f"{systems['data']['bytes'] / 1_048_576:.0f} MB data, {len(graph['nodes'])} parts, "
          f"{len(graph['edges'])} connections")


if __name__ == "__main__":
    main()
