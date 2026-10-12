import base64, copy, json, unittest
from pathlib import Path
from story_content import validate_payload, validate_entry

class ScreeningContentTests(unittest.TestCase):
    def setUp(self):
        root=Path(__file__).resolve().parents[1]
        envelope=json.loads((root/'ios/Hub Ball/Hub Ball/featured-preview.json').read_text())
        self.payload=json.loads(base64.b64decode(envelope['payloadBase64'])); self.entry=envelope['manifest']['entry']
    def test_exact_annual_outs_and_japan_interval(self):
        validate_payload(self.payload,self.entry)
        points=self.payload['chart']['series'][0]['points']
        self.assertEqual([round(p['y']*3) for p in points],[5,0,19,0,0,0,518])
        self.assertEqual(self.payload['presentation']['intervals'][0],{'start':2022.5,'end':2025.5,'label':'JAPAN · 2023–25'})
    def test_unsafe_style_and_invalid_intervals_rejected(self):
        for mutate in [lambda p:p['presentation'].update(style='remote-html'),lambda p:p['presentation']['intervals'][0].update(start=1900),lambda p:p['presentation'].update(sweepSeconds=float('inf'))]:
            payload=copy.deepcopy(self.payload);mutate(payload)
            with self.assertRaises(ValueError):validate_payload(payload,self.entry)
    def test_baseball_notation_cannot_be_mistaken_for_decimal_innings(self):
        payload=copy.deepcopy(self.payload);payload['chart']['series'][0]['points'][-1]['y']=172.2
        with self.assertRaises(ValueError):validate_payload(payload,self.entry)
    def test_older_capability_cannot_claim_screening_presentation(self):
        entry=copy.deepcopy(self.entry);entry['minimumRendererVersion']=4
        with self.assertRaises(ValueError):validate_payload(self.payload,entry)
if __name__=='__main__':unittest.main()
