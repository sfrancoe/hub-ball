"""Copy only newer, validated X snapshots to already tracked team files."""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Unexpected feed endpoint redirect')


def timestamp(value):
    stamp = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if stamp.utcoffset() is None:
        raise ValueError('Missing time zone')
    return stamp


def sync(repo, feeds):
    listed = subprocess.check_output(['git', 'ls-files', '-z', '--', 'data/*/*/x-feed.json'], cwd=repo)
    teams = {}
    for raw in listed.decode().split('\0'):
        if not raw:
            continue
        match = re.fullmatch(r'data/((?:nba|nfl|mlb|nhl)/[A-Z0-9]{2,4})/x-feed\.json', raw)
        if not match:
            raise ValueError('Unexpected tracked feed path')
        teams[match[1]] = repo / raw
    if len(teams) != 124 or set(teams) != set(feeds):
        raise ValueError('Incomplete or unexpected team registry')
    updates = []
    for team, path in teams.items():
        if path.resolve() != path or not path.is_file():
            raise ValueError('Expected a regular tracked feed file')
        old = json.loads(path.read_bytes())
        new = feeds[team]
        if any(new[k] != old[k] for k in ('source_url', 'sport', 'team_id')):
            raise ValueError(f'Source or team mismatch for {team}')
        if new['source_kind'] not in ('syndication-lab', 'browser-lab', 'published-snapshot') or new['source'] != 'X':
            raise ValueError(f'Unexpected source for {team}')
        observed = timestamp(new['generated_at'])
        if not 1 <= len(new['recent']) <= 24 or len(new['popular']) > 12 or observed > datetime.now(timezone.utc):
            raise ValueError(f'Invalid observation for {team}')
        for post in new['recent'] + new['popular']:
            url = urlsplit(post['url'])
            if not(post['text'] and post['author'] and url.scheme == 'https' and url.netloc in ('x.com','twitter.com')
                   and re.fullmatch(r'/[a-zA-Z0-9_]{1,15}/status/[0-9]+', url.path)
                   and url.path.rsplit('/',1)[-1] == post['id'] and timestamp(post['published']) <= observed):
                raise ValueError(f'Invalid post for {team}')
        if observed > timestamp(old['generated_at']):
            updates.append((path, new))
    for path, feed in updates:
        path.write_text(json.dumps(feed, ensure_ascii=False, indent=2) + '\n')
    return len(updates)


if __name__ == '__main__':
    endpoint = os.environ['HUB_X_SNAPSHOT_URL']
    if not re.fullmatch(r'https://private\.hubballfeeds\.app/private/[a-f0-9]{48}/x/teams\.json', endpoint):
        raise SystemExit('Unexpected hosted feed URL')
    req = Request(endpoint, headers={'User-Agent':'HubBall-X-Publisher/1.0','Accept':'application/json'})
    with build_opener(NoRedirect).open(req, timeout=25) as response:
        contents = response.read(10_000_001)
    if len(contents) > 10_000_000:
        raise SystemExit('Feed bundle too large')
    count = sync(Path(sys.argv[1]).resolve(), json.loads(contents))
    print(f'Validated 124 feeds; {count} updates.')
