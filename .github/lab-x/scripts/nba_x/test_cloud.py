import unittest
from cloud import permitted_path, outcome


class CloudTests(unittest.TestCase):
    def test_publication_is_limited_to_lab_feeds_rosters_and_status(self):
        for sport in ('mlb', 'nba', 'nfl', 'nhl'):
            self.assertTrue(permitted_path(f'data/{sport}/BOS/x-feed.json'))
            self.assertTrue(permitted_path(f'data/{sport}/BOS/roster.json'))
        self.assertTrue(permitted_path('data/lab-x-status.json'))
        for path in ['.env', '.github/workflows/other.yml', 'data/redsox/x-posts.json',
                     'data/nba/BOS/secret.json', 'data/nba/../../.env']:
            self.assertFalse(permitted_path(path))

    def test_rate_limiting_is_only_healthy_when_all_feeds_still_pass_audit(self):
        self.assertEqual(outcome(75, 0), 'rate-limited')
        self.assertEqual(outcome(75, 1), 'failed')
        self.assertEqual(outcome(1, 0), 'failed')
        self.assertEqual(outcome(0, 0), 'refreshed')
        self.assertEqual(outcome(None, 0), 'verified')
