import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/clinic_catalog.dart';
import '../data/service_categories.dart';
import '../models/dental_service.dart';
import '../models/dentist.dart';
import '../services/supabase_service.dart';

/// The procedure menu as the clinic currently offers it, with the headings it
/// is filed under.
class ServiceMenu {
  final List<ServiceGroup> groups;
  final List<DentalService> services;

  /// The clinic's specialization labels, keyed by the code
  /// `procedures.specialization` carries. Read from the `specializations`
  /// table, so the clinic can rename a service line without a new build.
  final Map<String, String> specializationLabels;

  const ServiceMenu({
    required this.groups,
    required this.services,
    this.specializationLabels = const {},
    this.servicesByGroup = const {},
  });

  /// Services per group code, in the order `booking_catalogue()` returned
  /// them. Empty when the menu was built from the tables instead.
  final Map<String, List<DentalService>> servicesByGroup;

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

/// One row of `clinic_closures`: either a dated closure or a recurring weekday,
/// all day or for a window.
class ClinicClosure {
  /// Date-only. Null for a recurring weekday closure.
  final DateTime? date;

  /// `DateTime.weekday` value. Null for a dated closure.
  final int? weekday;

  /// Minutes from midnight; both null for an all-day closure.
  final int? startMinute;
  final int? endMinute;

  const ClinicClosure({this.date, this.weekday, this.startMinute, this.endMinute});

  bool get isAllDay => startMinute == null || endMinute == null;

  bool appliesTo(DateTime day) {
    final dated = date;
    if (dated != null) {
      return dated.year == day.year && dated.month == day.month && dated.day == day.day;
    }
    return weekday == day.weekday;
  }
}

/// Opening hours from `clinic_settings` and closures from `clinic_closures`.
class ClinicSchedule {
  final int openMinute;
  final int closeMinute;
  final List<ClinicClosure> closures;

  const ClinicSchedule({
    required this.openMinute,
    required this.closeMinute,
    this.closures = const [],
  });

  /// Every weekday without a recurring all-day closure.
  Set<int> get operatingDays => {
        for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
          if (!closures.any((c) => c.date == null && c.weekday == weekday && c.isAllDay)) weekday,
      };

  bool isClosedAllDay(DateTime day) => closures.any((c) => c.isAllDay && c.appliesTo(day));

  bool overlapsClosure(DateTime day, int startMinute, int endMinute) => closures.any((c) =>
      !c.isAllDay &&
      c.appliesTo(day) &&
      startMinute < c.endMinute! &&
      c.startMinute! < endMinute);
}

/// The clinic's public reference data: the procedure menu, the service lines
/// it is grouped by, the dentist roster and the opening schedule. None of it is
/// patient-specific.
class ClinicApi {
  ClinicApi._();

  /// The bookable menu exactly as the clinic keeps it.
  ///
  /// Grouped by the clinic's own `booking_categories` when it has set them up
  /// (the same headings the web booking wizard shows), otherwise by the
  /// built-in patient-facing groups in `data/service_categories.dart`.
  ///
  /// Only active rows are offered: the clinic retires a procedure by clearing
  /// `is_active`, and a retired one must not appear in the booking wizard even
  /// though past appointments still point at it.
  static Future<ServiceMenu> loadMenu() async {
    final fromCatalogue = await _menuFromBookingCatalogue();
    if (fromCatalogue != null) return fromCatalogue;

    final client = SupabaseService.client;

    final results = await Future.wait([
      loadSpecializationLabels(),
      _loadBookingCategories(),
    ]);
    final specializationLabels = results[0] as Map<String, String>;
    final categoryRows = results[1] as List<Map<String, dynamic>>;

    final procedureRows = await client
        .from('procedures')
        .select('id, name, description, category, specialization, duration_min, '
            'base_price, min_rate, max_rate, price_unit')
        .eq('is_active', true)
        .order('name');

    if (categoryRows.isNotEmpty) {
      return _menuFromClinicCategories(
        procedureRows.cast<Map<String, dynamic>>(),
        categoryRows,
        specializationLabels,
      );
    }

    final services = procedureRows
        .cast<Map<String, dynamic>>()
        .map((row) => _serviceFrom(row, categoryIdForProcedure(_str(row['name']))))
        .toList();

    // Only the groups that actually have something bookable in them.
    final usedIds = services.map((s) => s.categoryId).toSet();
    final groups = [
      for (var i = 0; i < kServiceCategories.length; i++)
        if (usedIds.contains(kServiceCategories[i].id))
          ServiceGroup(
            code: kServiceCategories[i].id,
            label: kServiceCategories[i].label,
            blurb: kServiceCategories[i].blurb,
            sortOrder: i,
            directProcedureName: kServiceCategories[i].directProcedureName,
          ),
    ];

    return ServiceMenu(
      groups: groups,
      services: services,
      specializationLabels: specializationLabels,
    );
  }

  /// The menu from `booking_catalogue()`, the RPC the website's booking wizard
  /// reads. It returns the categories ordered by `sort_order` with each one's
  /// services already in order, so the app uses that order as returned rather
  /// than rebuilding it. Null when the RPC cannot be reached, which falls back
  /// to reading the tables.
  static Future<ServiceMenu?> _menuFromBookingCatalogue() async {
    try {
      final result = await SupabaseService.client.rpc('booking_catalogue');
      final categories = (result as List).cast<Map<String, dynamic>>();
      if (categories.isEmpty) return null;

      final labels = <String, String>{};
      final groups = <ServiceGroup>[];
      final byGroup = <String, List<DentalService>>{};
      final services = <DentalService>[];
      final seen = <String>{};

      for (var i = 0; i < categories.length; i++) {
        final category = categories[i];
        final code = _str(category['code']);
        if (code.isEmpty) continue;

        final specialization = _str(category['specialization']).toLowerCase();
        final specializationLabel = _str(category['specialization_label']);
        if (specialization.isNotEmpty && specializationLabel.isNotEmpty) {
          labels.putIfAbsent(specialization, () => specializationLabel);
        }

        final inGroup = <DentalService>[];
        for (final row in ((category['services'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          final service = _serviceFrom(row, code);
          if (service.id.isEmpty) continue;
          inGroup.add(service);
          if (seen.add(service.id)) services.add(service);
        }
        if (inGroup.isEmpty) continue;
        byGroup[code] = inGroup;

        // "Other / Not sure" has no submenu: tapping it books the Dental
        // Checkup outright, for a patient who cannot name what they need.
        final checkup = _checkupIn(inGroup);
        final isOther = code == 'checkup' ||
            _isOtherLabel(_str(category['label'])) ||
            (checkup != null && inGroup.length == 1);
        final other = serviceCategoryById(kOtherServiceCategoryId);
        final description = _str(category['description']);
        groups.add(ServiceGroup(
          code: code,
          label: isOther ? other.label : _str(category['label']),
          blurb: isOther && description.isEmpty ? other.blurb : description,
          sortOrder: i,
          directProcedureName: isOther ? (checkup ?? inGroup.first).name : '',
        ));
      }
      if (groups.isEmpty) return null;
      // "Other / Not sure" always closes the list, in whatever position it
      // came back; every other heading keeps the catalogue's order.
      final ordered = [
        ...groups.where((g) => !g.isDirectPick),
        ...groups.where((g) => g.isDirectPick),
      ];
      groups
        ..clear()
        ..addAll(ordered);

      final tableLabels = await loadSpecializationLabels();
      return ServiceMenu(
        groups: groups,
        services: services,
        servicesByGroup: byGroup,
        specializationLabels: {...labels, ...tableLabels},
      );
    } catch (e) {
      debugPrint('booking_catalogue unavailable: $e');
      return null;
    }
  }

  /// The Dental Checkup among [services], or null.
  static DentalService? _checkupIn(List<DentalService> services) {
    for (final service in services) {
      if (_sameName(service.name, kCheckupProcedureName)) return service;
    }
    return null;
  }

  static bool _isOtherLabel(String label) {
    final value = label.toLowerCase();
    return value.contains('other') || value.contains('not sure');
  }

  static bool _sameName(String a, String b) =>
      a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '') ==
      b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// The clinic's `booking_categories` with the procedures filed under each.
  /// Empty when the table is unseeded or unreadable.
  static Future<List<Map<String, dynamic>>> _loadBookingCategories() async {
    try {
      final rows = await SupabaseService.client
          .from('booking_categories')
          .select('code, label, description, sort_order, '
              'booking_category_services(procedure_id)')
          .eq('is_active', true)
          .order('sort_order');
      return rows.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('ClinicApi._loadBookingCategories failed: $e');
      return const [];
    }
  }

  static ServiceMenu _menuFromClinicCategories(
    List<Map<String, dynamic>> procedureRows,
    List<Map<String, dynamic>> categoryRows,
    Map<String, String> specializationLabels,
  ) {
    final categoryByProcedure = <String, String>{};
    for (final category in categoryRows) {
      final code = _str(category['code']);
      final links = (category['booking_category_services'] as List?) ?? const [];
      for (final link in links.cast<Map<String, dynamic>>()) {
        // A procedure filed twice stays under the first heading, in sort order.
        categoryByProcedure.putIfAbsent(_str(link['procedure_id']), () => code);
      }
    }

    final services = [
      for (final row in procedureRows)
        _serviceFrom(row, categoryByProcedure[_str(row['id'])] ?? kOtherServiceCategoryId),
    ];
    final usedIds = services.map((s) => s.categoryId).toSet();

    final groups = <ServiceGroup>[
      for (var i = 0; i < categoryRows.length; i++)
        if (usedIds.contains(_str(categoryRows[i]['code'])))
          ServiceGroup(
            code: _str(categoryRows[i]['code']),
            label: _str(categoryRows[i]['label']),
            blurb: _str(categoryRows[i]['description']),
            sortOrder: _int(categoryRows[i]['sort_order']) ?? i,
          ),
    ];

    // Anything the clinic has not filed yet still has to be bookable.
    if (usedIds.contains(kOtherServiceCategoryId) &&
        !groups.any((g) => g.code == kOtherServiceCategoryId)) {
      final other = serviceCategoryById(kOtherServiceCategoryId);
      groups.add(ServiceGroup(
        code: other.id,
        label: other.label,
        blurb: other.blurb,
        sortOrder: 1 << 20,
        directProcedureName: other.directProcedureName,
      ));
    }

    return ServiceMenu(
      groups: groups,
      services: services,
      specializationLabels: specializationLabels,
    );
  }

  /// The clinic's specialization labels, keyed by code. Empty when the table is
  /// unreadable or not seeded — callers then fall back to the built-in credential
  /// names in `data/clinic_catalog.dart`.
  static Future<Map<String, String>> loadSpecializationLabels() async {
    try {
      final rows = await SupabaseService.client
          .from('specializations')
          .select('code, label')
          .eq('is_active', true);

      return {
        for (final row in rows.cast<Map<String, dynamic>>())
          if (_str(row['code']).isNotEmpty)
            _str(row['code']).toLowerCase(): _str(row['label']),
      };
    } catch (e) {
      debugPrint('ClinicApi.loadSpecializationLabels failed: $e');
      return const {};
    }
  }

  /// The dentist roster: who the clinic has, what each one may perform, the
  /// days they hold clinic and their upcoming days off.
  ///
  /// Read through `patient_doctor_roster()` (see
  /// `docs/realtime_data_sync_migration.sql`), which can see `members` and
  /// `profiles` on the patient's behalf. Before that function is installed the
  /// tables are read directly, which works wherever RLS lets a patient read
  /// them. Returns null when the roster cannot be read at all, so the booking
  /// wizard can say so; an empty list is the clinic's real answer.
  static Future<List<Dentist>?> loadDoctors({
    Map<String, String> specializationLabels = const {},
  }) async {
    List<Map<String, dynamic>> rows;
    try {
      final result = await SupabaseService.client.rpc('patient_doctor_roster');
      rows = (result as List).cast<Map<String, dynamic>>();
    } on PostgrestException catch (e) {
      debugPrint('patient_doctor_roster unavailable (${e.message}); reading tables directly');
      try {
        rows = await _rosterFromTables();
      } catch (e) {
        debugPrint('ClinicApi.loadDoctors failed: $e');
        return null;
      }
    } catch (e) {
      debugPrint('ClinicApi.loadDoctors failed: $e');
      return null;
    }

    final dentists = rows.map((row) {
      final codes = {
        ..._codes(row['specialization_codes']),
        if (_str(row['specialization']).isNotEmpty) _str(row['specialization']).toLowerCase(),
      };
      final avatar = _str(row['avatar_url']);
      return Dentist(
        id: _str(row['id']),
        name: _str(row['full_name']),
        title: _titleFor(codes, specializationLabels),
        // Both are kept: the codes are what matching runs on, the credential
        // names are what the dentist-facing filters and copy read.
        specializationCodes: codes,
        specializations: {for (final code in codes) _credentialFrom(code)},
        procedureIds: {
          for (final id in (row['procedure_ids'] as List?) ?? const [])
            if (_str(id).isNotEmpty) _str(id),
        },
        clinicDays: _weekdays(row['clinic_days']),
        offDates: {
          for (final value in (row['off_dates'] as List?) ?? const [])
            if (_dateOnly(value) != null) _dateOnly(value)!,
        },
        avatarUrl: avatar.isEmpty ? null : avatar,
      );
    }).where((dentist) => dentist.name.isNotEmpty).toList();

    final hours = await _loadDoctorHours([for (final d in dentists) d.id]);
    return [
      for (final dentist in dentists)
        hours[dentist.id] == null ? dentist : dentist.withHours(hours[dentist.id]!),
    ];
  }

  /// Each dentist's working windows per weekday, from `patient_doctor_hours()`
  /// (docs/doctor_hours_migration.sql), or `doctor_schedules` directly where
  /// RLS lets a patient read it. Empty when neither is readable; each dentist
  /// is then taken to work the clinic's hours on their clinic days.
  static Future<Map<String, Map<int, List<DoctorHours>>>> _loadDoctorHours(
    List<String> doctorIds,
  ) async {
    if (doctorIds.isEmpty) return const {};
    List<Map<String, dynamic>> rows;
    try {
      final result = await SupabaseService.client.rpc('patient_doctor_hours');
      rows = (result as List).cast<Map<String, dynamic>>();
    } catch (e) {
      try {
        final result = await SupabaseService.client
            .from('doctor_schedules')
            .select('doctor_id, day_of_week, start_time, end_time, break_start, break_end')
            .inFilter('doctor_id', doctorIds);
        rows = result.cast<Map<String, dynamic>>();
      } catch (e) {
        debugPrint('Doctor hours unavailable: $e');
        return const {};
      }
    }

    final hours = <String, Map<int, List<DoctorHours>>>{};
    for (final row in rows) {
      final weekday = _weekdayFrom(row['day_of_week']);
      final start = _minuteOfDay(row['start_time']);
      final end = _minuteOfDay(row['end_time']);
      if (weekday == null || start == null || end == null || end <= start) continue;
      hours
          .putIfAbsent(_str(row['doctor_id']), () => {})
          .putIfAbsent(weekday, () => [])
          .add(DoctorHours(
            startMinute: start,
            endMinute: end,
            breakStartMinute: _minuteOfDay(row['break_start']),
            breakEndMinute: _minuteOfDay(row['break_end']),
          ));
    }
    return hours;
  }

  /// The roster read straight from `members`, `member_services`,
  /// `doctor_schedules` and `doctor_schedule_exceptions`, shaped like a
  /// `patient_doctor_roster()` row.
  static Future<List<Map<String, dynamic>>> _rosterFromTables() async {
    final client = SupabaseService.client;
    final members = await client
        .from('members')
        .select('id, full_name, role, status, specialization, specializations, '
            'member_services(procedure_id), doctor_schedules(day_of_week)')
        // `role` is the enum `user_role`: no pattern match, exact value only.
        .eq('role', 'doctor')
        .order('full_name');

    final active = members.cast<Map<String, dynamic>>().where((m) {
      final status = _str(m['status']).toLowerCase();
      return status.isEmpty || status == 'active';
    }).toList();

    final offByDoctor = <String, List<String>>{};
    if (active.isNotEmpty) {
      try {
        final today = DateTime.now();
        final exceptions = await client
            .from('doctor_schedule_exceptions')
            .select('doctor_id, exception_date')
            .inFilter('doctor_id', active.map((m) => _str(m['id'])).toList())
            .eq('is_off', true)
            .gte('exception_date',
                '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}');
        for (final row in exceptions.cast<Map<String, dynamic>>()) {
          offByDoctor.putIfAbsent(_str(row['doctor_id']), () => []).add(_str(row['exception_date']));
        }
      } catch (e) {
        debugPrint('doctor_schedule_exceptions unreadable: $e');
      }
    }

    return [
      for (final m in active)
        {
          'id': m['id'],
          'full_name': m['full_name'],
          'specialization': m['specialization'],
          'specialization_codes': m['specializations'],
          'clinic_days': [
            for (final s in ((m['doctor_schedules'] as List?) ?? const []).cast<Map<String, dynamic>>())
              s['day_of_week'],
          ],
          'procedure_ids': [
            for (final s in ((m['member_services'] as List?) ?? const []).cast<Map<String, dynamic>>())
              s['procedure_id'],
          ],
          'off_dates': offByDoctor[_str(m['id'])] ?? const [],
        },
    ];
  }

  /// "General Dentist · Orthodontist" — the credential line shown wherever a
  /// dentist is named. Built from the clinic's own labels when it has them.
  static String _titleFor(Set<String> codes, Map<String, String> labels) {
    final parts = <String>[];
    for (final code in codes) {
      final label = labels[code] ?? _credentialFrom(code);
      if (label.isNotEmpty && !parts.contains(label)) parts.add(label);
    }
    if (parts.isEmpty) return kGeneralDentistry;
    // A dentist covering everything would otherwise print a paragraph.
    if (parts.length > 3) return '${parts.take(3).join(' · ')} +${parts.length - 3}';
    return parts.join(' · ');
  }

  static Set<String> _codes(Object? value) {
    if (value is! List) return const {};
    return {
      for (final entry in value)
        if (_str(entry).isNotEmpty) _str(entry).toLowerCase(),
    };
  }

  /// `doctor_schedules.day_of_week` as `DateTime.weekday` values.
  ///
  /// Postgres and Dart disagree on the week: `extract(dow)` counts Sunday as 0,
  /// Dart counts Monday as 1 and Sunday as 7. A 0 therefore means Sunday.
  static Set<int> _weekdays(Object? value) {
    if (value is! List) return const {};
    final days = <int>{};
    for (final entry in value) {
      final day = _weekdayFrom(entry);
      if (day != null) days.add(day);
    }
    return days;
  }

  static int? _weekdayFrom(Object? value) {
    // `doctor_schedules.day_of_week` is the enum `weekday` ('Mon' .. 'Sun')
    // when read straight from the table.
    const names = {'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7};
    final text = _str(value).toLowerCase();
    if (text.length >= 3 && names.containsKey(text.substring(0, 3))) {
      return names[text.substring(0, 3)];
    }
    final day = value is int ? value : int.tryParse(text);
    if (day == null) return null;
    if (day == 0 || day == 7) return DateTime.sunday;
    if (day >= 1 && day <= 6) return day;
    return null;
  }

  /// The clinic's own contact card. Falls back to the placeholder rather than
  /// throwing: the app is still usable without it.
  static Future<ClinicProfile> loadClinic() async {
    final row = await SupabaseService.client
        .from('clinics')
        .select('name, address, phone, hours, is_open')
        .eq('is_active', true)
        .order('created_at')
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

  /// Opening hours and closures as the clinic set them in the admin portal.
  /// Null when unreadable, so the built-in week stays in force.
  static Future<ClinicSchedule?> loadSchedule() async {
    try {
      final client = SupabaseService.client;
      final results = await Future.wait(<Future<dynamic>>[
        client.from('clinic_settings').select('open_time, close_time').limit(1).maybeSingle(),
        client
            .from('clinic_closures')
            .select('closure_date, day_of_week, is_all_day, start_time, end_time'),
      ]);
      final settings = results[0] as Map<String, dynamic>?;
      final closureRows = (results[1] as List).cast<Map<String, dynamic>>();

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      final closures = <ClinicClosure>[];
      for (final row in closureRows) {
        final date = _dateOnly(row['closure_date']);
        // Past holidays can never affect a booking.
        if (date != null && date.isBefore(todayDate)) continue;
        final weekday = date == null ? _weekdayFrom(row['day_of_week']) : null;
        if (date == null && weekday == null) continue;
        final allDay = row['is_all_day'] != false;
        closures.add(ClinicClosure(
          date: date,
          weekday: weekday,
          startMinute: allDay ? null : _minuteOfDay(row['start_time']),
          endMinute: allDay ? null : _minuteOfDay(row['end_time']),
        ));
      }

      final open = _minuteOfDay(settings?['open_time']) ?? kClinicOpenMinute;
      final close = _minuteOfDay(settings?['close_time']) ?? kClinicCloseMinute;
      return ClinicSchedule(
        openMinute: open,
        closeMinute: close > open ? close : kClinicCloseMinute,
        closures: closures,
      );
    } catch (e) {
      debugPrint('ClinicApi.loadSchedule failed: $e');
      return null;
    }
  }

  static DentalService _serviceFrom(Map<String, dynamic> row, String categoryId) {
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
      specializationCode: specialization.isEmpty ? 'general' : specialization,
      categoryId: categoryId,
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
  static String _credentialFrom(String specialization) =>
      credentialForSpecializationCode(specialization);

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

  /// Postgres `time` (`13:30:00`) as minutes from midnight.
  static int? _minuteOfDay(Object? value) {
    final parts = _str(value).split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static DateTime? _dateOnly(Object? value) {
    final parsed = DateTime.tryParse(_str(value));
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
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
  List<Dentist> _doctors = const [];
  ClinicSchedule? _schedule;
  bool _rosterFailed = false;
  bool _isLoading = false;
  String? _loadError;
  Future<void>? _inFlight;

  List<DentalService> get services => List.unmodifiable(_menu.services);

  /// The headings, in the order the clinic wants them shown.
  List<ServiceGroup> get groups => List.unmodifiable(_menu.groups);

  /// Services per group code, in `booking_catalogue()` order. Empty when the
  /// menu came from the tables.
  Map<String, List<DentalService>> get servicesByGroup => _menu.servicesByGroup;

  /// The clinic's name, address, number and opening hours.
  ClinicProfile get clinic => _clinic;

  /// Opening hours and closures, or null before the first load.
  ClinicSchedule? get schedule => _schedule;

  /// True when the last roster load could not read the clinic's dentists at
  /// all, as opposed to reading an empty roster. The booking wizard words its
  /// empty state differently for the two.
  bool get rosterFailed => _rosterFailed;

  /// The dentist roster as the clinic keeps it. Empty until the first load, and
  /// when it is unreadable — `clinic_catalog.dart` falls back to the built-in
  /// roster in that case rather than showing none.
  List<Dentist> get doctors => List.unmodifiable(_doctors);

  /// Specialization labels by code, from the clinic's own `specializations`
  /// table. Empty when it is not seeded.
  Map<String, String> get specializationLabels =>
      Map.unmodifiable(_menu.specializationLabels);

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get hasLoaded => _menu.services.isNotEmpty;

  Future<void> load({bool force = false}) {
    if (_inFlight != null && !force) return _inFlight!;
    // An empty roster is not "loaded": every dentist name in the patient's
    // record resolves through it, so it is retried rather than kept empty.
    if (hasLoaded && _doctors.isNotEmpty && !force) return Future.value();
    final request = _load();
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  /// Replaces the menu without touching the network, so tests of the booking
  /// maths can run against a fixed catalog.
  @visibleForTesting
  void seedForTest(
    List<DentalService> services, {
    List<ServiceGroup> groups = const [],
    List<Dentist> doctors = const [],
    Map<String, String> specializationLabels = const {},
    ClinicSchedule? schedule,
    bool rosterFailed = false,
  }) {
    _doctors = List.of(doctors);
    _rosterFailed = rosterFailed;
    _schedule = schedule;
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
                    directProcedureName: kServiceCategories[i].directProcedureName,
                  ),
            ],
      specializationLabels: specializationLabels,
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
      final results = await Future.wait([
        ClinicApi.loadMenu(),
        ClinicApi.loadClinic(),
        ClinicApi.loadSchedule(),
      ]);
      _menu = results[0] as ServiceMenu;
      _clinic = results[1] as ClinicProfile;
      _schedule = results[2] as ClinicSchedule? ?? _schedule;
    } catch (e) {
      _loadError = 'We could not load the service menu. Check your connection and try again.';
      debugPrint('ClinicCatalog.load failed: $e');
    }
    // Loaded even when the menu failed: dentist names across the patient's
    // record depend on it. After the menu, so credential lines use the
    // clinic's own `specializations` labels when those loaded.
    try {
      final doctors = await ClinicApi.loadDoctors(
        specializationLabels: _menu.specializationLabels,
      );
      // A failed read keeps the roster already in hand; a successful one, even
      // an empty one, is the clinic's real answer.
      _rosterFailed = doctors == null;
      if (doctors != null) _doctors = doctors;
      debugPrint('ClinicCatalog: ${_doctors.length} dentists from patient_doctor_roster');
    } catch (e) {
      _rosterFailed = true;
      debugPrint('ClinicCatalog roster load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
