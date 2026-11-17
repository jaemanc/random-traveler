import 'dart:math';

class Place {
  const Place(
    this.code,
    this.city,
    this.country,
    this.countryCode,
    this.lat,
    this.lon,
    this.daily,
  );
  final String code, city, country, countryCode;
  final double lat, lon;
  final int daily;
}

const places = <Place>[
  Place('ICN', 'Seoul', 'South Korea', 'KR', 37.46, 126.44, 75),
  Place('GMP', 'Seoul', 'South Korea', 'KR', 37.56, 126.8, 75),
  Place('PUS', 'Busan', 'South Korea', 'KR', 35.18, 128.94, 68),
  Place('CJU', 'Jeju', 'South Korea', 'KR', 33.51, 126.49, 72),
  Place('NRT', 'Tokyo', 'Japan', 'JP', 35.77, 140.39, 105),
  Place('HND', 'Tokyo', 'Japan', 'JP', 35.55, 139.78, 105),
  Place('FUK', 'Fukuoka', 'Japan', 'JP', 33.59, 130.45, 90),
  Place('KIX', 'Osaka', 'Japan', 'JP', 34.43, 135.24, 99),
  Place('TPE', 'Taipei', 'Taiwan', 'TW', 25.08, 121.23, 82),
  Place('BKK', 'Bangkok', 'Thailand', 'TH', 13.69, 100.75, 65),
  Place('SIN', 'Singapore', 'Singapore', 'SG', 1.36, 103.99, 130),
  Place('HKG', 'Hong Kong', 'Hong Kong', 'HK', 22.31, 113.91, 115),
  Place('CDG', 'Paris', 'France', 'FR', 49.01, 2.55, 160),
  Place('LHR', 'London', 'United Kingdom', 'GB', 51.47, -0.45, 170),
  Place('JFK', 'New York', 'United States', 'US', 40.64, -73.78, 185),
  Place('LAX', 'Los Angeles', 'United States', 'US', 33.94, -118.41, 175),
];
double distance(double lat, double lon, Place b) {
  final r = pi / 180, dLat = (b.lat - lat) * r, dLon = (b.lon - lon) * r;
  final h =
      pow(sin(dLat / 2), 2) +
      cos(lat * r) * cos(b.lat * r) * pow(sin(dLon / 2), 2);
  return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h));
}
