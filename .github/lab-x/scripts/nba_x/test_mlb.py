import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import build
from mlb import CLUBS_SOURCE, BOSTON_LIST, configured_teams, source_url
from sources import SyndicationLabSource


class MLBTests(unittest.TestCase):
    def test_all_30_sources_use_exact_official_authors_except_boston_list(self):
        teams = configured_teams(build.ROOT)
        self.assertEqual(len(teams), 30)
        self.assertEqual(len({t['x']['handle'].lower() for t in teams}), 30)
        for team in teams:
            if team['abbreviation'] == 'BOS':
                self.assertEqual(team['x']['list_id'], BOSTON_LIST)
            else:
                self.assertIsNone(team['x']['list_id'])
                self.assertEqual(source_url(team, CLUBS_SOURCE), 'https://x.com/' + team['x']['handle'])

    def test_one_shared_fetch_builds_all_clubs_without_cross_team_posts(self):
        teams = configured_teams(build.ROOT)
        tweets = [dict(id_str=str(i), full_text='An official update', user=dict(screen_name=t['x']['handle']),
                       created_at='Wed Nov 11 12:00:00 +0000 2026') for i, t in enumerate(teams, 1)]
        tweets.append(dict(id_str='99', full_text='Red Sox practice report', user=dict(screen_name='reporter'),
                           created_at='Wed Nov 11 12:00:00 +0000 2026'))
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, HUB_LAB_ALLOW_UNOFFICIAL_X='1'), \
             patch('sys.argv', ['build.py', '--sport', 'mlb', '--all', '--data-dir', tmp]), \
             patch.object(SyndicationLabSource, 'list_posts', return_value=tweets) as request, \
             patch.object(build, 'roster_terms', return_value=set()) as roster:
            self.assertEqual(build.main(), 0)
            self.assertEqual({c.args[0] for c in request.call_args_list}, {CLUBS_SOURCE, BOSTON_LIST})
            self.assertEqual(request.call_count, 2)
            self.assertEqual(roster.call_count, 1)
            for team in teams:
                feed = json.loads((Path(tmp) / team['abbreviation'] / 'x-feed.json').read_text())
                self.assertEqual(feed['sport'], 'mlb')
                self.assertEqual(feed['team_id'], team['id'])
                self.assertEqual(len(feed['recent']), 1)
                self.assertIsNone(feed['recent'][0]['likes'])
                self.assertEqual(feed['popular'], [])
                if team['abbreviation'] != 'BOS':
                    self.assertEqual(feed['recent'][0]['handle'], team['x']['handle'])

    def test_shared_clubs_adapter_uses_existing_public_route(self):
        body = b'<script id="__NEXT_DATA__">{"props":{"pageProps":{"timeline":{"entries":[]}}}}</script>'
        with patch.dict(os.environ, HUB_LAB_ALLOW_UNOFFICIAL_X='1'), patch('sources.fetch', return_value=body) as fetch:
            self.assertEqual(SyndicationLabSource().list_posts(CLUBS_SOURCE), [])
            self.assertIn('/screen-name/MLB/slug/clubs?', fetch.call_args.args[0])
