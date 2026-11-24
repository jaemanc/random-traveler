import 'dart:async';
import 'dart:convert';

import 'package:elsewhere_travel/flight_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'publishes the first itinerary and updates the same route, then reuses it',
    () async {
      var now = DateTime.utc(2026, 11, 24, 0);
      final today = Completer<http.Response>();
      final tomorrow = Completer<http.Response>();
      var requests = 0;
      late http.Response Function(http.Request) flightsForRefresh;
      final client = MockClient((request) async {
        requests++;
        if (requests > 2) return flightsForRefresh(request);
        return request.url.queryParameters['outbound_date'] == '2026-11-24'
            ? today.future
            : tomorrow.future;
      });
      http.Response flights(String date, {int price = 200}) => http.Response(
        jsonEncode({
          'search_metadata': {'status': 'Success'},
          'best_flights': [
            {
              'price': price,
              'flights': [
                {
                  'departure_airport': {'id': 'ICN', 'time': '$date 13:00'},
                  'arrival_airport': {'id': 'NRT', 'time': '$date 15:00'},
                },
              ],
            },
          ],
        }),
        200,
      );
      flightsForRefresh = (request) =>
          flights(request.url.queryParameters['outbound_date']!, price: 180);
      final search = MobileFlightSearch('', now: () => now);
      await http.runWithClient(() async {
        final stream = StreamIterator(search.search('ICN', ['NRT']));
        final first = stream.moveNext();
        tomorrow.complete(flights('2026-11-25'));
        expect(await first, isTrue);
        expect(stream.current['destination'], 'NRT');
        expect(stream.current['flight'], isNull);
        expect(stream.current['tomorrowFlight'], isNotNull);
        final second = stream.moveNext();
        today.complete(flights('2026-11-24'));
        expect(await second, isTrue);
        expect(stream.current['destination'], 'NRT');
        expect(stream.current['flight'], isNotNull);
        expect(stream.current['tomorrowFlight'], isNotNull);
        expect(await stream.moveNext(), isFalse);
        now = now.add(const Duration(hours: 1, minutes: 59));
        final fresh = await search.search('ICN', ['NRT']).single;
        expect(fresh['cached'], isTrue);
        expect(requests, 2);
        now = now.add(const Duration(minutes: 1));
        final updates = await search.search('ICN', ['NRT']).toList();
        expect(updates.first['cached'], isTrue);
        expect(updates.first['flight']['amount'], 200);
        expect(updates.last['cached'], isFalse);
        expect(updates.last['flight']['amount'], 180);
        expect(updates.last['tomorrowFlight']['amount'], 180);
        expect(requests, 4);
      }, () => client);
    },
  );
}
