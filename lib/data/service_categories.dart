import '../models/dental_service.dart';

/// The patient-facing groups the booking wizard lists procedures under.
///
/// These are deliberately phrased as the reason a patient books — "Improve
/// smile", "Jaw problem" — rather than as the clinic's own `specialization`
/// codes, which stay on [DentalService.specializationCode] because the dentist
/// roster still matches on them.
///
/// The mapping lives here rather than in the database on purpose: the clinic's
/// `procedures.category` column already holds its own internal values
/// (`Cleaning`, `Restorative`, `Surgery`, …) that the clinic's own tools read,
/// and overwriting them to suit this app would break those. See
/// `docs/service_categories.sql` for the migration if you would rather hold
/// this in Supabase later.
class ServiceCategoryDef {
  /// Stable key stored on [DentalService.categoryId].
  final String id;

  final String label;

  /// One line under the heading saying what belongs in the group.
  final String blurb;

  /// Exact procedure names, as the clinic writes them in `procedures.name`.
  /// Matched case- and punctuation-insensitively — see [categoryIdForProcedure].
  final List<String> procedureNames;

  /// Set on a group that books one procedure outright instead of opening a
  /// submenu. A patient who does not know what they need should not have to
  /// choose from a list to say so, so tapping the group books this procedure.
  /// Empty on every group that lists its procedures normally.
  final String directProcedureName;

  const ServiceCategoryDef({
    required this.id,
    required this.label,
    required this.blurb,
    this.procedureNames = const [],
    this.directProcedureName = '',
  });

  /// True when tapping the heading books [directProcedureName] directly.
  bool get isDirectPick => directProcedureName.isNotEmpty;
}

/// The procedure a patient books when they cannot name what they need. It is
/// what the catch-all group books outright — see [ServiceCategoryDef.isDirectPick].
const String kCheckupProcedureName = 'Dental Checkup';

/// Key of the catch-all group. Anything the clinic adds that is not named in a
/// group below lands here rather than disappearing from the menu.
const String kOtherServiceCategoryId = 'other';

/// In the order the wizard shows them. The catch-all sits last.
const List<ServiceCategoryDef> kServiceCategories = [
  ServiceCategoryDef(
    id: 'improve-smile',
    label: 'Improve smile',
    blurb: 'Whitening, veneers and cosmetic work.',
    procedureNames: [
      'Teeth Whitening',
      'Veneers (Ceramic / Direct)',
      'Crowns / Smile Restoration',
      'Cosmetic Contouring',
    ],
  ),
  ServiceCategoryDef(
    id: 'braces-alignment',
    label: 'Braces and alignment',
    blurb: 'Straightening the teeth and holding them in place.',
    procedureNames: [
      'Metal Braces',
      'Ceramic Braces',
      'Clear Aligners',
      'Retainers',
    ],
  ),
  ServiceCategoryDef(
    id: 'child-dental-care',
    label: 'Child dental care',
    blurb: 'Preventive care for younger patients.',
    procedureNames: [
      'Preventive Care',
      'Fluoride Treatment',
      'Sealants',
      'Tooth Alignment Guidance',
    ],
  ),
  ServiceCategoryDef(
    id: 'tooth-extraction',
    label: 'Tooth extraction',
    blurb: 'Removing a tooth, and the care around it.',
    procedureNames: [
      'Simple Tooth Extraction',
      'Tooth Extraction',
      'Surgical Extraction',
      'Wisdom Tooth Removal',
      'Pre- and Post-Operative Care',
    ],
  ),
  ServiceCategoryDef(
    id: 'root-canal',
    label: 'Root canal',
    blurb: 'Treating infection inside the tooth.',
    procedureNames: [
      'Root Canal Treatment',
      'Infection Removal',
      'Sealing and Restoration',
      'Follow-up Check-up',
    ],
  ),
  ServiceCategoryDef(
    id: 'jaw-problem',
    label: 'Jaw problem',
    blurb: 'Jaw pain, clenching and bite trouble.',
    procedureNames: [
      'TMJ Evaluation',
      'Bite Adjustment',
      'Jaw Pain Management',
      'Custom Night Guard',
    ],
  ),
  ServiceCategoryDef(
    id: kOtherServiceCategoryId,
    label: 'Other / Not sure',
    blurb: 'Not sure what you need? This books a dental checkup.',
    directProcedureName: kCheckupProcedureName,
  ),
];

/// Lookup built once from [kServiceCategories], keyed by normalised name.
final Map<String, String> _categoryIdByProcedureName = {
  for (final category in kServiceCategories)
    for (final name in category.procedureNames) _normalise(name): category.id,
};

/// Which group [procedureName] belongs in, or [kOtherServiceCategoryId].
///
/// Matching ignores case, punctuation and spacing, so `Veneers (Ceramic /
/// Direct)` still matches if the clinic writes it `Veneers - Ceramic/Direct`.
/// A rename the clinic makes on their side lands the procedure in the catch-all
/// rather than dropping it from the menu.
String categoryIdForProcedure(String procedureName) =>
    _categoryIdByProcedureName[_normalise(procedureName)] ?? kOtherServiceCategoryId;

/// Lowercase, letters and digits only. Everything else collapses to a single
/// space so spacing and punctuation differences stop mattering.
String _normalise(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// The one procedure a direct-pick [group] books, picked out of the [services]
/// filed under it.
///
/// Falls back to the group's first procedure when the clinic has renamed or
/// retired the named one: the group must stay bookable rather than tap onto
/// nothing. Null for a group that opens a submenu, or an empty one.
DentalService? directPickService(ServiceGroup group, List<DentalService> services) {
  if (!group.isDirectPick || services.isEmpty) return null;
  final wanted = _normalise(group.directProcedureName);
  for (final service in services) {
    if (_normalise(service.name) == wanted) return service;
  }
  return services.first;
}

/// The group definition for [id], falling back to the catch-all.
ServiceCategoryDef serviceCategoryById(String id) => kServiceCategories.firstWhere(
      (category) => category.id == id,
      orElse: () => kServiceCategories.last,
    );
