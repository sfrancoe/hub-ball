// Starts refresh workflows on time. GitHub's own `schedule:` triggers are
// best-effort and were running the 2-hour data job and the 10-minute news job
// roughly every six hours. This Netlify scheduled function ticks every five
// minutes and dispatches each workflow whose cron (copied from its own file by
// scripts/generate_workflow_schedules.py) fell inside the last five minutes.
// The workflows keep their `schedule:` lines as a fallback; a workflow GitHub
// already started inside the window is not started again.
import { WORKFLOW_SCHEDULES } from './workflow-schedules.mjs';

const REPOSITORY = 'sfrancoe/red-sox';
const API = `https://api.github.com/repos/${REPOSITORY}/actions/workflows`;
const TICK_MINUTES = 5;
const FIELD_RANGES = [[0, 59], [0, 23], [1, 31], [1, 12], [0, 6]];

function fieldValues(field, [low, high]) {
  const values = new Set();
  for (const part of field.split(',')) {
    const [range, stepText] = part.split('/');
    const step = stepText === undefined ? 1 : Number(stepText);
    let start = low;
    let end = high;
    if (range !== '*') {
      [start, end] = range.split('-').map(Number);
      if (end === undefined) end = stepText === undefined ? start : high;
    }
    if (![start, end, step].every(Number.isInteger) || step < 1 || start < low || end > high + 1) {
      throw new Error(`Unsupported cron field "${field}"`);
    }
    for (let value = start; value <= end; value += step) values.add(value === 7 && high === 6 ? 0 : value);
  }
  return values;
}

export function parseCron(expression) {
  const fields = expression.trim().split(/\s+/);
  if (fields.length !== 5) throw new Error(`Cron must have five fields: "${expression}"`);
  const [minute, hour, day, month, weekday] = fields.map((field, index) => fieldValues(field, FIELD_RANGES[index]));
  return { minute, hour, day, month, weekday, dayRestricted: fields[2] !== '*', weekdayRestricted: fields[4] !== '*' };
}

export function cronMatches(cron, date) {
  if (!cron.minute.has(date.getUTCMinutes()) || !cron.hour.has(date.getUTCHours())
    || !cron.month.has(date.getUTCMonth() + 1)) return false;
  const day = cron.day.has(date.getUTCDate());
  const weekday = cron.weekday.has(date.getUTCDay());
  // Standard cron: when both day fields are restricted, either may match.
  if (cron.dayRestricted && cron.weekdayRestricted) return day || weekday;
  return day && weekday;
}

/** The tick's own boundary: Netlify can start a few seconds or a minute late. */
export function tickBoundary(now) {
  const boundary = new Date(now);
  boundary.setUTCSeconds(0, 0);
  boundary.setUTCMinutes(boundary.getUTCMinutes() - (boundary.getUTCMinutes() % TICK_MINUTES));
  return boundary;
}

/** Workflows with a cron minute in (boundary - 5 minutes, boundary]. */
export function dueWorkflows(schedules, boundary) {
  const minutes = Array.from({ length: TICK_MINUTES }, (_, index) =>
    new Date(boundary.getTime() - index * 60_000));
  return schedules.filter(row => row.crons.some(expression => {
    const cron = parseCron(expression);
    return minutes.some(minute => cronMatches(cron, minute));
  }));
}

function headers(token) {
  return {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${token}`,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'HubBall-workflow-timer',
  };
}

async function startedRecently(row, since, token, request) {
  const response = await request(`${API}/${row.workflow}/runs?per_page=1&branch=main`, {
    headers: headers(token), signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) return false; // Unknown: dispatching is the safe default.
  const run = (await response.json()).workflow_runs?.[0];
  return Boolean(run && new Date(run.created_at) > since);
}

async function dispatch(row, token, request) {
  const response = await request(`${API}/${row.workflow}/dispatches`, {
    method: 'POST',
    headers: { ...headers(token), 'Content-Type': 'application/json' },
    body: JSON.stringify({ ref: 'main', ...(row.inputs ? { inputs: row.inputs } : {}) }),
    signal: AbortSignal.timeout(8_000),
  });
  if (response.status !== 204) {
    throw new Error(`GitHub returned ${response.status}: ${(await response.text()).slice(0, 200)}`);
  }
}

export async function runTick({ now = new Date(), token, request = fetch, schedules = WORKFLOW_SCHEDULES } = {}) {
  const boundary = tickBoundary(now);
  const since = new Date(boundary.getTime() - TICK_MINUTES * 60_000);
  return Promise.all(dueWorkflows(schedules, boundary).map(async row => {
    try {
      if (await startedRecently(row, since, token, request)) {
        return { workflow: row.workflow, outcome: 'already running' };
      }
      await dispatch(row, token, request);
      return { workflow: row.workflow, outcome: 'dispatched' };
    } catch (error) {
      return { workflow: row.workflow, outcome: 'failed', error: String(error?.message ?? error) };
    }
  }));
}

export default async () => {
  const token = process.env.GITHUB_WORKFLOW_TOKEN;
  if (!token) {
    console.error('workflow-timer: GITHUB_WORKFLOW_TOKEN is not set; no workflows started.');
    return new Response('Missing GitHub token', { status: 500 });
  }
  const results = await runTick({ token });
  for (const result of results) {
    const line = `workflow-timer: ${result.workflow} ${result.outcome}${result.error ? ` (${result.error})` : ''}`;
    (result.outcome === 'failed' ? console.error : console.log)(line);
  }
  const failed = results.filter(result => result.outcome === 'failed').length;
  return new Response(JSON.stringify({ results }), {
    status: failed ? 502 : 200,
    headers: { 'Content-Type': 'application/json' },
  });
};

export const config = { schedule: '*/5 * * * *' };
