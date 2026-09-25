import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tooth_geometry.dart';
import 'tooth_glyphs.dart';

/// A tap on one surface of one crown, reported the way a chart row records it:
/// the Universal tooth number, and the clinical surface name for that tooth
/// ('occlusal' or 'incisal', 'mesial', 'distal', 'buccal' or 'facial',
/// 'lingual'). The name is [surfaceName]'s, so what a tap reports and what a
/// path in `assets/images/tooth_map.svg` is called are the same string.
typedef ToothSurfaceTap = void Function(int toothNumber, String surfaceId);

/// Widest the chart is allowed to get. Past this the arch stops reading as a
/// mouth and starts reading as wallpaper, so on tablets and desktop it centres
/// at this width instead of stretching.
const double kDentalArchMaxWidth = 420;

/// The horseshoe odontogram: both dental arches laid out as they are in
/// `assets/reference_ui/ui_teeth.png`, every tooth drawn and hit-tested on its
/// own. The same measurements build the exported vector asset
/// `assets/images/tooth_map.svg`, so the two never drift apart.
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

  /// The tooth numbers printed outside the arch.
  final Color labelColor;

  /// Outline per tooth number, from the same condition as [conditionColors].
  /// A tooth absent here is outlined in [idleStroke], or [outlineColor].
  final Map<int, Color> conditionStrokes;

  /// Outline for a tooth with nothing recorded against it.
  final Color? idleStroke;

  /// The darker shade of each tooth's colour, drawn toward the crown's rim so
  /// the lighter biting area stands out from it — the chart's top-down take
  /// on a light crown over a darker root. A tooth absent here falls back to
  /// [idleRoot], then to a flat fill.
  final Map<int, Color> rootColors;
  final Color? idleRoot;

  /// Teeth outlined with a dashed line ([kToothDashPattern]) rather than a
  /// solid one.
  final Set<int> dashedTeeth;

  /// Fill per surface, as `{toothNumber: {surfaceId: colour}}`, with the
  /// surface ids [ToothSurfaceTap] reports. A surface listed here is painted
  /// over its crown's own fill, so one tooth can carry caries on its mesial
  /// and a restoration on its occlusal at once. Anything not listed keeps the
  /// crown's colour.
  final Map<int, Map<String, Color>> surfaceColors;

  /// Called with the surface under the tap, when the caller records conditions
  /// against single surfaces. [onSelect] still fires with the tooth either
  /// way, so whole-tooth selection keeps working underneath.
  final ToothSurfaceTap? onSurfaceSelect;

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
    this.conditionStrokes = const {},
    this.idleStroke,
    this.rootColors = const {},
    this.idleRoot,
    this.dashedTeeth = const {},
    this.surfaceColors = const {},
    this.onSurfaceSelect,
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
          aspectRatio: kChartAspect,
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
                    if (tooth == null) return;
                    widget.onSelect(tooth);
                    final onSurface = widget.onSurfaceSelect;
                    if (onSurface == null) return;
                    final surface = layout.surfaceNearest(tooth, details.localPosition);
                    onSurface(tooth, surfaceName(tooth, surface));
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
                        conditionStrokes: widget.conditionStrokes,
                        idleStroke: widget.idleStroke,
                        rootColors: widget.rootColors,
                        idleRoot: widget.idleRoot,
                        dashedTeeth: widget.dashedTeeth,
                        surfaceColors: widget.surfaceColors,
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

/// The measured arch for one canvas size: where every crown sits, how big it
/// is and which way it faces.
///
/// The measuring itself lives in [ArchGeometry], which has no Flutter behind
/// it; this wraps it in the `dart:ui` types the painter and the hit test want.
class DentalArchLayout {
  final Size size;
  final ArchGeometry geometry;

  const DentalArchLayout({required this.size, required this.geometry});

  static DentalArchLayout build(Size size) {
    return DentalArchLayout(
      size: size,
      geometry: ArchGeometry.build(size.width, size.height),
    );
  }

  double get cell => geometry.cell;

  Map<int, ToothPlacement> get placements => geometry.placements;

  /// Font size for the tooth numbers at this canvas size.
  double get numberFontSize => geometry.numberFontSize;

  /// Where a tooth's number is centred: straight out of the arch from the
  /// crown, clear of it by the reference's gap plus half the text's own
  /// extent.
  Offset numberCenterFor(int tooth, double textExtent) {
    final centre = geometry.numberCenterFor(tooth, textExtent);
    return Offset(centre.x, centre.y);
  }

  Matrix4 transformFor(int tooth, {double scale = 1}) {
    final placement = placements[tooth]!;
    return Matrix4.identity()
      ..translate(placement.center.x, placement.center.y)
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
      final centre = entry.value.center;
      final distance = (Offset(centre.x, centre.y) - point).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    return nearestDistance <= cell * 0.62 ? nearest : null;
  }

  /// Which surface of [tooth] [point] falls on, or null when it falls outside
  /// the crown altogether. The whole-tooth hit test above is what selection
  /// runs on; this is the finer one, for callers that record a condition
  /// against a single surface rather than a whole tooth.
  ToothSurface? surfaceAt(int tooth, Offset point) {
    if (!placements.containsKey(tooth)) return null;
    final transform = transformFor(tooth).storage;
    for (final entry in glyphFor(tooth).surfaces.entries) {
      if (entry.value.transform(transform).contains(point)) return entry.key;
    }
    return null;
  }

  /// The surface a tap on [tooth] belongs to, never null.
  ///
  /// [toothAt] already answers with a crown for a tap that landed in the
  /// hairline beside one, so the surface hit test has to answer for those taps
  /// too: it falls back to whichever surface of that crown the tap is nearest.
  ToothSurface surfaceNearest(int tooth, Offset point) {
    final inside = surfaceAt(tooth, point);
    if (inside != null) return inside;

    final transform = transformFor(tooth).storage;
    var nearest = ToothSurface.centre;
    var nearestDistance = double.infinity;
    for (final entry in glyphFor(tooth).surfaces.entries) {
      final centre = entry.value.transform(transform).getBounds().center;
      final distance = (centre - point).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    return nearest;
  }
}

// --- Painting -------------------------------------------------------------

/// The website's `stroke-dasharray: 3 2`: a 3px dash, then a 2px gap.
const List<double> kToothDashPattern = [3, 2];

/// [source] cut into dashes of [pattern] (dash, gap, dash, gap, ...), for a
/// dashed outline Canvas cannot draw natively.
Path dashedPath(Path source, List<double> pattern) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    while (distance < metric.length) {
      final length = pattern[index % pattern.length];
      if (index.isEven) {
        dashed.addPath(
          metric.extractPath(distance, math.min(distance + length, metric.length)),
          Offset.zero,
        );
      }
      distance += length;
      index++;
    }
  }
  return dashed;
}

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
  final Map<int, Color> conditionStrokes;
  final Color? idleStroke;
  final Map<int, Color> rootColors;
  final Color? idleRoot;
  final Set<int> dashedTeeth;
  final Map<int, Map<String, Color>> surfaceColors;

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
    required this.conditionStrokes,
    required this.idleStroke,
    required this.rootColors,
    required this.idleRoot,
    required this.dashedTeeth,
    required this.surfaceColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // The picked tooth goes last so its ring is never clipped by a neighbour
    // that happens to be drawn after it.
    for (final tooth in [...kUpperArchTeeth, ...kLowerArchTeeth]) {
      if (tooth != selectedTooth) _paintTooth(canvas, tooth);
    }
    final selected = selectedTooth;
    if (selected != null && layout.placements.containsKey(selected)) {
      _paintTooth(canvas, selected);
    }

    // Numbers last, so a crown scaled up by selection never rides over one.
    for (final tooth in [...kUpperArchTeeth, ...kLowerArchTeeth]) {
      _paintToothNumber(canvas, tooth);
    }
  }

  /// The Universal number, sitting just outside its crown along the arch's
  /// outward normal — the placement the reference chart uses.
  void _paintToothNumber(Canvas canvas, int tooth) {
    if (!layout.placements.containsKey(tooth)) return;

    final selected = tooth == selectedTooth;
    final painter = TextPainter(
      text: TextSpan(
        text: '$tooth',
        style: TextStyle(
          color: selected ? selectedOutline : labelColor,
          fontSize: layout.numberFontSize,
          // The picked tooth's number is bolder, so the number and the ring
          // agree about which tooth is being talked about.
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final center =
        layout.numberCenterFor(tooth, math.max(painter.width, painter.height));
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  void _paintTooth(Canvas canvas, int tooth) {
    final selected = tooth == selectedTooth;
    final hovered = tooth == hoveredTooth && !selected;
    final condition = conditionColors[tooth];
    final strokeWidth = math.max(1.0, layout.cell * kToothStrokeUnits);

    // A tooth carrying a condition keeps that colour whether or not it is
    // picked — selection is called out by the ring instead, so no clinical
    // state is ever painted over.
    final fill = condition ?? (selected ? selectedFill : idleFill);

    canvas.save();
    canvas.transform(layout.transformFor(tooth, scale: selected ? selectionScale : 1).storage);

    final glyph = layout.glyphFor(tooth);
    final root = condition != null ? rootColors[tooth] : (selected ? null : idleRoot);
    final fillPaint = Paint()..color = fill;
    if (root != null) {
      // Lighter at the centre of the crown, deepening to the root shade at
      // its rim, in one colour family.
      final bounds = glyph.outline.getBounds();
      fillPaint.shader = RadialGradient(
        colors: [fill, fill, root],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromCircle(
        center: bounds.center,
        radius: math.max(bounds.width, bounds.height) / 2,
      ));
    }
    canvas.drawPath(glyph.outline, fillPaint);

    // Surface conditions sit on top of the crown's own colour: the five
    // regions tile the crown exactly, so a surface fill covers its own ground
    // and nothing else. Painted before the outline and the fissures, which
    // then read over the top of it.
    final surfaces = surfaceColors[tooth];
    if (surfaces != null && surfaces.isNotEmpty) {
      for (final entry in glyph.surfaces.entries) {
        final color = surfaces[surfaceName(tooth, entry.key)];
        if (color == null) continue;
        canvas.drawPath(entry.value, Paint()..color = color);
      }
    }

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

    // The condition's own outline colour, as the website draws it; the picked
    // tooth takes the selection colour on top of its halo instead.
    final stroke = selected ? selectedOutline : (conditionStrokes[tooth] ?? idleStroke ?? outlineColor);
    final dashed = dashedTeeth.contains(tooth);
    canvas.drawPath(
      dashed ? dashedPath(glyph.outline, kToothDashPattern) : glyph.outline,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? strokeWidth * 1.9 : strokeWidth
        ..strokeJoin = StrokeJoin.round
        // Round caps would lengthen every dash past its 3px.
        ..strokeCap = dashed ? StrokeCap.butt : StrokeCap.round,
    );

    final groovePaint = Paint()
      ..color = stroke.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * kGrooveStrokeFraction
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final groove in glyph.grooves) {
      canvas.drawPath(groove, groovePaint);
    }

    canvas.restore();
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
        old.idleStroke != idleStroke ||
        old.idleRoot != idleRoot ||
        !mapEquals(old.rootColors, rootColors) ||
        !mapEquals(old.conditionColors, conditionColors) ||
        !_sameSurfaceColors(old.surfaceColors, surfaceColors) ||
        !mapEquals(old.conditionStrokes, conditionStrokes) ||
        !setEquals(old.dashedTeeth, dashedTeeth);
  }

  /// [mapEquals] compares the inner maps by identity, which would miss a
  /// surface whose colour changed inside a map the caller rebuilt.
  static bool _sameSurfaceColors(
    Map<int, Map<String, Color>> a,
    Map<int, Map<String, Color>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!mapEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
}
