"""Shared read-only NFL GOAT client. Credentials never enter generated output."""
from __future__ import annotations

import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parents[1]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('BALLDONTLIE redirect refused')


def api_key() -> str:
    key = os.environ.get('BALLDONTLIE_API_KEY', '')
    if not key:
        try:
            key = next((s.split('=', 1)[1].strip().strip('\"\'') for s in
                        (ROOT / '.env').read_text().splitlines() if s.startswith('BALLDONTLIE_API_KEY=')), '')
        except OSError:
            pass
    if not key or any(ord(c) < 33 or ord(c) >= 127 for c in key):
        raise RuntimeError('Missing local BALLDONTLIE_API_KEY; value not printed')
    return key


class NFLClient:
    def __init__(self) -> None:
        self.key = api_key()
        self.next_start = 0.0
        self.opener = build_opener(NoRedirect())
        self.responses: dict[str, dict] = {}

    def get(self, route: str) -> dict:
        if not route.startswith('/nfl/v1/') or '..' in route:
            raise ValueError('Invalid NFL route')
        for attempt in range(3):
            time.sleep(max(0, self.next_start - time.monotonic()))
            self.next_start = time.monotonic() + .25
            try:
                request = Request('https://api.balldontlie.io' + route,
                                  headers={'Authorization': self.key, 'User-Agent': 'HubBallLab/0.1', 'Accept': 'application/json'})
                with self.opener.open(request, timeout=30) as response:
                    payload = json.load(response)
                if 'data' not in payload:
                    raise RuntimeError('NFL response missing data')
                self.responses[route] = payload
                return payload
            except HTTPError as exc:
                if exc.code == 429:
                    raise RuntimeError('NFL rate limit reached; stop and retry after 65 seconds') from None
                if exc.code < 500 or attempt == 2:
                    raise RuntimeError(f'NFL HTTP {exc.code} on {route}') from None
            except (URLError, TimeoutError):
                if attempt == 2:
                    raise RuntimeError(f'NFL request failed on {route}') from None
            time.sleep(2 ** attempt)
        raise RuntimeError('NFL request failed')

    def pages(self, route: str) -> list[dict]:
        rows, seen, cursor = [], set(), None
        while True:
            separator = '&' if '?' in route else '?'
            page = self.get(route + (f'{separator}cursor={cursor}' if cursor is not None else ''))
            if not isinstance(page['data'], list):
                raise ValueError('Expected NFL array')
            rows.extend(page['data'])
            cursor = page.get('meta', {}).get('next_cursor')
            if cursor is None:
                return rows
            if cursor in seen or len(seen) >= 100:
                raise ValueError('Invalid NFL pagination')
            seen.add(cursor)
