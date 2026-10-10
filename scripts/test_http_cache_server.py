#!/usr/bin/env python3
"""Small dependency-free HTTP origin used by the Swift cache integration test."""

from __future__ import annotations

import json
import sys
import threading
import time
from email.utils import formatdate
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


class FixtureState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.live = False
        self.version = 1
        self.fail_discovery = False
        self.fail_game = False
        self.game_requests = 0
        self.schedule_requests = 0
        self.story_redirect_hits = 0
        self.trajectory_mode = "reset"


STATE = FixtureState()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)

        if parsed.path == '/beta-fixture/releases/testflight-v1.json':
            now = datetime.now(timezone.utc)
            self.send_json({'schemaVersion': 1, 'bundleID': 'com.sfrancoe.HubBall', 'enabled': True, 'target': {
                'version': '1.1', 'build': 9999, 'audience': 'all-supported-testers', 'available': True,
                'confirmedAt': now.strftime('%Y-%m-%dT%H:%M:%SZ'), 'expiresAt': (now + timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ'),
                'minimumOS': '17.0', 'deviceFamilies': ['iphone', 'ipad'],
                'verifiedGroupIDs': ['a7c07355-b794-49b9-b36d-75c129c8d6bb', '58b84a1e-c8ab-4b73-9948-3362b4569fd1']
            }}, 'no-store')
            return

        if parsed.path == '/story-fixture/stories/catalog-v1.json':
            self.send_response(302)
            self.send_header('Location', '/story-fixture/redirect-target')
            self.send_header('Content-Length', '0')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            return
        if parsed.path == '/story-fixture/redirect-target':
            with STATE.lock: STATE.story_redirect_hits += 1
            self.send_json({'schemaVersion': 1, 'revision': 'redirect', 'publishedAt': '2026-10-08T11:00:00Z', 'stories': []}, 'no-store')
            return
        if parsed.path == '/story-fixture/stats':
            with STATE.lock: hits = STATE.story_redirect_hits
            self.send_json({'redirectHits': hits}, 'no-store')
            return
        if parsed.path == '/story-fixture-good/stories/catalog-v1.json':
            self.send_json(json.loads((Path(__file__).resolve().parents[1] / 'data/stories/catalog-v1.json').read_text()), 'no-store')
            return

        if parsed.path == '/trajectory-fixture-control':
            with STATE.lock: STATE.trajectory_mode = query.get('mode', ['reset'])[0]
            self.send_json({'ok': True}, 'no-store'); return
        if parsed.path.startswith('/trajectory-fixture/stories/'):
            app = Path(__file__).resolve().parents[1] / 'ios/Hub Ball/Hub Ball'
            catalog = json.loads((app / 'story-catalog.json').read_text())
            with STATE.lock: mode = STATE.trajectory_mode
            if mode == 'offline': self.send_json({'offline': True}, 'no-store', status=503); return
            if parsed.path.endswith('/catalog-v1.json'):
                if mode == 'reset': catalog['stories'] = [e for e in catalog['stories'] if e['renderer'] == 'guess-reveal']
                self.send_json(catalog, 'no-store'); return
            entry = next((e for e in catalog['stories'] if parsed.path == '/trajectory-fixture/' + f"stories/{e['id']}/{e['revision']}.json"), None)
            if entry:
                body = (app / f"story-seed-{entry['id']}.json").read_bytes()
                self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Cache-Control', 'no-store'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body); return
            self.send_json({'error': 'not found'}, 'no-store', status=404); return

        if parsed.path == "/control":
            with STATE.lock:
                STATE.live = query.get("live", ["0"])[0] == "1"
                STATE.version = int(query.get("version", ["1"])[0])
                STATE.fail_discovery = query.get("failDiscovery", ["0"])[0] == "1"
                STATE.fail_game = query.get("failGame", ["0"])[0] == "1"
            self.send_json({"ok": True}, "no-store")
            return

        if parsed.path == "/stats":
            with STATE.lock:
                body = {
                    "gameRequests": STATE.game_requests,
                    "scheduleRequests": STATE.schedule_requests,
                }
            self.send_json(body, "no-store")
            return

        if parsed.path.endswith("/mlb/schedule"):
            with STATE.lock:
                STATE.schedule_requests += 1
                fail = STATE.fail_discovery
                live = STATE.live
            if fail:
                self.send_json({"error": "fixture discovery failure"}, "no-store", status=503)
                return
            status = {
                "abstractGameState": "Live" if live else "Final",
                "codedGameState": "I" if live else "F",
            }
            self.send_json({
                "dates": [{"games": [{
                    "gamePk": 9010,
                    "gameDate": "2026-09-18T23:00:00Z",
                    "status": status,
                }]}],
            }, "no-store")
            return

        if parsed.path.endswith("/mlb/game"):
            with STATE.lock:
                STATE.game_requests += 1
                fail = STATE.fail_game
                live = STATE.live
                version = STATE.version
            if fail:
                self.send_json({"error": "fixture game failure"}, "public, max-age=1", status=503)
                return
            self.send_json(game_payload(live=live, version=version), "public, max-age=5")
            return

        if "/data/" in parsed.path and parsed.path.endswith("schedule.json"):
            self.send_json({
                "generated_at": "fixture",
                "regular_season_end": "2026-09-27",
                "source": "test",
                "team": "Boston",
                "games": [],
            }, "no-store")
            return

        self.send_json({"error": "not found"}, "no-store", status=404)

    def send_json(self, payload: object, cache_control: str, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", cache_control)
        if cache_control.startswith("public"):
            self.send_header("Expires", formatdate(time.time() + 5, usegmt=True))
            self.send_header("Last-Modified", formatdate(time.time(), usegmt=True))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def game_payload(*, live: bool, version: int) -> dict[str, object]:
    abstract = "Live" if live else "Final"
    code = "I" if live else "F"
    venue = f"Fenway {'live' if live else 'final'} {version}"
    team = {
        "id": 111,
        "name": "Boston Red Sox",
        "abbreviation": "BOS",
        "record": {"leagueRecord": {"wins": 80, "losses": 70}},
    }
    opponent = {
        "id": 147,
        "name": "New York Yankees",
        "abbreviation": "NYY",
        "record": {"leagueRecord": {"wins": 75, "losses": 75}},
    }
    line_team = {"runs": 3, "hits": 5, "errors": 0, "leftOnBase": 4}
    line_opponent = {"runs": 2, "hits": 4, "errors": 1, "leftOnBase": 5}
    empty_box = {"batters": [], "battingOrder": [], "pitchers": [], "players": {}}
    return {
        "gamePk": 9010,
        "gameData": {
            "status": {"abstractGameState": abstract, "codedGameState": code},
            "datetime": {"dateTime": "2026-09-18T23:00:00Z"},
            "venue": {"name": venue},
            "gameInfo": {"gameDurationMinutes": 180, "attendance": 30000},
            "teams": {"away": team, "home": opponent},
        },
        "liveData": {
            "linescore": {"teams": {"away": line_team, "home": line_opponent}, "innings": []},
            "boxscore": {"teams": {"away": empty_box, "home": empty_box}},
            "plays": {"allPlays": [], "scoringPlays": []},
            "decisions": {},
        },
    }


def main() -> None:
    ready_file = Path(sys.argv[1])
    # Bind to all local interfaces so an iOS Simulator can reach this
    # dependency-free fixture through the host's LAN address.
    server = ThreadingHTTPServer(("0.0.0.0", 0), Handler)
    ready_file.write_text(str(server.server_port), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
