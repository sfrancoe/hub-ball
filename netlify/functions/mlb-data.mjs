import { gameNarratives } from '../lib/game-narrative.mjs';
import { MLB_TEAMS } from './team-registry.mjs';

const MLB_ORIGIN = 'https://statsapi.mlb.com';
const RAW_DATA_ROOT = 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data';
const FALLBACK_USER_AGENT = 'HubBall/1.0 (+https://api.autumnlane.io)';
const LIVE_GAME_CACHE_CONTROL = 'public, max-age=5, stale-while-revalidate=15';
const FINAL_GAME_CACHE_CONTROL = 'public, max-age=300, stale-while-revalidate=60';
export const TEAMS = new Map(MLB_TEAMS.map(team => [team.api_key, team.mlb_id]));
TEAMS.set('red-sox', 111);
const TEAM_CONFIGS = new Map(MLB_TEAMS.map(team => [team.api_key, team]));
TEAM_CONFIGS.set('red-sox', TEAM_CONFIGS.get('redsox'));
const LEAGUES = {
  AL: {
    id: 103,
    name: 'American League',
    divisions: new Map([[201, 'AL East'], [202, 'AL Central'], [200, 'AL West']]),
    order: [201, 202, 200],
  },
  NL: {
    id: 104,
    name: 'National League',
    divisions: new Map([[204, 'NL East'], [205, 'NL Central'], [203, 'NL West']]),
    order: [204, 205, 203],
  },
};

function validDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value || '');
}

function easternDate(date = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

async function fetchSource(url, request = fetch) {
  let lastError;
  for (const headers of [
    { Accept: 'application/json' },
    { Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT },
  ]) {
    try {
      const response = await request(url, {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`Upstream returned ${response.status}`);
      const body = await response.text();
      const payload = JSON.parse(body);
      return { body, payload };
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function upstreamURL(requestURL, team) {
  const route = requestURL.pathname.replace(/^\/api\/mlb\/?/, '');
  if (route === 'schedule') {
    const today = easternDate();
    const startDate = validDate(requestURL.searchParams.get('startDate'))
      ? requestURL.searchParams.get('startDate')
      : today;
    const endDate = validDate(requestURL.searchParams.get('endDate'))
      ? requestURL.searchParams.get('endDate')
      : today;
    const url = new URL('/api/v1/schedule', MLB_ORIGIN);
    url.search = new URLSearchParams({
      sportId: '1',
      teamId: String(team.mlb_id),
      startDate,
      endDate,
      // Include every postseason round, even for installed clients sending gameType=R.
      gameTypes: 'R,F,D,L,W',
    });
    return { route, url };
  }

  if (route === 'game') {
    const gamePk = requestURL.searchParams.get('gamePk') || '';
    if (!/^\d{1,10}$/.test(gamePk)) return null;
    return { route, url: new URL(`/api/v1.1/game/${gamePk}/feed/live`, MLB_ORIGIN) };
  }

  if (route === 'standings') {
    const league = LEAGUES[team.league];
    if (!league) return null;
    const url = new URL('/api/v1/standings', MLB_ORIGIN);
    url.search = new URLSearchParams({
      leagueId: String(league.id),
      season: easternDate().slice(0, 4),
      standingsTypes: 'regularSeason,wildCard',
      hydrate: 'team',
    });
    return { route, url, league };
  }
  return null;
}

function lastTen(teamRecord) {
  const split = teamRecord?.records?.splitRecords?.find(item => item.type === 'lastTen');
  return split ? `${split.wins || 0}-${split.losses || 0}` : '—';
}

function standingsRow(teamRecord, rankKey, favoriteID) {
  const team = teamRecord.team || {};
  return {
    id: team.id,
    name: team.name || 'Team',
    short_name: team.shortName || team.teamName || 'Team',
    abbreviation: team.abbreviation || '',
    rank: teamRecord[rankKey] || '—',
    wins: teamRecord.wins || 0,
    losses: teamRecord.losses || 0,
    pct: teamRecord.winningPercentage || '.000',
    games_back: teamRecord.gamesBack || '—',
    wild_card_games_back: teamRecord.wildCardGamesBack || '—',
    last_ten: lastTen(teamRecord),
    streak: teamRecord.streak?.streakCode || '—',
    is_favorite: team.id === favoriteID,
  };
}

function liveStandings(payload, team, league) {
  const divisions = [];
  let wildCard = [];
  for (const record of payload.records || []) {
    const rows = record.teamRecords || [];
    if (record.standingsType === 'regularSeason') {
      const divisionID = record.division?.id;
      const name = league.divisions.get(divisionID);
      if (name) {
        divisions.push({
          id: divisionID,
          name,
          teams: rows.map(row => standingsRow(row, 'divisionRank', team.mlb_id)),
        });
      }
    } else if (record.standingsType === 'wildCard') {
      wildCard = rows.map(row => standingsRow(row, 'wildCardRank', team.mlb_id));
    }
  }
  divisions.sort((a, b) => league.order.indexOf(a.id) - league.order.indexOf(b.id));
  if (divisions.length !== 3 || !wildCard.length) {
    throw new Error('MLB returned incomplete standings');
  }
  const sourceUpdatedAt = (payload.records || [])
    .map(record => record.lastUpdated)
    .filter(Boolean)
    .sort()
    .at(-1);
  return {
    generated_at: new Date().toISOString(),
    source_updated_at: sourceUpdatedAt || null,
    source: 'MLB Stats API',
    freshness: 'live',
    season: Number(easternDate().slice(0, 4)),
    league: league.name,
    divisions,
    wild_card: wildCard,
  };
}

function snapshotPath(team) {
  return `${team.data_directory}/standings.json`;
}

async function savedStandings(team) {
  const { payload } = await fetchSource(`${RAW_DATA_ROOT}/${snapshotPath(team)}`);
  return { ...payload, freshness: 'stale' };
}

function gameIncludesTeam(payload, teamID) {
  const teams = payload?.gameData?.teams;
  return teams?.away?.id === teamID || teams?.home?.id === teamID;
}

function officialRecap(content) {
  const recap = content?.editorial?.recap?.mlb;
  const headline = String(recap?.headline || '').trim();
  const slug = String(recap?.slug || '').trim();
  if (!headline || !slug) return null;
  return { headline, url: `https://www.mlb.com/news/${slug}` };
}

// Schema 2 preserves the installed clients' field names and remaps scoring
// indices after removing non-scoring plays. Never send pitch events to the app.
export function projectGame(payload) {
  const pick = (value, keys) => Object.fromEntries(keys.filter(key => value?.[key] !== undefined)
    .map(key => [key, value[key]]));
  const battingKeys = ['note', 'atBats', 'runs', 'hits', 'rbi', 'baseOnBalls', 'strikeOuts', 'leftOnBase', 'homeRuns', 'stolenBases'];
  const pitchingKeys = ['note', 'inningsPitched', 'hits', 'runs', 'earnedRuns', 'baseOnBalls', 'strikeOuts', 'homeRuns', 'numberOfPitches'];
  const teams = Object.fromEntries(['away', 'home'].map(side => {
    const box = payload.liveData?.boxscore?.teams?.[side] || {};
    const players = Object.fromEntries(Object.entries(box.players || {}).map(([id, player]) => [id, {
      ...pick(player, ['person', 'position']),
      stats: { batting: pick(player.stats?.batting, battingKeys), pitching: pick(player.stats?.pitching, pitchingKeys) },
      seasonStats: { batting: pick(player.seasonStats?.batting, ['avg', 'homeRuns']) },
    }]));
    return [side, { ...pick(box, ['battingOrder', 'batters', 'pitchers']), players }];
  }));
  const plays = payload.liveData?.plays || {};
  const scoring = (plays.scoringPlays || []).map(index => plays.allPlays?.[index]).filter(Boolean)
    .map(play => ({ about: pick(play.about, ['inning', 'halfInning']),
      result: pick(play.result, ['event', 'rbi', 'description', 'awayScore', 'homeScore']),
      matchup: { batter: play.matchup?.batter } }));
  return {
    schema: 2,
    narratives: gameNarratives(payload),
    ...pick(payload, ['gamePk', 'officialRecap']),
    gameData: {
      ...pick(payload.gameData, ['status', 'teams', 'venue', 'datetime', 'gameInfo']),
      players: Object.fromEntries(Object.entries(payload.gameData?.players || {})
        .map(([id, player]) => [id, pick(player, ['lastName'])])),
    },
    liveData: {
      ...pick(payload.liveData, ['linescore', 'decisions']),
      boxscore: { teams },
      plays: { scoringPlays: scoring.map((_, index) => index), allPlays: scoring },
    },
  };
}

export function gameCacheControl(payload) {
  const status = payload?.gameData?.status;
  const isConfirmedFinal = status?.abstractGameState === 'Final'
    && ['F', 'O'].includes(status?.codedGameState);
  return isConfirmedFinal ? FINAL_GAME_CACHE_CONTROL : LIVE_GAME_CACHE_CONTROL;
}

const handleRequest = async request => {
  const requestURL = new URL(request.url);
  const team = TEAM_CONFIGS.get(requestURL.searchParams.get('team'));
  const upstream = team ? upstreamURL(requestURL, team) : null;
  if (!upstream) {
    return Response.json({ error: 'Unknown live-data request.' }, { status: 404 });
  }

  try {
    let { body, payload } = await fetchSource(upstream.url);
    if (upstream.route === 'game' && !gameIncludesTeam(payload, team.mlb_id)) {
      return Response.json({ error: 'Game does not belong to the requested team.' }, { status: 404 });
    }
    if (upstream.route === 'game') {
      const gamePk = requestURL.searchParams.get('gamePk');
      try {
        const contentURL = new URL(`/api/v1/game/${gamePk}/content`, MLB_ORIGIN);
        const { payload: content } = await fetchSource(contentURL);
        const recap = officialRecap(content);
        if (recap) {
          payload = { ...payload, officialRecap: recap };
          body = JSON.stringify(payload);
        }
      } catch (error) {
        // A box score is still useful while MLB's delayed editorial feed catches up.
        console.warn(`Official recap unavailable for game ${gamePk}`, error);
      }
    }
    if (upstream.route === 'game') {
      payload = projectGame(payload);
      body = JSON.stringify(payload);
    }
    if (upstream.route === 'standings') {
      payload = liveStandings(payload, team, upstream.league);
      body = JSON.stringify(payload);
    }
    return new Response(body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': upstream.route === 'standings'
          ? 'public, max-age=30, stale-while-revalidate=30'
          : upstream.route === 'game'
            ? gameCacheControl(payload)
            : LIVE_GAME_CACHE_CONTROL,
        'Netlify-CDN-Cache-Control': upstream.route === 'standings'
          ? 'public, durable, max-age=30, stale-while-revalidate=30'
          : upstream.route === 'game'
            ? `public, durable, ${gameCacheControl(payload).slice('public, '.length)}`
            : `public, durable, ${LIVE_GAME_CACHE_CONTROL.slice('public, '.length)}`,
        'X-Data-Freshness': 'live',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    if (upstream?.route === 'standings') {
      console.warn('Live standings failed; serving saved snapshot', error);
      try {
        const fallback = await savedStandings(team);
        return Response.json(fallback, {
          headers: {
            'Cache-Control': 'public, max-age=15',
            'Netlify-CDN-Cache-Control': 'public, durable, max-age=15',
            'Access-Control-Allow-Origin': '*',
            'X-Content-Type-Options': 'nosniff',
            'X-Data-Freshness': 'stale',
          },
        });
      } catch (fallbackError) {
        console.error('Saved standings fallback failed', fallbackError);
      }
    }
    console.error('Live MLB data failed', error);
    return Response.json({ error: 'Live game data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export default async request => {
  const response = await handleRequest(request);
  response.headers.set('Netlify-Vary', 'query=team|gamePk|startDate|endDate');
  return response;
};

export const config = { path: '/api/mlb/*', method: 'GET' };
