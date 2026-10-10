import copy
import json
from pathlib import Path
import tempfile
import unittest
import build_separated_story as s
from story_content import encoded
ROOT = Path(__file__).resolve().parents[1]

class SeparatedStoryTests(unittest.TestCase):
    def setUp(self):
        self.proof = json.loads((ROOT/'docs/stories/separated-story-source.json').read_bytes())
    def test_verified_resource_bytes_and_isolation(self):
        with tempfile.TemporaryDirectory() as directory:
            s.write(s.build(self.proof),Path(directory),self.proof['retrievedAt'])
            for file in Path(directory).iterdir(): self.assertEqual(file.read_bytes(),(ROOT/'ios/Hub Ball/Hub Ball'/file.name).read_bytes())
        published=json.loads((ROOT/'data/stories/catalog-v1.json').read_bytes())
        self.assertNotIn('separated-by-one',[x['id'] for x in published['stories']])
    def test_both_full_regular_season_arrays_and_ending_measures(self):
        story=s.build(self.proof);chart=story['chart']
        self.assertEqual([x['y'] for x in chart['series'][0]['points']],s.CWS)
        self.assertEqual([x['y'] for x in chart['series'][1]['points']],s.CLE)
        self.assertEqual(chart['durationSeconds'],10); self.assertEqual(chart['yAxis']['maximum'],70)
        self.assertEqual(chart['emphasis'][0]['holdSeconds'],0)
        self.assertIn('CWS 7 · CLE 6',chart['emphasis'][0]['detail']);self.assertIn('CLE 85 · CWS 84',chart['emphasis'][0]['detail'])
    def test_wrong_game_type_totals_or_time_fail(self):
        for field in ['type','score','time','series']:
            bad=copy.deepcopy(self.proof)
            if field=='type':bad['regularSeason'][0]['gameType']='D'
            if field=='score':bad['regularSeason'][0]['cws']=5
            if field=='time':bad['game5']['utc']='2026-10-11T01:00:00Z'
            if field=='series':bad['game5']['seriesWins']=[3,2]
            with self.assertRaises(ValueError):s.build(bad)

if __name__=='__main__':unittest.main()
