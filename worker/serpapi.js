// Normalize Google Flights results to the itinerary fields shared by the Worker.
export async function searchSerpApi({key, origin, destination, date, returnDate, now}) {
 const url = new URL('https://serpapi.com/search.json');
 url.search = new URLSearchParams({
  engine:'google_flights', api_key:key, departure_id:origin, arrival_id:destination,
  outbound_date:date, type:returnDate ? '1' : '2', currency:'USD', hl:'en',
  ...(returnDate ? {return_date:returnDate} : {}),
 });
 const response = await fetch(url);
 if (!response.ok) return null;
 const body = await response.json();
 if (body.search_metadata?.status !== 'Success') return null;
 // Search results have no offer expiry. Only reuse them for the Worker cache window.
 const expiresAt = new Date(+now + 120_000).toISOString();
 return [...(body.best_flights ?? []), ...(body.other_flights ?? [])].flatMap(option => {
  if (typeof option.price !== 'number' || option.price <= 0 || !option.flights?.length) return [];
  const minutes = option.total_duration;
  const duration = Number.isFinite(minutes) ? `PT${Math.floor(minutes/60)}H${minutes%60}M` : '';
  return [{
   booking_url:body.search_metadata.google_flights_url,
   total_amount:option.price, total_currency:'USD', expires_at:expiresAt,
   checked_at: new Date((body.search_metadata.processed_at ?? '').replace(' UTC', 'Z').replace(' ', 'T')),
   slices:[{
    duration,
    segments:option.flights.map((flight, i) => ({
     flight_number:flight.flight_number,
     departing_at:flight.departure_airport?.time?.replace(' ', 'T'),
     arriving_at:flight.arrival_airport?.time?.replace(' ', 'T'),
     origin:{iata_code:flight.departure_airport?.id},
     destination:{iata_code:flight.arrival_airport?.id},
     operating_carrier:{name:flight.airline},
     layover_minutes:option.layovers?.[i]?.id === flight.arrival_airport?.id
      ? option.layovers?.[i]?.duration : undefined,
    })),
   }],
  }];
 });
}
