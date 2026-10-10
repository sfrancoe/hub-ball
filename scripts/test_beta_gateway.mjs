import assert from 'node:assert/strict';
import handler, { ALLOWED_PATHS } from '../netlify/functions/app-data.mjs';
const originalFetch = globalThis.fetch;
try {
  const disabled = { schemaVersion: 1, bundleID: 'com.sfrancoe.HubBall', enabled: false, target: null };
  globalThis.fetch = async url => { assert.match(url, /\/data\/releases\/testflight-v1.json$/); return Response.json(disabled); };
  for (const prefix of ['/api/data/', '/data/']) {
    const response = await handler(new Request('https://example.test' + prefix + 'releases/testflight-v1.json'));
    assert.equal(response.status, 200); assert.deepEqual(await response.json(), disabled);
    assert.equal(response.headers.get('Cache-Control'), 'no-store'); assert.equal(response.headers.get('Netlify-CDN-Cache-Control'), 'no-store');
  }
  globalThis.fetch = async () => Response.json({ ...disabled, enabled: true, target: { audience: 'scott-only' } });
  let response = await handler(new Request('https://example.test/api/data/releases/testflight-v1.json')); assert.equal(response.status, 502);
  globalThis.fetch = async () => new Response(' '.repeat(16385));
  response = await handler(new Request('https://example.test/api/data/releases/testflight-v1.json')); assert.equal(response.status, 502);
  response = await handler(new Request('https://example.test/api/data/releases/other.json')); assert.equal(response.status, 404);
  assert(ALLOWED_PATHS.has('releases/testflight-v1.json'));
  console.log('beta gateway tests passed');
} finally { globalThis.fetch = originalFetch; }
