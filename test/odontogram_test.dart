import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/records/dental_arch_chart.dart';
import 'package:mb_dental_app/screens/records/tooth_glyphs.dart';

/// Canvas sizes the chart has to survive: a small phone, a large phone, and
/// the width it caps out at on tablet and desktop.
const List<double> _widths = [300, 360, kDentalArchMaxWidth];

Size _canvasFor(double width) => Size(width, width / 0.632);

/// The corners of a tooth's cell once it has been rotated into place — what
/// actually has to stay on the canvas.
List<Offset> _cornersOf(ToothPlacement placement) {
  final halfW = placement.width / 2;
  final halfH = placement.height / 2;
  final cos = math.cos(placement.angle);
  final sin = math.sin(placement.angle);
  return [
    for (final corner in [
      Offset(-halfW, -halfH),
      Offset(halfW, -halfH),
      Offset(halfW, halfH),
      Offset(-halfW, halfH),
    ])
      placement.center +
          Offset(
            corner.dx * cos - corner.dy * sin,
            corner.dx * sin + corner.dy * cos,
          ),
  ];
}

void main() {
  group('tooth types', () {
    test('every quadrant runs incisor, canine, premolar, molar outwards', () {
      // #8 is the upper right central and #1 the upper right third molar, so
      // walking that quadrant should walk the four crown types in order.
      expect(toothTypeOf(8), ToothType.incisor);
      expect(toothTypeOf(7), ToothType.incisor);
      expect(toothTypeOf(6), ToothType.canine);
      expect(toothTypeOf(5), ToothType.premolar);
      expect(toothTypeOf(4), ToothType.premolar);
      expect(toothTypeOf(3), ToothType.molar);
      expect(toothTypeOf(1), ToothType.molar);
    });

    test('the four quadrants mirror each other', () {
      for (var i = 0; i < 8; i++) {
        final type = toothTypeOf(8 - i);
        expect(toothTypeOf(9 + i), type, reason: 'upper left #${9 + i}');
        expect(toothTypeOf(24 - i), type, reason: 'lower left #${24 - i}');
        expect(toothTypeOf(25 + i), type, reason: 'lower right #${25 + i}');
      }
    });

    test('molars are the widest crowns and lower incisors the narrowest', () {
      expect(toothWidthFactor(3), greaterThan(toothWidthFactor(5)));
      expect(toothWidthFactor(5), greaterThan(toothWidthFactor(7)));
      expect(toothWidthFactor(24), lessThan(toothWidthFactor(8)));
    });
  });

  group('arch layout', () {
    test('places all 32 teeth at every supported width', () {
      for (final width in _widths) {
        final layout = DentalArchLayout.build(_canvasFor(width));
        expect(layout.placements.length, 32, reason: 'at ${width}px');
        for (var n = 1; n <= 32; n++) {
          expect(layout.placements.containsKey(n), isTrue, reason: '#$n at ${width}px');
        }
      }
    });

    test('no crown is clipped by the edge of the canvas', () {
      for (final width in _widths) {
        final size = _canvasFor(width);
        final layout = DentalArchLayout.build(size);
        for (final entry in layout.placements.entries) {
          for (final corner in _cornersOf(entry.value)) {
            expect(corner.dx, greaterThanOrEqualTo(-0.5), reason: '#${entry.key} at ${width}px');
            expect(corner.dx, lessThanOrEqualTo(size.width + 0.5), reason: '#${entry.key} at ${width}px');
            expect(corner.dy, greaterThanOrEqualTo(-0.5), reason: '#${entry.key} at ${width}px');
            expect(corner.dy, lessThanOrEqualTo(size.height + 0.5), reason: '#${entry.key} at ${width}px');
          }
        }
      }
    });

    test('neighbouring crowns sit flush, neither gapped nor overlapping', () {
      final size = _canvasFor(360);
      final layout = DentalArchLayout.build(size);
      for (final arch in [kUpperArchTeeth, kLowerArchTeeth]) {
        for (var i = 0; i + 1 < arch.length; i++) {
          final a = layout.placements[arch[i]]!;
          final b = layout.placements[arch[i + 1]]!;
          // Centres exactly the sum of the two half-widths apart means the
          // crowns touch. Teeth are spaced along the arc while this measures
          // the chord, so allow a few percent either way.
          final abutting = (a.width + b.width) / 2;
          expect(
            (a.center - b.center).distance / abutting,
            closeTo(1.0, 0.06),
            reason: '#${arch[i]} to #${arch[i + 1]}',
          );
        }
      }
    });

    test('the upper arch sits above the gap and the lower arch below it', () {
      final size = _canvasFor(360);
      final layout = DentalArchLayout.build(size);
      for (final n in kUpperArchTeeth) {
        expect(layout.placements[n]!.center.dy, lessThan(size.height / 2), reason: '#$n');
      }
      for (final n in kLowerArchTeeth) {
        expect(layout.placements[n]!.center.dy, greaterThan(size.height / 2), reason: '#$n');
      }
    });

    test('numbering runs left to right up top and right to left below', () {
      final layout = DentalArchLayout.build(_canvasFor(360));
      for (var i = 0; i + 1 < kUpperArchTeeth.length; i++) {
        expect(
          layout.placements[kUpperArchTeeth[i]]!.center.dx,
          lessThan(layout.placements[kUpperArchTeeth[i + 1]]!.center.dx),
          reason: '#${kUpperArchTeeth[i]} should sit left of #${kUpperArchTeeth[i + 1]}',
        );
      }
      for (var i = 0; i + 1 < kLowerArchTeeth.length; i++) {
        expect(
          layout.placements[kLowerArchTeeth[i]]!.center.dx,
          greaterThan(layout.placements[kLowerArchTeeth[i + 1]]!.center.dx),
          reason: '#${kLowerArchTeeth[i]} should sit right of #${kLowerArchTeeth[i + 1]}',
        );
      }
    });

    test('the front teeth meet at the midline', () {
      final size = _canvasFor(360);
      final layout = DentalArchLayout.build(size);
      // The central incisors straddle the centre. #8 is the patient's upper
      // right, which is the viewer's left; #25 is the lower right, likewise on
      // the viewer's left — the lower arch runs the other way round.
      for (final pair in [[8, 9], [25, 24]]) {
        final left = layout.placements[pair[0]]!.center.dx;
        final right = layout.placements[pair[1]]!.center.dx;
        expect(left, lessThan(size.width / 2), reason: '#${pair[0]}');
        expect(right, greaterThan(size.width / 2), reason: '#${pair[1]}');
        expect((size.width - left - right).abs(), lessThan(1), reason: 'not symmetrical');
      }
    });
  });

  group('hit testing', () {
    test('every tooth answers a tap on its own crown', () {
      for (final width in _widths) {
        final layout = DentalArchLayout.build(_canvasFor(width));
        for (final entry in layout.placements.entries) {
          expect(layout.toothAt(entry.value.center), entry.key, reason: '#${entry.key} at ${width}px');
        }
      }
    });

    test('a tap out in the empty middle of the mouth selects nothing', () {
      final size = _canvasFor(360);
      final layout = DentalArchLayout.build(size);
      expect(layout.toothAt(Offset(size.width / 2, size.height / 2)), isNull);
    });
  });

  group('chart widget', () {
    Widget wrap(int selected, ValueChanged<int> onSelect) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: DentalArchChart(
                  conditionColors: const {14: Color(0xFFFFB74D)},
                  selectedTooth: selected,
                  onSelect: onSelect,
                  idleFill: const Color(0xFFFFFFFF),
                  outlineColor: const Color(0xFF2F3D4C),
                  selectedFill: const Color(0xFFEE8172),
                  selectedOutline: const Color(0xFFC2503F),
                  labelColor: const Color(0xFF64748B),
                ),
              ),
            ),
          ),
        );

    testWidgets('reports the tooth that was tapped', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tapped = <int>[];
      await tester.pumpWidget(wrap(6, tapped.add));
      await tester.pumpAndSettle();

      final chart = tester.getTopLeft(find.byType(CustomPaint).last);
      final layout = DentalArchLayout.build(_canvasFor(360));

      for (final tooth in [1, 8, 14, 24, 32]) {
        await tester.tapAt(chart + layout.placements[tooth]!.center);
        await tester.pump();
      }
      expect(tapped, [1, 8, 14, 24, 32]);
    });
  });
}
