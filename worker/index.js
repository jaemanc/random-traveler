import {searchSerpApi} from './serpapi.js';
const airportZones = {
 'Asia/Seoul':'ICN GMP PUS CJU TAE CJJ KWJ USN RSU',
 'Asia/Tokyo':'NRT HND FUK KIX CTS NGO OKA',
 'Asia/Taipei':'TPE', 'Asia/Bangkok':'BKK', 'Asia/Singapore':'SIN', 'Asia/Hong_Kong':'HKG',
 'Asia/Shanghai':'PEK PVG CAN', 'Asia/Manila':'MNL', 'Asia/Ho_Chi_Minh':'HAN SGN DAD',
 'Asia/Kuala_Lumpur':'KUL', 'Asia/Jakarta':'CGK', 'Asia/Kolkata':'DEL',
 'Asia/Dubai':'DXB', 'Asia/Qatar':'DOH', 'Europe/Istanbul':'IST',
 'Europe/Paris':'CDG', 'Europe/London':'LHR', 'Europe/Berlin':'FRA',
 'Europe/Amsterdam':'AMS', 'Europe/Madrid':'MAD', 'Europe/Rome':'FCO',
 'America/New_York':'JFK', 'America/Los_Angeles':'LAX SFO SEA', 'America/Chicago':'ORD',
 'America/Toronto':'YYZ', 'America/Vancouver':'YVR', 'America/Mexico_City':'MEX',
 'America/Sao_Paulo':'GRU', 'Australia/Sydney':'SYD', 'Australia/Melbourne':'MEL',
 'Pacific/Auckland':'AKL', 'Africa/Johannesburg':'JNB',
};
const zones = Object.fromEntries(Object.entries(airportZones).flatMap(
 ([zone,codes]) => codes.split(' ').map(code => [code,zone]),
));
const airports = new Set(Object.keys(zones));
const json = (body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store','access-control-allow-origin':'*'}});
const hour = 3_600_000;
const localDateTime = (date, zone) =>
 new Intl.DateTimeFormat('sv-SE', {
  timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit',
  hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
 }).format(date).replace(' ', 'T');
const wallTime = value => Date.parse(value + 'Z');
const dateAfter = (date, days) =>
 new Date(Date.parse(date + 'T00:00:00Z') + days * 24 * hour).toISOString().slice(0, 10);

function utcTime(value, zone) {
 const target = wallTime(value);
 if (!Number.isFinite(target)) return NaN;
 let instant = target;
 for (let i = 0; i < 3; i++) {
  instant += target - wallTime(localDateTime(new Date(instant), zone));
 }
 return instant;
}

function pickRoute(offers, {now, end, tomorrow, cached}) {
 const routes = new Map();
 for (const offer of offers) {
  const departure = Date.parse(offer.departAtUtc);
  if (departure <= now || Date.parse(offer.expiresAt) <= now) continue;
  const route = routes.get(offer.destination) ?? {destination:offer.destination, flight:null, tomorrowFlight:null};
  if (!route.flight && departure <= end) {
   route.flight = offer;
  } else if (!route.tomorrowFlight && offer.depart.slice(0,10) === tomorrow &&
    offer.depart.slice(11,16) >= '12:00' && offer.depart.slice(11,16) < '18:00' &&
    offer.departAtUtc !== route.flight?.departAtUtc) {
   route.tomorrowFlight = offer;
  }
  if (route.flight || route.tomorrowFlight) routes.set(offer.destination, route);
 }
 const choices = [...routes.values()];
 const selected = choices[Math.floor(Math.random() * choices.length)];
 return {...(selected ?? {flight:null, tomorrowFlight:null}), cached, poolSize:choices.length};
}

export default {
 async fetch(request, env) {
  const u = new URL(request.url);
  const origin = u.searchParams.get('origin');
  const requested = [...new Set((u.searchParams.get('destination') ?? '').split(','))];
  const pool = requested.length > 1;
  const destination = requested[0];
  const hours = Number(u.searchParams.get('hours')), kind = u.searchParams.get('kind');
  if (!airports.has(origin) || requested.length > airports.size || requested.some(code => !airports.has(code) || code === origin) ||
      ![12,24,48].includes(hours) || !['one-way','round-trip'].includes(kind)) {
   return json({error:'Invalid search'}, 400);
  }
  const serpKey = env.SERPAPI_API_KEY || env.sera_api_key;
  const provider = serpKey ? 'serpapi' : 'duffel';
  const groupKey = serpKey && pool ? [...requested].sort().join(',') : destination;
  const key = new Request(`${u.origin}${u.pathname}?version=5&provider=${provider}&origin=${origin}&destination=${groupKey}&pool=${pool}&hours=${hours}&kind=${kind}`);
  const edge = globalThis.caches?.default;
  const now = new Date(), end = new Date(+now + hours * hour), zone = zones[origin];
  const today = localDateTime(now, zone).slice(0, 10);
  const tomorrow = dateAfter(today, 1);
  const cached = await edge?.match(key);
  if (cached) {
   const value = await cached.json();
   if (pool && value.tomorrow === tomorrow && Array.isArray(value.offers)) {
    const selected = pickRoute(value.offers, {now,end,tomorrow,cached:true});
    if (selected.poolSize || !value.offers.length) return json(selected);
   }
   if (!pool && value.tomorrow === tomorrow && [value.flight, value.tomorrowFlight].every(f =>
     !f || Date.parse(f.departAtUtc) > now && Date.parse(f.expiresAt) > now)) {
    return json({...value, cached:true});
   }
  }
  if (!serpKey && !env.DUFFEL_TOKEN) return json({error:'Flight provider not configured'}, 503);
  const candidates = [...requested].sort();
  for (let i = 0; i < Math.min(4, candidates.length) && candidates.length > 4; i++) {
   const next = i + Math.floor(Math.random() * (candidates.length - i));
   [candidates[i], candidates[next]] = [candidates[next], candidates[i]];
  }
  const searched = serpKey && pool ? candidates.slice(0,4) : [destination];
  const queryDestination = searched.join(',');
  const dates = [...new Set([today, tomorrow, localDateTime(end, zone).slice(0, 10)])];
  const batches = await Promise.all(dates.map(async date => {
   const slices = [{origin,destination,departure_date:date}];
   if (kind === 'round-trip') {
    slices.push({origin:destination,destination:origin,departure_date:dateAfter(date, 3)});
   }
   try {
    if (serpKey) return await searchSerpApi({
     key:serpKey, origin, destination:queryDestination, date, now,
     returnDate:kind === 'round-trip' ? dateAfter(date, 3) : undefined,
    });
    const response = await fetch('https://api.duffel.com/air/offer_requests?return_offers=true&supplier_timeout=10000', {
     method:'POST',
     headers:{authorization:`Bearer ${env.DUFFEL_TOKEN}`,'duffel-version':'v2','content-type':'application/json'},
     body:JSON.stringify({data:{slices,passengers:[{type:'adult'}],cabin_class:'economy'}}),
    });
    if (response.ok) return (await response.json()).data?.offers ?? [];
   } catch {}
   return null;
  }));
  if (batches.every(batch => batch === null)) return json({error:'Flight provider unavailable'}, 502);
  const offers = [];
  for (const offer of batches.flatMap(batch => batch ?? [])) {
   const first = offer.slices?.[0], segments = first?.segments ?? [];
   const depart = segments[0]?.departing_at, arrive = segments.at(-1)?.arriving_at;
   if (!depart || !arrive || offer.live_mode === false || !(Date.parse(offer.expires_at) > now)) continue;
   const departure = utcTime(depart, zone);
   const amount = Number(offer.total_amount);
   if (!Number.isFinite(departure) || departure <= now || !Number.isFinite(amount)) continue;
   const connections = segments.slice(0,-1).map((segment, index) => {
    const next = segments[index+1], airport = segment.destination;
    const elapsed = (Date.parse(next.departing_at + 'Z') - Date.parse(segment.arriving_at + 'Z')) / 60000;
    return {
     code: airport?.iata_code,
     minutes: Number.isFinite(segment.layover_minutes) ? segment.layover_minutes :
       airport?.iata_code && airport.iata_code === next.origin?.iata_code &&
       Number.isFinite(elapsed) && elapsed >= 0 ? elapsed : null,
    };
   });
   const actualDestination = pool && serpKey ? segments.at(-1)?.destination?.iata_code : destination;
   if (!searched.includes(actualDestination)) continue;
   offers.push({
    destination:actualDestination,
    airline: [...new Set(segments.map(s=>s.operating_carrier?.name||s.marketing_carrier?.name).filter(Boolean))].join(' + ') || 'Airline unavailable',
    depart, arrive, departAtUtc:new Date(departure).toISOString(),
    duration:(first.duration||'').replace(/^PT(?:(\d+)H)?(?:(\d+)M)?$/,(_,h,m)=>[h&&h+'h',m&&m+'m'].filter(Boolean).join(' '))||'See itinerary',
    amount, currency:offer.total_currency, checkedAt:Number.isFinite(+offer.checked_at) ? offer.checked_at.toISOString() : now.toISOString(), expiresAt:offer.expires_at,
    via:connections.map(stop=>stop.code).filter(Boolean), connections, kind,
   });
  }
  offers.sort((a,b) => a.departAtUtc.localeCompare(b.departAtUtc) ||
    (a.currency === b.currency ? a.amount-b.amount : 0));
  const selected = pickRoute(offers, {now,end,tomorrow,cached:false});
  const value = pool ? {offers, tomorrow} : {...selected, tomorrow};
  if (edge && batches.every(batch => batch !== null)) await edge.put(key,new Response(JSON.stringify(value),{headers:{'content-type':'application/json','cache-control':'public,max-age=120'}}));
  return json(selected);

 }
};
