import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import handler from '../netlify/functions/app-data.mjs';
const value=JSON.parse(await readFile(new URL('../data/stories/featured-v1.json',import.meta.url)));
const originalFetch=globalThis.fetch, originalError=console.error;
try {
  console.error=()=>{};
  for(const host of ['api.autumnlane.io','red-sox.netlify.app']) for(const prefix of ['/api/data/','/data/']) {
    globalThis.fetch=async()=>new Response(JSON.stringify(value));
    const result=await handler(new Request(`https://${host}${prefix}stories/featured-v1.json`,{headers:{'If-None-Match':'anything'}}));
    assert.equal(result.status,200);assert.equal(result.headers.get('Cache-Control'),'no-store');
    assert.equal(result.headers.get('Netlify-CDN-Cache-Control'),'no-store');assert.equal(result.headers.get('ETag'),null);
    assert.equal((await result.json()).entry.id,'almost-every-out-a-k');
  }
  for(const mutate of [v=>v.enabled='true',v=>v.entry.revision='../bad',v=>v.entry.id='../bad',v=>v.expiresAt='2026-10-30T00:00:00Z',v=>v.schemaVersion=2,v=>v.entry.teamIDs=[114,114],v=>v.minimumBuild=0,v=>v.enabled=false]) {
    const copy=structuredClone(value);mutate(copy);globalThis.fetch=async()=>new Response(JSON.stringify(copy));
    assert.equal((await handler(new Request('https://example.test/api/data/stories/featured-v1.json'))).status,502);
  }
  const off={...value,enabled:false,entry:null};globalThis.fetch=async()=>new Response(JSON.stringify(off));
  assert.equal((await handler(new Request('https://example.test/api/data/stories/featured-v1.json'))).status,200);
  globalThis.fetch=async()=>new Response(' '.repeat(16*1024+1));
  assert.equal((await handler(new Request('https://example.test/api/data/stories/featured-v1.json'))).status,502);
  console.log('Featured gateway: both origins/routes, no-store, finite validation, disable and size limits passed.');
} finally {globalThis.fetch=originalFetch;console.error=originalError;}
