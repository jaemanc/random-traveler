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
globalThis.fetch=async(_url, options)=>{
  const date = JSON.parse(options.body).data.slices[0].departure_date;
  const today = local(0).slice(0,10);
  const tomorrow = new Date(Date.parse(today + "T00:00:00Z") + 86400000).toISOString().slice(0,10);
  searches++;
  const earliest = {
    live_mode:true,expires_at:new Date(Date.now()+3600000).toISOString(),
    total_amount:'182.40',total_currency:'USD',
    slices:[{origin:{time_zone:'Asia/Seoul'},duration:'PT4H20M',segments:[
      {departing_at:local(7200000),arriving_at:local(10800000),destination:{iata_code:'TPE'},operating_carrier:{name:'Example Air'}},
      {departing_at:local(12000000),arriving_at:local(18000000),origin:{iata_code:'TPE'},destination:{iata_code:'FUK'},operating_carrier:{name:'Example Air'}},
    ]}],
  };
  const next = {
    ...earliest,
    total_amount: '90',
    slices: [{duration:'PT2H',segments:[{
      departing_at: tomorrow+'T13:00:00', arriving_at: tomorrow+'T15:00:00',
    }]}],
  };
  return new Response(JSON.stringify({data:{offers:[...(date===tomorrow?[next]:[]), earliest]}}));

};
const route=dest=>new Request(`https://example.com/?origin=ICN&destination=${dest}&hours=12&kind=round-trip`);
const first=await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
const {flight:offer, tomorrowFlight} = await first.json();
assert.equal(tomorrowFlight.depart.slice(11,16), "13:00");
assert.equal(offer.amount, 182.4);
assert.equal(offer.via[0],'TPE');
assert.equal(offer.connections[0].minutes, 20);
const afterFirst=searches;
const second=await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
assert.equal((await second.json()).cached,true);
assert.equal(searches,afterFirst);
assert.equal((await (await worker.fetch(route('FUK'),{})).json()).cached,true);
const cacheKey = [...stored.keys()][0];
const stale=await stored.get(cacheKey).clone().json();
stale.flight.expiresAt=new Date(Date.now()-1000).toISOString();
stored.set(cacheKey,new Response(JSON.stringify(stale)));
await worker.fetch(route('FUK'),{DUFFEL_TOKEN:'test'});
assert.ok(searches>afterFirst);
const afterRefresh=searches;
await worker.fetch(route('KIX'),{DUFFEL_TOKEN:'test'});
assert.ok(searches>afterRefresh);
assert.equal(first.headers.get('access-control-allow-origin'),'*');
globalThis.fetch=realFetch;

// One grouped request per date feeds multiple real destination buckets.
const originalRandom = Math.random;
const groups = [];
globalThis.fetch = async url => {
 const params = new URL(url).searchParams;
 groups.push(params.get('arrival_id'));
 const departure = params.get('outbound_date') + ' 13:15';
 const options = ['FUK', 'NRT'].map(id => ({
  price: 200, total_duration: 150,
  flights: [{
   airline:'Example Air',
   departure_airport:{id:'ICN', time:departure},
   arrival_airport:{id, time:params.get('outbound_date') + ' 15:45'},
  }],
 }));
 return Response.json({search_metadata:{status:'Success'},best_flights:options});
};
try {
 Math.random = () => 0;
 const grouped = dest => new Request(`https://example.com/?origin=ICN&destination=${dest}&hours=12&kind=round-trip`);
 const first = await (await worker.fetch(grouped('NRT,FUK'), {SERPAPI_API_KEY:'test'})).json();
 assert.equal(first.poolSize, 2);
 assert.equal(first.destination, 'FUK');
 assert.equal(first.tomorrowFlight.destination, first.destination);
 assert.deepEqual(groups, ['FUK,NRT', 'FUK,NRT']);
 Math.random = () => 0.99;
 const second = await (await worker.fetch(grouped('FUK,NRT'), {SERPAPI_API_KEY:'test'})).json();
 assert.equal(second.cached, true);
 assert.equal(second.destination, 'NRT');
 assert.equal(second.tomorrowFlight.destination, second.destination);
 assert.equal(groups.length, 2);
} finally {
 Math.random = originalRandom;
 globalThis.fetch = realFetch;
}
