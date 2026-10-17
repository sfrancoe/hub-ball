import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { getPostseasonResponse, normalizePostseason, TOURNAMENT_FORMATS } from '../netlify/functions/postseason.mjs';

const fixture = async year => JSON.parse(await readFile(new URL(`./fixtures/postseason-${year}.json`, import.meta.url)));
const completed = normalizePostseason(await fixture(2025), '2025', '2026-09-26T00:00:00Z');
assert.equal(completed.games.length, 47);
assert.equal(completed.series.length, 11);
assert.deepEqual(TOURNAMENT_FORMATS[2026], { F: 2, D: 3, L: 4, W: 4 });
assert.ok(completed.series.every(series => series.requiredWins === ({
  'wild-card': 2, 'division-series': 3, 'league-championship': 4, 'world-series': 4,
})[series.round]));
assert.equal(completed.phase, 'complete');
const wcA = completed.series.find(series => series.round === 'wild-card' && series.league === 'AL' && series.bracketSlot === 'A');
const alDsB = completed.series.find(series => series.round === 'division-series' && series.league === 'AL' && series.bracketSlot === 'B');
assert.deepEqual(wcA.nextSlots, [alDsB.id]);
assert.ok(completed.series.filter(series => series.round === 'league-championship')
  .every(series => series.nextSlots?.[0] === completed.series.find(item => item.round === 'world-series')?.id));
assert.equal(completed.series.find(series => series.round === 'world-series').nextSlots, null);
assert.ok(completed.games.every(game => !game.timeTBD));
assert.ok(completed.series.some(series => series.round === 'world-series'));
assert.ok(completed.series.every(series => series.participants.length >= 2));
assert.ok(completed.series.some(series => series.winnerTeamId !== null));
assert.ok(completed.games.every(game => game.winnerTeamId === null || game.abstractState === 'Final'));
assert.ok(completed.games.every(game => game.liveInning !== null));
assert.ok(completed.games.some(game => game.broadcasts.length > 0));

const duplicateSource = await fixture(2025);
const firstGame = duplicateSource.dates[0].games[0];
duplicateSource.dates[0].games.push(structuredClone(firstGame));
const deduplicated = normalizePostseason(duplicateSource, '2025');
assert.equal(deduplicated.games.length, 47);
assert.equal(deduplicated.series.find(item => item.id === deduplicated.games[0].seriesId).gameIds.length, 3);

const conflictSource = await fixture(2025);
const conflictGame = structuredClone(conflictSource.dates[0].games[0]);
conflictGame.teams.away.score += 1;
conflictSource.dates[0].games.push(conflictGame);
const conflict = normalizePostseason(conflictSource, '2025');
assert.equal(conflict.series.find(item => item.id === conflict.games[0].seriesId).state, 'unknown');

const conditionalSource = await fixture(2026);
const conditionalGame = structuredClone(conditionalSource.dates[0].games[0]);
conditionalGame.ifNecessary = 'Y';
conditionalGame.status = { abstractGameState: 'Final', codedGameState: 'C', detailedState: 'Cancelled' };
conditionalGame.teams.away.score = 0;
conditionalGame.teams.home.score = 0;
conditionalGame.teams.away.isWinner = false;
conditionalGame.teams.home.isWinner = false;
conditionalSource.dates[0].games[0] = conditionalGame;
const conditional = normalizePostseason(conditionalSource, '2026');
assert.equal(conditional.games[0].conditional, true);
assert.equal(conditional.games[0].winnerTeamId, null);
const canceledSeries = conditional.series.find(item => item.id === conditional.games[0].seriesId);
assert.equal(canceledSeries.completedGameCount, 0);
assert.equal(canceledSeries.state, 'scheduled');

const upcoming = normalizePostseason(await fixture(2026), '2026', '2026-09-26T00:00:00Z');
assert.equal(upcoming.games.length, 53);
assert.equal(upcoming.phase, 'field-setting');
assert.ok(upcoming.games.some(game => game.timeTBD));
assert.ok(upcoming.teamsAndSlots.some(team => team.unresolved));
assert.ok(upcoming.teamsAndSlots.filter(team => !team.unresolved)
  .every(team => team.qualification === 'unknown'));
assert.ok(upcoming.games.filter(game => game.timeTBD).every(game => game.gameDate));

const lateGameSource = await fixture(2026);
lateGameSource.dates[0].games[0].gameDate = '2026-09-30T00:00:00Z';
lateGameSource.dates[0].games[0].officialDate = '2026-09-29';
const lateGame = normalizePostseason(lateGameSource, '2026').games
  .find(game => game.gamePk === lateGameSource.dates[0].games[0].gamePk);
assert.equal(lateGame.gameDate, '2026-09-30T00:00:00Z');
assert.equal(lateGame.officialDate, '2026-09-29');

let fetchedURL;
const response = await getPostseasonResponse(
  new Request('https://example.test/api/postseason?season=2026'),
  async url => {
    fetchedURL = String(url);
    return new Response(JSON.stringify(await fixture(2026)));
  },
  new Date('2026-09-26T00:00:00Z'),
);
assert.equal(response.status, 200);
assert.match(fetchedURL, /gameTypes=F%2CD%2CL%2CW/);
assert.match(fetchedURL, /hydrate=linescore%2Cbroadcasts/);
assert.match(response.headers.get('Cache-Control'), /max-age=300/);
assert.match(response.headers.get('Netlify-CDN-Cache-Control'), /durable/);
assert.equal((await response.json()).schemaVersion, 1);

const rejected = await getPostseasonResponse(
  new Request('https://example.test/api/postseason?season=2024'),
  async () => { throw new Error('must not fetch'); },
);
assert.equal(rejected.status, 400);


// Captured MLB ALCS rainout: one gamePk appears as both postponed and makeup.
const rainoutSource = await fixture('2026-alcs-rainout');
const alcsID = '2026-al-league-championship-main';
const sourceGames = source => source.dates.flatMap(date => date.games);
const alcs = source => normalizePostseason(source, '2026').series.find(row => row.id === alcsID);
const rainoutRecords = sourceGames(rainoutSource).filter(game => game.gamePk === 849817);
assert.equal(rainoutRecords.length, 2);
assert.deepEqual(rainoutRecords.map(game => game.status.codedGameState), ['D', 'S']);
function assertReconciledRainout(source) {
  const normalized = normalizePostseason(source, '2026');
  const series = normalized.series.find(row => row.id === alcsID);
  assert.equal(series.state, 'scheduled');
  assert.equal(series.completedGameCount, 3);
  assert.deepEqual(series.wins, { 114: 2, 139: 1 });
  assert.equal(series.winnerTeamId, null);
  const makeup = normalized.games.filter(game => game.gamePk === 849817);
  assert.equal(makeup.length, 1);
  assert.equal(makeup[0].gameNumber, 5);
  assert.equal(makeup[0].gameDate, '2026-10-18T21:00:00Z');
  assert.equal(makeup[0].abstractState, 'Preview');
  assert.equal(makeup[0].winnerTeamId, null);
  const next = normalized.games.filter(game => game.seriesId === alcsID && game.abstractState === 'Preview')
    .sort((a, b) => a.gameDate.localeCompare(b.gameDate));
  assert.deepEqual(next.slice(0, 2).map(game => [game.gameNumber, game.gameDate]), [
    [4, '2026-10-18T00:00:00Z'], [5, '2026-10-18T21:00:00Z'],
  ]);
}
assertReconciledRainout(rainoutSource);
const reversedRainout = structuredClone(rainoutSource);
reversedRainout.dates.reverse().forEach(date => date.games.reverse());
assertReconciledRainout(reversedRainout);

for (const missingLink of ['rescheduleDate', 'rescheduledFrom']) {
  const oneLink = structuredClone(rainoutSource);
  for (const game of sourceGames(oneLink)) delete game[missingLink];
  assertReconciledRainout(oneLink);
}
const unlinkedRainout = structuredClone(rainoutSource);
for (const game of sourceGames(unlinkedRainout)) {
  delete game.rescheduleDate; delete game.rescheduledFrom;
}
assert.equal(alcs(unlinkedRainout).state, 'unknown');

const missingMakeup = structuredClone(rainoutSource);
for (const date of missingMakeup.dates) date.games = date.games.filter(game =>
  game.gamePk !== 849817 || game.status.codedGameState === 'D');
assert.equal(alcs(missingMakeup).state, 'scheduled');
assert.deepEqual(alcs(missingMakeup).wins, { 114: 2, 139: 1 });
assert.equal(alcs(missingMakeup).completedGameCount, 3);

const conflictingRainout = structuredClone(rainoutSource);
const contradictoryFinal = structuredClone(sourceGames(conflictingRainout).find(game => game.gamePk === 849818));
contradictoryFinal.teams.home.score += 1;
conflictingRainout.dates[0].games.push(contradictoryFinal);
assert.equal(alcs(conflictingRainout).state, 'unknown');
assert.equal(alcs(conflictingRainout).wins, null);

const mismatchedTeams = structuredClone(rainoutSource);
sourceGames(mismatchedTeams).find(game => game.gamePk === 849817 && game.status.codedGameState === 'S')
  .teams.away.team = { id: 119, name: 'Los Angeles Dodgers' };
assert.equal(alcs(mismatchedTeams).state, 'unknown');
const misleadingLink = structuredClone(rainoutSource);
sourceGames(misleadingLink).find(game => game.gamePk === 849817 && game.status.codedGameState === 'D')
  .rescheduleDate = '2026-10-19T21:00:00Z';
assert.equal(alcs(misleadingLink).state, 'unknown');

const scoredPostponement = structuredClone(rainoutSource);
sourceGames(scoredPostponement).find(game => game.gamePk === 849817 && game.status.codedGameState === 'D')
  .teams.away.score = 1;
assert.equal(alcs(scoredPostponement).state, 'unknown');

const completedMakeup = structuredClone(rainoutSource);
const finalMakeup = sourceGames(completedMakeup).find(game => game.gamePk === 849817 && game.status.codedGameState === 'S');
finalMakeup.status = { abstractGameState: 'Final', codedGameState: 'F', detailedState: 'Final' };
finalMakeup.teams.away.score = 2; finalMakeup.teams.away.isWinner = true;
finalMakeup.teams.home.score = 0; finalMakeup.teams.home.isWinner = false;
assert.equal(alcs(completedMakeup).completedGameCount, 4);
assert.deepEqual(alcs(completedMakeup).wins, { 114: 2, 139: 2 });
const conflictingMakeup = structuredClone(completedMakeup);
const otherFinal = structuredClone(sourceGames(conflictingMakeup).find(game => game.gamePk === 849817 && game.status.codedGameState === 'F'));
otherFinal.teams.away.score = 3;
conflictingMakeup.dates[0].games.push(otherFinal);
assert.equal(alcs(conflictingMakeup).state, 'unknown');

const rainoutResponse = await getPostseasonResponse(
  new Request('https://example.test/api/postseason?season=2026'),
  async () => Response.json(rainoutSource), new Date('2026-10-17T12:00:00Z'),
);
assert.equal(rainoutResponse.status, 200);
assert.deepEqual((await rainoutResponse.json()).series.find(row => row.id === alcsID).wins, { 114: 2, 139: 1 });

console.log('postseason normalization and gateway tests passed, including ALCS rainout reconciliation');

