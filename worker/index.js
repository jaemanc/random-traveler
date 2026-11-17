const airports = new Set('ICN GMP PUS CJU NRT HND FUK KIX TPE BKK SIN HKG CDG LHR JFK LAX'.split(' '));
const zones={ICN:'Asia/Seoul',GMP:'Asia/Seoul',PUS:'Asia/Seoul',CJU:'Asia/Seoul',NRT:'Asia/Tokyo',HND:'Asia/Tokyo',FUK:'Asia/Tokyo',KIX:'Asia/Tokyo',TPE:'Asia/Taipei',BKK:'Asia/Bangkok',SIN:'Asia/Singapore',HKG:'Asia/Hong_Kong',CDG:'Europe/Paris',LHR:'Europe/London',JFK:'America/New_York',LAX:'America/Los_Angeles'};
const json = (body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*'}});
export default { async fetch(request,env){
 const u=new URL(request.url),origin=u.searchParams.get('origin'),destination=u.searchParams.get('destination'),hours=Number(u.searchParams.get('hours')),kind=u.searchParams.get('kind');
 if(!airports.has(origin)||!airports.has(destination)||origin===destination||![12,24,48].includes(hours)||!['one-way','round-trip'].includes(kind))return json({error:'Invalid search'},400);
 const key=new Request(`${u.origin}${u.pathname}?origin=${origin}&destination=${destination}&hours=${hours}&kind=${kind}`);
 // shortcut: edge entries are local to each data center; use KV if global cache sharing is required.
 const edge=globalThis.caches?.default,cached=await edge?.match(key);
 const now=new Date(),end=new Date(now.getTime()+hours*3600000);
 if(cached){
  const value=await cached.json(),flight=value.flight;
  const local=new Date(now.toLocaleString('en-US',{timeZone:zones[origin]}));
  if(!flight||(new Date(flight.depart)>local&&new Date(flight.depart)-local<=hours*3600000&&new Date(flight.expiresAt)>now))return json({...value,cached:true});
 }
 if(!env.DUFFEL_TOKEN)return json({error:'Missing Duffel token'},503);
 const day=x=>new Intl.DateTimeFormat('en-CA',{timeZone:zones[origin],year:'numeric',month:'2-digit',day:'2-digit'}).format(x);
 const dates=[...new Set([day(now),day(end)])];
 let best;
 for(const date of dates){
  const slices=[{origin,destination,departure_date:date}];
  if(kind==='round-trip'){let back=new Date(date+'T12:00:00Z');back.setUTCDate(back.getUTCDate()+3);slices.push({origin:destination,destination:origin,departure_date:back.toISOString().slice(0,10)})}
  const r=await fetch('https://api.duffel.com/air/offer_requests?return_offers=true&supplier_timeout=10000',{method:'POST',headers:{authorization:`Bearer ${env.DUFFEL_TOKEN}`,'duffel-version':'v2','content-type':'application/json'},body:JSON.stringify({data:{slices,passengers:[{type:'adult'}],cabin_class:'economy'}})});
  if(!r.ok)return json({error:'Flight provider unavailable'},502);
  const data=(await r.json()).data;
  for(const offer of data.offers||[]){
   const first=offer.slices?.[0],segments=first?.segments||[],depart=segments[0]?.departing_at,arrive=segments.at(-1)?.arriving_at;
   if(!depart||!arrive||offer.live_mode===false)continue;
   const zone=first.origin?.time_zone||'UTC';
   const local=new Date(new Date().toLocaleString('en-US',{timeZone:zone}));
   const localDeparture=new Date(depart);
   const delta=localDeparture-local;
   if(delta<0||delta>hours*3600000||new Date(offer.expires_at)<now)continue;
   const amount=Number(offer.total_amount);
   if(!Number.isFinite(amount))continue;
   if(!best||amount<best.amount)best={airline:segments.map(s=>s.operating_carrier?.name||s.marketing_carrier?.name).filter(Boolean).filter((v,i,a)=>a.indexOf(v)===i).join(' + ')||'Airline unavailable',depart,arrive,duration:(first.duration||'').replace(/^PT(?:(\d+)H)?(?:(\d+)M)?$/,(_,h,m)=>[h&&h+'h',m&&m+'m'].filter(Boolean).join(' '))||'See itinerary',amount,currency:offer.total_currency,checkedAt:now.toISOString(),expiresAt:offer.expires_at,via:segments.slice(0,-1).map(s=>s.destination?.iata_code).filter(Boolean),kind};
  }
 }
 const value={flight:best||null};
 if(edge)await edge.put(key,new Response(JSON.stringify(value),{headers:{'content-type':'application/json','cache-control':'public,max-age=120'}}));
 return json({...value,cached:false});
}};
