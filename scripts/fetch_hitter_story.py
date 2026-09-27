#!/usr/bin/env python3
"""Rebuild the .300-or-better story from MLB's qualified season totals (stdlib only)."""
import concurrent.futures
from datetime import datetime, timezone
from decimal import Decimal
import json
from pathlib import Path
import re
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "https://statsapi.mlb.com/api/v1/stats?stats=season&group=hitting&season={year}&sportIds=1&playerPool=QUALIFIED&sortStat=avg&order=desc&limit=1000"
FIRST_YEAR = 1976
LAST_FINAL_YEAR = 2025
SNAPSHOT_YEAR = 2026
FALLBACK_UA = "OpenAI File Downloader, XaiImageApiFetch/1.0"


def fetch_json(url: str) -> dict:
    fallback = False
    for attempt in range(4):
        request = urllib.request.Request(url, headers={"User-Agent": FALLBACK_UA} if fallback else {})
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except (urllib.error.URLError, json.JSONDecodeError) as error:
            if isinstance(error, urllib.error.HTTPError) and error.code in (401, 403):
                raise  # Do not bypass access controls.
            if attempt == 3:
                raise
            if not fallback:
                fallback = True
            time.sleep(2 ** attempt)
    raise RuntimeError(f"Unable to retrieve {url}")


def extract_season(year: int, payload: dict) -> dict:
    stats = payload['stats'][0]
    rows = stats['splits']
    if not rows or len(rows) != stats['totalSplits']:
        raise ValueError(f"Incomplete leaderboard for {year}")
    ids = [row['player']['id'] for row in rows]
    if len(ids) != len(set(ids)):
        raise ValueError(f"Duplicate player totals in {year}; reconcile traded players before publishing")
    players = []
    for row in rows:
        if row['season'] != str(year):
            raise ValueError(f"Wrong season in {year} response")
        stat = row['stat']
        if not re.fullmatch(r'(?:0)?\.\d{3}|1\.000', stat['avg']):
            raise ValueError(f"Invalid displayed AVG: {stat['avg']}")
        players.append({
            'id': row['player']['id'], 'name': row['player']['fullName'],
            'avg': stat['avg'], 'hits': stat['hits'], 'at_bats': stat['atBats'],
            'plate_appearances': stat['plateAppearances'],
        })
    return {
        'year': year, 'provisional': year > LAST_FINAL_YEAR,
        'source': SOURCE.format(year=year), 'qualified_total': len(players),
        'count': sum(Decimal(p['avg']) >= Decimal('.300') for p in players),
        'players': players,
    }


def fetch_season(year: int) -> dict:
    return extract_season(year, fetch_json(SOURCE.format(year=year)))


def main() -> None:
    # All requests must succeed before either local output is updated.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        seasons = list(executor.map(fetch_season, range(FIRST_YEAR, SNAPSHOT_YEAR + 1)))
    snapshot = {
        'retrieved_at_utc': datetime.now(timezone.utc).isoformat(),
        'definition': 'MLB qualified hitters with officially displayed AVG >= .300, including exactly .300',
        'qualification': 'MLB playerPool=QUALIFIED; MLB season totals combine traded-player performance',
        'last_final_year': LAST_FINAL_YEAR,
        'seasons': seasons,
    }
    module = ROOT / 'ios/Hub Ball/Hub Ball/MLB300HitterData.swift'
    swift = module.read_text()
    entries = []
    for season in seasons:
        provisional = ', isProvisional: true' if season['provisional'] else ''
        entries.append(f"        .init(year: {season['year']}, count: {season['count']}{provisional})")
    swift, changed = re.subn(r'    static let seasons: \[Season\] = \[.*?\n    \]',
                            '    static let seasons: [Season] = [\n' + ',\n'.join(entries) + '\n    ]',
                            swift, flags=re.S)
    if changed != 1:
        raise ValueError('Cannot locate season array; no files updated')
    (ROOT / 'data/mlb300-hitters.json').write_text(json.dumps(snapshot, indent=2, ensure_ascii=False) + '\n')
    module.write_text(swift)
    print('Counts:', ','.join(str(s['count']) for s in seasons))
    peak = max(seasons, key=lambda s: s['count'])
    print(f"Peak: {peak['year']} = {peak['count']}; ending: {seasons[-1]['count']}")
    print('Snapshot labels and editorial copy must be reviewed after each refresh.')


if __name__ == '__main__':
    main()
