import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch
import build
from rosters import roster_terms, terms_for_names
from filter import relevant
from sources import BrowserCaptureLabSource, SyndicationLabSource

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sync_lab_x_lists import apply_list_mappings


class OtherSportFeedTests(unittest.TestCase):
    def test_patriots_mapping_survives_registry_regeneration_and_filters_other_games(self):
        root = Path(__file__).resolve().parents[2]
        rows = json.loads((root / 'config/nfl-teams.json').read_text())
        team = next(t for t in apply_list_mappings(rows, 'nfl', root) if t['abbreviation'] == 'NE')
        self.assertEqual(team['x']['list_id'], '1574085879840342016')
        self.assertTrue(relevant({'text': 'Patriots postgame notes'}, team['x'], set()))
        self.assertFalse(relevant({'text': 'Buccaneers at Bears on NBC'}, team['x'], set()))

    def test_browser_bootstrap_preserves_observation_time_and_checks_list_identity(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}):
            path = Path(tmp) / 'capture.json'
            path.write_text(json.dumps({'source_url': 'https://x.com/i/lists/123',
                'observed_at': '2026-11-08T12:00:00Z', 'tweets': [{
                    'id_str': '456', 'full_text': 'Patriots postgame notes', 'favorite_count': 7,
                    'created_at': 'Sun, 08 Nov 2026 11:00:00 GMT', 'user': {'screen_name': 'reporter'}}]}))
            source = BrowserCaptureLabSource(path)
            team = {'id': '17', 'sportID': 'NFL', 'x': {'list_id': '123', 'match_terms': ['patriots'], 'link_terms': [], 'excluded_terms': []}}
            feed = build.make_feed(team, '123', source, source.list_posts('123'), set(), source.observed_at)
            self.assertEqual(feed['source_kind'], 'browser-lab')
            self.assertEqual(feed['generated_at'], '2026-11-08T12:00:00+00:00')
            self.assertEqual(feed['likes_as_of'], feed['generated_at'])
            self.assertEqual(feed['popular'][0]['likes'], 7)
            with self.assertRaises(ValueError):
                source.list_posts('999')
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(RuntimeError):
            BrowserCaptureLabSource(Path('not-read-without-lab-gate'))

    def test_sport_specific_builder_does_not_fetch_unmapped_teams(self):
        for sport in ('nfl', 'nhl'):
            with self.subTest(sport=sport), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / 'config').mkdir()
                teams = [dict(id='1', abbreviation='ONE', sportID=sport.upper(), x={
                    'list_id': '123', 'handle': None, 'match_terms': ['mapped team'], 'link_terms': [], 'excluded_terms': [],
                }), dict(id='2', abbreviation='TWO', sportID=sport.upper())]
                (root / f'config/{sport}-teams.json').write_text(json.dumps(teams))
                tweet = {'id_str': '123', 'text': 'Mapped team update',
                         'created_at': 'Sun Nov 08 12:00:00 +0000 2026', 'user': {'screen_name': 'team'}}
                with patch.object(build, 'ROOT', root), patch('sys.argv', ['build.py', '--all', '--sport', sport]), \
                     patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
                     patch.object(SyndicationLabSource, 'list_posts', return_value=[tweet]) as request, \
                     patch.object(build, 'roster_terms', return_value=set()):
                    self.assertEqual(build.main(), 0)
                request.assert_called_once_with('123')
                feed = json.loads((root / f'data/{sport}/ONE/x-feed.json').read_text())
                self.assertEqual(feed['sport'], sport)
                self.assertEqual(feed['team_id'], '1')
                self.assertEqual(feed['source_url'], 'https://x.com/i/lists/123')
                self.assertFalse((root / f'data/{sport}/TWO').exists())
                self.assertFalse((root / 'data/nba').exists())

    def test_verified_official_author_keeps_generic_posts_without_widening_other_authors(self):
        config = {'list_id': '123', 'handle': 'AZCardinals', 'accept_official_posts': True,
                  'match_terms': ['arizona cardinals'], 'link_terms': [], 'excluded_terms': []}
        tweet = {'user': {'screen_name': 'azcardinals'}, 'text': 'GAME DAY'}
        self.assertTrue(relevant(tweet, config, set()))
        self.assertFalse(relevant(dict(tweet, user={'screen_name': 'unrelated'}), config, set()))
        self.assertFalse(relevant(tweet, dict(config, accept_official_posts=False), set()))

    def test_no_mappings_makes_no_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config').mkdir()
            (root / 'config/nfl-teams.json').write_text('[{"id":"1","abbreviation":"ONE"}]')
            with patch.object(build, 'ROOT', root), patch('sys.argv', ['build.py', '--all', '--sport', 'nfl']), \
                 patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
                 patch.object(SyndicationLabSource, 'list_posts') as request:
                self.assertEqual(build.main(), 0)
            request.assert_not_called()

    def test_rosters_use_selected_sport(self):
        for sport, path in [('NBA', 'basketball/nba')]:
            with self.subTest(sport=sport), tempfile.TemporaryDirectory() as tmp, \
                 patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
                 patch('rosters.fetch', return_value=b'{"athletes":[{"displayName":"Fixture Player"}]}') as fetch:
                terms = roster_terms({'id': '1', 'abbreviation': 'ONE', 'sportID': sport}, Path(tmp) / 'roster.json')
                self.assertIn('fixture player', terms)
                fetch.assert_called_once_with(f'https://site.api.espn.com/apis/site/v2/sports/{path}/teams/1/roster')

    def test_nfl_roster_uses_balldontlie_and_never_espn(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
             patch('rosters.NFLClient') as client, patch('rosters.fetch') as espn:
            client.return_value.get.return_value = {'data': [{'player': {'first_name': 'Drake', 'last_name': 'Maye'}}]}
            terms = roster_terms({'id': '17', 'bdlID': 1, 'abbreviation': 'NE', 'sportID': 'NFL'}, Path(tmp) / 'roster.json')
            self.assertIn('drake maye', terms)
            client.return_value.get.assert_called_once_with('/nfl/v1/teams/1/roster')
            espn.assert_not_called()

    def test_nhl_roster_uses_season_memberships_and_never_espn(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {'HUB_LAB_ALLOW_UNOFFICIAL_X': '1'}), \
             patch('rosters.NHLClient') as client, patch('rosters.fetch') as espn:
            client.return_value.pages.return_value = [{'id': 7, 'full_name': 'David Pastrnak'}]
            terms = roster_terms({'id': '1', 'bdlID': 51, 'abbreviation': 'BOS', 'sportID': 'NHL'}, Path(tmp) / 'roster.json')
            self.assertIn('david pastrnak', terms)
            route = client.return_value.pages.call_args.args[0]
            self.assertTrue(route.startswith('/nhl/v1/players?team_ids[]=51&seasons[]='))
            espn.assert_not_called()

    def test_registry_generation_preserves_only_reviewed_list_mappings(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config').mkdir()
            mapping = {'leagues': {'nfl': {'ONE': {'list_id': '123', 'url': 'https://x.com/i/lists/123', 'public': True}}, 'nhl': {}}}
            (root / 'config/lab-x-lists.json').write_text(json.dumps(mapping))
            rows = [dict(id='1', city='Mapped', name='Team', abbreviation='ONE', division='East'),
                    dict(id='2', city='Other', name='Team', abbreviation='TWO')]
            result = apply_list_mappings(rows, 'nfl', root)
            self.assertEqual(result[0]['division'], 'East')
            self.assertEqual(result[0]['x']['list_id'], '123')
            self.assertEqual(result[0]['x']['match_terms'], ['mapped team'])
            self.assertNotIn('x', result[1])
            self.assertEqual(result, apply_list_mappings(result, 'nfl', root))
            mapping['leagues']['nfl']['ONE']['list_id'] = 'invalid'
            (root / 'config/lab-x-lists.json').write_text(json.dumps(mapping))
            with self.assertRaises(ValueError):
                apply_list_mappings(rows, 'nfl', root)

    def test_live_registry_copies_match_and_lists_are_distinct(self):
        root = Path(__file__).resolve().parents[2]
        ids = []
        for sport in ('nfl', 'nhl'):
            teams = json.loads((root / f'config/{sport}-teams.json').read_text())
            self.assertEqual(len(teams), 32)
            self.assertEqual(teams, json.loads((root / f'ios/Hub Ball/Hub Ball/NBA/{sport}-teams.json').read_text()))
            ids.extend(t['x']['list_id'] for t in teams if t.get('x'))
        self.assertTrue(ids)
        self.assertEqual(len(ids), len(set(ids)))

    def test_all_nfl_teams_have_reviewed_sources_and_filter_unrelated_posts(self):
        root = Path(__file__).resolve().parents[2]
        teams = apply_list_mappings(json.loads((root / 'config/nfl-teams.json').read_text()), 'nfl', root)
        manifest = json.loads((root / 'config/lab-x-lists.json').read_text())['leagues']['nfl']
        self.assertEqual(len(manifest), 32)
        for team in teams:
            with self.subTest(team=team['abbreviation']):
                source = manifest[team['abbreviation']]
                self.assertGreater(source['members_at_verification'], 0)
                self.assertTrue(source['public'])
                config = team['x']
                self.assertTrue(relevant({'text': config['match_terms'][0] + ' practice report'}, config, set()))
                self.assertFalse(relevant({'text': 'Election polling update and a weather forecast'}, config, set()))
                self.assertFalse(relevant({'text': '#NHL hockey highlights'}, config, set()))

    def test_all_nhl_teams_have_reviewed_sources_and_filter_unrelated_posts(self):
        root = Path(__file__).resolve().parents[2]
        teams = apply_list_mappings(json.loads((root / 'config/nhl-teams.json').read_text()), 'nhl', root)
        manifest = json.loads((root / 'config/lab-x-lists.json').read_text())['leagues']['nhl']
        self.assertEqual(len(manifest), 32)
        for team in teams:
            with self.subTest(team=team['abbreviation']):
                source = manifest[team['abbreviation']]
                self.assertGreater(source['members_at_verification'], 0)
                self.assertTrue(source['public'])
                config = team['x']
                self.assertTrue(relevant({'text': config['match_terms'][0] + ' practice report'}, config, set()))
                self.assertFalse(relevant({'text': 'Election polling update and a weather forecast'}, config, set()))
                self.assertFalse(relevant({'text': '#NFL touchdown highlights'}, config, set()))
        self.assertEqual(manifest['FLA']['list_id'], '1428032013945163779')
        self.assertEqual(manifest['LA']['list_id'], '1031965332313800704')

    def test_capitals_do_not_accept_kraken_lineup_through_shared_lindgren_surname(self):
        root = Path(__file__).resolve().parents[2]
        team = next(t for t in json.loads((root / 'config/nhl-teams.json').read_text()) if t['abbreviation'] == 'WSH')
        roster = terms_for_names(['Charlie Lindgren'])
        self.assertFalse(relevant({'text': 'Kraken at practice: Lindgren-Fleury'}, team['x'], roster))
        self.assertTrue(relevant({'text': 'Charlie Lindgren starts tonight'}, team['x'], roster))
        self.assertTrue(relevant({'text': '@Capitals: Lindgren starts tonight'}, team['x'], roster))


if __name__ == '__main__':
    unittest.main()
