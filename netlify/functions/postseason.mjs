import { MLB_TEAMS } from './team-registry.mjs';

const MLB_ORIGIN = 'https://statsapi.mlb.com';
const FALLBACK_USER_AGENT = 'HubBall/1.0 (+https://api.autumnlane.io)';
const SUPPORTED_SEASONS = new Set(['2025', '2026']);
const TEAM_BY_ID = new Map(MLB_TEAMS.map(team => [team.mlb_id, team]));
const ROUND_BY_TYPE = { F: 'wild-card', D: 'division-series', L: 'league-championship', W: 'world-series' };
export const TOURNAMENT_FORMATS = {
  2025: { F: 2, D: 3, L: 4, W: 4 },
  2026: { F: 2, D: 3, L: 4, W: 4 },
};

async function fetchSource(url, request = fetch) {
  let lastError;
  for (const headers of [
    { Accept: 'application/json' },
    { Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT },
  ]) {
    try {
      const response = await request(url, { headers, signal: AbortSignal.timeout(12_000) });
      if (!response.ok) throw new Error(`MLB returned ${response.status}`);
      return await response.json();
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function leagueFor(game) {
  const description = `${game.seriesDescription || ''} ${game.description || ''}`;
  if (/\bAL\b|American League/i.test(description)) return 'AL';
  if (/\bNL\b|National League/i.test(description)) return 'NL';
  return game.gameType === 'W' ? 'MLB' : null;
}

function club(raw) {
  const team = raw?.team || {};
  const id = Number.isInteger(team.id) ? team.id : null;
  const known = id === null ? null : TEAM_BY_ID.get(id);
  const name = typeof team.name === 'string' ? team.name : null;
  const resolved = Boolean(known && name === known.full_name);
  return {
    teamId: resolved ? id : null,
    name,
    abbreviation: resolved ? known.abbreviation : null,
    slot: resolved ? null : name,
    resolved,
  };
}

function gameState(raw, away, home) {
  const status = raw.status || {};
  const final = status.abstractGameState === 'Final'
    && ['F', 'O'].includes(status.codedGameState);
  const awayWinner = raw.teams?.away?.isWinner === true;
  const homeWinner = raw.teams?.home?.isWinner === true;
  const awayScore = raw.teams?.away?.score;
  const homeScore = raw.teams?.home?.score;
  const scoresAgree = Number.isFinite(awayScore) && Number.isFinite(homeScore)
    && awayScore !== homeScore && (awayScore > homeScore) === awayWinner;
  const winner = final && away.resolved && home.resolved && awayWinner !== homeWinner && scoresAgree
    ? (awayWinner ? away.teamId : home.teamId)
    : null;
  return { final, winner };
}

function advancementSlot(season, gameType, league, bracketSlot) {
  if (!league) return null;
  if (gameType === 'F') {
    if (bracketSlot === 'A') return [`${season}-${league.toLowerCase()}-division-series-b`];
    if (bracketSlot === 'B') return [`${season}-${league.toLowerCase()}-division-series-a`];
    return null;
  }
  if (gameType === 'D') return [`${season}-${league.toLowerCase()}-league-championship-main`];
  if (gameType === 'L') return [`${season}-mlb-world-series-main`];
  return null;
}

function isMakeupReplacement(postponed, replacement) {
  if (postponed.status?.codedGameState !== 'D'
    || postponed.status?.detailedState !== 'Postponed'
    || !['Preview', 'Live', 'Final'].includes(replacement.status?.abstractGameState)
    || replacement.status?.codedGameState === 'D'
    || postponed.gameType !== replacement.gameType
    || !leagueFor(postponed) || leagueFor(postponed) !== leagueFor(replacement)) return false;
  for (const side of ['away', 'home']) {
    const old = postponed.teams?.[side], next = replacement.teams?.[side];
    if (!Number.isInteger(old?.team?.id) || old.team.id !== next?.team?.id
      || typeof old.team.name !== 'string' || old.team.name !== next.team.name
      || old.score != null || old.isWinner === true) return false;
  }
  const originalDate = Date.parse(postponed.gameDate), makeupDate = Date.parse(replacement.gameDate);
  if (!Number.isFinite(originalDate) || !Number.isFinite(makeupDate) || makeupDate <= originalDate) return false;
  // MLB may retain the rainout row alongside its explicitly linked makeup,
  // even when the makeup has a different series game number/description.
  const forward = postponed.rescheduleDate, backward = replacement.rescheduledFrom;
  if (forward != null && forward !== replacement.gameDate) return false;
  if (backward != null && backward !== postponed.gameDate) return false;
  return forward === replacement.gameDate || backward === postponed.gameDate;
}

export function normalizePostseason(payload, season, checkedAt = new Date().toISOString()) {
  const sourceGames = (payload.dates || []).flatMap(date => date.games || []);
  const seenGames = new Map();
  const duplicateConflicts = new Set();
  const unidentifiedGames = [];
  for (const raw of sourceGames) {
    if (!Number.isInteger(raw.gamePk)) { unidentifiedGames.push(raw); continue; }
    const prior = seenGames.get(raw.gamePk);
    if (!prior) {
      seenGames.set(raw.gamePk, raw);
      continue;
    }
    if (isMakeupReplacement(prior, raw)) { seenGames.set(raw.gamePk, raw); continue; }
    if (isMakeupReplacement(raw, prior)) continue;
    const facts = value => JSON.stringify({
      gameType: value.gameType,
      description: value.description,
      status: value.status?.abstractGameState,
      away: [value.teams?.away?.team?.id, value.teams?.away?.team?.name, value.teams?.away?.score, value.teams?.away?.isWinner],
      home: [value.teams?.home?.team?.id, value.teams?.home?.team?.name, value.teams?.home?.score, value.teams?.home?.isWinner],
    });
    if (facts(prior) !== facts(raw)) duplicateConflicts.add(raw.gamePk);
  }
  const rawGames = [...seenGames.values(), ...unidentifiedGames];
  const grouped = new Map();
  const games = rawGames.flatMap(raw => {
    const round = ROUND_BY_TYPE[raw.gameType];
    const description = String(raw.description || '').trim();
    const gameMatch = description.match(/\s+Game\s+(\d+)\s*$/i);
    const descriptionSlot = gameMatch ? description.slice(0, gameMatch.index).trim() : '';
    const league = leagueFor(raw);
    const bracketSlot = descriptionSlot.match(/'([AB])'/i)?.[1]?.toUpperCase()
      || (raw.gameType === 'W' ? 'main' : raw.gameType === 'L' ? 'main' : null);
    const slot = bracketSlot || '';
    const away = club(raw.teams?.away);
    const home = club(raw.teams?.home);
    const knownParticipants = away.resolved && home.resolved && away.teamId !== home.teamId;
    const { final, winner } = gameState(raw, away, home);
    const resultConfirmed = final && knownParticipants && winner !== null
      && Number.isFinite(raw.teams?.away?.score) && Number.isFinite(raw.teams?.home?.score);
    const seriesId = round && slot && league
      ? `${season}-${league.toLowerCase()}-${round}-${slot.toLowerCase()}`
      : null;
    const isTBD = raw.status?.startTimeTBD === true;
    const item = {
      gamePk: Number.isInteger(raw.gamePk) ? raw.gamePk : null,
      seriesId,
      gameNumber: Number.isInteger(raw.seriesGameNumber) ? raw.seriesGameNumber : null,
      gameType: raw.gameType || null,
      gameDate: typeof raw.gameDate === 'string' ? raw.gameDate : null,
      officialDate: typeof raw.officialDate === 'string' ? raw.officialDate : null,
      timeTBD: isTBD,
      status: raw.status?.detailedState || raw.status?.abstractGameState || 'Unknown',
      abstractState: raw.status?.abstractGameState || 'Unknown',
      broadcasts: [...new Set((raw.broadcasts || [])
        .filter(item => item.type === 'TV' && typeof item.name === 'string')
        .map(item => item.name.trim()).filter(Boolean))].slice(0, 3),
      conditional: raw.ifNecessary === 'Y',
      away,
      home,
      awayScore: resultConfirmed ? raw.teams.away.score : null,
      homeScore: resultConfirmed ? raw.teams.home.score : null,
      winnerTeamId: resultConfirmed ? winner : null,
      liveInning: Number.isInteger(raw.linescore?.currentInning) ? raw.linescore.currentInning : null,
    };
    if (seriesId) {
      const entry = grouped.get(seriesId) || {
        id: seriesId,
        round,
        league,
        bracketSlot: slot,
        requiredWins: TOURNAMENT_FORMATS[season]?.[raw.gameType] || null,
        gameIds: [],
        _games: [],
        _invalid: false,
      };
      entry.gameIds.push(item.gamePk);
      entry._games.push({ item, confirmed: resultConfirmed });
      entry._invalid ||= duplicateConflicts.has(item.gamePk)
        || (item.abstractState === 'Final' && ['F', 'O'].includes(raw.status?.codedGameState) && !resultConfirmed);
      grouped.set(seriesId, entry);
    }
    return item.gamePk === null ? [] : [item];
  });

  const series = [...grouped.values()].map(entry => {
    const participants = new Map();
    let consistent = true;
    for (const { item } of entry._games) {
      for (const side of [item.away, item.home]) {
        if (!side.resolved) continue;
        const prior = participants.get(side.teamId);
        if (prior && prior.name !== side.name) consistent = false;
        participants.set(side.teamId, side);
      }
    }
    const wins = new Map([...participants.keys()].map(id => [id, 0]));
    const completed = new Set();
    for (const { item, confirmed } of entry._games) {
      if (!confirmed || completed.has(item.gamePk)) continue;
      completed.add(item.gamePk);
      wins.set(item.winnerTeamId, (wins.get(item.winnerTeamId) || 0) + 1);
    }
    const winners = entry.requiredWins
      ? [...wins].filter(([, count]) => count >= entry.requiredWins).map(([id]) => id)
      : [];
    const invalid = !consistent || entry._invalid || winners.length > 1;
    const winnerTeamId = invalid || winners.length !== 1 ? null : winners[0];
    return {
      id: entry.id,
      round: entry.round,
      league: entry.league,
      bracketSlot: entry.bracketSlot,
      participants: [...participants.values()],
      unresolvedSlots: entry._games.flatMap(({ item }) => [item.away, item.home])
        .filter(side => !side.resolved && side.slot).map(side => side.slot).filter((x, i, a) => a.indexOf(x) === i),
      requiredWins: entry.requiredWins,
      gameIds: entry.gameIds.filter(Number.isInteger),
      completedGameCount: completed.size,
      wins: invalid ? null : Object.fromEntries(wins),
      winnerTeamId,
      state: invalid ? 'unknown' : winnerTeamId ? 'complete' : entry._games.some(({ item }) => item.abstractState === 'Live') ? 'live' : 'scheduled',
      nextSlots: advancementSlot(season, entry._games[0]?.item.gameType, entry.league, entry.bracketSlot),
    };
  }).sort((a, b) => (a.round || '').localeCompare(b.round || '') || a.id.localeCompare(b.id));
  const confirmedTeams = new Set(series.filter(item => item.state === 'complete')
    .flatMap(item => item.participants.map(participant => participant.teamId)));
  const slots = new Map();
  for (const item of games) {
    for (const team of [item.away, item.home]) {
      const key = team.resolved ? `team-${team.teamId}` : `slot-${team.slot}`;
      if (!slots.has(key)) slots.set(key, {
        id: key,
        teamId: team.teamId,
        name: team.name,
        unresolved: !team.resolved,
        qualification: team.resolved && confirmedTeams.has(team.teamId) ? 'confirmed-by-play' : 'unknown',
      });
    }
  }
  const active = games.some(game => game.abstractState === 'Live');
  const championshipComplete = series.some(item => item.round === 'world-series' && item.state === 'complete');
  return {
    schemaVersion: 1,
    season: Number(season),
    phase: active ? 'active' : championshipComplete ? 'complete' : games.some(game => game.abstractState === 'Final') ? 'in-progress' : 'field-setting',
    checkedAt,
    providerUpdatedAt: null,
    source: 'MLB Stats API schedule',
    sourceURL: `${MLB_ORIGIN}/api/v1/schedule?sportId=1&season=${season}&gameTypes=F,D,L,W&hydrate=linescore,broadcasts`,
    teamsAndSlots: [...slots.values()],
    series,
    games,
  };
}

export async function getPostseasonResponse(request, fetchImpl = fetch, now = new Date()) {
  const url = new URL(request.url);
  const season = url.searchParams.get('season') || String(now.getFullYear());
  if (!SUPPORTED_SEASONS.has(season)) {
    return Response.json({ error: 'Unsupported postseason season.' }, {
      status: 400,
      headers: { 'Netlify-Vary': 'query=season', 'Cache-Control': 'no-store' },
    });
  }
  const providerURL = new URL('/api/v1/schedule', MLB_ORIGIN);
  providerURL.search = new URLSearchParams({ sportId: '1', season, gameTypes: 'F,D,L,W', hydrate: 'linescore,broadcasts' });
  try {
    const payload = await fetchSource(providerURL, fetchImpl);
    const data = normalizePostseason(payload, season, now.toISOString());
    const today = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
    }).format(now);
    const live = data.games.some(game => game.abstractState === 'Live'
      || (game.timeTBD && game.gameDate?.slice(0, 10) === today)
      || (!game.timeTBD && game.gameDate
        && Math.abs(Date.parse(game.gameDate) - now.valueOf()) <= 6 * 60 * 60 * 1000));
    const cache = live ? 'public, max-age=15, stale-while-revalidate=15' : 'public, max-age=300, stale-while-revalidate=60';
    return Response.json(data, {
      headers: {
        'Netlify-Vary': 'query=season',
        'Cache-Control': cache,
        'Netlify-CDN-Cache-Control': `public, durable, ${cache.slice('public, '.length)}`,
        'Access-Control-Allow-Origin': '*',
        'X-Data-Freshness': 'live',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    console.error('Postseason data unavailable', error);
    return Response.json({ error: 'Postseason data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Netlify-Vary': 'query=season', 'Cache-Control': 'no-store' },
    });
  }
}

export default request => getPostseasonResponse(request);
export const config = { path: '/api/postseason', method: 'GET' };
