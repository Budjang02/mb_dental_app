import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/screens/records/dental_arch_chart.dart';
import 'package:mb_dental_app/screens/records/dental_records_screen.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The tooth-status colour system: crown, root, outline and badge text per
/// status, the same in both themes.
void main() {
  const crowns = <String, int>{
    'Healthy': 0xFFF8FAFC,
    'Caries/Cavity': 0xFFFDBA74,
    'Filled': 0xFF93C5FD,
    'Crown': 0xFFFCD34D,
    'Missing': 0x99CBD5E1,
    'Root Canal': 0xFFD8B4FE,
    'Impacted': 0xFFF9A8D4,
    'Other': 0xFF5EEAD4,
  };

  test('every status has its crown colour, and all four maps cover the same statuses', () {
    crowns.forEach((condition, value) {
      expect(kToothConditionColors[condition], Color(value), reason: condition);
    });
    for (final map in [kToothConditionColors, kToothConditionRoots, kToothConditionStrokes, kToothConditionText]) {
      expect(map.keys.toSet(), crowns.keys.toSet());
    }
    expect(kToothConditionOrder.toSet(), crowns.keys.toSet());
  });

  test('the root is a slightly darker shade than the crown', () {
    for (final condition in crowns.keys) {
      final crown = kToothConditionColors[condition]!;
      final root = kToothConditionRoots[condition]!;
      expect(root.computeLuminance(), lessThan(crown.computeLuminance()), reason: condition);
      expect(_contrast(crown, root), lessThan(1.6), reason: '$condition root is too far from its crown');
    }
  });

  test('badge text reads on its badge at 4.5:1 or better', () {
    for (final condition in crowns.keys) {
      final ground = kToothConditionColors[condition]!.withAlpha(0xFF);
      expect(_contrast(kToothConditionText[condition]!, ground), greaterThanOrEqualTo(4.5), reason: condition);
    }
  });

  test('status codes land on their own colour', () {
    expect(canonicalToothCondition('ROOT_CANAL'), 'Root Canal');
    expect(canonicalToothCondition('CROWN'), 'Crown');
    expect(canonicalToothCondition('FILLED'), 'Filled');
    expect(canonicalToothCondition('HEALTHY'), 'Healthy');
    expect(canonicalToothCondition('Marked'), 'Other');
    expect(toothConditionLabel('Other'), 'Other / Marked');
  });

  test('every spelling of a status reaches it, never the Other catch-all', () {
    for (final raw in ['Root Canal', 'ROOT_CANAL', 'root-canal', 'Root Canal Treatment', 'RCT', 'Endodontic', 'rootcanal']) {
      expect(canonicalToothCondition(raw), 'Root Canal', reason: raw);
    }
    expect(canonicalToothCondition('Root canal + crown'), 'Root Canal');
    expect(canonicalToothCondition('Caries/Cavity'), 'Caries/Cavity');
    expect(canonicalToothCondition('Decayed'), 'Caries/Cavity');
    expect(canonicalToothCondition('Filling'), 'Filled');
    expect(canonicalToothCondition('Composite restoration'), 'Filled');
    expect(canonicalToothCondition('Porcelain Crown'), 'Crown');
    expect(canonicalToothCondition('Extracted'), 'Missing');
    expect(canonicalToothCondition('Impacted wisdom tooth'), 'Impacted');
    expect(canonicalToothCondition(' '), 'Healthy');
    expect(canonicalToothCondition('Sealant'), 'Other');
  });

  test('no two statuses share a crown colour', () {
    expect(kToothConditionColors.values.toSet(), hasLength(kToothConditionColors.length));
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

  test('tooth numbers outside Universal 1-32 are ignored, not thrown on', () {
    expect(toothNumberOf('#1'), 1);
    expect(toothNumberOf('#32'), 32);
    expect(toothNumberOf('#46'), isNull);
    expect(toothNumberOf('#0'), isNull);
    expect(toothNumberOf('Full Mouth'), isNull);
  });
}
