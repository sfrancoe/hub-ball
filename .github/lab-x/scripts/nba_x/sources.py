"""Swappable X list sources. The unofficial adapter is private-lab only."""
from __future__ import annotations

import json
import os
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from html.parser import HTMLParser
from typing import Protocol
from urllib.error import HTTPError
from urllib.request import Request, urlopen

USER_AGENT = 'HubBallLab/0.1 (private prototype)'


class RateLimitError(RuntimeError):
    """The upstream quota is exhausted; leave remaining teams for a later run."""


def require_lab() -> None:
    if os.environ.get('HUB_LAB_ALLOW_UNOFFICIAL_X') != '1':
        raise RuntimeError('Set HUB_LAB_ALLOW_UNOFFICIAL_X=1 for private Lab research')


def fetch(url: str) -> bytes:
    error = None
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers={'User-Agent': USER_AGENT}), timeout=30) as response:
                return response.read()
        except (OSError, TimeoutError) as exc:
            if isinstance(exc, HTTPError) and exc.code == 429:
                retry_after = exc.headers.get('Retry-After') if exc.headers else None
                detail = f" (Retry-After: {retry_after})" if retry_after else ""
                raise RateLimitError(f'HTTP 429: upstream rate limit{detail}') from exc
            error = exc
            if attempt < 2:
                time.sleep(2 ** attempt)
    raise RuntimeError(f'Could not fetch {url}: {error}')


class XSource(Protocol):
    kind: str
    def list_posts(self, list_id: str) -> list[dict]: ...


class NextDataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.reading = False
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == 'script' and dict(attrs).get('id') == '__NEXT_DATA__':
            self.reading = True

    def handle_endtag(self, tag: str) -> None:
        if tag == 'script':
            self.reading = False

    def handle_data(self, data: str) -> None:
        if self.reading:
            self.parts.append(data)


class SyndicationLabSource:
    kind = 'syndication-lab'

    def list_posts(self, list_id: str) -> list[dict]:
        require_lab()
        if list_id != 'mlb-clubs' and (not isinstance(list_id, str) or not list_id.isascii() or not list_id.isdigit()):
            raise ValueError('List ID must be a string of digits')
        route = 'screen-name/MLB/slug/clubs' if list_id == 'mlb-clubs' else 'list-id/' + list_id
        url = ('https://syndication.twitter.com/srv/timeline-list/' + route
               + '?lang=en&theme=light&showHeader=false&hideBorder=true')
        parser = NextDataParser()
        parser.feed(fetch(url).decode('utf-8', errors='replace'))
        if not parser.parts:
            raise RuntimeError('X list response did not contain timeline data')
        try:
            entries = json.loads(''.join(parser.parts))['props']['pageProps']['timeline']['entries']
            if not isinstance(entries, list):
                raise ValueError('entries is not a list')
            return [e['content']['tweet'] for e in entries if isinstance(e, dict)
                    and isinstance(e.get('content'), dict) and isinstance(e['content'].get('tweet'), dict)]
        except (KeyError, TypeError, ValueError) as exc:
            raise RuntimeError(f'Invalid X timeline response: {exc}') from exc


class XApiSource:
    kind = 'x-api'

    def list_posts(self, list_id: str) -> list[dict]:
        raise NotImplementedError("Paid source: requires Scott's approval and budget guardrails. See plan Section 7.")


class BrowserCaptureLabSource:
    """One-time bootstrap from observed public List DOM, with honest provenance/time."""
    kind = 'browser-lab'

    def __init__(self, path: Path) -> None:
        require_lab()
        self.capture = json.loads(path.read_text())
        self.observed_at = datetime.fromisoformat(self.capture['observed_at'].replace('Z', '+00:00'))
        if self.observed_at.tzinfo is None or self.observed_at > datetime.now(timezone.utc):
            raise ValueError('Capture must have a past, timezone-aware observation time')

    def list_posts(self, list_id: str) -> list[dict]:
        require_lab()
        if self.capture['source_url'] != f'https://x.com/i/lists/{list_id}':
            raise ValueError('Capture does not match the configured public List')
        tweets = self.capture['tweets']
        if not isinstance(tweets, list) or not tweets:
            raise ValueError('Capture must contain observed posts')
        # DOM time elements are exported as UTC strings, not Twitter API dates.
        return [dict(tweet, created_at=parsedate_to_datetime(tweet['created_at']).strftime('%a %b %d %H:%M:%S %z %Y'))
                for tweet in tweets]
