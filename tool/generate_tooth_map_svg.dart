// Writes `assets/images/tooth_map.svg`: the odontogram as a clean vector
// template, drawn from the very measurements the on-screen chart is painted
// from (`lib/screens/records/tooth_geometry.dart`).
//
//   dart run tool/generate_tooth_map_svg.dart [path]
//
// The asset carries no colour coding, no selection fills and no text, so it is
// a base template rather than a snapshot of one patient's chart. What it does
// carry is the numbering and the boundaries: `tooth-1` .. `tooth-32` in
// Universal order, and inside each, one path per surface
// (`tooth-3-occlusal`, `tooth-3-mesial`, ...). Those ids and those boundaries
// are computed the same way the app computes its hit targets, so anything
// keyed on a tooth number — event listeners, condition rows, database ids —
// keeps working against either the asset or the live chart, unchanged.

import 'dart:io';

import 'package:mb_dental_app/screens/records/tooth_geometry.dart';
import 'package:mb_dental_app/screens/records/tooth_map_svg.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'assets/images/tooth_map.svg';
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(buildToothMapSvg());

  final geometry = ArchGeometry.build(kToothMapWidth, kToothMapHeight);
  final surfaces = geometry.placements.keys
      .map((tooth) => geometry.shapeFor(tooth).surfaces.length)
      .fold<int>(0, (total, count) => total + count);
  stdout.writeln('Wrote $path — ${geometry.placements.length} teeth, $surfaces surfaces, '
      '${kToothMapWidth.toStringAsFixed(0)}x${kToothMapHeight.toStringAsFixed(0)}.');
}
