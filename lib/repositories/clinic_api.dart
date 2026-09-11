import 'package:flutter/cupertino.dart';

import '../data/clinic_catalog.dart';
import '../data/service_categories.dart';
import '../models/dental_service.dart';
import '../services/supabase_service.dart';

/// The procedure menu as the clinic currently offers it, with the headings it
/// is filed under.
class ServiceMenu {
  final List<ServiceGroup> groups;
  final List<DentalService> services;

  const ServiceMenu({required this.groups, required this.services});

  static const ServiceMenu empty = ServiceMenu(groups: [], services: []);
}

/// The clinic's own details, as the clinic keeps them.
class ClinicProfile {
  final String name;
  final String address;
  final String phone;
  final String hours;
  final bool isOpen;

  const ClinicProfile({
    required this.name,
    required this.address,
    required this.phone,
    required this.hours,
    required this.isOpen,
  });

  /// Shown until the real row arrives, and if it never does. Only the clinic's
  /// name is safe to hardcode — an out-of-date address or number sends a
  /// patient to the wrong place.
  static const ClinicProfile placeholder = ClinicProfile(
    name: 'Mariano & Bolasoc Dental Center',
    address: '',
    phone: '',
    hours: '',
    isOpen: true,
  );

  bool get hasContactDetails => address.isNotEmpty || phone.isNotEmpty;
}

/// The clinic's public reference data: the procedure menu and the service lines
/// it is grouped by. None of it is patient-specific.
class ClinicApi {
  ClinicApi._();

  /// The bookable menu exactly as the clinic keeps it, grouped the way a
  /// patient thinks about it (see `data/service_categories.dart`).
  ///
  /// Only active rows are offered: the clinic retires a procedure by clearing
  /// `is_active`, and a retired one must not appear in the booking wizard even
  /// though past appointments still point at it.
  static Future<ServiceMenu> loadMenu() async {
    final client = SupabaseService.client;

    final procedureRows = await client
        .from('procedures')
        .select('id, name, description, category, specialization, duration_min, '
            'base_price, min_rate, max_rate, price_unit')
        .eq('is_active', true)
        .order('name');

    final services = procedureRows.cast<Map<String, dynamic>>().map(_serviceFrom).toList();

    // Only the groups that actually have something bookable in them. A group
    // the clinic has retired every procedure from is left out rather than
    // shown as an empty heading the patient can open onto nothing.
    final usedIds = services.map((s) => s.categoryId).toSet();
    final groups = [
      for (var i = 0; i < kServiceCategories.length; i++)
        if (usedIds.contains(kServiceCategories[i].id))
          ServiceGroup(
            code: kServiceCategories[i].id,
            label: kServiceCategories[i].label,
            blurb: kServiceCategories[i].blurb,
            sortOrder: i,
          ),
    ];

    return ServiceMenu(groups: groups, services: services);
  }

  /// The clinic's own contact card. Falls back to the placeholder rather than
  /// throwing: the app is still usable without it.
  static Future<ClinicProfile> loadClinic() async {
    final row = await SupabaseService.client
        .from('clinics')
        .select('name, address, phone, hours, is_open')
        .eq('is_active', true)
        .limit(1)
        .maybeSingle();

    if (row == null) return ClinicProfile.placeholder;
    final name = _str(row['name']);
    return ClinicProfile(
      name: name.isNotEmpty ? name : ClinicProfile.placeholder.name,
      address: _str(row['address']),
      phone: _str(row['phone']),
      hours: _str(row['hours']),
      isOpen: row['is_open'] != false,
    );
  }

  static DentalService _serviceFrom(Map<String, dynamic> row) {
    final specialization = _str(row['specialization']).toLowerCase();
    final priceUnit = _str(row['price_unit']);
    final description = _str(row['description']);
    // `category` is the clinic's own label for the procedure and is set on only
    // part of the menu, so it is a description hint rather than the grouping.
    final category = _str(row['category']);

    return DentalService(
      id: _str(row['id']),
      name: _str(row['name']),
      description: description.isNotEmpty ? description : category,
      // Codes are grouped on as-is: inventing a bucket here would hide a new
      // service line the clinic adds.
      specializationCode: specialization.isEmpty ? 'general' : specialization,
      // Grouped by the procedure's name, not by anything the row carries: the
      // clinic's own `category` column holds its internal values and most rows
      // leave it null.
      categoryId: categoryIdForProcedure(_str(row['name'])),
      // Kept on the 15-minute booking grid the slot picker works in.
      durationMinutes: _roundToGrid(_int(row['duration_min']) ?? 30),
      // Much of the menu carries 0.00 as its base price because the clinic
      // quotes it at the chair; `min_rate` is the next best figure.
      price: _firstPositive([
        _double(row['base_price']),
        _double(row['min_rate']),
      ]),
      requiredSpecialization: _credentialFrom(specialization),
      priceUnit: priceUnit,
    );
  }

  /// Maps the database's short specialization codes onto the credential names
  /// the dentist roster is written in.
  static String _credentialFrom(String specialization) {
    switch (specialization) {
      case 'ortho':
      case 'tmj':
        return kOrthodontics;
      case 'restorative':
        return kProsthodontics;
      case 'surgery':
        return kOralSurgery;
      case 'esthetics':
        return kCosmeticDentistry;
      default:
        return kGeneralDentistry;
    }
  }

  static int _roundToGrid(int minutes) {
    if (minutes <= 0) return 30;
    final remainder = minutes % 15;
    return remainder == 0 ? minutes : minutes + (15 - remainder);
  }

  static double _firstPositive(List<double?> candidates) {
    for (final value in candidates) {
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  static String _str(Object? value) => value?.toString().trim() ?? '';

  static int? _int(Object? value) =>
      value is int ? value : (value is num ? value.toInt() : int.tryParse('$value'));

  static double? _double(Object? value) =>
      value is double ? value : (value is num ? value.toDouble() : double.tryParse('$value'));
}

/// Holds the loaded procedure menu for the whole app.
///
/// The booking wizard reads it through the helpers in `clinic_catalog.dart`,
/// which is why this is a singleton rather than something passed down the tree.
class ClinicCatalog extends ChangeNotifier {
  static final ClinicCatalog _instance = ClinicCatalog._internal();
  factory ClinicCatalog() => _instance;
  ClinicCatalog._internal();

  ServiceMenu _menu = ServiceMenu.empty;
  ClinicProfile _clinic = ClinicProfile.placeholder;
  bool _isLoading = false;
  String? _loadError;
  Future<void>? _inFlight;

  List<DentalService> get services => List.unmodifiable(_menu.services);

  /// The headings, in the order the clinic wants them shown.
  List<ServiceGroup> get groups => List.unmodifiable(_menu.groups);

  /// The clinic's name, address, number and opening hours.
  ClinicProfile get clinic => _clinic;

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get hasLoaded => _menu.services.isNotEmpty;

  Future<void> load({bool force = false}) {
    if (_inFlight != null && !force) return _inFlight!;
    if (hasLoaded && !force) return Future.value();
    final request = _load();
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  /// Replaces the menu without touching the network, so tests of the booking
  /// maths can run against a fixed catalog.
  @visibleForTesting
  void seedForTest(List<DentalService> services, {List<ServiceGroup> groups = const []}) {
    _menu = ServiceMenu(
      services: services,
      groups: groups.isNotEmpty
          ? groups
          : [
              for (var i = 0; i < kServiceCategories.length; i++)
                if (services.any((s) => s.categoryId == kServiceCategories[i].id))
                  ServiceGroup(
                    code: kServiceCategories[i].id,
                    label: kServiceCategories[i].label,
                    blurb: kServiceCategories[i].blurb,
                    sortOrder: i,
                  ),
            ],
    );
    _isLoading = false;
    _loadError = null;
    notifyListeners();
  }

  Future<void> _load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([ClinicApi.loadMenu(), ClinicApi.loadClinic()]);
      _menu = results[0] as ServiceMenu;
      _clinic = results[1] as ClinicProfile;
    } catch (e) {
      _loadError = 'We could not load the service menu. Check your connection and try again.';
      debugPrint('ClinicCatalog.load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
