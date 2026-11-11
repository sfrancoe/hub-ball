"""Provider-specific roster terms, cached for private Lab research."""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from sources import fetch, require_lab

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from nfl_bdl import NFLClient
from nhl_bdl import NHLClient
from mlb_bdl import MLBClient

COMMON = {'anderson', 'anthony', 'campbell', 'gray', 'harris', 'hill', 'miller', 'scott',
          'short', 'story', 'walker', 'west', 'white', 'young', 'green', 'brown', 'porter',
          'murray', 'johnson', 'williams', 'lindgren'}
# Ryan (Seattle) and Charlie (Washington) share Lindgren. Require a full name
# or team context instead of admitting one club's lineup into the other's feed.


def terms_for_names(names: list[str], *, surnames: bool = True) -> set[str]:
    # NFL media Lists include national reporters: shared surnames and ordinary
    # words (e.g. Likely) are insufficient evidence of team relevance.
    terms = set()
    for name in names:
        name = name.strip().lower()
        if not name:
            continue
        terms.add(name)
        surname = re.split(r'[\s-]+', name)[-1]
        if surnames and len(surname) >= 5 and surname not in COMMON:
            terms.add(surname)
    return terms


def roster_terms(team: dict, path: Path, dry_run: bool = False) -> set[str]:
    require_lab()
    cached = {}
    try:
        cached = json.loads(path.read_text())
        age = datetime.now(timezone.utc) - datetime.fromisoformat(cached['generated_at'])
        if age < timedelta(days=1) and cached.get('names') and (team.get('sportID') not in ('MLB', 'NFL', 'NHL') or cached.get('provider') == 'balldontlie'):
            return terms_for_names(cached['names'], surnames=team.get('sportID') != 'NFL')
    except (OSError, ValueError, KeyError, TypeError):
        cached = {}
    if team.get('sportID') in ('MLB', 'NFL', 'NHL') and cached.get('provider') != 'balldontlie':
        cached = {}
    try:
        sport = team.get('sportID', 'NBA').lower()
        if sport == 'nfl':
            bdl_id = team.get('bdlID')
            if not isinstance(bdl_id, int):
                raise ValueError('NFL registry has no BALLDONTLIE ID')
            payload = NFLClient().get(f'/nfl/v1/teams/{bdl_id}/roster')
            names = list({(r['player']['first_name'] + ' ' + r['player']['last_name']).strip() for r in payload['data']})
        elif sport == 'mlb':
            bdl_id = team.get('bdlID')
            if not isinstance(bdl_id, int):
                raise ValueError('MLB registry has no BALLDONTLIE ID')
            rows = MLBClient().pages(f'/mlb/v1/players/active?team_ids[]={bdl_id}&per_page=100')
            names = [(r['first_name'] + ' ' + r['last_name']).strip() for r in rows]
        elif sport == 'nhl':
            bdl_id = team.get('bdlID')
            if not isinstance(bdl_id, int):
                raise ValueError('NHL registry has no BALLDONTLIE ID')
            now = datetime.now(timezone.utc)
            season = now.year - (now.month < 9)
            rows = NHLClient().pages(f'/nhl/v1/players?team_ids[]={bdl_id}&seasons[]={season}&per_page=100')
            names = [r.get('full_name') or (r['first_name'] + ' ' + r['last_name']).strip() for r in rows]
        else:
            sport_path = {'nba': 'basketball/nba', 'nhl': 'hockey/nhl'}[sport]
            url = f"https://site.api.espn.com/apis/site/v2/sports/{sport_path}/teams/{team['id']}/roster"
            payload = json.loads(fetch(url))
            rows = payload['athletes']
            athletes = [a for row in rows for a in (row.get('items') if isinstance(row.get('items'), list) else [row])]
            names = [a['displayName'] for a in athletes if isinstance(a, dict) and isinstance(a.get('displayName'), str)]
        if not names:
            raise ValueError('roster contained no player names')
        if not dry_run:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({'generated_at': datetime.now(timezone.utc).isoformat(), 'names': names, 'provider': 'balldontlie' if sport in ('mlb', 'nfl', 'nhl') else 'espn'}, indent=2) + '\n')
        return terms_for_names(names, surnames=sport != 'nfl')
    except (RuntimeError, ValueError, KeyError, TypeError) as exc:
        print(f"WARNING: {team['abbreviation']} roster unavailable: {exc}; using cached names if available")
        return terms_for_names(cached.get('names', []), surnames=team.get('sportID') != 'NFL')
