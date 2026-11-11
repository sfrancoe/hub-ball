import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import build
from sources import RateLimitError, SyndicationLabSource
from rosters import terms_for_names
from filter import relevant


class AllSportsTests(unittest.TestCase):
    def test_nfl_shared_names_and_ordinary_words_do_not_admit_unrelated_posts(self):
        config = dict(list_id='1', match_terms=['new york giants'], link_terms=[], excluded_terms=[])
        roster = terms_for_names(['Isaiah Likely', 'Darius Alexander', 'Jon Harrison'], surnames=False)
        for text in ['The Eagles trade is likely to age well', 'Harrison Butker remains Chiefs kicker', 'Alexander scores for the Lakers']:
            self.assertFalse(relevant({'text': text}, config, roster))
        self.assertTrue(relevant({'text': 'Isaiah Likely returns to practice'}, config, roster))

    def test_all_four_sports_run_year_round(self):
        for month in range(1, 13):
            self.assertEqual(set(build.scheduled_sports(month)), {'mlb', 'nba', 'nfl', 'nhl'})

    def test_global_priority_rate_limit_and_next_run_fairness(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'config').mkdir()
            (root / 'config/nba-x.json').write_text('{"nba_teams_list_id":null}')
            for index, sport in enumerate(['nba', 'nhl', 'nfl', 'mlb'], 1):
                team = dict(id=str(index), abbreviation='ONE', sportID=sport.upper(), x=dict(
                    list_id=str(index), match_terms=['team update'], link_terms=[], excluded_terms=[]))
                (root / f'config/{sport}-teams.json').write_text(json.dumps([team]))
                if sport == 'mlb': mlb_team = team
                if sport != 'nfl':
                    path = root / f'data/{sport}/ONE/x-feed.json'
                    path.parent.mkdir(parents=True)
                    path.write_text(json.dumps(dict(generated_at=f'2026-11-0{index}T12:00:00+00:00', source_url=f'https://x.com/i/lists/{index}')))
            tweet = dict(id_str='123', text='Team update', created_at='Sun Nov 08 12:00:00 +0000 2026', user=dict(screen_name='reporter'))
            with patch.object(build, 'ROOT', root), patch('sys.argv', ['build.py', '--sport', 'all', '--all']), \
                 patch.dict(os.environ, HUB_LAB_ALLOW_UNOFFICIAL_X='1'), \
                 patch.object(build, 'scheduled_sports', return_value=['mlb', 'nfl', 'nhl', 'nba']), \
                 patch.object(build, 'configured_teams', return_value=[mlb_team]), \
                 patch.object(build, 'roster_terms', return_value=set()), \
                 patch.object(SyndicationLabSource, 'list_posts', side_effect=[[tweet], RateLimitError('429')]) as request:
                self.assertEqual(build.main(), 75)
                self.assertEqual([c.args[0] for c in request.call_args_list], ['3', '1'])
                request.reset_mock(side_effect=True)
                request.return_value = [tweet]
                self.assertEqual(build.main(), 0)
                self.assertEqual([c.args[0] for c in request.call_args_list], ['1', '2', '4', '3'])
