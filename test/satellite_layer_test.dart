import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:elsewhere_travel/satellite_layer.dart';

void main() {
  testWidgets('satellite globe has a continuous Earth surface', (tester) async {
    final photo = await tester.runAsync(() async {
      final bytes = await rootBundle.load('assets/earth-blue-marble.jpg');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    });
    final key = GlobalKey();
    final controller = GlobeController(autoRotate: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xff08121c),
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 600,
                height: 600,
                child: Globe(
                  controller: controller,
                  autoRotate: false,
                  radiusMultiplier: 0.9,
                  theme: GlobeSkins.midnight.copyWith(
                    atmosphere: const GlobeAtmosphereStyle(
                      color: Color(0xffa6c9d3),
                      altitude: 0.08,
                      glowIntensity: 0.2,
                      innerShadowIntensity: 0.08,
                    ),
                    surface: GlobeSkins.midnight.surface.copyWith(
                      surfaceColor: const Color(0xff061624),
                      pointOpacity: 0,
                    ),
                  ),
                  layers: [SatelliteLayer(photo!)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(key),
      matchesGoldenFile('satellite_layer.png'),
    );
    await tester.pumpWidget(const SizedBox());
    photo.dispose();
    controller.dispose();
  });
}
