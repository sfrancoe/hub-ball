import unittest
from datetime import datetime, timezone
from audit import check_feed


class AuditTests(unittest.TestCase):
    def test_distinguishes_fresh_correct_feed_from_stale_empty_or_wrong_source(self):
        now = datetime(2026, 11, 11, 12, tzinfo=timezone.utc)
        team = dict(id='2', sportID='NBA')
        post = dict(id='123', text='Observed post', url='https://x.com/reporter/status/123',
                    published='2026-11-11T11:00:00+00:00', likes=None)
        feed = dict(sport='nba', team_id='2', source_url='https://x.com/i/lists/1',
                    source_kind='syndication-lab', generated_at=now.isoformat(), recent=[post], popular=[])
        def errors(value):
            return check_feed(value, team, feed['source_url'], now, 12)['errors']
        self.assertEqual(errors(feed), [])
        self.assertIn('wrong sport/team', errors(dict(feed, sport='mlb')))
        self.assertIn('wrong source', errors(dict(feed, source_url='https://x.com/i/lists/2')))
        self.assertIn('empty or oversized feed', errors(dict(feed, recent=[])))
        self.assertIn('observation outside freshness window', errors(dict(feed, generated_at='2026-11-10T12:00:00+00:00')))
        self.assertIn('invalid popular eligibility', errors(dict(feed, popular=[post])))
