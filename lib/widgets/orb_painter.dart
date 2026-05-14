import 'dart:math';
import 'package:flutter/material.dart';

class OrbStateConfig {
  final Color  color;
  final int    particleCount;
  final double breathSpeed;
  final double breathStrength;
  final double lineMaxDist;
  final double lineMaxAlpha;
  final double radiusScale;
  final double colorVariation;
  const OrbStateConfig({
    required this.color, required this.particleCount,
    required this.breathSpeed, required this.breathStrength,
    required this.lineMaxDist, required this.lineMaxAlpha,
    required this.radiusScale, required this.colorVariation,
  });
}

const Map<String, OrbStateConfig> kOrbStates = {
  'listening': OrbStateConfig(color: Color(0xFF3366FF), particleCount: 400,
    breathSpeed: 0.008, breathStrength: 0.03, lineMaxDist: 0.35,
    lineMaxAlpha: 0.25, radiusScale: 1.0, colorVariation: 0.15),
  'thinking':  OrbStateConfig(color: Color(0xFF33FF66), particleCount: 650,
    breathSpeed: 0.015, breathStrength: 0.05, lineMaxDist: 0.4,
    lineMaxAlpha: 0.35, radiusScale: 1.1, colorVariation: 0.20),
  'speaking':  OrbStateConfig(color: Color(0xFF66CCFF), particleCount: 550,
    breathSpeed: 0.05,  breathStrength: 0.06, lineMaxDist: 0.3,
    lineMaxAlpha: 0.3,  radiusScale: 1.05, colorVariation: 0.12),
  'error':     OrbStateConfig(color: Color(0xFFFF3333), particleCount: 400,
    breathSpeed: 0.025, breathStrength: 0.04, lineMaxDist: 0.3,
    lineMaxAlpha: 0.4,  radiusScale: 1.1, colorVariation: 0.10),
  'sleeping':  OrbStateConfig(color: Color(0xFFEECC33), particleCount: 75,
    breathSpeed: 0.004, breathStrength: 0.08, lineMaxDist: 0.1,
    lineMaxAlpha: 0.1,  radiusScale: 0.5, colorVariation: 0.08),
};

class Particle {
  double x, y, z;
  final double colorOffset;
  Particle(this.x, this.y, this.z, this.colorOffset);

  static Particle random(Random rng) {
    final theta = rng.nextDouble() * 2 * pi;
    final phi   = rng.nextDouble() * pi;
    final r     = 0.2 + rng.nextDouble() * 0.8;
    return Particle(
      r * sin(phi) * cos(theta),
      r * sin(phi) * sin(theta),
      r * cos(phi),
      (rng.nextDouble() - 0.5) * 0.3,
    );
  }

  void rotateY(double cosA, double sinA) {
    final nx =  x * cosA + z * sinA;
    final nz = -x * sinA + z * cosA;
    x = nx; z = nz;
  }
}

class OrbPainter extends CustomPainter {
  final List<Particle>           particles;
  final String                   state;
  final double                   breathPhase;
  final Color                    currentColor;
  final double                   currentRadius;
  final List<(int, int, double)> beams;

  static const double _fov      = 3.5;
  static const double _baseSize = 3.0;

  OrbPainter({
    required this.particles, required this.state,
    required this.breathPhase, required this.currentColor,
    required this.currentRadius, required this.beams,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cfg   = kOrbStates[state] ?? kOrbStates['listening']!;
    final cx    = size.width  / 2;
    final cy    = size.height / 2;
    final scale = size.width  / 2 * 0.85;

    final breath  = sin(breathPhase);
    final display = currentRadius + breath * cfg.breathStrength;

    final projected = <(double, double, double, double)>[];
    for (final p in particles) {
      final sx = p.x * display;
      final sy = p.y * display;
      final sz = p.z * display;
      final perspective = _fov / (_fov + sz);
      final px = cx + sx * scale * perspective;
      final py = cy - sy * scale * perspective;
      final dist = sqrt(sx*sx + sy*sy + sz*sz);
      final ps = _baseSize * (1.0 / (0.5 + dist)) * perspective;
      projected.add((px, py, sz, ps));
    }

    final r = currentColor.red   / 255.0;
    final g = currentColor.green / 255.0;
    final b = currentColor.blue  / 255.0;

    // Draw beams
    final linePaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8;
    for (final (i, j, alpha) in beams) {
      if (i >= projected.length || j >= projected.length) continue;
      final (ax, ay, _, __) = projected[i];
      final (bx, by, _, __2) = projected[j];
      linePaint.color = Color.fromARGB(
        (alpha * 255).clamp(0, 255).toInt(),
        (r * 255).toInt(), (g * 255).toInt(), (b * 255).toInt(),
      );
      canvas.drawLine(Offset(ax, ay), Offset(bx, by), linePaint);
    }

    // Draw particles
    final paint = Paint()..style = PaintingStyle.fill;
    for (int idx = 0; idx < particles.length && idx < projected.length; idx++) {
      final (px, py, _, ps) = projected[idx];
      final v = particles[idx].colorOffset * cfg.colorVariation;
      paint.color = Color.fromARGB(
        220,
        ((r + v) * 255).clamp(0, 255).toInt(),
        ((g + v) * 255).clamp(0, 255).toInt(),
        ((b + v) * 255).clamp(0, 255).toInt(),
      );
      canvas.drawCircle(Offset(px, py), ps.clamp(0.5, 6.0), paint);
    }
  }

  @override
  bool shouldRepaint(OrbPainter old) => true;
}
