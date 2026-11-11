"""Exercise publication orchestration without network or real Git mutations."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class RefreshTests(unittest.TestCase):
    def run_refresh(self, fetch_status=0):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            binaries = root / 'bin'
            binaries.mkdir()
            data = root / 'data-repo'
            (data / '.git').mkdir(parents=True)
            (data / 'data/nfl/NE').mkdir(parents=True)
            (data / 'data/nhl/BOS').mkdir(parents=True)
            (data / 'data/mlb/BOS').mkdir(parents=True)
            log = root / 'calls'
            scripts = {
                'git': '''#!/bin/bash
echo "git $*" >> "$CALL_LOG"
case "$3" in
  branch) echo lab-data/nba-x ;;
  rev-list) echo 1 ;;
  diff) exit 1 ;;
esac
''',
                'python3': '''#!/bin/bash
echo "python3 $*" >> "$CALL_LOG"
exit "$FETCH_STATUS"
''',
            }
            for name, text in scripts.items():
                path = binaries / name
                path.write_text(text)
                path.chmod(0o755)
            env = dict(os.environ, PATH=f'{binaries}:/usr/bin:/bin', CALL_LOG=str(log),
                       HUB_NBA_DATA_REPO=str(data), HUB_NBA_LAB_REPO=str(root / 'lab'),
                       FETCH_STATUS=str(fetch_status))
            result = subprocess.run(['/bin/bash', str(Path(__file__).with_name('refresh.sh'))],
                                    env=env, capture_output=True, text=True)
            return result.returncode, log.read_text().splitlines()

    def test_all_leagues_share_one_queue_and_all_nfl_teams_are_published(self):
        status, calls = self.run_refresh()
        self.assertEqual(status, 0)
        fetches = [call for call in calls if call.startswith('python3')]
        self.assertEqual(len(fetches), 1)
        self.assertIn('--sport all --all', fetches[0])
        self.assertNotIn('--team NE', fetches[0])
        for sport in ('mlb', 'nba', 'nfl', 'nhl'):
            self.assertTrue(any(f'add -- data/{sport}/' in call for call in calls))
        self.assertIn('push origin lab-data/nba-x', calls[-1])

    def test_rate_limit_stops_requests_but_still_publishes_completed_work(self):
        status, calls = self.run_refresh(fetch_status=75)
        self.assertEqual(status, 75)
        self.assertEqual(len([call for call in calls if call.startswith('python3')]), 1)
        self.assertIn('push origin lab-data/nba-x', calls[-1])

    def test_other_fetch_failure_still_publishes_completed_work(self):
        status, calls = self.run_refresh(fetch_status=1)
        self.assertEqual(status, 1)
        self.assertIn('push origin lab-data/nba-x', calls[-1])
