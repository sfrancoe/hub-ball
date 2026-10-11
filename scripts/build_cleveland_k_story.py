#!/usr/bin/env python3
"""Verify official Cleveland outs; bundle private content only, never publish."""
from collections import Counter
from datetime import datetime, timezone
import argparse, json
from pathlib import Path
from story_content import encoded, digest, require, validate_catalog, validate_payload

COMMENTARY = "Cleveland set a major league record (regular OR postseason) for the number of strikeouts in a 9-inning game going back to 1900. They did this in the deciding Game 5 of the ALDS. Guardians move on after winning 2-0."
FEED_URL = 'https://statsapi.mlb.com/api/v1.1/game/849831/feed/live'
RECORD_URL = 'https://www.mlb.com/news/stats-and-facts-from-the-guardians-2026-alds-game-5-win'

def project(feed):
    g=feed['gameData']; scores=feed['liveData']['linescore']['teams']
    require(feed['gamePk']==849831 and g['datetime']['officialDate']=='2026-10-10' and g['game']['type']=='D', 'Wrong game/date/type')
    require(g['status']['abstractGameState']=='Final' and g['teams']['home']['id']==114 and g['teams']['away']['id']==145 and scores['home']['runs']==2 and scores['away']['runs']==0, 'Final result changed')
    outs=[]; previous={}
    for play in feed['liveData']['plays']['allPlays']:
        if not play['about']['isTopInning']: continue
        inning=play['about']['inning']; before=previous.get(inning,0); after=play['count']['outs']
        if after<=before: continue
        require(after-before==1 and after==len([o for o in outs if o['inning']==inning])+1, 'Multiple or missing outs')
        runner_outs=[r for r in play['runners'] if r['movement'].get('isOut')]
        require(len(runner_outs)==1 and runner_outs[0]['details']['runner']['id']==play['matchup']['batter']['id'], 'Expected one batter out, no runner/double-play outs')
        outs.append({'number':len(outs)+1,'inning':inning,'result':'strikeout' if play['result']['eventType']=='strikeout' else 'other','pitcher':play['matchup']['pitcher']['fullName'],'batter':play['matchup']['batter']['fullName']})
        previous[inning]=after
    require(len(outs)==27 and [o['number'] for o in outs if o['result']=='other']==[1,3,9,14,17,24], 'Selected out sequence changed')
    require(Counter(o['pitcher'] for o in outs)=={'Gavin Williams':17,'Erik Sabrowski':1,'Hunter Gaddis':4,'Cade Smith':5}, 'Pitcher outs mismatch')
    require(Counter(o['pitcher'] for o in outs if o['result']=='strikeout')=={'Gavin Williams':12,'Erik Sabrowski':1,'Hunter Gaddis':4,'Cade Smith':4}, 'Pitcher strikeouts mismatch')
    return outs

def build(feed, stamp):
    return validate_payload({'schemaVersion':1,'id':'almost-every-out-a-k','renderer':'inning-out-grid','rendererVersion':1,'title':'Almost every out a K','heading':'Wow!','commentary':COMMENTARY,'durationSeconds':9.6,'outs':project(feed),
        'methodology':['All 27 Chicago batter outs in chronological top-inning order from official Game 849831 play-by-play. No double plays or runner outs. The six non-strikeout outs are 1, 3, 9, 14, 17 and 24.','Williams: 12 strikeouts in 17 outs; Sabrowski: 1 in 1; Gaddis: 4 in 4; Smith: 4 in 5. Total 21 strikeouts in 27 outs.','MLB reports a nine-inning team strikeout record across regular season and postseason since at least 1900. Commentary is the exact wording approved by Scott on October 11, 2026.','Original native tiles and typography only. No copied photos, video, logos, audio, or article text. Source access alone does not grant commercial reuse rights.'],
        'sources':[{'id':'mlb-game','title':'MLB official ALDS Game 5 live feed, October 10, 2026','url':FEED_URL,'retrievedAt':stamp},{'id':'mlb-record','title':'MLB stats and facts from the Guardians 2026 ALDS Game 5 win','url':RECORD_URL,'retrievedAt':stamp}]})

def main():
    a=argparse.ArgumentParser();a.add_argument('--feed',type=Path,required=True);a.add_argument('--output',type=Path,required=True);args=a.parse_args()
    stamp=datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ');story=build(json.loads(args.feed.read_text()),stamp);data=encoded(story)
    entry={'id':story['id'],'title':story['title'],'revision':digest(data),'summary':'All 27 outs. Twenty-one strikeouts. Cleveland advances with a 2–0 Game 5 win.','fallback':'Cleveland struck out 21 White Sox batters in 27 outs to win ALDS Game 5, 2–0, on October 10, 2026.','publishedAt':stamp,'teamIDs':[114],'renderer':'inning-out-grid','rendererVersion':1,'minimumRendererVersion':4}
    catalog={'schemaVersion':1,'revision':'private-cleveland-october11','publishedAt':stamp,'stories':[entry]};validate_catalog(catalog);validate_payload(story,entry)
    args.output.mkdir(parents=True,exist_ok=True);(args.output/'story-private-cleveland-k.json').write_bytes(data);(args.output/'story-private-cleveland-catalog.json').write_bytes(encoded(catalog));print('Private bundled grid:',entry['revision'])

if __name__=='__main__':main()
