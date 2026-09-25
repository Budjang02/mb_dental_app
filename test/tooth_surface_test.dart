import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/records/dental_arch_chart.dart';
import 'package:mb_dental_app/screens/records/tooth_geometry.dart';
import 'package:mb_dental_app/screens/records/tooth_glyphs.dart';
import 'package:mb_dental_app/screens/records/tooth_map_svg.dart';

Size _canvasFor(double width) => Size(width, width / kChartAspect);

/// Points spread over a tooth's box, used to check the five surfaces cover the
/// crown between them without overlapping.
List<Offset> _probes(double w, double h) => [
      for (var i = 1; i < 10; i++)
        for (var j = 1; j < 10; j++) Offset(w * i / 10, h * j / 10),
    ];

/// True when the polygon through [points] crosses itself — which a surface
/// must never do: a bow tie hit-tests as two lobes with a hole between them
/// and paints over its neighbours.
bool _selfIntersects(List<Pt> points) {
  bool crosses(Pt a, Pt b, Pt c, Pt d) {
    double side(Pt p, Pt q, Pt r) =>
        (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    final d1 = side(a, b, c);
    final d2 = side(a, b, d);
    final d3 = side(c, d, a);
    final d4 = side(c, d, b);
    return ((d1 > 1e-9 && d2 < -1e-9) || (d1 < -1e-9 && d2 > 1e-9)) &&
        ((d3 > 1e-9 && d4 < -1e-9) || (d3 < -1e-9 && d4 > 1e-9));
  }

  for (var i = 0; i + 1 < points.length; i++) {
    for (var j = i + 2; j + 1 < points.length; j++) {
      // Neighbouring edges share an endpoint, and the first and last edge of a
      // closed run share one too; neither is a crossing.
      if (i == 0 && j + 1 == points.length - 1) continue;
      if (crosses(points[i], points[i + 1], points[j], points[j + 1])) return true;
    }
  }
  return false;
}

/// The area a closed run of points encloses.
double _area(List<Pt> points) {
  var total = 0.0;
  for (var i = 0; i < points.length; i++) {
    final next = points[(i + 1) % points.length];
    total += points[i].x * next.y - next.x * points[i].y;
  }
  return total.abs() / 2;
}

void main() {
  group('crown surfaces', () {
    test('every tooth is cut into all five surfaces', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final shape = buildToothShape(tooth, 60, 58);
        expect(shape.surfaces.length, ToothSurface.values.length, reason: '#$tooth');
        for (final surface in ToothSurface.values) {
          expect(shape.surfaces.containsKey(surface), isTrue, reason: '#$tooth $surface');
        }
      }
    });

    test('the surfaces tile the crown: no gaps, no overlaps', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final glyph = buildToothGlyph(tooth, 60, 58);
        for (final probe in _probes(60, 58)) {
          if (!glyph.outline.contains(probe)) continue;
          final hits = glyph.surfaces.entries.where((e) => e.value.contains(probe)).length;
          // A probe on a shared boundary can read as either side; anything
          // that lands in three regions at once, or in none, is a real hole.
          expect(hits, inInclusiveRange(1, 2), reason: '#$tooth at $probe matched $hits surfaces');
        }
      }
    });

    test('no surface crosses itself', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final shape = buildToothShape(tooth, 60, 58);
        for (final entry in shape.surfaces.entries) {
          expect(
            _selfIntersects(entry.value.flatten()),
            isFalse,
            // One sector per crown straddles the point the outline starts at.
            // Picking its points in ring order took them from both ends of the
            // ring, which drew this surface as a bow tie across the crown.
            reason: '#$tooth ${surfaceName(tooth, entry.key)} is not a simple region',
          );
        }
      }
    });

    test('the five surfaces add up to the whole crown', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final shape = buildToothShape(tooth, 60, 58);
        final crown = _area(shape.outline.flatten());
        final surfaces = shape.surfaces.values
            .map((contour) => _area(contour.flatten()))
            .fold<double>(0, (total, area) => total + area);
        // Flattening the crown's curves loses a sliver against the straight
        // edges the surfaces are cut with; 2% covers that and nothing larger.
        expect(surfaces / crown, closeTo(1, 0.02), reason: '#$tooth');
      }
    });

    test('every fissure stays inside its own crown', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final glyph = buildToothGlyph(tooth, 60, 58);
        for (var i = 0; i < glyph.grooves.length; i++) {
          for (final metric in glyph.grooves[i].computeMetrics()) {
            for (var step = 0; step <= 20; step++) {
              final point = metric.getTangentForOffset(metric.length * step / 20)!.position;
              expect(
                glyph.outline.contains(point),
                isTrue,
                // A fissure that runs past the crown border reads as a crack
                // through the tooth, and paints over the neighbour beside it.
                reason: '#$tooth groove ${i + 1} leaves the crown at $point',
              );
            }
          }
        }
      }
    });

    test('the fissure pattern follows the tooth anatomy', () {
      // Maxillary molars carry an oblique ridge, so their fissures meet the
      // central fossa from three sides; mandibular ones run a central groove
      // the length of the crown with three branches off it.
      for (final tooth in [1, 2, 3, 14, 15, 16]) {
        expect(buildToothShape(tooth, 60, 58).grooves, hasLength(3), reason: '#$tooth');
      }
      for (final tooth in [17, 18, 19, 30, 31, 32]) {
        expect(buildToothShape(tooth, 60, 58).grooves, hasLength(4), reason: '#$tooth');
      }
      // One fissure between the two cusps of a premolar, plus its end pits or
      // its lingual groove; a single crescent on an incisor.
      for (final tooth in [4, 5, 12, 13, 20, 21, 28, 29]) {
        expect(
          buildToothShape(tooth, 60, 58).grooves.length,
          inInclusiveRange(2, 3),
          reason: '#$tooth',
        );
      }
      for (final tooth in [7, 8, 9, 10, 23, 24, 25, 26]) {
        expect(buildToothShape(tooth, 60, 58).grooves, hasLength(1), reason: '#$tooth');
      }
    });

    test('the same fissure runs to the same side in every quadrant', () {
      // The buccal groove of a mandibular molar leaves the central groove on
      // the cheek side and towards the back of the mouth. Written once, it has
      // to come out that way in all four quadrants — which is what the mesial
      // mirroring in the pattern is for.
      for (final tooth in [18, 19, 30, 31]) {
        final shape = buildToothShape(tooth, 60, 58);
        final central = shape.grooves.first.flatten();
        final buccal = shape.grooves[1].flatten();
        expect(buccal.last.y, lessThan(29), reason: '#$tooth runs to the tongue side');
        final mesialIsPlusX = tooth == 18 || tooth == 19;
        // The central groove is written from the mesial end, so its own first
        // point says which way mesial points on this crown.
        expect(
          central.first.x > 30,
          mesialIsPlusX,
          reason: '#$tooth has its central groove back to front',
        );
      }
    });

    test('the biting surface is the middle of the crown', () {
      for (var tooth = 1; tooth <= 32; tooth++) {
        final glyph = buildToothGlyph(tooth, 60, 58);
        expect(
          glyph.surfaces[ToothSurface.centre]!.contains(const Offset(30, 29)),
          isTrue,
          reason: '#$tooth',
        );
      }
    });

    test('clinical names follow the tooth: occlusal at the back, incisal at the front', () {
      expect(surfaceName(3, ToothSurface.centre), 'occlusal');
      expect(surfaceName(3, ToothSurface.outer), 'buccal');
      expect(surfaceName(8, ToothSurface.centre), 'incisal');
      expect(surfaceName(8, ToothSurface.outer), 'facial');
      for (var tooth = 1; tooth <= 32; tooth++) {
        expect(surfaceName(tooth, ToothSurface.lingual), 'lingual');
        expect(surfaceName(tooth, ToothSurface.towardMidline), 'mesial');
        expect(surfaceName(tooth, ToothSurface.awayFromMidline), 'distal');
      }
    });

    test('mesial faces the midline and buccal faces out of the arch', () {
      final layout = DentalArchLayout.build(_canvasFor(360));
      final geometry = layout.geometry;
      final mouthCentre = Offset(geometry.width / 2, geometry.height / 2);

      Offset centroidOf(int tooth, ToothSurface surface) {
        final contour = geometry.shapeFor(tooth).surfaces[surface]!;
        final points = contour.flatten().map((p) => geometry.toChart(tooth, p)).toList();
        final sum = points.fold(const Pt(0, 0), (Pt total, Pt p) => total + p);
        return (sum * (1 / points.length)).offset;
      }

      for (var tooth = 1; tooth <= 32; tooth++) {
        // The central incisor of this tooth's own arch, which is where the
        // midline is: mesial has to point towards it.
        final midlineTooth = tooth <= 16 ? (tooth <= 8 ? 8 : 9) : (tooth <= 24 ? 24 : 25);
        if (tooth == midlineTooth) continue;
        final midline = geometry.placements[midlineTooth]!.center.offset;
        final mesial = centroidOf(tooth, ToothSurface.towardMidline);
        final distal = centroidOf(tooth, ToothSurface.awayFromMidline);
        expect(
          (mesial - midline).distance,
          lessThan((distal - midline).distance),
          reason: '#$tooth has mesial and distal the wrong way round',
        );

        // Buccal or facial is the cheek side, so it sits further from the
        // empty middle of the mouth than the tongue side does.
        final outer = centroidOf(tooth, ToothSurface.outer);
        final lingual = centroidOf(tooth, ToothSurface.lingual);
        expect(
          (outer - mouthCentre).distance,
          greaterThan((lingual - mouthCentre).distance),
          reason: '#$tooth has its cheek and tongue sides swapped',
        );
      }
    });

    test('a tap inside a crown resolves to one of that crown surfaces', () {
      final layout = DentalArchLayout.build(_canvasFor(360));
      for (var tooth = 1; tooth <= 32; tooth++) {
        final centre = layout.placements[tooth]!.center.offset;
        expect(layout.surfaceAt(tooth, centre), ToothSurface.centre, reason: '#$tooth');
      }
      // Well outside the arch, nothing is hit.
      expect(layout.surfaceAt(1, const Offset(-50, -50)), isNull);
    });
  });

  group('exported asset', () {
    final file = File('assets/images/tooth_map.svg');

    test('assets/images/tooth_map.svg is what the geometry draws today', () {
      expect(file.existsSync(), isTrue, reason: 'run: dart run tool/generate_tooth_map_svg.dart');
      expect(
        file.readAsStringSync().replaceAll('\r\n', '\n'),
        buildToothMapSvg(),
        reason: 'the asset is stale — run: dart run tool/generate_tooth_map_svg.dart',
      );
    });

    test('carries every tooth and every surface, and no labels or colour coding', () {
      final svg = buildToothMapSvg();
      for (var tooth = 1; tooth <= 32; tooth++) {
        expect(svg, contains('id="tooth-$tooth"'), reason: '#$tooth is missing');
        for (final surface in ToothSurface.values) {
          expect(svg, contains('id="tooth-$tooth-${surfaceName(tooth, surface)}"'), reason: '#$tooth $surface');
        }
      }
      expect(svg, isNot(contains('<text')));
      // Black lines on white crowns, and nothing else: a base template has no
      // condition or selection colour baked into it.
      final colours = RegExp(r'#[0-9A-Fa-f]{6}')
          .allMatches(svg)
          .map((match) => match.group(0)!.toUpperCase())
          .toSet();
      expect(colours, {'#000000', '#FFFFFF'});
    });

    test('draws every crown where the chart puts it', () {
      final geometry = ArchGeometry.build(kToothMapWidth, kToothMapHeight);
      final svg = buildToothMapSvg();
      for (var tooth = 1; tooth <= 32; tooth++) {
        // The first point of the crown's path, which the chart places by
        // rotating the tooth's own box onto the arch.
        final start = geometry.toChart(tooth, geometry.shapeFor(tooth).outline.start);
        final drawn = RegExp('id="tooth-$tooth-crown" d="M ([-0-9.]+) ([-0-9.]+)').firstMatch(svg);
        expect(drawn, isNotNull, reason: '#$tooth has no crown path');
        expect(double.parse(drawn!.group(1)!), closeTo(start.x, 0.01), reason: '#$tooth x');
        expect(double.parse(drawn.group(2)!), closeTo(start.y, 0.01), reason: '#$tooth y');
      }
    });

    test('is drawn at the chart own proportions', () {
      expect(kToothMapHeight / kToothMapWidth, closeTo(1 / kChartAspect, 0.001));
      expect(buildToothMapSvg(), contains('viewBox="0 0 1200 1899"'));
      // Sanity: the fit loop settled rather than bottoming out.
      final geometry = ArchGeometry.build(kToothMapWidth, kToothMapHeight);
      expect(geometry.cell, greaterThan(kToothMapWidth * 0.05));
      expect(geometry.cell, lessThan(kToothMapWidth * 0.2));
      expect(math.min(geometry.width, geometry.height), greaterThan(0));
    });
  });
}
