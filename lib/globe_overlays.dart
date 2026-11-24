import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_globe/flutter_globe.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'package:url_launcher/url_launcher.dart';

import 'data.dart';

Future<List<List<Vector3D>>> loadCountryLines() async {
  final rings =
      jsonDecode(await rootBundle.loadString('assets/country-lines.json'))
          as List;
  return [
    for (final ring in rings.cast<List>())
      [
        for (final point in ring.cast<List>())
          Vector3D.fromDegrees(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          ),
      ],
  ];
}

class GlobeOverlays extends GlobeLayer {
  GlobeOverlays(this.rings, this.controller, this.routeCodes)
    : super(zIndex: 16);

  final List<List<Vector3D>> rings;
  final GlobeController controller;
  final Set<String> routeCodes;
  (Quaternion3D, Offset, double)? _borderKey;
  Path? _borders;
  static final airports = {
    for (final p in places) p.code: Vector3D.fromDegrees(p.lat, p.lon),
  };

  static const names = {
    'ICN': 'Incheon Intl.',
    'GMP': 'Gimpo Intl.',
    'PUS': 'Gimhae Intl.',
    'CJU': 'Jeju Intl.',
    'NRT': 'Narita Intl.',
    'HND': 'Haneda',
    'FUK': 'Fukuoka Airport',
    'KIX': 'Kansai Intl.',
    'TPE': 'Taoyuan Intl.',
    'BKK': 'Suvarnabhumi',
    'SIN': 'Changi',
    'HKG': 'Hong Kong Intl.',
    'CDG': 'Charles de Gaulle',
    'LHR': 'Heathrow',
    'JFK': 'Kennedy Intl.',
    'LAX': 'Los Angeles Intl.',
  };

  @override
  void paint(GlobeRenderContext context) {
    final zoom = controller.zoom;
    if (zoom >= 1.1) {
      final key = (
        context.rotation,
        context.camera.center,
        context.camera.radius,
      );
      if (_borderKey != key) {
        _borderKey = key;
        final borders = _borders = Path();
        for (final ring in rings) {
          var drawing = false;
          for (final point in ring) {
            final v = context.rotation.rotateVector(point);
            if (v.z <= 0.04) {
              drawing = false;
              continue;
            }
            final p = context.camera.project(v).offset;
            if (drawing) {
              borders.lineTo(p.dx, p.dy);
            } else {
              borders.moveTo(p.dx, p.dy);
            }
            drawing = true;
          }
        }
      }
      context.canvas.drawPath(
        _borders!,
        Paint()
          ..color = const Color(0x99dceeff)
          ..strokeWidth = 0.65
          ..style = PaintingStyle.stroke,
      );
    }

    final labels = <Rect>[];
    final viewport = (Offset.zero & context.size).deflate(6);
    final detailed = zoom >= 1.8;
    final ordered = [
      ...places.where((p) => routeCodes.contains(p.code)),
      ...places.where((p) => !routeCodes.contains(p.code)),
    ];
    for (final airport in ordered) {
      final active = routeCodes.contains(airport.code);

      final v = context.rotation.rotateVector(airports[airport.code]!);
      if (v.z < 0.12) continue;
      final p = context.camera.project(v).offset;
      if (!viewport.contains(p)) continue;
      final dot = Paint()..color = const Color(0xff67dcff);
      context.canvas.drawCircle(p, detailed ? 3.5 : 2.3, dot);
      if (detailed) {
        context.canvas.drawCircle(p, 2, Paint()..color = Colors.white);
      }
      if (zoom < 1.45 && !active) continue;

      final width = detailed ? 134.0 : 28.0;
      final height = detailed ? 34.0 : 16.0;
      final gap = detailed ? 10.0 : 4.0;
      Rect? badge;
      for (final dy in detailed ? [0.0, -22.0, 22.0] : [0.0]) {
        for (final x in [p.dx + gap, p.dx - gap - width]) {
          final candidate = Rect.fromLTWH(
            x,
            p.dy - height / 2 + dy,
            width,
            height,
          );
          if (viewport.contains(candidate.topLeft) &&
              viewport.contains(candidate.bottomRight) &&
              !labels.any(candidate.inflate(3).overlaps)) {
            badge = candidate;
            break;
          }
        }
        if (badge != null) break;
      }
      if (badge == null) continue;
      final rect = badge;
      labels.add(rect);
      final canvas = context.canvas;
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));
      if (detailed) {
        final edge = Offset(
          rect.center.dx > p.dx ? rect.left : rect.right,
          rect.center.dy,
        );
        canvas.drawLine(p, edge, dot..strokeWidth = 1.5);
      }
      canvas.drawRRect(
        shape,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xf522415a), Color(0xf509152b)],
          ).createShader(rect),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..color = const Color(0xaac6e6ff)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      if (detailed) {
        final icon = Icons.flight;
        _text(
          canvas,
          String.fromCharCode(icon.codePoint),
          rect.centerLeft + const Offset(9, 0),
          TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: icon.fontFamily,
          ),
        );
        canvas.drawLine(
          rect.topLeft + const Offset(27, 8),
          rect.bottomLeft + const Offset(27, -8),
          Paint()..color = const Color(0x77c6e6ff),
        );
        _text(
          canvas,
          airport.code,
          rect.centerLeft + const Offset(33, 0),
          const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        );
        _text(
          canvas,
          '${airport.city}\n${names[airport.code] ?? ''}',
          rect.centerLeft + const Offset(65, 0),
          const TextStyle(color: Color(0xffe2efff), fontSize: 8, height: 1.17),
        );
      } else {
        _text(
          canvas,
          airport.code,
          rect.centerLeft + const Offset(4, 0),
          const TextStyle(color: Colors.white, fontSize: 9),
        );
      }
    }
  }

  static void _text(
    Canvas canvas,
    String value,
    Offset leftCenter,
    TextStyle style,
  ) {
    final text = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, leftCenter - Offset(0, text.height / 2));
    text.dispose();
  }
}

(double, double) globeCenter(Quaternion3D rotation) {
  final v = rotation.conjugate.rotateVector(Vector3D.unitZ);
  return (asin((-v.y).clamp(-1.0, 1.0)) * 180 / pi, atan2(v.x, v.z) * 180 / pi);
}

class DetailedMap extends StatefulWidget {
  const DetailedMap({
    super.key,
    required this.center,
    required this.airports,
    required this.onExit,
  });

  final (double, double) center;
  final List<Place> airports;
  final ValueChanged<(double, double)> onExit;

  @override
  State<DetailedMap> createState() => _DetailedMapState();
}

class _DetailedMapState extends State<DetailedMap> {
  static const tileUrl = String.fromEnvironment(
    'OSM_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const entryZoom = 6.0;
  final controller = MapController();
  late final initialCenter = LatLng(
    widget.center.$1.clamp(-85.0, 85.0),
    widget.center.$2,
  );
  late LatLng center = initialCenter;
  Timer? timeout;
  bool ready = false;
  bool unavailable = false;
  bool revealScheduled = false;

  @override
  void initState() {
    super.initState();
    timeout = Timer(const Duration(seconds: 8), () {
      if (!ready) setState(() => unavailable = true);
    });
  }

  @override
  void dispose() {
    timeout?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _exit() => widget.onExit((center.latitude, center.longitude));

  void _zoom(double delta) {
    final camera = controller.camera;
    final next = camera.zoom + delta;
    if (next < entryZoom) {
      _exit();
    } else {
      controller.move(camera.center, min(17, next));
    }
  }

  void _openGoogleMaps() => launchUrl(
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${center.latitude},${center.longitude}',
    }),
    mode: LaunchMode.externalApplication,
  );

  void _reveal() {
    if (ready || revealScheduled) return;
    revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      timeout?.cancel();
      setState(() {
        ready = true;
        unavailable = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        ignoring: !ready,
        child: AnimatedOpacity(
          opacity: ready ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: FlutterMap(
            mapController: controller,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: entryZoom,
              minZoom: entryZoom - 1,
              maxZoom: 17,
              backgroundColor: Colors.transparent,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camera, _) {
                center = camera.center;
                if (camera.zoom < entryZoom - 0.25) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && controller.camera.zoom < entryZoom - 0.25) {
                      _exit();
                    }
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.example.elsewhereTravel',
                panBuffer: 0,
                maxNativeZoom: 13,
                tileBuilder: (_, child, tile) {
                  if (tile.loadFinishedAt != null && !tile.loadError) _reveal();
                  return child;
                },
              ),
              MarkerLayer(
                markers: [
                  for (final airport in widget.airports)
                    Marker(
                      point: LatLng(airport.lat, airport.lon),
                      width: 86,
                      height: 30,
                      alignment: Alignment.centerRight,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 20,
                            color: Color(0xff2878f0),
                          ),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(airport.code),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                permanentHeight: 22,
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () => launchUrl(
                      Uri.https('www.openstreetmap.org', '/copyright'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (!ready)
        Align(
          alignment: Alignment.topCenter,
          child: unavailable
              ? FilledButton(
                  onPressed: _openGoogleMaps,
                  child: const Text('Open Google Maps'),
                )
              : const IgnorePointer(
                  child: Chip(label: Text('Loading detailed map…')),
                ),
        ),
      if (ready)
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: 'Zoom in on map',
                onPressed: () => _zoom(1),
                icon: const Icon(Icons.add),
              ),
              IconButton.filledTonal(
                tooltip: 'Zoom out on map',
                onPressed: () => _zoom(-1),
                icon: const Icon(Icons.remove),
              ),
              IconButton.filledTonal(
                tooltip: 'Back to globe',
                onPressed: _exit,
                icon: const Icon(Icons.public),
              ),
              IconButton.filledTonal(
                tooltip: 'Open Google Maps',
                onPressed: _openGoogleMaps,
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Decorative traffic follows independent, continuous tracks, without airport endpoints.
class AmbientFlights extends GlobeLayer {
  const AmbientFlights() : super(zIndex: 17);

  static final _silhouette = Path()
    ..moveTo(0, -8)
    ..quadraticBezierTo(2, -8, 2, -4)
    ..lineTo(2, -2)
    ..lineTo(8, 2)
    ..lineTo(8, 4)
    ..lineTo(2, 2)
    ..lineTo(1.5, 5)
    ..lineTo(4, 7)
    ..lineTo(4, 8)
    ..lineTo(0, 7)
    ..lineTo(-4, 8)
    ..lineTo(-4, 7)
    ..lineTo(-1.5, 5)
    ..lineTo(-2, 2)
    ..lineTo(-8, 4)
    ..lineTo(-8, 2)
    ..lineTo(-2, -2)
    ..lineTo(-2, -4)
    ..quadraticBezierTo(-2, -8, 0, -8)
    ..close();

  @override
  void paint(GlobeRenderContext context) {
    final time = context.animationTimeMs / 1000;
    final paint = Paint();
    for (var i = 0; i < 20; i++) {
      final speed = (i.isEven ? 1 : -1) * (7 + i % 5 * 1.3);
      final longitude = i * 137.508 + speed * time;
      final band = (i % 7 - 3) * 15.0;
      final phase = longitude * pi / 180 + i * 0.63;
      final latitude = band + 19 * sin(phase);
      final position = context.rotation.rotateVector(
        Vector3D.fromDegrees(latitude, longitude),
      );
      if (position.z <= 0.12) continue;
      final step = speed * 0.04;
      final next = context.rotation.rotateVector(
        Vector3D.fromDegrees(
          band + 19 * sin(phase + step * pi / 180),
          longitude + step,
        ),
      );
      final point = context.camera.project(position).offset;
      final heading = context.camera.project(next).offset - point;
      final fade = ((position.z - 0.12) / 0.3).clamp(0.0, 1.0);
      drawPlane(
        context.canvas,
        paint,
        point,
        heading.direction,
        fade,
        0.65 + i % 3 * 0.09,
      );
    }
  }

  static void drawPlane(
    Canvas canvas,
    Paint paint,
    Offset point,
    double heading,
    double fade,
    double scale,
  ) {
    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas.rotate(heading + pi / 2);
    canvas.scale(scale, scale);
    canvas.drawPath(
      _silhouette,
      paint
        ..color = const Color(0xff192f60).withValues(alpha: fade * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      _silhouette,
      paint
        ..color = const Color(0xffd9efff).withValues(alpha: fade)
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }
}

class SearchFlightBurst extends GlobeLayer {
  SearchFlightBurst() : super(zIndex: 18);

  static const planeCount = 13;
  double? _start;

  @override
  void paint(GlobeRenderContext context) {
    final elapsed =
        context.animationTimeMs - (_start ??= context.animationTimeMs);
    final radius = min(context.camera.radius, context.size.shortestSide / 2);
    final paint = Paint();
    for (var i = 0; i < planeCount; i++) {
      final age = (elapsed - i * 38) / (1400 + i % 4 * 180);
      if (age < 0) continue;
      final progress = age % 1;
      final direction = i * 2.39996;
      final distance = radius * (0.18 + progress * (0.48 + i % 4 * 0.08));
      final point =
          context.camera.center + Offset.fromDirection(direction, distance);
      final fade = min(progress * 8, (1 - progress) * 4).clamp(0.0, 1.0);
      AmbientFlights.drawPlane(
        context.canvas,
        paint,
        point,
        direction,
        fade,
        0.78,
      );
    }
  }
}
