"""Reuse reviewed MLB sources inside the private Lab refresh queue."""
import json
from pathlib import Path

CLUBS_SOURCE = 'mlb-clubs'
BOSTON_LIST = '1431748439818346496'


def configured_teams(root: Path) -> list[dict]:
    teams = json.loads((root / 'config/mlb-lab-teams.json').read_text())
    originals = {t['id']: t for t in json.loads((root / 'config/mlb-teams.json').read_text())['teams']}
    for team in teams:
        original = originals[team['hubTeamID']]
        # The shared MLB clubs timeline is filtered by exact author, not team words.
        team['x'] = dict(list_id=None, handle=original['x_handle'], match_terms=[], link_terms=[], excluded_terms=[])
        if team['hubTeamID'] == 'boston':
            team['x'].update(list_id=BOSTON_LIST, match_terms=['red sox', 'redsox', 'bosox', 'fenway', 'woosox', 'soxprospects'],
                             excluded_terms=['white sox', '#nfl', '#nba', '#nhl'])
    return teams


def source_url(team: dict, list_id: str) -> str:
    if list_id == CLUBS_SOURCE:
        return 'https://x.com/' + team['x']['handle']
    return 'https://x.com/i/lists/' + list_id
