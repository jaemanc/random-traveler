import assert from 'node:assert/strict';
import worker from './index.js';

const realFetch=globalThis.fetch;

const stored=new Map();
globalThis.caches={default:{
  match:async key=>stored.get(key.url)?.clone(),
  put:async(key,response)=>stored.set(key.url,response.clone()),
}};
const local=offset=>new Date(Date.now()+offset).toLocaleString('sv-SE',{timeZone:'Asia/Seoul'}).replace(' ','T');
let searches=0;
globalThis.fetch=async()=>{
  searches++;
  return new Response(JSON.stringify({data:{offers:[{
    live_mode:true,expires_at:new Date(Date.now()+3600000).toISOString(),
    total_amount:'182.40',total_currency:'USD',
    slices:[{origin:{time_zone:'Asia/Seoul'},duration:'PT4H20M',segments:[
      {departing_at:local(7200000),arriving_at:local(10800000),destination:{iata_code:'TPE'},operating_carrier:{name:'Example Air'}},
      {departing_at:local(12000000),arriving_at:local(18000000),destination:{iata_code:'FUK'},operating_carrier:{name:'Example Air'}},
    ]}],
  }]}}));
};
const route=dest=>new Request(`https://example.com/?origin=ICN&destination=${dest}&hours=12&kind=round-trip`);
const first=await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
assert.equal((await first.json()).flight.via[0],'TPE');
const afterFirst=searches;
const second=await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
assert.equal((await second.json()).cached,true);
assert.equal(searches,afterFirst);
assert.equal((await (await worker.fetch(route('FUK'),{})).json()).cached,true);
const stale=await stored.get(route('FUK').url).clone().json();
stale.flight.expiresAt=new Date(Date.now()-1000).toISOString();
stored.set(route('FUK').url,new Response(JSON.stringify(stale)));
await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
assert.ok(searches>afterFirst);
const afterRefresh=searches;
await worker.fetch(route('KIX'),{DUFFEL_TOKEN:'test'});
assert.ok(searches>afterRefresh);
assert.equal(first.headers.get('access-control-allow-origin'),'*');
globalThis.fetch=realFetch;
