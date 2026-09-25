import 'dart:ui';

import 'tooth_geometry.dart';

export 'tooth_geometry.dart'
    show
        ToothType,
        ToothSurface,
        toothTypeOf,
        toothWidthFactor,
        toothHeightFactor,
        maxToothExtent,
        surfaceName;

/// One tooth as the chart draws it: the crown silhouette, the fissures scored
/// across its biting surface, and the five surfaces that crown divides into.
///
/// The shapes themselves are measured in `tooth_geometry.dart`, which knows
/// nothing about Flutter; this is only where they become paths the canvas can
/// draw and hit-test. The exported asset is built from those same shapes, so
/// what is on screen and what is in `assets/images/tooth_map.svg` are one
/// drawing.
class ToothGlyph {
  final Path outline;
  final List<Path> grooves;

  /// The crown's five surfaces, keyed by which one they are. They tile the
  /// crown exactly — no overlap, nothing left between them — so a tap inside
  /// the crown always lands in exactly one of them.
  final Map<ToothSurface, Path> surfaces;

  const ToothGlyph(this.outline, this.grooves, [this.surfaces = const {}]);
}

/// Builds [tooth]'s crown in a box of [w] x [h], seen from above as the
/// reference draws it. The box's top edge (y = 0) is the tooth's outer,
/// cheek-facing side; the chart rotates the box so that edge points out of
/// the arch.
ToothGlyph buildToothGlyph(int tooth, double w, double h) {
  final shape = buildToothShape(tooth, w, h);
  return ToothGlyph(
    pathOf(shape.outline),
    [for (final groove in shape.grooves) pathOf(groove)],
    {for (final entry in shape.surfaces.entries) entry.key: pathOf(entry.value)},
  );
}

/// A measured point as the canvas sees it.
extension PtOffset on Pt {
  Offset get offset => Offset(x, y);
}

/// The canvas path for one measured contour.
Path pathOf(ShapeContour contour) {
  final path = Path()..moveTo(contour.start.x, contour.start.y);
  for (final segment in contour.segments) {
    final control = segment.control;
    if (control == null) {
      path.lineTo(segment.end.x, segment.end.y);
    } else {
      path.quadraticBezierTo(control.x, control.y, segment.end.x, segment.end.y);
    }
  }
  if (contour.closed) path.close();
  return path;
}
