import { MLB_TEAMS } from './team-registry.mjs';
import { createHash } from 'node:crypto';

const RAW_DATA_ROOT = 'https://raw.githubusercontent.com/sfrancoe/red-sox/main/data';
const FALLBACK_USER_AGENT = 'HubBall/1.0 (+https://api.autumnlane.io)';

const STANDARD_FILES = [
  'meta.json', 'pitching.json', 'recent-game.json', 'schedule.json',
  'seasons.json', 'standings.json', 'x-posts.json',
];

function teamFiles(team) {
  const files = [
    ...STANDARD_FILES,
    ...team.news_sources.map(source => `${source.key}.json`),
  ];
  if (team.features.players) files.push('players.json');
  return files;
}

// Every team's feeds live in data/<team>/. Boston's shipped app builds (and the
// original Red Sox web pages) still request its feeds at the data root, so those
// root paths are served from data/redsox/. The exception is the Four Roads /
// Game 108 story data, which stays at the root and is built by fetch_seasons.py.
const ROOT_STORY_FILES = new Set(['seasons.json', 'meta.json']);

export const ROOT_ALIASES = new Map(MLB_TEAMS
  .filter(team => team.legacy_root_data)
  .flatMap(team => teamFiles(team)
    .filter(file => !ROOT_STORY_FILES.has(file))
    .map(file => [file, `${team.data_directory}/${file}`])));

export const ALLOWED_PATHS = new Set(MLB_TEAMS.flatMap(team => [
  ...teamFiles(team).map(file => `${team.data_directory}/${file}`),
  ...(team.legacy_root_data ? teamFiles(team) : []),
]));

// Shared comparison artifacts never carry a team-directory prefix. Keep the
// allowlist finite: a new season is a deliberate gateway/deployment change.
for (const year of [2023, 2024, 2025, 2026]) {
  ALLOWED_PATHS.add(`leaderboards/${year}.json`);
}
ALLOWED_PATHS.add('postseason-history/2026.json');
ALLOWED_PATHS.add('postseason-history/2026-v2.json');
ALLOWED_PATHS.add('postseason-news/2026.json');
ALLOWED_PATHS.add('stories/catalog-v1.json');
ALLOWED_PATHS.add('stories/featured-v1.json');
ALLOWED_PATHS.add('releases/testflight-v1.json');

// A player card requests a single generated career record by the stable numeric
// ID in its roster feed. Restrict this dynamic collection to a filename only:
// no nested paths, extensions, or arbitrary repository reads are permitted.
function isAllowedPath(path) {
  return ALLOWED_PATHS.has(path) || /^player-careers\/\d{1,10}\.json$/.test(path)
    || (path.split('/')[1]?.length <= 80 && path.length <= 160 && /^stories\/[a-z0-9]+(?:-[a-z0-9]+)*\/[a-f0-9]{64}\.json$/.test(path));
}

const hash = data => createHash('sha256').update(data).digest('hex');

// Fixed endpoint, bounded dates and scalar content; payloads still require immutable SHA paths.
export function validateFeatured(value) {
  const slug = x => typeof x === 'string' && x.length <= 80 && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(x);
  const integer = (x, min, max) => Number.isInteger(x) && x >= min && x <= max;
  const timestamp = x => typeof x === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(x)
    && Number.isFinite(Date.parse(x)) && new Date(x).toISOString() === x.replace('Z', '.000Z');
  const text = (x, max) => typeof x === 'string' && x.length > 0 && x.length <= max && !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(x);
  const start = Date.parse(value.notBefore), end = Date.parse(value.expiresAt);
  if (value.schemaVersion !== 1 || typeof value.enabled !== 'boolean' || !slug(value.revision)
    || ![value.publishedAt, value.notBefore, value.expiresAt].every(timestamp)
    || end <= start || end - start > 7 * 86400000 || Date.parse(value.publishedAt) > end
    || !integer(value.minimumBuild, 1, 1000000)) throw new Error('Invalid featured manifest');
  if (!value.enabled) { if (value.entry !== null) throw new Error('Disabled entry'); return; }
  const e = value.entry;
  if (!e || !slug(e.id) || typeof e.revision !== 'string' || !/^[a-f0-9]{64}$/.test(e.revision)
    || !slug(e.renderer) || !integer(e.rendererVersion, 1, 100) || !integer(e.minimumRendererVersion, 1, 100)
    || !timestamp(e.publishedAt) || !text(e.title, 160) || !text(e.summary, 400) || !text(e.fallback, 2000)
    || !Array.isArray(e.teamIDs) || e.teamIDs.length > 30 || new Set(e.teamIDs).size !== e.teamIDs.length
    || !e.teamIDs.every(x => integer(x, 1, 1000))) throw new Error('Invalid featured entry');
}

async function storyBytes(response, limit) {
  if (Number(response.headers.get('Content-Length')) > limit) throw new Error('Story too large');
  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new Error('Story too large');
      chunks.push(Buffer.from(value));
    }
  } finally { await reader.cancel(); }
  return Buffer.concat(chunks);
}

function requestedPath(request) {
  const pathname = new URL(request.url).pathname;
  const prefix = ['/api/data/', '/data/'].find(candidate => pathname.startsWith(candidate));
  if (!prefix) return null;
  try {
    return decodeURIComponent(pathname.slice(prefix.length));
  } catch {
    return null;
  }
}

async function fetchSource(path, request = fetch) {
  let lastError;
  for (const headers of [
    { Accept: 'application/json' },
    { Accept: 'application/json', 'User-Agent': FALLBACK_USER_AGENT },
  ]) {
    try {
      const response = await request(`${RAW_DATA_ROOT}/${path}`, {
        headers,
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
      let body;
      if (path === 'releases/testflight-v1.json') {
        const bytes = await storyBytes(response, 16 * 1024);
        const parsed = JSON.parse(bytes.toString('utf8'));
        if (parsed.schemaVersion !== 1 || parsed.bundleID !== 'com.sfrancoe.HubBall' || typeof parsed.enabled !== 'boolean'
          || (parsed.enabled ? parsed.target?.audience !== 'all-supported-testers' : parsed.target !== null)) throw new Error('Invalid beta release manifest');
        body = bytes;
      } else if (path === 'stories/featured-v1.json') {
        const bytes = await storyBytes(response, 16 * 1024);
        validateFeatured(JSON.parse(bytes.toString('utf8')));
        body = bytes;
      } else if (path.startsWith('stories/')) {
        const catalog = path === 'stories/catalog-v1.json';
        const bytes = await storyBytes(response, (catalog ? 128 : 512) * 1024);
        const parsed = JSON.parse(bytes.toString('utf8'));
        if (parsed.schemaVersion !== 1) throw new Error('Unsupported story schema');
        if (!catalog && hash(bytes) !== path.split('/').at(-1).slice(0, -5)) throw new Error('Story hash mismatch');
        if (catalog && (!Array.isArray(parsed.stories) || parsed.stories.length > 120)) throw new Error('Invalid catalog');
        body = bytes;
      } else {
        body = await response.text();
        JSON.parse(body);
      }
      return body;
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

export default async request => {
  const path = requestedPath(request);
  if (!path || !isAllowedPath(path)) {
    return Response.json({ error: 'Unknown app data file.' }, {
      status: 404,
      headers: { 'Cache-Control': 'no-store' },
    });
  }

  try {
    const body = await fetchSource(ROOT_ALIASES.get(path) ?? path);
    const catalog = path === 'stories/catalog-v1.json';
    const story = path.startsWith('stories/');
    const etag = story && path !== 'stories/featured-v1.json' ? `"${hash(body)}"` : null;
    const cacheHeaders = ['releases/testflight-v1.json', 'stories/featured-v1.json'].includes(path) ? {
      'Cache-Control': 'no-store',
      'Netlify-CDN-Cache-Control': 'no-store',
    } : catalog ? {
      'Cache-Control': 'public, max-age=0, must-revalidate',
      'Netlify-CDN-Cache-Control': 'public, durable, max-age=30',
    } : story ? {
      'Cache-Control': 'public, max-age=31536000, immutable',
      'Netlify-CDN-Cache-Control': 'public, durable, max-age=31536000',
    } : {
      'Cache-Control': 'public, max-age=60, stale-while-revalidate=300',
      'Netlify-CDN-Cache-Control': 'public, durable, max-age=300, stale-while-revalidate=3600',
    };
    if (etag && request.headers.get('If-None-Match') === etag) {
      return new Response(null, { status: 304, headers: { ...cacheHeaders, ETag: etag } });
    }
    return new Response(body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        ...cacheHeaders,
        ...(etag ? { ETag: etag } : {}),
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    console.error(`App data refresh failed for ${path}`, error);
    return Response.json({ error: 'App data is temporarily unavailable.' }, {
      status: 502,
      headers: { 'Cache-Control': 'no-store' },
    });
  }
};

export const config = { path: ['/api/data/*', '/data/*'], method: 'GET' };
