import assert from 'node:assert/strict';
import worker from './index.js';

const url='https://example.com/?provider=skyscanner&origin=ICN&destination=FUK&hours=12&kind=round-trip';
assert.equal((await worker.fetch(new Request(url),{})).status,200);
const realFetch=globalThis.fetch;
globalThis.fetch=async()=>new Response(JSON.stringify({content:{results:{quotes:{a:{minPrice:{amount:'12345',unit:'PRICE_UNIT_CENTI'}},b:{minPrice:{amount:'150',unit:'PRICE_UNIT_WHOLE'}}}}}}));
const result=await worker.fetch(new Request(url),{SKYSCANNER_API_KEY:'test'});
assert.equal((await result.json()).fare.amount,123.45);
globalThis.fetch=realFetch;
