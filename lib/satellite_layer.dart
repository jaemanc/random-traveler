import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_globe/flutter_globe.dart';

/// NASA Blue Marble surface; flight routes remain in flutter_globe's own layer.
class SatelliteLayer extends GlobeLayer {
  SatelliteLayer(this.image) : super(zIndex: 15);
  final ui.Image image;
  static final _mesh = [
    for (var y = 0; y < 24; y++)
      for (var x = 0; x < 48; x++)
        [
          _vertex(x, y),
          _vertex(x + 1, y),
          _vertex(x, y + 1),
          _vertex(x + 1, y),
          _vertex(x + 1, y + 1),
          _vertex(x, y + 1),
        ],
  ];
  static (Vector3D, Offset) _vertex(int x, int y) {
    final lat = 90 - y * 180 / 24;
    final lon = -180 + x * 360 / 48;
    return (Vector3D.fromDegrees(lat, lon), Offset(x / 48, y / 24));
  }

  @override
  void paint(GlobeRenderContext context) {
    final camera = context.camera;
    final canvas = context.canvas;
    canvas.drawCircle(
      camera.center,
      camera.radius,
      Paint()..color = const Color(0xff061624),
    );
    final positions = <Offset>[];
    final tex = <Offset>[];
    for (final triangle in _mesh) {
      final rotated = triangle
          .map((v) => context.rotation.rotateVector(v.$1))
          .toList();
      if (rotated.any((v) => v.z < 0.02)) continue;
      for (var i = 0; i < 3; i++) {
        positions.add(camera.project(rotated[i]).offset);
        tex.add(
          Offset(
            triangle[i].$2.dx * image.width,
            triangle[i].$2.dy * image.height,
          ),
        );
      }
    }
    if (positions.isEmpty) return;
    final shader = ui.ImageShader(
      image,
      ui.TileMode.clamp,
      ui.TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    );
    canvas.drawVertices(
      ui.Vertices(ui.VertexMode.triangles, positions, textureCoordinates: tex),
      ui.BlendMode.srcOver,
      Paint()..shader = shader,
    );
    canvas.drawCircle(
      camera.center,
      camera.radius,
      Paint()
        ..shader =
            RadialGradient(
              colors: const [Colors.transparent, Color(0x77000000)],
              stops: const [0.65, 1],
            ).createShader(
              Rect.fromCircle(center: camera.center, radius: camera.radius),
            ),
    );
  }
}
