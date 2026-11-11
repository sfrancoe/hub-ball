#!/usr/bin/env python3
"""Build private Lab social snapshots; never overwrite a good feed with an empty one."""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from html import unescape
from pathlib import Path
from filter import relevant
from rosters import roster_terms
from mlb import CLUBS_SOURCE, configured_teams, source_url
from sources import BrowserCaptureLabSource, RateLimitError, SyndicationLabSource, require_lab

ROOT = Path(__file__).resolve().parents[2]
RATE_LIMIT_EXIT = 75


def clean(value: object) -> str:
    return re.sub(r'\s+', ' ', unescape(value if isinstance(value, str) else '')).strip()


def normalize(tweet: dict) -> dict | None:
    user = tweet.get('user') or {}
    text, handle, post_id = clean(tweet.get('full_text') or tweet.get('text')), clean(user.get('screen_name')), clean(tweet.get('id_str'))
    if not text or not re.fullmatch(r'[A-Za-z0-9_]{1,15}', handle) or not re.fullmatch(r'[0-9]+', post_id):
        return None
    try:
        published = datetime.strptime(clean(tweet.get('created_at')), '%a %b %d %H:%M:%S %z %Y').isoformat()
    except ValueError:
        return None
    likes = tweet.get('favorite_count')
    if not isinstance(likes, int) or isinstance(likes, bool) or likes < 0:
        likes = None
    quoted = tweet.get('quoted_status') or {}
    quoted_user = quoted.get('user') or {}
    media = (tweet.get('extended_entities') or {}).get('media') or []
    return {'id': post_id, 'text': text, 'url': f'https://x.com/{handle}/status/{post_id}',
            'published': published, 'likes': likes, 'author': clean(user.get('name')) or handle,
            'handle': handle, 'avatar': clean(user.get('profile_image_url_https')),
            'media': clean(media[0].get('media_url_https')) if media else '',
            'quoted_text': clean(quoted.get('full_text') or quoted.get('text')),
            'quoted_author': clean(quoted_user.get('name')), 'quoted_handle': clean(quoted_user.get('screen_name'))}


def make_feed(team: dict, list_id: str, source: object, tweets: list[dict], roster: set[str], now: datetime) -> dict | None:
    posts, seen = [], set()
    for tweet in tweets:
        if not relevant(tweet, team['x'], roster):
            continue
        post = normalize(tweet)
        if post and post['id'] not in seen:
            seen.add(post['id'])
            posts.append(post)
    if not posts:
        return None
    posts.sort(key=lambda p: p['published'], reverse=True)
    cutoff = now - timedelta(hours=24)
    popular = [p for p in posts if p['likes'] is not None and cutoff <= datetime.fromisoformat(p['published']) <= now]
    popular.sort(key=lambda p: (p['likes'], p['published']), reverse=True)
    stamp = now.isoformat()
    return {'generated_at': stamp, 'source': 'X', 'source_kind': source.kind,
            'source_url': source_url(team, list_id), 'team_id': team['id'],
            'sport': team.get('sportID', 'NBA').lower(),
            'likes_as_of': stamp, 'recent': posts[:24], 'popular': popular[:12]}


def save_feed(path: Path, feed: dict | None) -> bool:
    if feed is None:
        print(f'WARNING: no matching posts; kept previous snapshot at {path}')
        return False
    try:
        old = json.loads(path.read_text())
    except (OSError, ValueError):
        old = {}
    # A successful fetch is fresh even when the posts/counts have not changed.
    # Persist its verification time so an unchanged feed cannot monopolize quota.
    if old == feed:
        print(f'Unchanged: {path}')
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(feed, indent=2, ensure_ascii=False) + '\n')
    return True


def refresh_priority(team: dict, data_dir: Path, shared: str | None) -> tuple[bool, datetime, str]:
    """Give missing/newly mapped and older feeds first access to the upstream quota."""
    oldest = datetime.min.replace(tzinfo=timezone.utc)
    try:
        feed = json.loads((data_dir / team['abbreviation'] / 'x-feed.json').read_text())
        expected = source_url(team, team['x']['list_id'] or shared)
        stamp = datetime.fromisoformat(feed['generated_at'])
        if stamp.tzinfo is None:
            stamp = oldest
        return feed.get('source_url') == expected, stamp, team['abbreviation']
    except (OSError, ValueError, KeyError, TypeError):
        return False, oldest, team['abbreviation']


def scheduled_sports(month: int) -> list[str]:
    # Offseason trades and roster news still matter; all four leagues run year-round.
    return ['mlb', 'nba', 'nfl', 'nhl']


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--team')
    group.add_argument('--all', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--sport', choices=['mlb', 'nba', 'nfl', 'nhl', 'all'], default='nba',
                        help='all shares one oldest-first queue across active leagues')
    parser.add_argument('--capture', type=Path, help='Bootstrap one team from an observed public List capture')
    parser.add_argument('--data-dir', type=Path, default=None, help='Sport directory, or parent data directory with --sport all')
    args = parser.parse_args()
    if args.capture and not args.team:
        parser.error('--capture requires --team')
    if args.sport == 'all' and args.team:
        parser.error('--sport all requires --all')
    require_lab()
    sports = scheduled_sports(datetime.now(timezone.utc).month) if args.sport == 'all' else [args.sport]
    tasks = []
    for sport in sports:
        teams = configured_teams(ROOT) if sport == 'mlb' else json.loads((ROOT / f'config/{sport}-teams.json').read_text())
        teams = [team for team in teams if team.get('x')]
        if args.team:
            teams = [t for t in teams if t['abbreviation'].upper() == args.team.upper()]
        shared = json.loads((ROOT / 'config/nba-x.json').read_text())['nba_teams_list_id'] if sport == 'nba' else None
        if sport == 'mlb':
            shared = CLUBS_SOURCE
        data_dir = ((args.data_dir or ROOT / 'data') / sport if args.sport == 'all'
                    else args.data_dir or ROOT / 'data' / sport)
        tasks.extend((team, data_dir, shared) for team in teams)
    if not tasks and args.all:
        print(f'{args.sport.upper()}: no verified public Lists configured; no requests made')
        return 0
    if not tasks:
        parser.error('Unknown team abbreviation (use registry abbreviations, e.g. NY)')
    if args.all:
        tasks.sort(key=lambda task: refresh_priority(*task))
    source = BrowserCaptureLabSource(args.capture) if args.capture else SyndicationLabSource()
    list_cache = {}
    failures = 0
    for index, (team, data_dir, shared) in enumerate(tasks):
        abbr = team['abbreviation']
        list_id = team['x']['list_id'] or shared
        if not list_id or (not team['x']['list_id'] and not team['x']['handle']):
            print(f'WARNING: {abbr}: missing List ID or confirmed official handle; kept previous snapshot')
            failures += 1
            continue
        try:
            if list_id not in list_cache:
                list_cache[list_id] = source.list_posts(list_id)
            roster = roster_terms(team, data_dir / abbr / 'roster.json', args.dry_run) if team['x']['list_id'] else set()
            observed_at = source.observed_at if isinstance(source, BrowserCaptureLabSource) else datetime.now(timezone.utc)
            feed = make_feed(team, list_id, source, list_cache[list_id], roster, observed_at)
            if not feed:
                print(f'WARNING: {abbr}: zero matching posts; kept previous snapshot')
                failures += 1
                continue
            print(f"{team.get('sportID', 'NBA')} {abbr}: {len(feed['recent'])} recent, {len(feed['popular'])} popular")
            if args.dry_run:
                for post in feed['recent'][:3]:
                    print(f"  @{post['handle']} ({post['published']}): {post['text']}\n    {post['url']}")
            else:
                save_feed(data_dir / abbr / 'x-feed.json', feed)
        except RateLimitError as exc:
            print(f'WARNING: {abbr}: {exc}; kept previous snapshots. '
                  f'Deferred {len(tasks) - index} teams until the next scheduled refresh.', file=sys.stderr)
            return RATE_LIMIT_EXIT
        except (RuntimeError, ValueError, OSError, KeyError, TypeError) as exc:
            print(f'WARNING: {abbr}: {exc}; kept previous snapshot', file=sys.stderr)
            failures += 1
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
