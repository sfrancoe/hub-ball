import assert from 'node:assert/strict';
import handler, { ALLOWED_PATHS } from '../netlify/functions/app-data.mjs';

const originalFetch = globalThis.fetch;

try {
  let calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return new Response('{"ok":true}', { status: 200 });
  };

  // Installed Boston builds request root paths; the feeds live in data/redsox/.
  let response = await handler(new Request('https://example.test/api/data/schedule.json'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/redsox/schedule.json');
  assert.equal(calls[0].options.headers['User-Agent'], undefined);
  assert.match(response.headers.get('Netlify-CDN-Cache-Control'), /durable/);
  assert.match(response.headers.get('Netlify-CDN-Cache-Control'), /stale-while-revalidate=3600/);

  calls = [];
  response = await handler(new Request('https://example.test/data/schedule.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/redsox/schedule.json');

  for (const file of ['globe.json', 'herald.json', 'athletic.json', 'masslive.json', 'players.json',
    'pitching.json', 'recent-game.json', 'standings.json', 'x-posts.json']) {
    calls = [];
    response = await handler(new Request(`https://example.test/api/data/${file}`));
    assert.equal(response.status, 200, file);
    assert.equal(calls[0].url, `https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/redsox/${file}`);
  }

  // The Four Roads / Game 108 story data stays at the root.
  for (const file of ['seasons.json', 'meta.json']) {
    calls = [];
    response = await handler(new Request(`https://example.test/api/data/${file}`));
    assert.equal(response.status, 200, file);
    assert.equal(calls[0].url, `https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/${file}`);
  }

  calls = [];
  response = await handler(new Request('https://example.test/api/data/redsox/schedule.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/redsox/schedule.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/leaderboards/2026.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/leaderboards/2026.json');

  calls = [];
  response = await handler(new Request('https://example.test/data/leaderboards/2026.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/leaderboards/2026.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/postseason-history/2026.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/postseason-history/2026.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/postseason-history/2026-v2.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/postseason-history/2026-v2.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/yankees/standings.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/yankees/standings.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/mets/standings.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/mets/standings.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/yankees/players.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/yankees/players.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/rays/tampabay.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/rays/tampabay.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/player-careers/680776.json'));
  assert.equal(response.status, 200);
  assert.equal(calls[0].url, 'https://raw.githubusercontent.com/sfrancoe/hub-ball/main/data/player-careers/680776.json');

  calls = [];
  response = await handler(new Request('https://example.test/api/data/../netlify.toml'));
  assert.equal(response.status, 404);
  assert.equal(calls.length, 0);

  calls = [];
  response = await handler(new Request('https://example.test/api/data/player-careers/680776.json/extra'));
  assert.equal(response.status, 404);
  assert.equal(calls.length, 0);

  let attempt = 0;
  globalThis.fetch = async (_url, options) => {
    attempt += 1;
    if (attempt === 1) throw new Error('blocked');
    assert.equal(options.headers['User-Agent'], 'HubBall/1.0 (+https://api.autumnlane.io)');
    return new Response('{"fallback":true}', { status: 200 });
  };
  response = await handler(new Request('https://example.test/api/data/meta.json'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { fallback: true });
  assert.equal(attempt, 2);

  console.log('app-data tests passed');
} finally {
  globalThis.fetch = originalFetch;
}

assert.equal(ALLOWED_PATHS.has('orioles/standings.json'), true);
assert.equal(ALLOWED_PATHS.has('orioles/x-posts.json'), true);
assert.equal(ALLOWED_PATHS.has('orioles/players.json'), true);
assert.equal(ALLOWED_PATHS.has('dodgers/los-angeles-times.json'), true);
assert.equal(ALLOWED_PATHS.has('redsox/standings.json'), true);
assert.equal(ALLOWED_PATHS.has('standings.json'), true);
assert.equal(ALLOWED_PATHS.has('leaderboards/2026.json'), true);
assert.equal(ALLOWED_PATHS.has('leaderboards/2022.json'), false);
assert.equal(ALLOWED_PATHS.has('postseason-history/2026.json'), true);
assert.equal(ALLOWED_PATHS.has('postseason-history/2026-v2.json'), true);
assert.equal(ALLOWED_PATHS.has('postseason-history/2025.json'), false);
assert.equal(ALLOWED_PATHS.has('postseason-news/2026.json'), true);
assert.equal(ALLOWED_PATHS.has('postseason-news/2025.json'), false);
