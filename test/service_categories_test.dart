import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/service_categories.dart';

void main() {
  group('procedure to category mapping', () {
    // Every name here is one the clinic already has in `procedures`. If a
    // rename on their side breaks the match, the procedure falls into the
    // catch-all rather than vanishing — these assertions catch that happening.
    const expected = <String, String>{
      'Teeth Whitening': 'improve-smile',
      'Veneers (Ceramic / Direct)': 'improve-smile',
      'Crowns / Smile Restoration': 'improve-smile',
      'Cosmetic Contouring': 'improve-smile',
      'Metal Braces': 'braces-alignment',
      'Ceramic Braces': 'braces-alignment',
      'Clear Aligners': 'braces-alignment',
      'Retainers': 'braces-alignment',
      'Preventive Care': 'child-dental-care',
      'Fluoride Treatment': 'child-dental-care',
      'Sealants': 'child-dental-care',
      'Tooth Alignment Guidance': 'child-dental-care',
      'Simple Tooth Extraction': 'tooth-extraction',
      'Tooth Extraction': 'tooth-extraction',
      'Wisdom Tooth Removal': 'tooth-extraction',
      'Pre- and Post-Operative Care': 'tooth-extraction',
      'Root Canal Treatment': 'root-canal',
      'Infection Removal': 'root-canal',
      'Sealing and Restoration': 'root-canal',
      'Follow-up Check-up': 'root-canal',
      'TMJ Evaluation': 'jaw-problem',
      'Bite Adjustment': 'jaw-problem',
      'Jaw Pain Management': 'jaw-problem',
      'Custom Night Guard': 'jaw-problem',
    };

    expected.forEach((procedure, categoryId) {
      test('"$procedure" belongs to $categoryId', () {
        expect(categoryIdForProcedure(procedure), categoryId);
      });
    });

    test('anything unmapped falls into the catch-all', () {
      // Real rows in the clinic's table that the spec does not name.
      expect(categoryIdForProcedure('Dental Checkup'), kOtherServiceCategoryId);
      expect(categoryIdForProcedure('General Cleaning'), kOtherServiceCategoryId);
      expect(categoryIdForProcedure('Surgical Extraction'), kOtherServiceCategoryId);
      expect(categoryIdForProcedure('Something Brand New'), kOtherServiceCategoryId);
      expect(categoryIdForProcedure(''), kOtherServiceCategoryId);
    });

    test('matching survives case, spacing and punctuation differences', () {
      expect(categoryIdForProcedure('teeth whitening'), 'improve-smile');
      expect(categoryIdForProcedure('Veneers - Ceramic/Direct'), 'improve-smile');
      expect(categoryIdForProcedure('  Metal   Braces  '), 'braces-alignment');
      expect(categoryIdForProcedure('Pre and Post Operative Care'), 'tooth-extraction');
    });

    test('the catch-all is last, so it never pushes a real group down', () {
      expect(kServiceCategories.last.id, kOtherServiceCategoryId);
      expect(kServiceCategories.where((c) => c.id == kOtherServiceCategoryId).length, 1);
    });

    test('no procedure is claimed by two groups', () {
      final seen = <String>{};
      for (final category in kServiceCategories) {
        for (final name in category.procedureNames) {
          expect(seen.add(name.toLowerCase()), isTrue,
              reason: '"$name" is listed under more than one category');
        }
      }
    });
  });
}
