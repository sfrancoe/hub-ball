import copy, json, unittest, tempfile
from publish_story import stage
from pathlib import Path
from build_cleveland_k_story import build, project, COMMENTARY
from story_content import validate_payload

class ClevelandFactsTests(unittest.TestCase):
    def setUp(self):
        self.feed=json.loads((Path(__file__).resolve().parent / "fixtures/cleveland-849831-outs.json").read_text())
    def test_official_out_sequence_and_exact_commentary(self):
        story=build(self.feed,"2026-10-11T15:00:00Z")
        self.assertEqual(story['commentary'],COMMENTARY)
        self.assertEqual([o['number'] for o in story['outs'] if o['result']=='other'],[1,3,9,14,17,24])
        self.assertEqual(sum(o['result']=='strikeout' for o in story['outs']),21)
    def test_local_stage_declares_capability_four_and_preserves_fallback(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);payload=root/'story.json'
            payload.write_text(json.dumps(build(self.feed,"2026-10-11T15:00:00Z")))
            catalog=stage(payload,root/'data','A private test',[114])
            self.assertEqual(catalog['stories'][0]['minimumRendererVersion'],4)
            self.assertEqual(catalog['stories'][0]['fallback'],COMMENTARY)
    def test_wrong_score_and_double_play_fail(self):
        self.feed['liveData']['linescore']['teams']['home']['runs']=3
        with self.assertRaises(ValueError):project(self.feed)
        self.feed['liveData']['linescore']['teams']['home']['runs']=2
        play=next(p for p in self.feed['liveData']['plays']['allPlays'] if p['about']['isTopInning'] and p['count']['outs']==1)
        play['count']['outs']=2
        with self.assertRaises(ValueError):project(self.feed)
    def test_duration_order_inning_result_and_capability_rejected(self):
        original=build(self.feed,"2026-10-11T15:00:00Z")
        for change in ['duration','order','inning','result']:
            story=copy.deepcopy(original)
            if change=='duration':story['durationSeconds']=False
            elif change=='order':story['outs'][0]['number']=2
            elif change=='inning':story['outs'][0]['inning']=2
            else:story['outs'][0]['result']='eval'
            with self.assertRaises(ValueError):validate_payload(story)
        entry={k:original[k] for k in ['id','title','renderer','rendererVersion']};entry['minimumRendererVersion']=3
        with self.assertRaises(ValueError):validate_payload(original,entry)

if __name__=='__main__':unittest.main()
