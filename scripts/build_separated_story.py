#!/usr/bin/env python3
"""Verify and bundle a private October 10 story. Never publishes to the shared feed."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from story_content import digest, encoded, require, validate_catalog, validate_payload

CWS = [0,6,8,11,16,19,22,29,31,37,42,49,55,58]
CLE = [0,5,6,10,16,20,21,27,35,38,41,44,51,57]
SCORES = [(6,5),(2,1),(3,4),(5,6),(3,4),(3,1),(7,6),(2,8),(6,3),(5,3),(7,3),(6,7),(3,6)]
SCHEDULE_URL = 'https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=145&opponentId=114&startDate=2026-03-01&endDate=2026-10-10'
STANDINGS_URL = 'https://statsapi.mlb.com/api/v1/standings?leagueId=103&season=2026&standingsTypes=regularSeason&date=2026-09-27'


def proof_from(snapshots: Path) -> dict:
    raw = (snapshots/'schedule.json').read_bytes()
    games = sorted([g for d in json.loads(raw)['dates'] for g in d['games']], key=lambda g: (g['officialDate'],g['gamePk']))
    def project(g):
        teams = {t['team']['id']: t for t in g['teams'].values()}
        require(set(teams) == {145,114}, 'Wrong opponents')
        return {'gameID':g['gamePk'],'date':g['officialDate'],'gameType':g['gameType'],'state':g['status']['abstractGameState'],'cws':teams[145].get('score'),'cle':teams[114].get('score')}
    regular = [project(g) for g in games if g['gameType'] == 'R']
    alds = [project(g) for g in games if g['gameType'] == 'D' and g['status']['abstractGameState'] == 'Final']
    tonight = [g for g in games if g['gamePk'] == 849831]
    require(len(tonight) == 1, 'Expected Game 5')
    g = tonight[0]
    standings_raw = (snapshots/'standings.json').read_bytes()
    rows = [t for record in json.loads(standings_raw)['records'] for t in record['teamRecords'] if t['team']['id'] in [145,114]]
    require(len(rows) == 2, 'Expected both standings rows')
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    proof = {'retrievedAt':stamp,'regularSeason':regular,'aldsExcluded':alds,'seasonWins':{str(t['team']['id']):t['wins'] for t in rows},'game5':{'id':g['gamePk'],'officialDate':g['officialDate'],'utc':g['gameDate'],'state':g['status']['abstractGameState'],'away':g['teams']['away']['team']['id'],'home':g['teams']['home']['team']['id'],'seriesWins':[g['teams']['away']['leagueRecord']['wins'],g['teams']['home']['leagueRecord']['wins']]},'scheduleSHA256':digest(raw),'standingsSHA256':digest(standings_raw)}
    verify(proof)
    return proof


def verify(proof: dict) -> None:
    rows = proof['regularSeason']
    require(len(rows) == 13 and len({r['gameID'] for r in rows}) == 13, 'Expected 13 unique regular-season meetings')
    require(all(r['gameType'] == 'R' and r['state'] == 'Final' for r in rows), 'Only completed regular season allowed')
    require([r['date'] for r in rows] == sorted(r['date'] for r in rows) and rows[0]['date'] == '2026-06-22' and rows[-1]['date'] == '2026-09-16', 'Incorrect chronological series')
    require([(r['cws'],r['cle']) for r in rows] == SCORES, 'Scores disagree with selected premise')
    cws = cle = 0
    a,b = [0],[0]
    for r in rows:
        cws += r['cws']; cle += r['cle']; a.append(cws); b.append(cle)
    require(a == CWS and b == CLE, 'Cumulative totals disagree')
    require(sum(r['cws'] > r['cle'] for r in rows) == 7 and sum(r['cle'] > r['cws'] for r in rows) == 6, 'Wrong head-to-head wins')
    require(proof['seasonWins'] == {'145':84,'114':85}, 'Wrong regular-season standings')
    alds = proof['aldsExcluded']
    require(len(alds) == 4 and all(r['gameType'] == 'D' for r in alds), 'Expected four separately excluded ALDS games')
    require(sum(r['cws'] for r in alds)+58 == 73 and sum(r['cle'] for r in alds)+57 == 78, 'All-17-meetings cross-check mismatch')
    require(proof['game5'] == {'id':849831,'officialDate':'2026-10-10','utc':'2026-10-11T00:00:00Z','state':'Preview','away':145,'home':114,'seriesWins':[2,2]}, 'Game 5 timing or series state changed; reassess tonight copy')


def build(proof: dict) -> dict:
    verify(proof)
    story = {'schemaVersion':1,'id':'separated-by-one','renderer':'chart-trajectory','rendererVersion':1,
        'title':'Separated by One','kicker':'2026 REGULAR-SEASON MEETINGS · OCTOBER 10 PREVIEW',
        'intro':'Thirteen meetings. One run between them. Follow Chicago and Cleveland through their 2026 regular-season series.',
        'chart':{'kind':'line','durationSeconds':10,'xAxis':{'label':'Regular-season meeting','minimum':0,'maximum':13,'ticks':[0,1,3,5,7,9,11,13]},'yAxis':{'label':'Cumulative runs','minimum':0,'maximum':70,'ticks':[0,10,20,30,40,50,60,70]},
        'series':[{'id':'cws','label':'Chicago White Sox','color':'navy','points':[{'x':i,'y':n} for i,n in enumerate(CWS)]},{'id':'cle','label':'Cleveland Guardians','color':'coral','points':[{'x':i,'y':n} for i,n in enumerate(CLE)]}],
        'emphasis':[{'id':'one-game','x':13,'y':58,'holdSeconds':0,'title':'Tonight: one game to advance.','detail':'Head-to-head wins: CWS 7 · CLE 6\nOverall season wins: CLE 85 · CWS 84\nOctober 10, 2026 · CWS at CLE · 8 p.m. ET\nALDS Game 5 · series tied 2–2'}]},
        'conclusion':'2026 regular-season runs: CWS 58 · CLE 57. One run apart across thirteen meetings. One win apart in their head-to-head series. One win apart in the season standings.',
        'methodology':['The chart includes all thirteen completed 2026 REGULAR-SEASON meetings, June 22 through September 16, in date/game-ID order. Each point adds that game’s full final team score. Start at zero; straight connections are visual guides between discrete game totals, not play-by-play. Both series use the same zero-based 0–70 scale and ten-second animation.',
        'Head-to-head wins are Chicago 7, Cleveland 6. Overall regular-season standings as of September 27 are Cleveland 85–77 and Chicago 84–78. These are separate measures, explicitly labeled in the ending comparison.',
        'Spring training and the ALDS are excluded. Through four completed ALDS games, all seventeen regular-season-plus-ALDS meetings would total Chicago 73, Cleveland 78; those are NOT the chart’s 58 and 57.',
        'This is a dated October 10, 2026 preview: ALDS Game 5, Chicago at Cleveland, scheduled for 8 p.m. Eastern (October 11 at 00:00 UTC), series tied 2–2. “Tonight” refers to that date. Scheduling facts were verified when this private build was prepared; this is not a live scoreboard.',
        'Original writing and native graphics of factual scores. No third-party photos, logos, music, video or article prose. Source links support verification; public access is not a commercial reuse license.'],
        'sources':[{'id':'mlb-meetings','title':'MLB official 2026 White Sox–Guardians schedule and scores','url':SCHEDULE_URL,'retrievedAt':proof['retrievedAt']},{'id':'mlb-standings','title':'MLB official American League regular-season standings · September 27','url':STANDINGS_URL,'retrievedAt':proof['retrievedAt']}]}
    return validate_payload(story)


def write(story: dict, output: Path, stamp: str) -> None:
    data = encoded(story)
    entry = {'id':story['id'],'revision':digest(data),'title':story['title'],'summary':'Thirteen 2026 regular-season meetings. Chicago 58 runs, Cleveland 57. Tonight, one game to advance.','fallback':story['conclusion'],'publishedAt':stamp,'teamIDs':[145,114],'renderer':'chart-trajectory','rendererVersion':1,'minimumRendererVersion':2}
    catalog = {'schemaVersion':1,'revision':'private-separated-october10','publishedAt':stamp,'stories':[entry]}
    validate_catalog(catalog);validate_payload(story,entry)
    (output/'story-private-separated-catalog.json').write_bytes(encoded(catalog))
    (output/'story-private-separated-by-one.json').write_bytes(data)


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--snapshots',type=Path)
    p.add_argument('--proof',type=Path,default=root/'docs/stories/separated-story-source.json')
    args = p.parse_args()
    proof = proof_from(args.snapshots) if args.snapshots else json.loads(args.proof.read_bytes())
    args.proof.write_bytes(encoded(proof));story=build(proof)
    write(story,root/'ios/Hub Ball/Hub Ball',proof['retrievedAt'])
    print('Verified13 regular-season games, excluded4 ALDS games; private native resources only. Nothing published.')
