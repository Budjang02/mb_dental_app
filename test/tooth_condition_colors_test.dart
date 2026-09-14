import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/records/dental_arch_chart.dart';
import 'package:mb_dental_app/screens/records/dental_records_screen.dart';

/// The website's css/odontogram.css, value for value.
void main() {
  const expected = <String, (int, int)>{
    'Healthy': (0xFFD1FAE5, 0xFF10B981),
    'Caries/Cavity': (0xFFFEF3C7, 0xFFF59E0B),
    'Filled': (0xFFDBEAFE, 0xFF3B82F6),
    'Crown': (0xFFF3E8FF, 0xFFA855F7),
    'Missing': (0xFFFEE2E2, 0xFFEF4444),
    'Root Canal': (0xFFFFF7ED, 0xFFEA580C),
    'Impacted': (0xFFFCE7F3, 0xFFEC4899),
    'Other': (0xFFE0E7FF, 0xFF6366F1),
  };

  test('every condition has the website\'s exact fill and stroke', () {
    expect(kToothConditionColors.keys.toSet(), expected.keys.toSet());
    expect(kToothConditionStrokes.keys.toSet(), expected.keys.toSet());
    expected.forEach((condition, colors) {
      expect(kToothConditionColors[condition], Color(colors.$1), reason: '$condition fill');
      expect(kToothConditionStrokes[condition], Color(colors.$2), reason: '$condition stroke');
    });
  });

  test('only Missing is dashed, with stroke-dasharray 3 2', () {
    expect(kToothDashedConditions, {'Missing'});
    expect(kToothDashPattern, [3, 2]);
  });

  test('condition spellings map to their own colour, never all to one', () {
    expect(canonicalToothCondition('crown'), 'Crown');
    expect(canonicalToothCondition('CARIES'), 'Caries/Cavity');
    expect(canonicalToothCondition('cavity'), 'Caries/Cavity');
    expect(canonicalToothCondition('Root canal'), 'Root Canal');
    expect(canonicalToothCondition('root_canal'), 'Root Canal');
    expect(canonicalToothCondition(' filled '), 'Filled');
    expect(canonicalToothCondition('missing'), 'Missing');
    expect(canonicalToothCondition('impacted'), 'Impacted');
    expect(canonicalToothCondition(''), 'Healthy');
    expect(canonicalToothCondition('Marked'), 'Other');
  });

  test('a dashed outline is 3px dashes separated by 2px gaps', () {
    final line = Path()
      ..moveTo(0, 0)
      ..lineTo(20, 0);
    final segments = dashedPath(line, kToothDashPattern).computeMetrics().toList();
    // 20px of 3+2 repeats: dashes at 0, 5, 10 and 15.
    expect(segments, hasLength(4));
    for (final segment in segments) {
      expect(segment.length, closeTo(3, 0.001));
    }
  });
}
