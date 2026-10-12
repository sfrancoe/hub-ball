import assert from 'node:assert/strict';
import handler, { TEAMS } from '../netlify/functions/mlb-data.mjs';

const originalFetch = globalThis.fetch;
const requests = [];
globalThis.fetch = async url => {
  requests.push(String(url));
  if (String(url).includes('/standings')) {
    const nationalLeague = new URL(String(url)).searchParams.get('leagueId') === '104';
    const division = (id, name, abbreviation, rank) => ({
      standingsType: 'regularSeason',
      division: { id },
      lastUpdated: '2026-09-10T02:15:01.914Z',
      teamRecords: [{
        team: {
          id: id === 201 ? 111 : id === 204 ? 121 : id,
          name, shortName: name, abbreviation,
        },
        divisionRank: String(rank), wins: 80, losses: 67,
        winningPercentage: '.544', gamesBack: '8.0', wildCardGamesBack: '+6.0',
        streak: { streakCode: 'L2' },
        records: { splitRecords: [{ type: 'lastTen', wins: 6, losses: 4 }] },
      }],
    });
    const divisions = nationalLeague
      ? [
        division(204, 'New York Mets', 'NYM', 2),
        division(205, 'Chicago Cubs', 'CHC', 1),
        division(203, 'Los Angeles Dodgers', 'LAD', 1),
      ]
      : [
        division(201, 'Boston Red Sox', 'BOS', 3),
        division(202, 'Cleveland Guardians', 'CLE', 1),
        division(200, 'Seattle Mariners', 'SEA', 1),
      ];
    const favorite = nationalLeague
      ? { id: 121, name: 'New York Mets', shortName: 'NY Mets', abbreviation: 'NYM' }
      : { id: 111, name: 'Boston Red Sox', shortName: 'Boston', abbreviation: 'BOS' };
    return new Response(JSON.stringify({ records: [
      ...divisions,
      {
        standingsType: 'wildCard',
        lastUpdated: '2026-09-10T02:15:01.914Z',
        teamRecords: [{
          team: favorite,
          wildCardRank: '1', wins: 80, losses: 67, winningPercentage: '.544',
          gamesBack: '8.0', wildCardGamesBack: '+6.0', streak: { streakCode: 'L2' },
          records: { splitRecords: [{ type: 'lastTen', wins: 6, losses: 4 }] },
        }],
      },
    ] }));
  }
  if (String(url).includes('/schedule')) {
    return new Response(JSON.stringify({ dates: [] }));
  }
  if (String(url).includes('/content')) {
    return new Response(JSON.stringify({
      editorial: { recap: { mlb: { headline: 'Boston wins', slug: 'boston-wins' } } },
    }));
  }
  return new Response(JSON.stringify({
    gamePk: 123,
    gameData: { teams: { away: { id: 111 }, home: { id: 147 } } },
  }));
};

let response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=red-sox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[0], /teamId=111/);
assert.match(requests[0], /startDate=2026-09-01/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=redsox&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[1], /teamId=111/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=mets&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[2], /teamId=121/);

response = await handler(new Request(
  'https://example.test/api/mlb/schedule?team=rays&startDate=2026-09-01&endDate=2026-09-06',
));
assert.equal(response.status, 200);
assert.match(requests[3], /teamId=139/);

assert.equal(TEAMS.size, 31);
assert.equal(TEAMS.get('orioles'), 110);
assert.equal(TEAMS.get('dodgers'), 119);
assert.equal(TEAMS.get('brewers'), 158);

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=123'));
assert.equal(response.status, 200);
assert.match(requests[4], /game\/123\/feed\/live/);
assert.match(requests[5], /game\/123\/content/);
assert.deepEqual((await response.json()).officialRecap, {
  headline: 'Boston wins',
  url: 'https://www.mlb.com/news/boston-wins',
});

response = await handler(new Request('https://example.test/api/mlb/standings?team=redsox'));
assert.equal(response.status, 200);
assert.match(requests[6], /leagueId=103/);
assert.equal(response.headers.get('X-Data-Freshness'), 'live');
assert.equal(response.headers.get('Netlify-CDN-Cache-Control'),
  'public, durable, max-age=30, stale-while-revalidate=30');
const standings = await response.json();
assert.equal(standings.freshness, 'live');
assert.equal(standings.source_updated_at, '2026-09-10T02:15:01.914Z');
assert.equal(standings.divisions[0].name, 'AL East');
assert.equal(standings.divisions[0].teams[0].losses, 67);
assert.equal(standings.divisions[0].teams[0].is_favorite, true);
assert.equal(standings.wild_card[0].streak, 'L2');

response = await handler(new Request('https://example.test/api/mlb/standings?team=mets'));
assert.equal(response.status, 200);
assert.match(requests[7], /leagueId=104/);
const nationalStandings = await response.json();
assert.equal(nationalStandings.league, 'National League');
assert.equal(nationalStandings.divisions[0].name, 'NL East');
assert.equal(nationalStandings.divisions[0].teams[0].is_favorite, true);

response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=nope'));
assert.equal(response.status, 404);

response = await handler(new Request('https://example.test/api/mlb/schedule?team=unknown'));
assert.equal(response.status, 404);

globalThis.fetch = async url => {
  if (String(url).startsWith('https://statsapi.mlb.com/')) {
    return new Response('{"error":"unavailable"}', { status: 502 });
  }
  assert.equal(String(url),
    'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/redsox/standings.json');
  return new Response(JSON.stringify({
    generated_at: '2026-09-10T00:15:03Z', source: 'MLB Stats API', season: 2026,
    league: 'American League', divisions: [{ id: 201, name: 'AL East', teams: [] }],
    wild_card: [],
  }));
};
response = await handler(new Request('https://example.test/api/mlb/standings?team=redsox'));
assert.equal(response.status, 200);
assert.equal(response.headers.get('X-Data-Freshness'), 'stale');
assert.equal((await response.json()).freshness, 'stale');

const cacheHeaderCases = [
  ['live', { abstractGameState: 'Live', codedGameState: 'I' },
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['confirmed final', { abstractGameState: 'Final', codedGameState: 'F' },
    'public, max-age=300, stale-while-revalidate=60',
    'public, durable, max-age=300, stale-while-revalidate=60'],
  ['confirmed extra-innings final', { abstractGameState: 'Final', codedGameState: 'O' },
    'public, max-age=300, stale-while-revalidate=60',
    'public, durable, max-age=300, stale-while-revalidate=60'],
  ['suspended', { abstractGameState: 'Live', codedGameState: 'S' },
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['postponed', { abstractGameState: 'Preview', codedGameState: 'P' },
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['cancelled', { abstractGameState: 'Final', codedGameState: 'C' },
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['missing status', {},
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['malformed status', null,
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
  ['unknown status', { abstractGameState: 'Final', codedGameState: 'D' },
    'public, max-age=5, stale-while-revalidate=15',
    'public, durable, max-age=5, stale-while-revalidate=15'],
];

for (const [label, status, cacheControl, cdnCacheControl] of cacheHeaderCases) {
  globalThis.fetch = async url => {
    if (String(url).includes('/content')) return new Response('{}');
    return new Response(JSON.stringify({
      gamePk: 123,
      gameData: {
        status,
        teams: { away: { id: 111 }, home: { id: 147 } },
      },
    }));
  };
  response = await handler(new Request('https://example.test/api/mlb/game?team=red-sox&gamePk=123'));
  assert.equal(response.status, 200, label);
  assert.equal(response.headers.get('Cache-Control'), cacheControl, label);
  assert.equal(response.headers.get('Netlify-CDN-Cache-Control'), cdnCacheControl, label);
}

// Old installed apps still send gameType=R. The gateway must discover every
// postseason round for all teams without waiting for an app update.
for (const [team, teamID] of TEAMS) {
  for (const gameType of ['R', 'F', 'D', 'L', 'W']) {
    globalThis.fetch = async url => {
      const query = new URL(url).searchParams;
      assert.equal(query.get('teamId'), String(teamID));
      assert.equal(query.get('gameType'), null);
      const included = query.get('gameTypes').split(',');
      assert.deepEqual(included, ['R', 'F', 'D', 'L', 'W']);
      return Response.json({ dates: [{ games: included.includes(gameType) ? [{
        gamePk: 849851, gameType,
        status: { abstractGameState: 'Live', codedGameState: 'I' },
      }] : [] }] });
    };
    response = await handler(new Request(
      `https://example.test/api/mlb/schedule?team=${team}&startDate=2026-09-29&endDate=2026-09-29&gameType=R`,
    ));
    assert.equal(response.status, 200);
    assert.equal((await response.json()).dates[0].games[0].gameType, gameType);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=5, stale-while-revalidate=15');
  }
}

globalThis.fetch = originalFetch;
console.log('MLB live-data gateway tests passed');

const { projectGame } = await import('../netlify/functions/mlb-data.mjs');
const projected = projectGame({
  gamePk: 123, gameData: { players: { ID1: { lastName: 'Betts', biography: 'unused' } } },
  officialRecap: { headline: 'Recap', url: 'https://mlb.com/news/recap' },
  liveData: { plays: { scoringPlays: [1, 3], allPlays: [
    { result: { event: 'Out' } },
    { about: { inning: 1, halfInning: 'top', unused: true }, result: { event: 'Home Run', awayScore: 1 }, matchup: { batter: { fullName: 'Betts' }, pitcher: {} }, playEvents: Array(100).fill('pitch') },
    { result: { event: 'Out' } },
    { about: { inning: 3, halfInning: 'bottom' }, result: { event: 'Single', homeScore: 1 } },
  ] } },
});
assert.equal(projected.schema, 2);
assert.deepEqual(projected.liveData.plays.scoringPlays, [0, 1]);
assert.equal(projected.liveData.plays.allPlays[0].result.event, 'Home Run');
assert.equal(projected.liveData.plays.allPlays[1].about.inning, 3);
assert.equal(projected.liveData.plays.allPlays[0].playEvents, undefined);
assert.equal(projected.gameData.players.ID1.biography, undefined);
assert.equal(projected.officialRecap.headline, 'Recap');
console.log('MLB projection preserves scoring indices and removes unused fields');
const { gameNarratives } = await import('../netlify/lib/game-narrative.mjs');
const derby = {
  gameData: { status: { abstractGameState: 'Final', codedGameState: 'F' }, teams: {
    away: { id: 119, name: 'Los Angeles Dodgers', teamName: 'Dodgers' },
    home: { id: 137, name: 'San Francisco Giants', teamName: 'Giants' },
  }, venue: { name: 'Oracle Park' } },
  liveData: { linescore: { teams: { away: { runs: 4 }, home: { runs: 2 } } } },
};
assert.match(gameNarratives(derby)[119].summary, /^The Dodgers beat the Giants, 4–2/);
assert.match(gameNarratives(derby)[137].summary, /^The Giants fell to the Dodgers, 4–2/);
assert.doesNotMatch(JSON.stringify(gameNarratives(derby)), /Boston|Red Sox/);

// Ported sentences from the original on-device recap: go-ahead plays, the
// losing side's biggest swing, and walk-off wording.
const scoredGame = (away, home, runs, plays, venue = 'Fenway Park') => ({
  gameData: { status: { abstractGameState: 'Final', codedGameState: 'F' }, teams: { away, home }, venue: { name: venue } },
  liveData: {
    linescore: { teams: { away: { runs: runs[0] }, home: { runs: runs[1] } } },
    plays: {
      scoringPlays: plays.map((_, index) => index),
      allPlays: plays.map(([inning, batter, event, rbi, awayScore, homeScore]) => ({
        about: { inning }, matchup: { batter: { fullName: batter } },
        result: { event, rbi, awayScore, homeScore },
      })),
    },
  },
});
const royals = { id: 118, name: 'Kansas City Royals', teamName: 'Royals' };
const redSox = { id: 111, name: 'Boston Red Sox', teamName: 'Red Sox' };
const yankees = { id: 147, name: 'New York Yankees', teamName: 'Yankees' };
const mets = { id: 121, name: 'New York Mets', teamName: 'Mets' };

const goAhead = gameNarratives(scoredGame(royals, redSox, [1, 4], [
  [2, 'Bobby Witt Jr.', 'Single', 1, 1, 0],
  [6, 'Rafael Devers', 'Home Run', 2, 1, 2],
  [8, 'Jarren Duran', 'Double', 2, 1, 4],
]));
assert.equal(goAhead[111].summary, 'The Red Sox beat the Royals, 4–1, at Fenway Park. '
  + 'Rafael Devers’ two-run home run in the 6th put Boston ahead for good.');
assert.equal(goAhead[118].summary, 'The Royals fell to the Red Sox, 4–1, at Fenway Park. '
  + 'Rafael Devers’ two-run home run in the 6th put the Red Sox ahead for good. '
  + 'Kansas City’s biggest swing came on Bobby Witt Jr.’s single in the 2nd.');

const walkoff = gameNarratives(scoredGame(yankees, redSox, [2, 3], [
  [1, 'Aaron Judge', 'Home Run', 2, 2, 0],
  [5, 'Trevor Story', 'Single', 1, 2, 1],
  [9, 'Rafael Devers', 'Home Run', 2, 2, 3],
]));
assert.equal(walkoff[111].summary, 'Rafael Devers delivered a walk-off home run in the 9th inning as the Red Sox '
  + 'rallied past the Yankees, 3–2, at Fenway Park. '
  + 'Boston trailed 2–0 before Trevor Story’s single in the 5th cut the deficit to one.');

const subway = gameNarratives(scoredGame(mets, yankees, [1, 3], [
  [3, 'Pete Alonso', 'Home Run', 1, 1, 0],
  [4, 'Aaron Judge', 'Home Run', 3, 1, 3],
], 'Yankee Stadium'));
assert.equal(subway[147].summary, 'The Yankees beat the Mets, 3–1, at Yankee Stadium. '
  + 'Aaron Judge’s three-run home run in the 4th put the Yankees ahead for good.');
assert.match(subway[121].summary, /The Mets’ biggest swing came on Pete Alonso’s home run in the 3rd\.$/);
assert.doesNotMatch(JSON.stringify(subway), /New York/, 'Same-city games name the club, not the city');
console.log('Server recaps keep go-ahead, biggest-swing and walk-off sentences');
