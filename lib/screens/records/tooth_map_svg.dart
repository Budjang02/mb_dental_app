import 'dart:math' as math;

import 'tooth_geometry.dart';

/// The odontogram as a standalone vector template.
///
/// The drawing is the app's own: every crown, fissure and surface boundary
/// comes out of [ArchGeometry], the same measurements the chart on screen is
/// painted and hit-tested from. That is what keeps the asset and the app in
/// agreement — `tooth-14` is the same crown in both, and `tooth-14-mesial`
/// covers the same ground.
///
/// The template carries no condition colours, no selection fill and no text,
/// so it is a base to colour rather than a snapshot of one patient's chart.
/// `tool/generate_tooth_map_svg.dart` writes it to
/// `assets/images/tooth_map.svg`; `test/tooth_surface_test.dart` fails if that
/// file and this drawing ever drift apart.

/// Canvas width for the exported asset, in SVG user units. The chart's own
/// aspect keeps the arches in the proportions the reference has; being vector,
/// the file is sharp at any size, and 1200 keeps the numbers readable.
const double kToothMapWidth = 1200;
final double kToothMapHeight = (kToothMapWidth / kChartAspect).roundToDouble();

const String _outline = '#000000';
const String _crownFill = '#FFFFFF';
const String _background = '#FFFFFF';

/// The whole asset, as SVG text.
String buildToothMapSvg({double width = kToothMapWidth, double? height}) {
  final canvasHeight = height ?? (width / kChartAspect).roundToDouble();
  return _svg(ArchGeometry.build(width, canvasHeight), width, canvasHeight);
}

String _svg(ArchGeometry geometry, double width, double height) {
  // The same widths the painter strokes with, so the asset and the live chart
  // have the same weight of line at the same size.
  final stroke = math.max(1.0, geometry.cell * kToothStrokeUnits);
  final grooveStroke = stroke * kGrooveStrokeFraction;

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 ${_number(width)} ${_number(height)}" '
        'width="${_number(width)}" height="${_number(height)}">')
    ..writeln('  <title>Occlusal tooth map — Universal numbering 1-32</title>')
    ..writeln('  <desc>Base template: 32 crowns seen from above, upper arch #1-16 '
        'and lower arch #17-32. Each tooth is a group id="tooth-N"; each surface '
        'inside it is a path id="tooth-N-surface" covering that surface exactly.</desc>')
    ..writeln('  <rect id="background" x="0" y="0" width="${_number(width)}" '
        'height="${_number(height)}" fill="$_background"/>');

  for (final (name, arch) in [('upper', kUpperArchTeeth), ('lower', kLowerArchTeeth)]) {
    buffer.writeln('  <g id="$name-arch" data-arch="$name">');
    for (final tooth in arch) {
      _writeTooth(buffer, geometry, tooth, name, stroke, grooveStroke);
    }
    buffer.writeln('  </g>');
  }

  buffer.writeln('</svg>');
  return buffer.toString();
}

void _writeTooth(
  StringBuffer buffer,
  ArchGeometry geometry,
  int tooth,
  String arch,
  double stroke,
  double grooveStroke,
) {
  final shape = geometry.shapeFor(tooth);
  String d(ShapeContour contour) => _pathData(geometry, tooth, contour);

  buffer
    ..writeln('    <g id="tooth-$tooth" data-tooth="$tooth" data-arch="$arch" '
        'data-type="${toothTypeOf(tooth).name}">')
    ..writeln('      <path class="crown" id="tooth-$tooth-crown" d="${d(shape.outline)}" '
        'fill="$_crownFill" stroke="$_outline" stroke-width="${_number(stroke)}" '
        'stroke-linejoin="round" stroke-linecap="round"/>')
    ..writeln('      <g class="grooves" fill="none" stroke="$_outline" '
        'stroke-width="${_number(grooveStroke)}" stroke-linecap="round" stroke-linejoin="round">');
  for (var i = 0; i < shape.grooves.length; i++) {
    buffer.writeln('        <path id="tooth-$tooth-groove-${i + 1}" d="${d(shape.grooves[i])}"/>');
  }
  buffer.writeln('      </g>');

  // Surfaces are drawn invisibly: they carry the boundaries an interactive
  // chart selects on, and the template is meant to look like the reference —
  // an outline and its fissures, nothing else. Give one a fill and it shows.
  buffer.writeln('      <g class="surfaces" fill="none" stroke="none" pointer-events="all">');
  for (final surface in ToothSurface.values) {
    final contour = shape.surfaces[surface];
    if (contour == null) continue;
    final name = surfaceName(tooth, surface);
    buffer.writeln('        <path id="tooth-$tooth-$name" data-tooth="$tooth" '
        'data-surface="$name" d="${d(contour)}"/>');
  }
  buffer
    ..writeln('      </g>')
    ..writeln('    </g>');
}

/// One contour as SVG path data, in chart coordinates: the crown's own box is
/// rotated onto the arch exactly as the painter rotates it, so a path here
/// covers the same pixels the app hit-tests.
String _pathData(ArchGeometry geometry, int tooth, ShapeContour contour) {
  Pt at(Pt point) => geometry.toChart(tooth, point);

  final start = at(contour.start);
  final buffer = StringBuffer('M ${_number(start.x)} ${_number(start.y)}');
  for (final segment in contour.segments) {
    final end = at(segment.end);
    final control = segment.control;
    if (control == null) {
      buffer.write(' L ${_number(end.x)} ${_number(end.y)}');
    } else {
      final c = at(control);
      buffer.write(' Q ${_number(c.x)} ${_number(c.y)} ${_number(end.x)} ${_number(end.y)}');
    }
  }
  if (contour.closed) buffer.write(' Z');
  return buffer.toString();
}

/// Two decimals is finer than a thousandth of the canvas — past that the file
/// only grows.
String _number(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}
