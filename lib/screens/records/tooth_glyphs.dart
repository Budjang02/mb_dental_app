import 'dart:math' as math;
import 'dart:ui';

/// The four crown shapes the odontogram draws. Every tooth is one of these,
/// so incisors never come out looking like molars — the reference chart
/// distinguishes them clearly and so does this.
enum ToothType { incisor, canine, premolar, molar }

/// Crown type for a Universal tooth number (#1-32).
ToothType toothTypeOf(int tooth) {
  // Position within the quadrant, counting back from the midline: 1 = central
  // incisor, 3 = canine, 4-5 = premolars, 6-8 = molars.
  final fromMidline = switch (tooth) {
    <= 8 => 9 - tooth, // #8 central -> 1, #1 third molar -> 8
    <= 16 => tooth - 8, // #9 central -> 1, #16 third molar -> 8
    <= 24 => 25 - tooth, // #24 central -> 1, #17 third molar -> 8
    _ => tooth - 24, // #25 central -> 1, #32 third molar -> 8
  };
  if (fromMidline <= 2) return ToothType.incisor;
  if (fromMidline == 3) return ToothType.canine;
  if (fromMidline <= 5) return ToothType.premolar;
  return ToothType.molar;
}

/// Crown width for a Universal tooth number, as a multiple of the chart's
/// cell size. Mandibular front teeth are markedly narrower than maxillary
/// ones, which is what gives a real arch its shape — and the reference's.
double toothWidthFactor(int tooth) {
  final lower = tooth >= 17;
  return switch (tooth) {
    1 || 16 || 17 || 32 => 0.95, // third molars
    2 || 15 || 18 || 31 => 1.00, // second molars
    3 || 14 || 19 || 30 => 1.06, // first molars
    4 || 13 || 20 || 29 => 0.82, // second premolars
    5 || 12 || 21 || 28 => 0.84, // first premolars
    6 || 11 => 0.84, // maxillary canines
    22 || 27 => 0.78, // mandibular canines
    7 || 10 => 0.76, // maxillary laterals
    23 || 26 => 0.70, // mandibular laterals
    8 || 9 => 0.86, // maxillary centrals
    _ => lower ? 0.66 : 0.86, // mandibular centrals
  };
}

/// Crown length, again in cell sizes. Occlusal crowns are close to square,
/// so these stay near the width factors.
double toothHeightFactor(int tooth) {
  return switch (toothTypeOf(tooth)) {
    ToothType.molar => 0.98,
    ToothType.premolar => 0.90,
    ToothType.canine => 1.02,
    ToothType.incisor => 0.92,
  };
}

/// The largest half-extent any tooth reaches, used to inset the arch from the
/// edge of the canvas so no crown is ever clipped.
double get maxToothExtent => 1.06;

/// One tooth as the chart draws it: the crown silhouette plus the fissures
/// scored across its biting surface.
class ToothGlyph {
  final Path outline;
  final List<Path> grooves;

  const ToothGlyph(this.outline, this.grooves);
}

/// Builds [tooth]'s crown in a box of [w] x [h], seen from above as the
/// reference draws it. The box's top edge (y = 0) is the tooth's outer,
/// cheek-facing side; the chart rotates the box so that edge points out of
/// the arch.
ToothGlyph buildToothGlyph(int tooth, double w, double h) {
  Offset p(double x, double y) => Offset(x * w, y * h);
  double s(double v) => v * math.min(w, h);

  switch (toothTypeOf(tooth)) {
    case ToothType.molar:
      // A rounded square with four lobes, the widest crown on the arch.
      return ToothGlyph(
        _roundedPolygon(
          [
            p(0.06, 0.24),
            p(0.25, 0.05),
            p(0.75, 0.05),
            p(0.94, 0.24),
            p(0.95, 0.74),
            p(0.77, 0.95),
            p(0.23, 0.95),
            p(0.05, 0.74),
          ],
          s(0.17),
        ),
        [
          // The occlusal cross: a central fissure with a branch to each cusp.
          _polyline([p(0.50, 0.11), p(0.50, 0.90)]),
          _polyline([p(0.13, 0.35), p(0.50, 0.49)]),
          _polyline([p(0.87, 0.35), p(0.50, 0.49)]),
        ],
      );

    case ToothType.premolar:
      // Smaller and rounder than a molar, with a single groove between its
      // two cusps.
      return ToothGlyph(
        _roundedPolygon(
          [
            p(0.07, 0.27),
            p(0.29, 0.06),
            p(0.71, 0.06),
            p(0.93, 0.27),
            p(0.94, 0.71),
            p(0.73, 0.94),
            p(0.27, 0.94),
            p(0.06, 0.71),
          ],
          s(0.21),
        ),
        [
          _curve(p(0.18, 0.48), p(0.50, 0.40), p(0.82, 0.48)),
          _polyline([p(0.50, 0.44), p(0.50, 0.76)]),
        ],
      );

    case ToothType.canine:
      // Tapers to a cusp on its outer edge — the sharpest crown on the arch.
      return ToothGlyph(
        _roundedPolygon(
          [
            p(0.50, 0.00),
            p(0.88, 0.26),
            p(0.95, 0.68),
            p(0.71, 0.97),
            p(0.29, 0.97),
            p(0.05, 0.68),
            p(0.12, 0.26),
          ],
          s(0.08),
        ),
        [
          _polyline([p(0.50, 0.17), p(0.50, 0.56)]),
          _polyline([p(0.50, 0.40), p(0.29, 0.34)]),
          _polyline([p(0.50, 0.40), p(0.71, 0.34)]),
        ],
      );

    case ToothType.incisor:
      // A soft rounded wedge, scored once just inside its biting edge.
      return ToothGlyph(
        _roundedPolygon(
          [
            p(0.50, 0.03),
            p(0.86, 0.23),
            p(0.94, 0.66),
            p(0.73, 0.96),
            p(0.27, 0.96),
            p(0.06, 0.66),
            p(0.14, 0.23),
          ],
          s(0.10),
        ),
        [
          _curve(p(0.20, 0.31), p(0.50, 0.14), p(0.80, 0.31)),
        ],
      );
  }
}

/// A closed polygon with every corner rounded off, which is how all four
/// crown shapes are built: straight-edged outlines read as machine parts,
/// and real crowns have no corners.
Path _roundedPolygon(List<Offset> vertices, double radius) {
  final path = Path();
  for (var i = 0; i < vertices.length; i++) {
    final current = vertices[i];
    final previous = vertices[(i - 1 + vertices.length) % vertices.length];
    final next = vertices[(i + 1) % vertices.length];

    final toPrevious = previous - current;
    final toNext = next - current;
    // Never round away more than half an edge, or neighbouring corners eat
    // into each other and the outline folds over itself.
    final start = current + toPrevious * (math.min(radius, toPrevious.distance / 2) / toPrevious.distance);
    final end = current + toNext * (math.min(radius, toNext.distance / 2) / toNext.distance);

    if (i == 0) {
      path.moveTo(start.dx, start.dy);
    } else {
      path.lineTo(start.dx, start.dy);
    }
    path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
  }
  path.close();
  return path;
}

Path _polyline(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  return path;
}

Path _curve(Offset from, Offset control, Offset to) {
  return Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
}
