import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/data/service_categories.dart';
import 'package:mb_dental_app/models/dental_service.dart';

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
      'Surgical Extraction': 'tooth-extraction',
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
      expect(categoryIdForProcedure('Something Brand New'), kOtherServiceCategoryId);
      expect(categoryIdForProcedure(''), kOtherServiceCategoryId);
    });

    test('matching survives case, spacing and punctuation differences', () {
      expect(categoryIdForProcedure('teeth whitening'), 'improve-smile');
      expect(categoryIdForProcedure('Veneers - Ceramic/Direct'), 'improve-smile');
      expect(categoryIdForProcedure('  Metal   Braces  '), 'braces-alignment');
      expect(categoryIdForProcedure('Pre and Post Operative Care'), 'tooth-extraction');
    });

    test('the catch-all books a checkup outright instead of listing procedures', () {
      final other = serviceCategoryById(kOtherServiceCategoryId);
      expect(other.isDirectPick, isTrue);
      expect(other.directProcedureName, kCheckupProcedureName);
      // No submenu: a group that books one procedure must not also list them.
      expect(other.procedureNames, isEmpty);
    });

    test('every other group opens a submenu', () {
      for (final category in kServiceCategories) {
        if (category.id == kOtherServiceCategoryId) continue;
        expect(category.isDirectPick, isFalse, reason: category.id);
        expect(category.procedureNames, isNotEmpty, reason: category.id);
      }
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
  group('direct-pick group', () {
    DentalService service(String name) => DentalService(
          id: name,
          name: name,
          description: '',
          specializationCode: 'general',
          categoryId: kOtherServiceCategoryId,
          durationMinutes: 30,
          price: 0,
          requiredSpecialization: 'General Dentistry',
        );

    const other = ServiceGroup(
      code: kOtherServiceCategoryId,
      label: 'Other / not sure',
      blurb: '',
      sortOrder: 6,
      directProcedureName: kCheckupProcedureName,
    );

    const listed = ServiceGroup(
      code: 'root-canal',
      label: 'Root canal',
      blurb: '',
      sortOrder: 4,
    );

    test('books the named procedure', () {
      final picked = directPickService(
        other,
        [service('Surgical Extraction'), service(kCheckupProcedureName)],
      );
      expect(picked?.name, kCheckupProcedureName);
    });

    test('matches the name past case and punctuation', () {
      expect(directPickService(other, [service('dental  check-up')])?.name,
          'dental  check-up');
    });

    test('falls back to the first procedure when the clinic renamed it', () {
      expect(directPickService(other, [service('Consultation')])?.name, 'Consultation');
    });

    test('is null for a group with a submenu, and for an empty group', () {
      expect(directPickService(listed, [service('Root Canal Treatment')]), isNull);
      expect(directPickService(other, const []), isNull);
    });
  });
}
