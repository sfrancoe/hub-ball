import assert from 'node:assert/strict';
import handler, {
  config, cronMatches, dueWorkflows, parseCron, runTick, tickBoundary,
} from '../netlify/functions/workflow-timer.mjs';
import { WORKFLOW_SCHEDULES } from '../netlify/functions/workflow-schedules.mjs';

const at = text => new Date(`${text}Z`);
const due = text => dueWorkflows(WORKFLOW_SCHEDULES, tickBoundary(at(text))).map(row => row.workflow);

assert.equal(config.schedule, '*/5 * * * *');

// Every generated cron parses.
for (const row of WORKFLOW_SCHEDULES) for (const cron of row.crons) parseCron(cron);

// Cron semantics used by the workflows.
assert.equal(cronMatches(parseCron('9-59/10 * * * *'), at('2026-10-10T01:19:00')), true);
assert.equal(cronMatches(parseCron('9-59/10 * * * *'), at('2026-10-10T01:20:00')), false);
assert.equal(cronMatches(parseCron('47 */2 * * *'), at('2026-10-10T02:47:00')), true);
assert.equal(cronMatches(parseCron('47 */2 * * *'), at('2026-10-10T03:47:00')), false);
assert.equal(cronMatches(parseCron('55 12 * 10 1'), at('2026-10-12T12:55:00')), true); // Monday in October
assert.equal(cronMatches(parseCron('55 12 * 10 1'), at('2026-10-13T12:55:00')), false);
assert.equal(cronMatches(parseCron('55 12 * 10 1'), at('2026-11-02T12:55:00')), false);
assert.equal(cronMatches(parseCron('7,37 * * * *'), at('2026-10-10T05:37:00')), true);
assert.throws(() => parseCron('* * *'));
assert.throws(() => parseCron('61 * * * *'));

// A tick that starts late still claims its own five-minute window.
assert.deepEqual(tickBoundary(at('2026-10-10T02:51:40')), at('2026-10-10T02:50:00'));
assert.ok(due('2026-10-10T02:50:03').includes('refresh-mlb-team-data.yml'));
assert.ok(!due('2026-10-10T02:55:00').includes('refresh-mlb-team-data.yml'));
assert.ok(due('2026-10-10T01:10:00').includes('refresh-mlb-team-news.yml'));
assert.ok(due('2026-10-10T01:20:00').includes('refresh-mlb-team-news.yml'));
assert.ok(!due('2026-10-10T01:15:00').includes('refresh-mlb-team-news.yml'));

// Over a full week, each workflow is due exactly once for every cron minute.
const start = at('2026-10-05T00:00:00').getTime();
for (const row of WORKFLOW_SCHEDULES) {
  const crons = row.crons.map(parseCron);
  let matchingWindows = 0;
  let dueTicks = 0;
  for (let tick = start; tick < start + 7 * 86_400_000; tick += 5 * 60_000) {
    const boundary = new Date(tick);
    const window = [0, 1, 2, 3, 4].map(offset => new Date(tick - offset * 60_000));
    if (window.some(minute => crons.some(cron => cronMatches(cron, minute)))) matchingWindows += 1;
    if (dueWorkflows([row], boundary).length) dueTicks += 1;
  }
  assert.ok(matchingWindows > 0, row.workflow);
  assert.equal(dueTicks, matchingWindows, row.workflow);
}

// Dispatch: skips a workflow GitHub already started, passes declared inputs,
// and reports a refused dispatch without hiding the others.
const calls = [];
const fakeGitHub = async (url, options = {}) => {
  calls.push({ url, options });
  if (url.includes('/runs?')) {
    const recent = url.includes('refresh-playoff-history.yml');
    return Response.json({ workflow_runs: [{ created_at: recent ? '2026-10-10T01:06:00Z' : '2026-10-09T20:00:00Z' }] });
  }
  if (url.includes('refresh-postseason-news.yml')) return new Response('nope', { status: 422 });
  return new Response(null, { status: 204 });
};
let results = await runTick({ now: at('2026-10-10T01:10:02'), token: 't0k', request: fakeGitHub });
const outcome = name => results.find(result => result.workflow === name)?.outcome;
assert.equal(outcome('refresh-playoff-history.yml'), 'already running');
assert.equal(outcome('refresh-mlb-team-news.yml'), 'dispatched');
const news = calls.find(call => call.url.endsWith('refresh-mlb-team-news.yml/dispatches'));
assert.equal(news.options.method, 'POST');
assert.equal(news.options.headers.Authorization, 'Bearer t0k');
assert.deepEqual(JSON.parse(news.options.body), { ref: 'main' });

calls.length = 0;
results = await runTick({ now: at('2026-10-10T01:50:00'), token: 't0k', request: fakeGitHub });
assert.equal(outcome('refresh-postseason-news.yml'), 'failed');
assert.match(results.find(result => result.outcome === 'failed').error, /422/);
const playoff = calls.find(call => call.url.endsWith('refresh-playoff-history.yml/dispatches'));
assert.equal(playoff, undefined); // :37 is not in the 01:45–01:50 window

calls.length = 0;
results = await runTick({ now: at('2026-10-10T01:40:00'), token: 't0k', request: async (url, options = {}) => {
  calls.push({ url, options });
  return url.includes('/runs?') ? Response.json({ workflow_runs: [] }) : new Response(null, { status: 204 });
} });
const playoffDispatch = calls.find(call => call.url.endsWith('refresh-playoff-history.yml/dispatches'));
assert.deepEqual(JSON.parse(playoffDispatch.options.body), { ref: 'main', inputs: { scheduled: 'true' } });

// Without a token the timer does nothing and says so.
const savedToken = process.env.GITHUB_WORKFLOW_TOKEN;
delete process.env.GITHUB_WORKFLOW_TOKEN;
const originalError = console.error;
console.error = () => {};
try {
  assert.equal((await handler(new Request('https://example.test/'))).status, 500);
} finally {
  console.error = originalError;
  if (savedToken !== undefined) process.env.GITHUB_WORKFLOW_TOKEN = savedToken;
}

console.log('workflow timer checks passed');
