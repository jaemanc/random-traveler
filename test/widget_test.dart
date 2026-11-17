import 'package:flutter_test/flutter_test.dart';
import 'package:elsewhere_travel/data.dart';

void main() {
  test('nearest airport uses coordinates', () {
    final sorted = [...places]
      ..sort(
        (a, b) =>
            distance(37.46, 126.44, a).compareTo(distance(37.46, 126.44, b)),
      );
    expect(sorted.first.code, 'ICN');
  });
}
