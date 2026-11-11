#!/usr/bin/env python3
"""Single-writer hosted refresh; publish only Lab data and an honest run receipt."""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
BRANCH = 'lab-data/nba-x'
REMOTE = 'https://github.com/sfrancoe/hub-ball'


def permitted_path(path):
    parts = Path(path).parts
    return path == 'data/lab-x-status.json' or (
        len(parts) == 4 and parts[0] == 'data' and parts[1] in ('mlb', 'nba', 'nfl', 'nhl')
        and parts[2].isascii() and parts[2].isalnum()
        and parts[3] in ('x-feed.json', 'roster.json'))


def outcome(fetch_status, audit_status):
    if audit_status or fetch_status not in (0, 75, None):
        return 'failed'
    return 'verified' if fetch_status is None else 'rate-limited' if fetch_status == 75 else 'refreshed'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data-repo', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--verify-only', action='store_true', help='Check hosting, BDL access and publication without X requests')
    args = parser.parse_args()
    repo = args.data_repo.resolve()

    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(repo), *arguments], text=True).rstrip('\n')

    if git('branch', '--show-current') != BRANCH or git('status', '--porcelain'):
        raise RuntimeError('Expected a clean checkout of the dedicated Lab data branch')
    if git('remote', 'get-url', 'origin').removesuffix('.git') != REMOTE:
        raise RuntimeError('Unexpected data repository')
    if not os.environ.get('BALLDONTLIE_API_KEY'):
        raise RuntimeError('Missing BALLDONTLIE_API_KEY environment secret')
    # A hosting cutover must not turn an earlier rate limit into an immediate retry.
    not_before = os.environ.get('X_REFRESH_NOT_BEFORE')
    if not args.verify_only and not_before and datetime.now(timezone.utc) < datetime.fromisoformat(not_before):
        raise RuntimeError('Wait for the next scheduled refresh; cutover cooldown is active')
    print(git('pull', '--ff-only'))
    before = git('rev-parse', 'HEAD')
    fetch_status = None
    if args.verify_only:
        sys.path.insert(0, str(HERE.parent))
        from nfl_bdl import NFLClient
        payload = NFLClient().get('/nfl/v1/teams')
        if not isinstance(payload.get('data'), list) or len(payload['data']) < 32:
            raise RuntimeError('BALLDONTLIE roster credential check failed')
        print('Hosted BALLDONTLIE access verified; no X request made.')
    else:
        fetch_status = subprocess.run([sys.executable, str(HERE / 'build.py'), '--sport', 'all', '--all',
                                       '--data-dir', str(repo / 'data')], check=False).returncode
    audit_status = subprocess.run([sys.executable, str(HERE / 'audit.py'), '--data-dir', str(repo / 'data'),
                                   '--output', str(args.report)], check=False).returncode
    report = json.loads(args.report.read_text())
    status_path = repo / 'data/lab-x-status.json'
    previous = json.loads(status_path.read_text()) if status_path.exists() else {}
    now = datetime.now(timezone.utc).isoformat()
    state = outcome(fetch_status, audit_status)
    run_id = os.environ.get('GITHUB_RUN_ID', '')
    status = dict(checked_at=now, mode='verify-only' if args.verify_only else 'refresh', outcome=state,
                  fetch_exit=fetch_status, audit_exit=audit_status,
                  last_refresh_attempt_at=previous.get('last_refresh_attempt_at') if args.verify_only else now,
                  runtime_commit=os.environ.get('GITHUB_SHA'), data_commit_before=before,
                  run_url=f'https://github.com/sfrancoe/hub-ball/actions/runs/{run_id}', leagues={})
    for sport in ('mlb', 'nba', 'nfl', 'nhl'):
        rows = [r for r in report['teams'] if r['sport'] == sport]
        status['leagues'][sport] = dict(teams=len(rows), healthy=sum(not r['errors'] for r in rows),
            recent=sum(r.get('recent', 0) for r in rows),
            oldest_observation_hours=max((r.get('age_hours', 0) for r in rows), default=0))
    status_path.write_text(json.dumps(status, indent=2) + '\n')
    changed = git('status', '--porcelain', '--untracked-files=all').splitlines()
    paths = [line[3:] for line in changed]
    if not all(permitted_path(path) for path in paths):
        raise RuntimeError('Refusing to publish changes outside the Lab feed allowlist')
    git('add', '--', *paths)
    if not all(permitted_path(path) for path in git('diff', '--cached', '--name-only').splitlines()):
        raise RuntimeError('Unexpected staged paths')
    git('commit', '-m', 'Verify hosted Lab X refresh [skip netlify]' if args.verify_only else 'Refresh four-sport Lab X feeds [skip netlify]')
    git('push', 'origin', f'HEAD:refs/heads/{BRANCH}')
    print('Published data commit', git('rev-parse', 'HEAD'))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as stream:
            stream.write(f'## Lab X: {state}\n\nMode: {status["mode"]}. No paid X APIs.\n\n')
            for sport, league in status['leagues'].items():
                stream.write(f'- {sport.upper()}: {league["healthy"]}/{league["teams"]} healthy; oldest observation {league["oldest_observation_hours"]:.1f} hours.\n')
    if fetch_status == 75:
        print('::warning::X rate limited this run. Completed feeds were published; remaining teams wait for the next schedule.')
    return int(state == 'failed')


if __name__ == '__main__':
    raise SystemExit(main())
