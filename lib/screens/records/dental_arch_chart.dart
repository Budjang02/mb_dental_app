import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tooth_glyphs.dart';

/// Universal numbers in the order they sit along each arch, read left to right
/// across the chart. The patient faces the viewer, so the patient's right is
/// the viewer's left: #1 (upper right third molar) opens the upper arch on the
/// left, and #32 (lower right third molar) closes the lower arch on that same
/// side.
const List<int> kUpperArchTeeth = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
const List<int> kLowerArchTeeth = [17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32];

/// Width over height of the chart, taken off the reference drawing: there each
/// arch measures 545x405 and the pair together spans 545x840.
const double _chartAspect = 0.632;

/// Widest the chart is allowed to get. Past this the arch stops reading as a
/// mouth and starts reading as wallpaper, so on tablets and desktop it centres
/// at this width instead of stretching.
const double kDentalArchMaxWidth = 420;

/// Slack between neighbouring crowns and at the ends of each arch, in cells.
/// Crowns sit flush against each other the way they do in the reference and in
/// a real mouth, so there is nothing between them but their two outlines.
const double _gapUnits = 0.0;
const double _padUnits = 0.08;

/// Share of the chart's height left empty between the two arches — the wide
/// separation the reference has.
const double _archGapFraction = 0.065;

/// The horseshoe odontogram: both dental arches laid out as they are in
/// `assets/reference_ui/teeth_ui.png`, every tooth drawn and hit-tested on its
/// own.
///
/// The chart renders whatever the caller passes it and reports taps back — it
/// holds no state of its own, so the screen's existing selection and condition
/// logic keeps running unchanged underneath it.
class DentalArchChart extends StatefulWidget {
  /// Fill per Universal tooth number, straight from the app's condition map.
  /// A tooth that is absent has nothing recorded and is drawn in [idleFill].
  final Map<int, Color> conditionColors;

  /// The tooth currently picked out, or null when none is. Nothing is
  /// selected until the user taps a crown.
  final int? selectedTooth;
  final ValueChanged<int> onSelect;

  /// Fill for a tooth with nothing recorded against it.
  final Color idleFill;

  /// Outline and fissures. Crowns are always light, so this stays dark in
  /// both themes — that is what keeps them crisp on either card.
  final Color outlineColor;

  /// Fill for the selected tooth when it has no condition of its own, and the
  /// ring drawn around it either way.
  final Color selectedFill;
  final Color selectedOutline;

  /// "Up Teeth" / "Down Teeth", centred inside each arch.
  final Color labelColor;

  const DentalArchChart({
    super.key,
    required this.conditionColors,
    required this.selectedTooth,
    required this.onSelect,
    required this.idleFill,
    required this.outlineColor,
    required this.selectedFill,
    required this.selectedOutline,
    required this.labelColor,
  });

  @override
  State<DentalArchChart> createState() => _DentalArchChartState();
}

class _DentalArchChartState extends State<DentalArchChart> {
  DentalArchLayout? _layout;
  int? _hoveredTooth;

  DentalArchLayout _layoutFor(Size size) {
    final cached = _layout;
    if (cached != null && cached.size == size) return cached;
    return _layout = DentalArchLayout.build(size);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kDentalArchMaxWidth),
        child: AspectRatio(
          aspectRatio: _chartAspect,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _layoutFor(Size(constraints.maxWidth, constraints.maxHeight));
              return MouseRegion(
                cursor: _hoveredTooth == null ? MouseCursor.defer : SystemMouseCursors.click,
                onHover: (event) {
                  final tooth = layout.toothAt(event.localPosition);
                  if (tooth != _hoveredTooth) setState(() => _hoveredTooth = tooth);
                },
                onExit: (_) => setState(() => _hoveredTooth = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final tooth = layout.toothAt(details.localPosition);
                    if (tooth != null) widget.onSelect(tooth);
                  },
                  // A short lift on the tooth that was just picked: enough
                  // feedback to confirm the tap, not enough to be a flourish.
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(widget.selectedTooth),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutBack,
                    builder: (context, t, _) => CustomPaint(
                      size: layout.size,
                      painter: _ArchPainter(
                        layout: layout,
                        conditionColors: widget.conditionColors,
                        selectedTooth: widget.selectedTooth,
                        hoveredTooth: _hoveredTooth,
                        selectionScale: 1 + 0.07 * t,
                        idleFill: widget.idleFill,
                        outlineColor: widget.outlineColor,
                        selectedFill: widget.selectedFill,
                        selectedOutline: widget.selectedOutline,
                        labelColor: widget.labelColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- Geometry -------------------------------------------------------------

/// Half an ellipse, sampled so crowns can be spaced along it by arc length
/// rather than by angle: even angular steps would crowd the molars at the back
/// and stretch the incisors across the front.
class _EllipseArc {
  final double cx, cy, a, b;

  /// True for the maxillary arch, which sweeps over the top of its centre.
  final bool upper;

  final List<double> _u = <double>[];
  final List<double> _s = <double>[];

  _EllipseArc(this.cx, this.cy, this.a, this.b, this.upper) {
    const samples = 360;
    var previous = pointAt(0);
    _u.add(0);
    _s.add(0);
    var travelled = 0.0;
    for (var i = 1; i <= samples; i++) {
      final u = i / samples;
      final point = pointAt(u);
      travelled += (point - previous).distance;
      previous = point;
      _u.add(u);
      _s.add(travelled);
    }
  }

  double get length => _s.last;

  /// `u` runs 0 to 1 left to right along the upper arch and right to left
  /// along the lower one — the order the Universal numbers run in.
  double _phi(double u) => upper ? math.pi * (1 - u) : math.pi * u;

  Offset pointAt(double u) {
    final phi = _phi(u);
    final dy = b * math.sin(phi);
    return Offset(cx + a * math.cos(phi), upper ? cy - dy : cy + dy);
  }

  /// Turns a crown so the outer, cheek-facing edge of its cell points straight
  /// out of the arch — the orientation every tooth has in the reference.
  double angleAt(double u) {
    final phi = _phi(u);
    // Inward normal: the cell's top edge faces out, so its foot faces in.
    final nx = -b * math.cos(phi);
    final ny = (upper ? 1 : -1) * a * math.sin(phi);
    final length = math.sqrt(nx * nx + ny * ny);
    if (length == 0) return 0;
    return math.atan2(-nx / length, ny / length);
  }

  double uAtDistance(double s) {
    if (s <= 0) return 0;
    if (s >= length) return 1;
    var lo = 0;
    var hi = _s.length - 1;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_s[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _s[hi] - _s[lo];
    final t = span == 0 ? 0.0 : (s - _s[lo]) / span;
    return _u[lo] + (_u[hi] - _u[lo]) * t;
  }
}

/// Where one tooth ends up on the chart.
class ToothPlacement {
  final Offset center;
  final double angle;
  final double width;
  final double height;

  const ToothPlacement(this.center, this.angle, this.width, this.height);
}

/// The measured arch: where every crown sits, how big it is and which way it
/// faces, for one canvas size.
class DentalArchLayout {
  final Size size;
  final double cell;
  final Map<int, ToothPlacement> placements;
  final Offset upperLabel;
  final Offset lowerLabel;

  const DentalArchLayout({
    required this.size,
    required this.cell,
    required this.placements,
    required this.upperLabel,
    required this.lowerLabel,
  });

  static DentalArchLayout build(Size size) {
    final archH = size.height * (1 - _archGapFraction) / 2;
    final centerX = size.width / 2;

    double demandOf(List<int> arch) =>
        arch.fold<double>(0, (total, n) => total + toothWidthFactor(n)) +
        (arch.length - 1) * _gapUnits +
        2 * _padUnits;

    // Both arches ride the same ellipse, so the fuller of the two sets the
    // crown size and the other splits its slack between its ends. That keeps
    // upper and lower teeth drawn to one scale, as the reference has them.
    final demand = math.max(demandOf(kUpperArchTeeth), demandOf(kLowerArchTeeth));

    // Crown size decides how far the ellipse must sit in from the canvas edge
    // — a tooth reaches half its own extent past the arc — and that inset in
    // turn decides how much arc there is to fill. A few passes settle it.
    var cell = size.width * 0.11;
    var a = 0.0;
    var b = 0.0;
    for (var pass = 0; pass < 16; pass++) {
      final inset = cell * maxToothExtent / 2;
      a = centerX - inset;
      b = archH - inset;
      if (a <= 2 || b <= 2) break;
      cell = (cell + _halfEllipsePerimeter(a, b) / demand) / 2;
    }

    final upperArc = _EllipseArc(centerX, archH, a, b, true);
    final lowerArc = _EllipseArc(centerX, size.height - archH, a, b, false);

    final placements = <int, ToothPlacement>{};
    void layOut(List<int> arch, _EllipseArc arc) {
      final used = arch.fold<double>(0, (total, n) => total + toothWidthFactor(n) * cell) +
          (arch.length - 1) * _gapUnits * cell;
      var cursor = math.max(0.0, (arc.length - used) / 2);
      for (final n in arch) {
        final width = toothWidthFactor(n) * cell;
        cursor += width / 2;
        final u = arc.uAtDistance(cursor);
        placements[n] = ToothPlacement(
          arc.pointAt(u),
          arc.angleAt(u),
          width,
          toothHeightFactor(n) * cell,
        );
        cursor += width / 2 + _gapUnits * cell;
      }
    }

    layOut(kUpperArchTeeth, upperArc);
    layOut(kLowerArchTeeth, lowerArc);

    return DentalArchLayout(
      size: size,
      cell: cell,
      placements: placements,
      // Seated low inside the upper horseshoe and high inside the lower one,
      // where the reference puts its two labels.
      upperLabel: Offset(centerX, archH - b * 0.30),
      lowerLabel: Offset(centerX, size.height - archH + b * 0.32),
    );
  }

  /// Ramanujan's approximation, halved. Accurate to a fraction of a pixel at
  /// these eccentricities and far cheaper than sampling inside the fit loop.
  static double _halfEllipsePerimeter(double a, double b) {
    final h = math.pow((a - b) / (a + b), 2).toDouble();
    return math.pi * (a + b) * (1 + 3 * h / (10 + math.sqrt(4 - 3 * h))) / 2;
  }

  Matrix4 transformFor(int tooth, {double scale = 1}) {
    final placement = placements[tooth]!;
    return Matrix4.identity()
      ..translate(placement.center.dx, placement.center.dy)
      ..rotateZ(placement.angle)
      ..scale(scale, scale)
      ..translate(-placement.width / 2, -placement.height / 2);
  }

  ToothGlyph glyphFor(int tooth) {
    final placement = placements[tooth]!;
    return buildToothGlyph(tooth, placement.width, placement.height);
  }

  /// The tooth under [point]: the one whose crown actually contains it, or
  /// failing that the nearest crown within about half a cell — so a tap landing
  /// in the hairline between two teeth still picks one rather than nothing.
  int? toothAt(Offset point) {
    int? nearest;
    var nearestDistance = double.infinity;
    for (final entry in placements.entries) {
      final path = glyphFor(entry.key).outline.transform(transformFor(entry.key).storage);
      if (path.contains(point)) return entry.key;
      final distance = (entry.value.center - point).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    return nearestDistance <= cell * 0.62 ? nearest : null;
  }
}

// --- Painting -------------------------------------------------------------

class _ArchPainter extends CustomPainter {
  final DentalArchLayout layout;
  final Map<int, Color> conditionColors;
  final int? selectedTooth;
  final int? hoveredTooth;
  final double selectionScale;
  final Color idleFill;
  final Color outlineColor;
  final Color selectedFill;
  final Color selectedOutline;
  final Color labelColor;

  const _ArchPainter({
    required this.layout,
    required this.conditionColors,
    required this.selectedTooth,
    required this.hoveredTooth,
    required this.selectionScale,
    required this.idleFill,
    required this.outlineColor,
    required this.selectedFill,
    required this.selectedOutline,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintLabel(canvas, 'Up Teeth', layout.upperLabel);
    _paintLabel(canvas, 'Down Teeth', layout.lowerLabel);

    // The picked tooth goes last so its ring is never clipped by a neighbour
    // that happens to be drawn after it.
    for (final tooth in [...kUpperArchTeeth, ...kLowerArchTeeth]) {
      if (tooth != selectedTooth) _paintTooth(canvas, tooth);
    }
    final selected = selectedTooth;
    if (selected != null && layout.placements.containsKey(selected)) {
      _paintTooth(canvas, selected);
    }
  }

  void _paintTooth(Canvas canvas, int tooth) {
    final selected = tooth == selectedTooth;
    final hovered = tooth == hoveredTooth && !selected;
    final condition = conditionColors[tooth];
    final strokeWidth = math.max(1.0, layout.cell * 0.042);

    // A tooth carrying a condition keeps that colour whether or not it is
    // picked — selection is called out by the ring instead, so no clinical
    // state is ever painted over.
    final fill = condition ?? (selected ? selectedFill : idleFill);

    canvas.save();
    canvas.transform(layout.transformFor(tooth, scale: selected ? selectionScale : 1).storage);

    final glyph = layout.glyphFor(tooth);
    canvas.drawPath(glyph.outline, Paint()..color = fill);

    if (hovered) {
      canvas.drawPath(glyph.outline, Paint()..color = outlineColor.withOpacity(0.10));
    }

    if (selected) {
      canvas.drawPath(
        glyph.outline,
        Paint()
          ..color = selectedOutline.withOpacity(0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 5
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      glyph.outline,
      Paint()
        ..color = selected ? selectedOutline : outlineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? strokeWidth * 1.9 : strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final groovePaint = Paint()
      ..color = (selected ? selectedOutline : outlineColor).withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final groove in glyph.grooves) {
      canvas.drawPath(groove, groovePaint);
    }

    canvas.restore();
  }

  void _paintLabel(Canvas canvas, String text, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: labelColor,
          fontSize: math.max(12.0, layout.cell * 0.44),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ArchPainter old) {
    return old.layout != layout ||
        old.selectedTooth != selectedTooth ||
        old.hoveredTooth != hoveredTooth ||
        old.selectionScale != selectionScale ||
        old.idleFill != idleFill ||
        old.outlineColor != outlineColor ||
        old.selectedFill != selectedFill ||
        old.selectedOutline != selectedOutline ||
        old.labelColor != labelColor ||
        !mapEquals(old.conditionColors, conditionColors);
  }
}
