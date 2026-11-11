import json
import os
import re
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError
import build
from filter import relevant
from rosters import terms_for_names
from sources import RateLimitError, SyndicationLabSource, XApiSource, fetch

ROOT = Path(__file__).resolve().parents[2]

class NBAFeedTests(unittest.TestCase):
    def test_registry(self):
        teams = json.loads((ROOT / 'config/nba-teams.json').read_text())
        self.assertEqual(len(teams), 30)
        list_ids = [t['x']['list_id'] for t in teams]
        self.assertTrue(all(isinstance(list_id, str) and re.fullmatch(r'[0-9]+', list_id) for list_id in list_ids))
        self.assertEqual(len(set(list_ids)), 30, 'Every NBA team must have its own public List')
        traps = {'Heat', 'Magic', 'Thunder', 'Jazz', 'Suns', 'Kings', 'Nets', 'Spurs', 'Celtics', 'Hawks', 'Wizards', 'Rockets', 'Bulls', 'Bucks'}
        for t in teams:
            x = t['x']
            self.assertTrue(x['handle'] is None or re.fullmatch(r'[A-Za-z0-9_]{1,15}', x['handle']))
            self.assertTrue(x['list_id'] is None or isinstance(x['list_id'], str) and re.fullmatch(r'[0-9]+', x['list_id']))
            if t['name'] in traps:
                self.assertNotIn(t['name'].lower(), [s.lower() for s in x['match_terms']])
            config = dict(x, list_id='1')
            self.assertTrue(relevant({'text': t['city'] + ' ' + t['name']}, config, set()))
            self.assertFalse(relevant({'text': 'ordinary heat wave'}, config, set()))
        self.assertEqual(teams, json.loads((ROOT / 'ios/Hub Ball/Hub Ball/NBA/nba-teams.json').read_text()))

    def test_filter(self):
        config = {'list_id': '1', 'match_terms': ['boston celtics'], 'link_terms': ['celticsblog'], 'excluded_terms': ['bruins']}
        self.assertFalse(relevant({'text': 'Bruins and Tatum'}, config, {'tatum'}))
        self.assertTrue(relevant({'text': 'Boston Celtics and Bruins'}, config, set()))
        self.assertTrue(relevant({'text': 'Tatum scores'}, config, {'tatum'}))
        self.assertFalse(relevant({'text': 'Tatumville'}, config, {'tatum'}))
        self.assertTrue(relevant({'quoted_status': {'text': 'Boston Celtics win'}}, config, set()))
        self.assertTrue(relevant({'entities': {'urls': [{'expanded_url': 'https://celticsblog.com'}]}}, config, set()))
        self.assertTrue(relevant({'extended_entities': {'media': [{'ext_alt_text': 'Boston Celtics'}]}}, config, set()))
        self.assertTrue(relevant({'user': {'screen_name': 'Celtics'}}, {'list_id': None, 'handle': 'celtics'}, set()))
        self.assertFalse(relevant({'user': {'screen_name': 'other'}, 'text': 'Boston Celtics'}, {'list_id': None, 'handle': 'celtics'}, set()))
        self.assertEqual(terms_for_names(['Jayson Tatum', 'Derrick White']), {'jayson tatum', 'tatum', 'derrick white'})

    def test_gates_and_preservation(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError): SyndicationLabSource().list_posts('1')
        with self.assertRaises(NotImplementedError): XApiSource().list_posts('1')
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'feed.json'; path.write_text('original')
            self.assertFalse(build.save_feed(path, None))
            self.assertEqual(path.read_text(), 'original')

    def test_fetch_failure_keeps_existing_snapshot(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config').mkdir()
            (root / 'config/nba-teams.json').write_text(json.dumps([{'id': '2', 'abbreviation': 'BOS', 'x': {'list_id': '123', 'handle': 'celtics'}}]))
            (root / 'config/nba-x.json').write_text('{"nba_teams_list_id":null}')
            path = root / 'data/nba/BOS/x-feed.json'
            path.parent.mkdir(parents=True)
            path.write_text('last good')
            with patch.object(build, 'ROOT', root), patch('sys.argv', ['build.py', '--team', 'BOS', '--data-dir', str(root / 'data/nba')]), patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), patch.object(SyndicationLabSource, 'list_posts', side_effect=RuntimeError('offline')):
                self.assertEqual(build.main(), 1)
            self.assertEqual(path.read_text(), 'last good')

    def test_unchanged_posts_advance_verified_time_and_refresh_priority(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            teams = [dict(abbreviation=abbr, x={'list_id': '123'}) for abbr in ['AAA', 'BBB']]
            old = {'generated_at': '2026-11-07T12:00:00+00:00',
                   'likes_as_of': '2026-11-07T12:00:00+00:00',
                   'source_url': 'https://x.com/i/lists/123', 'source_kind': 'syndication-lab',
                   'team_id': '2', 'recent': [{'id': '1'}], 'popular': []}
            for team in teams:
                path = root / team['abbreviation'] / 'x-feed.json'
                path.parent.mkdir()
                path.write_text(json.dumps(old))
            fresh = dict(old, generated_at='2026-11-08T12:00:00+00:00', likes_as_of='2026-11-08T12:00:00+00:00')
            path = root / 'AAA/x-feed.json'
            self.assertTrue(build.save_feed(path, fresh))
            self.assertEqual(json.loads(path.read_text()), fresh)
            ordered = sorted(teams, key=lambda team: build.refresh_priority(team, root, None))
            self.assertEqual([team['abbreviation'] for team in ordered], ['BBB', 'AAA'])
            self.assertFalse(build.save_feed(path, fresh))

    def test_rate_limit_is_not_retried(self):
        error = HTTPError('https://example.invalid/list', 429, 'Too Many Requests', {'Retry-After': '7200'}, None)
        with patch('sources.urlopen', side_effect=error) as request, patch('sources.time.sleep') as sleep:
            with self.assertRaisesRegex(RateLimitError, 'Retry-After: 7200'):
                fetch('https://example.invalid/list')
        self.assertEqual(request.call_count, 1)
        sleep.assert_not_called()

    def test_transient_failure_still_retries(self):
        with patch('sources.urlopen', side_effect=URLError('offline')) as request, patch('sources.time.sleep') as sleep:
            with self.assertRaises(RuntimeError):
                fetch('https://example.invalid/list')
        self.assertEqual(request.call_count, 3)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 2])

    def test_rate_limit_stops_batch_preserves_feeds_and_prioritizes_deferred_teams(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config').mkdir()
            teams = [dict(id=str(index), abbreviation=abbr, x={
                'list_id': str(index), 'handle': 'celtics',
                'match_terms': ['boston celtics'], 'link_terms': [], 'excluded_terms': [],
            }) for index, abbr in enumerate(['AAA', 'BBB', 'CCC'], 1)]
            (root / 'config/nba-teams.json').write_text(json.dumps(teams))
            (root / 'config/nba-x.json').write_text('{"nba_teams_list_id":null}')
            data = root / 'data/nba'
            originals = {}
            for team in teams:
                path = data / team['abbreviation'] / 'x-feed.json'
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps({
                    'generated_at': '2026-11-07T12:00:00+00:00',
                    'source_url': f"https://x.com/i/lists/{team['x']['list_id']}",
                    'team_id': team['id'], 'recent': [{'text': 'last good'}],
                }))
                originals[team['abbreviation']] = path.read_bytes()
            tweet = {'id_str': '123', 'text': 'Boston Celtics win',
                     'created_at': 'Sat Nov 07 12:00:00 +0000 2026', 'user': {'screen_name': 'celtics'}}
            with patch.object(build, 'ROOT', root), patch('sys.argv', ['build.py', '--all', '--data-dir', str(data)]), \
                 patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
                 patch.object(SyndicationLabSource, 'list_posts', side_effect=[[tweet], RateLimitError('HTTP 429')]) as request, \
                 patch.object(build, 'roster_terms', return_value=set()):
                self.assertEqual(build.main(), build.RATE_LIMIT_EXIT)
            self.assertEqual([call.args[0] for call in request.call_args_list], ['1', '2'])
            self.assertNotEqual((data / 'AAA/x-feed.json').read_bytes(), originals['AAA'])
            for abbr in ['BBB', 'CCC']:
                self.assertEqual((data / abbr / 'x-feed.json').read_bytes(), originals[abbr])
            ordered = sorted(teams, key=lambda team: build.refresh_priority(team, data, None))
            self.assertEqual([team['abbreviation'] for team in ordered], ['BBB', 'CCC', 'AAA'])

    def test_refresh_prioritizes_unconnected_and_older_feeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            teams = [dict(abbreviation=abbr, x={'list_id': '123'}) for abbr in ['NEW', 'OLD', 'MOVED', 'MISSING']]
            for abbr, source, stamp in [
                ('NEW', '123', '2026-11-08T12:00:00+00:00'),
                ('OLD', '123', '2026-11-07T12:00:00+00:00'),
                ('MOVED', '456', '2026-11-08T13:00:00+00:00'),
            ]:
                folder = root / abbr
                folder.mkdir()
                (folder / 'x-feed.json').write_text(json.dumps({
                    'source_url': f'https://x.com/i/lists/{source}', 'generated_at': stamp,
                }))
            ordered = sorted(teams, key=lambda team: build.refresh_priority(team, root, None))
            self.assertEqual([team['abbreviation'] for team in ordered], ['MISSING', 'MOVED', 'OLD', 'NEW'])

    def test_captured_sources(self):
        from rosters import roster_terms
        fixture = Path(__file__).parent / 'fixtures'
        html = (fixture / 'syndication-list.html').read_bytes()
        roster = (fixture / 'espn-roster.json').read_bytes()
        with patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}):
            with patch('sources.fetch', return_value=html):
                tweets = SyndicationLabSource().list_posts('2119126425919684932')
            self.assertEqual(len(tweets), 1)
            self.assertTrue(tweets[0]['id_str'].isdigit())
            with tempfile.TemporaryDirectory() as tmp, patch('rosters.fetch', return_value=roster):
                terms = roster_terms({'id': '2', 'abbreviation': 'BOS'}, Path(tmp) / 'roster.json')
                self.assertTrue(terms)

    def test_snapshot(self):
        team = {'id': '2', 'x': {'list_id': '1', 'match_terms': ['boston celtics'], 'link_terms': [], 'excluded_terms': []}}
        tweet = {'id_str': '123', 'full_text': 'Boston Celtics win', 'created_at': 'Sat Nov 07 12:00:00 +0000 2026', 'user': {'screen_name': 'celtics'}, 'favorite_count': 5}
        feed = build.make_feed(team, '1', SyndicationLabSource(), [tweet, tweet], set(), datetime(2026, 11, 7, 13, tzinfo=timezone.utc))
        self.assertEqual(len(feed['recent']), 1)
        self.assertEqual(feed['popular'][0]['likes'], 5)
        self.assertEqual(feed['source_kind'], 'syndication-lab')
        del tweet['favorite_count']
        self.assertEqual(build.make_feed(team, '1', SyndicationLabSource(), [tweet], set(), datetime(2026, 11, 7, 13, tzinfo=timezone.utc))['popular'], [])

if __name__ == '__main__': unittest.main()
