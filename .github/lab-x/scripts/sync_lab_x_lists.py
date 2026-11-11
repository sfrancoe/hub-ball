#!/usr/bin/env python3
"""Apply reviewed NFL/NHL public X List mappings without any network requests."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def apply_list_mappings(rows: list[dict], sport: str, root: Path = ROOT) -> list[dict]:
    if sport not in ('nfl', 'nhl'):
        return rows
    path = root / 'config/lab-x-lists.json'
    mappings = json.loads(path.read_text())['leagues'][sport]
    known = {row['abbreviation'] for row in rows}
    if set(mappings) - known:
        raise ValueError(f'Unknown {sport.upper()} teams in X List map: {sorted(set(mappings) - known)}')
    for row in rows:
        row.pop('x', None)
        entry = mappings.get(row['abbreviation'])
        if entry is None:
            continue
        list_id = entry['list_id']
        if not isinstance(list_id, str) or not re.fullmatch(r'[0-9]+', list_id):
            raise ValueError(f'Invalid List ID for {sport}/{row["abbreviation"]}')
        if entry.get('public') is not True or entry.get('url') != f'https://x.com/i/lists/{list_id}':
            raise ValueError(f'List must be verified public with a matching URL: {sport}/{row["abbreviation"]}')
        full_name = row.get('displayName') or f'{row["city"]} {row["name"]}'
        handle = entry.get('handle')
        if handle is not None and (not isinstance(handle, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,15}', handle)):
            raise ValueError(f'Invalid official handle: {sport}/{row["abbreviation"]}')
        terms = [full_name.lower()] + (['@' + handle.lower()] if handle else [])
        terms += entry.get('match_terms', [])
        row['x'] = dict(list_id=list_id, handle=handle, accept_official_posts=bool(handle),
                        match_terms=terms, link_terms=entry.get('link_terms', []),
                        excluded_terms=['#' + league for league in ['mlb', 'nba', 'nfl', 'nhl'] if league != sport])
    return rows


def main() -> None:
    for sport in ('nfl', 'nhl'):
        filename = f'{sport}-teams.json'
        teams = apply_list_mappings(json.loads((ROOT / 'config' / filename).read_text()), sport)
        text = json.dumps(teams, indent=2) + '\n'
        for directory in [ROOT / 'config', ROOT / 'ios/Hub Ball/Hub Ball/NBA']:
            (directory / filename).write_text(text)
        print(f'{sport.upper()}: {sum(bool(team.get("x")) for team in teams)}/{len(teams)} verified public Lists mapped')


if __name__ == '__main__':
    main()
