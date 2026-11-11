#!/usr/bin/env python3
"""Audit all 124 Lab snapshots; published mode reads static JSON, never X APIs."""
import argparse
import concurrent.futures
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.request import urlopen
from mlb import CLUBS_SOURCE, configured_teams, source_url

ROOT = Path(__file__).resolve().parents[2]
PUBLIC_ROOT = 'https://raw.githubusercontent.com/sfrancoe/hub-ball/lab-data/nba-x/data'


def check_feed(feed, team, expected, now, max_age_hours):
    errors = []
    if feed.get('sport') != team.get('sportID', 'NBA').lower() or feed.get('team_id') != team['id']:
        errors.append('wrong sport/team')
    if feed.get('source_url') != expected:
        errors.append('wrong source')
    stamp = datetime.fromisoformat(feed['generated_at'].replace('Z', '+00:00'))
    age = (now - stamp).total_seconds() / 3600
    if not 0 <= age <= max_age_hours:
        errors.append('observation outside freshness window')
    if feed.get('source_kind') not in ('syndication-lab', 'browser-lab', 'published-snapshot'):
        errors.append('unknown provenance')
    if not 1 <= len(feed['recent']) <= 24 or len(feed['popular']) > 12:
        errors.append('empty or oversized feed')
    for mode in ('recent', 'popular'):
        posts = feed[mode]
        if len({p['id'] for p in posts}) != len(posts):
            errors.append('duplicate post IDs')
        for p in posts:
            date = datetime.fromisoformat(p['published'].replace('Z', '+00:00'))
            if not p['text'] or not p['url'].endswith('/status/' + p['id']) or date > stamp:
                errors.append('invalid post')
            likes = p.get('likes')
            if likes is not None and (not isinstance(likes, int) or isinstance(likes, bool) or likes < 0):
                errors.append('invalid likes')
            if mode == 'popular' and (likes is None or not stamp - timedelta(hours=24) <= date <= stamp):
                errors.append('invalid popular eligibility')
    return {'age_hours': round(age, 2), 'recent': len(feed['recent']), 'popular': len(feed['popular']),
            'generated_at': feed['generated_at'], 'source_kind': feed.get('source_kind'), 'errors': sorted(set(errors))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--published', action='store_true')
    source.add_argument('--data-dir', type=Path)
    parser.add_argument('--max-age-hours', type=float, default=12)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    tasks = []
    for sport in ('mlb', 'nba', 'nfl', 'nhl'):
        teams = configured_teams(ROOT) if sport == 'mlb' else json.loads((ROOT / f'config/{sport}-teams.json').read_text())
        assert len(teams) == (30 if sport in ('mlb', 'nba') else 32)
        for team in teams:
            expected = source_url(team, team['x']['list_id'] or CLUBS_SOURCE)
            tasks.append((sport, team, expected))
    now = datetime.now(timezone.utc)

    def check(task):
        sport, team, expected = task
        route = f'{sport}/{team["abbreviation"]}/x-feed.json'
        result = dict(sport=sport, team=team['abbreviation'], url=f'{PUBLIC_ROOT}/{route}', source_url=expected)
        try:
            if args.published:
                with urlopen(result['url'], timeout=30) as response:
                    assert response.status == 200
                    feed = json.load(response)
            else:
                feed = json.loads((args.data_dir / route).read_text())
            result.update(check_feed(feed, team, expected, now, args.max_age_hours))
        except Exception as exc:
            result['errors'] = [str(exc)]
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        results = list(pool.map(check, tasks))
    report = dict(checked_at=now.isoformat(), max_age_hours=args.max_age_hours, teams=results)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    for sport in ('mlb', 'nba', 'nfl', 'nhl'):
        rows = [r for r in results if r['sport'] == sport]
        ages = [r['age_hours'] for r in rows if 'age_hours' in r]
        print(f'{sport.upper()}: {sum(not r["errors"] for r in rows)}/{len(rows)} healthy; '
              f'{sum(r.get("recent", 0) for r in rows)} recent posts; oldest observation {max(ages, default=0):.1f}h')
        for row in rows:
            if row['errors']:
                print(' ', row['team'], '; '.join(row['errors']))
    return int(any(r['errors'] for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
