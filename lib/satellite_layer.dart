import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_globe/flutter_globe.dart';

/// NASA Blue Marble surface; flight routes remain in flutter_globe's own layer.
class SatelliteLayer extends GlobeLayer {
  SatelliteLayer(this.image) : super(zIndex: 15);
  final ui.Image image;
  late final ui.ImageShader _shader = ui.ImageShader(
    image,
    ui.TileMode.clamp,
    ui.TileMode.clamp,
    Matrix4.identity().storage,
    filterQuality: FilterQuality.medium,
  );
  (Quaternion3D, Offset, double)? _meshKey;
  ui.Vertices? _vertices;

  static final _mesh = [
    for (var y = 0; y < 32; y++)
      for (var x = 0; x < 64; x++) ...[
        [_vertex(x, y), _vertex(x + 1, y), _vertex(x, y + 1)],
        [_vertex(x + 1, y), _vertex(x + 1, y + 1), _vertex(x, y + 1)],
      ],
  ];
  static (Vector3D, Offset) _vertex(int x, int y) {
    final lat = 90 - y * 180 / 32;
    final lon = -180 + x * 360 / 64;
    return (Vector3D.fromDegrees(lat, lon), Offset(x / 64, y / 32));
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
    final key = (context.rotation, camera.center, camera.radius);
    if (_meshKey != key) {
      _meshKey = key;
      final positions = <Offset>[];
      final tex = <Offset>[];
      for (final triangle in _mesh) {
        final a = context.rotation.rotateVector(triangle[0].$1);
        final b = context.rotation.rotateVector(triangle[1].$1);
        final c = context.rotation.rotateVector(triangle[2].$1);
        if (a.z < 0.02 || b.z < 0.02 || c.z < 0.02) continue;
        positions.add(camera.project(a).offset);
        positions.add(camera.project(b).offset);
        positions.add(camera.project(c).offset);
        for (final (_, uv) in triangle) {
          tex.add(Offset(uv.dx * image.width, uv.dy * image.height));
        }
      }
      _vertices = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: tex,
      );
    }
    canvas.drawVertices(
      _vertices!,
      ui.BlendMode.srcOver,
      Paint()..shader = _shader,
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
