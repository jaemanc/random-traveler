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
// Extra departure airports do not expand the curated destination gallery.
const departureAirports = <Place>[
  ...places,
  Place('TAE', 'Daegu', 'South Korea', 'KR', 35.89, 128.66, 0),
  Place('CJJ', 'Cheongju', 'South Korea', 'KR', 36.72, 127.50, 0),
  Place('KWJ', 'Gwangju', 'South Korea', 'KR', 35.13, 126.81, 0),
  Place('USN', 'Ulsan', 'South Korea', 'KR', 35.59, 129.35, 0),
  Place('RSU', 'Yeosu', 'South Korea', 'KR', 34.84, 127.62, 0),
  Place('CTS', 'Sapporo', 'Japan', 'JP', 42.78, 141.69, 0),
  Place('NGO', 'Nagoya', 'Japan', 'JP', 34.86, 136.81, 0),
  Place('OKA', 'Okinawa', 'Japan', 'JP', 26.20, 127.65, 0),
  Place('PEK', 'Beijing', 'China', 'CN', 40.08, 116.58, 0),
  Place('PVG', 'Shanghai', 'China', 'CN', 31.14, 121.81, 0),
  Place('CAN', 'Guangzhou', 'China', 'CN', 23.39, 113.30, 0),
  Place('MNL', 'Manila', 'Philippines', 'PH', 14.51, 121.02, 0),
  Place('HAN', 'Hanoi', 'Vietnam', 'VN', 21.22, 105.81, 0),
  Place('SGN', 'Ho Chi Minh City', 'Vietnam', 'VN', 10.82, 106.65, 0),
  Place('DAD', 'Da Nang', 'Vietnam', 'VN', 16.04, 108.20, 0),
  Place('KUL', 'Kuala Lumpur', 'Malaysia', 'MY', 2.75, 101.71, 0),
  Place('CGK', 'Jakarta', 'Indonesia', 'ID', -6.13, 106.66, 0),
  Place('DEL', 'Delhi', 'India', 'IN', 28.56, 77.10, 0),
  Place('DXB', 'Dubai', 'United Arab Emirates', 'AE', 25.25, 55.36, 0),
  Place('DOH', 'Doha', 'Qatar', 'QA', 25.27, 51.61, 0),
  Place('IST', 'Istanbul', 'Türkiye', 'TR', 41.28, 28.75, 0),
  Place('FRA', 'Frankfurt', 'Germany', 'DE', 50.04, 8.56, 0),
  Place('AMS', 'Amsterdam', 'Netherlands', 'NL', 52.31, 4.77, 0),
  Place('MAD', 'Madrid', 'Spain', 'ES', 40.47, -3.56, 0),
  Place('FCO', 'Rome', 'Italy', 'IT', 41.80, 12.25, 0),
  Place('SFO', 'San Francisco', 'United States', 'US', 37.62, -122.38, 0),
  Place('SEA', 'Seattle', 'United States', 'US', 47.45, -122.31, 0),
  Place('ORD', 'Chicago', 'United States', 'US', 41.97, -87.90, 0),
  Place('YYZ', 'Toronto', 'Canada', 'CA', 43.68, -79.63, 0),
  Place('YVR', 'Vancouver', 'Canada', 'CA', 49.19, -123.18, 0),
  Place('MEX', 'Mexico City', 'Mexico', 'MX', 19.44, -99.07, 0),
  Place('GRU', 'São Paulo', 'Brazil', 'BR', -23.43, -46.47, 0),
  Place('SYD', 'Sydney', 'Australia', 'AU', -33.95, 151.18, 0),
  Place('MEL', 'Melbourne', 'Australia', 'AU', -37.67, 144.84, 0),
  Place('AKL', 'Auckland', 'New Zealand', 'NZ', -37.01, 174.79, 0),
  Place('JNB', 'Johannesburg', 'South Africa', 'ZA', -26.14, 28.25, 0),
];

double distance(double lat, double lon, Place b) {
  final r = pi / 180, dLat = (b.lat - lat) * r, dLon = (b.lon - lon) * r;
  final h =
      pow(sin(dLat / 2), 2) +
      cos(lat * r) * cos(b.lat * r) * pow(sin(dLon / 2), 2);
  return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h));
}
