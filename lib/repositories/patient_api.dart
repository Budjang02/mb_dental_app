import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/messages.dart';
import '../data/clinic_catalog.dart';
import '../models/appointment.dart';
import '../models/notification.dart';
import '../models/patient.dart';
import '../models/patient_document.dart';
import '../models/patient_message.dart';
import '../models/payment.dart';
import '../models/treatment.dart';
import '../models/treatment_note.dart';
import '../models/wallet_transaction.dart';
import '../services/supabase_service.dart';
import 'load_state.dart';
import 'notification_feed.dart';

/// Everything the signed-in patient owns, fetched in one pass so the screens
/// can keep reading plain synchronous getters.
class PatientSnapshot {
  final Patient patient;
  final List<Appointment> appointments;
  final List<Treatment> treatments;
  final List<TreatmentPlanItem> treatmentPlan;

  /// Every plan on the chart, for the "plan created or updated" notice.
  final List<TreatmentPlanSummary> treatmentPlans;
  final List<Payment> billing;
  /// The addressed notices, and what the derived ones are checked against.
  final NotificationSources notifications;
  final List<WalletTransaction> transactions;
  final List<PatientDocument> documents;

  /// Per-tooth chart entries, keyed the way the odontogram reads them.
  final List<Map<String, String>> toothRecords;

  /// Every entry the clinic has written in `treatment_notes`, newest first —
  /// the history behind the chart, which [toothRecords] only holds the present
  /// state of. Same map shape as [toothRecords].
  /// Active `treatment_notes`, newest first. Null when they could not be
  /// read, which is not the same as having none.
  final List<TreatmentNote>? treatmentNotes;

  /// The support conversation with the clinic, oldest first.
  final List<PatientMessage> messages;
  final double walletBalance;

  /// Bills the clinic sent to be paid from the patient's account, still pending.
  final List<VisitPaymentRequest> visitRequests;

  /// False while `patients.approved_at` is null: the clinic has not approved a
  /// self-registered account yet, and the clinic's booking rules refuse it.
  final bool isApprovedForBooking;

  /// True only when [walletBalance] came back from the server on this load.
  /// False when the wallet read failed — the figure below is then stale or
  /// zero, and showing it as the patient's balance would be a lie about money.
  final bool isWalletBalanceKnown;

  /// The sections whose read failed, and why. A section missing from this map
  /// loaded successfully, so an empty list for it means the patient has no
  /// rows — not that the request went wrong.
  final Map<SyncSection, SectionStatus> failures;

  const PatientSnapshot({
    required this.patient,
    required this.appointments,
    required this.treatments,
    required this.treatmentPlan,
    required this.treatmentPlans,
    required this.billing,
    required this.notifications,
    required this.transactions,
    required this.documents,
    required this.toothRecords,
    required this.treatmentNotes,
    required this.messages,
    required this.walletBalance,
    this.visitRequests = const [],
    required this.isApprovedForBooking,
    required this.isWalletBalanceKnown,
    this.failures = const {},
  });
}

/// The outstanding plan items the Records screen lists, and the plans
/// themselves for the notification feed.
/// The Wallet page's data: the ledger, the balance and the clinic's pending
/// payment requests. [balance] is null when `wallet_balance()` could not be
/// read — the page then says so instead of adding up the rows it has.
class WalletData {
  final List<WalletTransaction> transactions;
  final double? balance;
  final List<VisitPaymentRequest> visitRequests;

  const WalletData({this.transactions = const [], this.balance, this.visitRequests = const []});
}

class TreatmentPlanData {
  final List<TreatmentPlanItem> items;
  final List<TreatmentPlanSummary> plans;

  const TreatmentPlanData({required this.items, required this.plans});
}

/// Raised when a booking is attempted before the clinic has approved the
/// account (`patients.approved_at` is null).
class PatientNotApprovedException implements Exception {
  const PatientNotApprovedException();
  @override
  String toString() => 'This account is waiting for clinic approval';
}

/// Raised when the signed-in account has no patient record behind it. The
/// clinic creates patient rows, so this means the account exists in Auth but
/// nobody has linked it to a chart yet — a real state the UI has to explain
/// rather than a crash.
class NoPatientRecordException implements Exception {
  final String message;
  const NoPatientRecordException(this.message);
  @override
  String toString() => message;
}

/// Raised when a wallet payment is refused for want of funds. Carries both
/// figures so the screen can say how much short the patient is rather than only
/// that they are short.
class InsufficientWalletBalanceException implements Exception {
  final double available;
  final double required;

  const InsufficientWalletBalanceException({
    required this.available,
    required this.required,
  });

  double get shortfall => (required - available).clamp(0, double.infinity);

  @override
  String toString() =>
      'Insufficient wallet balance: $available available, $required required';
}

/// Raised when the slot went while the patient was checking out. The wallet is
/// untouched: the whole checkout is one database transaction.
class SlotTakenException implements Exception {
  const SlotTakenException();
  @override
  String toString() => 'That time slot is no longer available';
}

/// Raised when the server-side wallet checkout function is unavailable.
///
/// A paid booking must never silently fall back to a plain appointment insert:
/// that would tell the patient payment succeeded when no wallet debit happened.
class BookingPaymentServiceUnavailableException implements Exception {
  const BookingPaymentServiceUnavailableException();

  @override
  String toString() => 'The appointment payment service is unavailable';
}

/// Raised when checkout returned without either identifier that proves the
/// server created or found the booking.
class InvalidWalletCheckoutResultException implements Exception {
  const InvalidWalletCheckoutResultException();

  @override
  String toString() => 'The payment service returned no booking confirmation';
}

/// What a completed wallet checkout returns.
class WalletCheckoutResult {
  final String appointmentId;
  final double walletBalance;
  final String referenceNo;

  /// True when the call matched an earlier one by reference and changed
  /// nothing — a retry after a dropped connection, not a second booking.
  final bool wasIdempotentReplay;

  /// The status the database stored (`Confirmed` once the down payment is
  /// paid, as `book_appointment_v5` / `v6` do). Empty when not returned.
  final String status;

  const WalletCheckoutResult({
    required this.appointmentId,
    required this.walletBalance,
    required this.referenceNo,
    this.wasIdempotentReplay = false,
    this.status = '',
  });

  /// The RPC is authoritative only when it identifies the booking it created
  /// (or replayed). Both are normally supplied; accepting either preserves
  /// compatibility with the deployed function while refusing an empty result.
  bool get hasBookingConfirmation =>
      appointmentId.trim().isNotEmpty || referenceNo.trim().isNotEmpty;
}

/// What `reschedule_my_appointment()` reports: whether a paid deposit was
/// involved (the visit is then confirmed at its new time straight away), the
/// 5% fee taken from it, and how much of the deposit still counts toward the
/// final bill.
class RescheduleResult {
  final bool paid;
  final double fee;
  final double depositCredit;

  const RescheduleResult({required this.paid, required this.fee, required this.depositCredit});
}

/// Raised when the database refuses a cancel or reschedule for a reason the
/// patient can act on ("Same-day online rescheduling is closed…"). [message]
/// is the database's own sentence, safe to show.
class AppointmentChangeRefusedException implements Exception {
  final String message;
  const AppointmentChangeRefusedException(this.message);

  @override
  String toString() => message;
}

/// The Supabase reads and writes behind [PatientRepository].
///
/// Every table here is protected by row-level security keyed on the signed-in
/// user, so the filters below are a second line of defence and a way to keep
/// the payloads small — they are not what makes the data private.
class PatientApi {
  PatientApi._();

  /// Name of the storage bucket holding patient uploads. `patient_files` rows
  /// carry the object path inside it.
  static const String filesBucket = 'patient-files';

  /// Bucket holding profile photos. Public, unlike [filesBucket].
  static const String avatarsBucket = 'avatars';

  // --- Load ---

  /// Fetches the whole record, one section at a time and one failure at a time.
  ///
  /// Every section is read independently: a section that fails contributes its
  /// reason to [PatientSnapshot.failures] and leaves its own data empty, and
  /// every other section still arrives. A single refused table can therefore no
  /// longer take the whole record — and with it every screen — down with it.
  ///
  /// The one thing that is still fatal is identity: without a patient chart
  /// there is no id to query anything else by, so that throws
  /// [NoPatientRecordException] as before.
  static Future<PatientSnapshot> loadAll() async {
    final client = SupabaseService.client;
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      throw const NoPatientRecordException('You are signed out. Please sign in again.');
    }

    final failures = <SyncSection, SectionStatus>{};

    /// Runs one section's read. A failure is recorded against the section and
    /// [fallback] stands in, so the rest of the record still loads.
    ///
    /// Deliberately not a blanket "return empty on any error": the caller can
    /// tell the two apart through [failures], and only a section absent from
    /// that map is allowed to render an empty state.
    Future<T> section<T>(
      SyncSection which,
      Future<T> Function() fetch,
      T fallback,
    ) async {
      try {
        return await runWithRetry(fetch, context: 'PatientApi.${which.name}');
      } catch (e) {
        failures[which] = classifyFailure(e, context: 'PatientApi.${which.name}');
        return fallback;
      }
    }

    // The profile row fills the gaps in the chart. It is not worth failing the
    // load over on its own, so it is a section like any other.
    final profileRow = await section<Map<String, dynamic>?>(
      SyncSection.profile,
      () => client
          .from('profiles')
          .select('id, username, full_name, first_name, last_name, email, phone, gender, '
              'birthdate, address, blood_type, marital_status, medical_history, avatar_url')
          .eq('id', userId)
          .maybeSingle(),
      null,
    );

    var patientRow = await runWithRetry(
      () => _patientRowFor(userId),
      context: 'PatientApi.patientRow',
    );

    // The clinic creates the chart on the admin web platform, and it only
    // reaches this app once `patients.profile_id` points at the account. A
    // chart entered before the patient signed up has that column null, which
    // is why an admin-created profile can be invisible here. `claim_patient_chart`
    // links the two by the account's verified email — see
    // `docs/realtime_data_sync_migration.sql`.
    if (patientRow == null) {
      final claimed = await _claimPatientChart();
      if (claimed) patientRow = await _patientRowFor(userId);
    }

    if (patientRow == null) {
      throw const NoPatientRecordException(
        'We could not find your patient record. Please contact the clinic so they '
        'can link your account to your chart.',
      );
    }

    final patientId = patientRow['id'] as String;

    // Fetched together: none of these depend on each other, so one round trip
    // beats eight sequential ones on a phone connection. Each is wrapped on its
    // own, so `Future.wait` can no longer be failed by any one of them.
    final results = await Future.wait([
      section(SyncSection.appointments, () => fetchAppointments(patientId), const <Appointment>[]),
      section(SyncSection.treatmentPlan, () => fetchTreatmentPlan(patientId),
          const TreatmentPlanData(items: [], plans: [])),
      section(SyncSection.billing, () => fetchBilling(patientId), const <Payment>[]),
      section(SyncSection.notifications, () => fetchNotificationSources(userId, patientId),
          const NotificationSources()),
      section(SyncSection.wallet, () => fetchWallet(patientId), const WalletData()),
      section(SyncSection.documents, () => fetchDocuments(patientId),
          const <PatientDocument>[]),
      section(SyncSection.chart, () => fetchToothRecords(patientId),
          const <Map<String, String>>[]),
      section(SyncSection.messages, () => fetchMessages(patientId),
          const <PatientMessage>[]),
      // The treatment history shares the chart's section: both feed the same
      // two screens, and either one failing makes that section unreliable.
      // Not a `section`: a failed read is kept apart from an empty history
      // (null here) and does not mark the chart itself as failed.
      fetchTreatmentNotes(patientId).then<List<TreatmentNote>?>((v) => v, onError: (Object e) {
        debugPrint('treatment_notes unavailable: $e');
        return null;
      }),
    ]);

    final appointments = results[0] as List<Appointment>;
    final planData = results[1] as TreatmentPlanData;
    final treatmentPlan = planData.items;
    final billing = results[2] as List<Payment>;
    final notifications = results[3] as NotificationSources;
    final wallet = results[4] as WalletData;
    final transactions = wallet.transactions;
    final documents = results[5] as List<PatientDocument>;
    final toothRecords = results[6] as List<Map<String, String>>;
    final messages = results[7] as List<PatientMessage>;
    final treatmentNotes = results[8] as List<TreatmentNote>?;

    // Only `wallet_balance()` is the balance: it sums the whole ledger on the
    // server. A sum of the rows this device loaded is not shown as one.
    final isWalletBalanceKnown =
        wallet.balance != null && !failures.containsKey(SyncSection.wallet);

    return PatientSnapshot(
      patient: _patientFrom(patientRow, profileRow),
      appointments: appointments,
      // Treatment history is the record of visits that actually happened, so
      // it is derived from completed appointments rather than stored twice.
      treatments: treatmentsFrom(appointments),
      treatmentPlan: treatmentPlan,
      treatmentPlans: planData.plans,
      billing: billing,
      notifications: notifications,
      transactions: transactions,
      documents: documents,
      toothRecords: toothRecords,
      treatmentNotes: treatmentNotes,
      messages: messages,
      walletBalance: wallet.balance ?? 0,
      visitRequests: wallet.visitRequests,
      isApprovedForBooking: patientRow['approved_at'] != null,
      isWalletBalanceKnown: isWalletBalanceKnown,
      failures: failures,
    );
  }

  /// The whole balance, from `wallet_balance()` — the function the website
  /// reads and that sums every ledger row on the server. Throws when it cannot
  /// be read, so the caller shows "unavailable" rather than a partial sum.
  static Future<double> fetchWalletBalance() async {
    final value = await SupabaseService.client.rpc('wallet_balance');
    final balance = value is num ? value.toDouble() : double.tryParse('$value');
    if (balance == null) throw StateError('wallet_balance() returned no value');
    return balance;
  }

  /// Everything the Wallet page shows: the full ledger, the balance and the
  /// clinic's pending payment requests. A balance that could not be read is
  /// null, never a sum of the rows.
  static Future<WalletData> fetchWallet(String patientId) async {
    final results = await Future.wait<Object?>([
      fetchTransactions(patientId),
      fetchWalletBalance().then<double?>((v) => v, onError: (Object e) {
        debugPrint('wallet_balance() unavailable: $e');
        return null;
      }),
      fetchVisitRequests(patientId),
    ]);
    return WalletData(
      transactions: results[0] as List<WalletTransaction>,
      balance: results[1] as double?,
      visitRequests: results[2] as List<VisitPaymentRequest>,
    );
  }

  static Future<Map<String, dynamic>?> _patientRowFor(String userId) async {
    const base = 'id, patient_code, patient_number, first_name, last_name, email, phone, '
        'gender, date_of_birth, address, blood_type, civil_status, allergies, '
        'medications, conditions, status, last_visit_at, approved_at';

    Future<Map<String, dynamic>?> run(String columns) => SupabaseService.client
        .from('patients')
        .select(columns)
        .eq('profile_id', userId)
        .maybeSingle();

    // No `wallet_balance` column: the balance is `wallet_balance()`, the sum
    // of the whole ledger on the server (see [fetchWalletBalance]).
    return run(base);
  }

  /// Asks the database to attach an unlinked chart to this account, matching on
  /// the account's verified email.
  ///
  /// Deliberately a `security definer` function rather than an update policy on
  /// `patients`: the patient must never be able to write `profile_id` itself,
  /// and the match has to be made against the email in the JWT rather than
  /// anything the client sends. Returns false when there is nothing to claim,
  /// and also when the function is not installed yet — the caller then reports
  /// the unlinked-account message as before.
  static Future<bool> _claimPatientChart() async {
    try {
      final result = await SupabaseService.client.rpc('claim_patient_chart');
      return result == true;
    } on PostgrestException catch (e) {
      // `42883 undefined_function` / `PGRST202 not found in schema cache`:
      // `docs/realtime_data_sync_migration.sql` has not been applied to this project.
      final code = pgCode(e);
      if (code == '42883' || code == 'PGRST202') {
        debugPrint('claim_patient_chart is not installed; see docs/realtime_data_sync_migration.sql');
        return false;
      }
      rethrow;
    }
  }

  // --- Row mapping ---

  static Patient _patientFrom(Map<String, dynamic> row, Map<String, dynamic>? profile) {
    // The patient chart is the clinic's copy and wins wherever it is filled in;
    // the profile is what the patient maintains themselves and fills the gaps.
    String pick(String patientKey, String profileKey) {
      final fromPatient = _str(row[patientKey]);
      if (fromPatient.isNotEmpty) return fromPatient;
      return _str(profile?[profileKey]);
    }

    final email = pick('email', 'email');
    return Patient(
      id: _str(row['id']),
      patientCode: _str(row['patient_code']).isNotEmpty
          ? _str(row['patient_code'])
          : _str(row['patient_number']),
      firstName: pick('first_name', 'first_name'),
      lastName: pick('last_name', 'last_name'),
      username: _str(profile?['username']).isNotEmpty
          ? _str(profile?['username'])
          : (email.contains('@') ? email.split('@').first : ''),
      email: email,
      phone: pick('phone', 'phone'),
      gender: _nullableStr(pick('gender', 'gender')),
      dateOfBirth: _date(row['date_of_birth']) ?? _date(profile?['birthdate']),
      avatarPath: avatarUrlFrom(_str(profile?['avatar_url'])),
      bloodType: _nullableStr(pick('blood_type', 'blood_type')),
      address: _nullableStr(pick('address', 'address')),
      maritalStatus: _nullableStr(pick('civil_status', 'marital_status')),
      medicalHistory: _nullableStr(_medicalHistoryFrom(row, profile)),
    );
  }

  /// The chart splits what the patient's own profile keeps as one free-text
  /// field, so the three clinical columns are stitched back into it.
  static String _medicalHistoryFrom(Map<String, dynamic> row, Map<String, dynamic>? profile) {
    final parts = <String>[
      if (_str(row['conditions']).isNotEmpty) 'Conditions: ${_str(row['conditions'])}',
      if (_str(row['allergies']).isNotEmpty) 'Allergies: ${_str(row['allergies'])}',
      if (_str(row['medications']).isNotEmpty) 'Medications: ${_str(row['medications'])}',
    ];
    if (parts.isNotEmpty) return parts.join('\n');
    return _str(profile?['medical_history']);
  }

  /// Every column [_appointmentFrom] reads, shared by the list and the
  /// single-appointment fetch so the two can never map a booking differently.
  static const String _appointmentColumns =
      'id, appointment_date, appointment_time, status, notes, payment_method, '
      'cancellation_reason, cancelled_by, cancelled_by_id, reschedule_fee_total, '
      'procedure_id, doctor_id, confirmation_code, qr_token, '
      'estimated_total, downpayment_amount, downpayment_paid_at, '
      'created_at, confirmed_at, cancelled_at, arrived_at, booked_by, '
      'procedure:procedures!appointments_procedure_id_fkey(name, duration_min, base_price), '
      // `doctor_id` points at `members` (clinic staff); `created_by`
      // is the one that points at `profiles`. Embedding plain
      // `profiles` here silently resolved to whoever booked the visit
      // instead of the dentist seeing the patient.
      'doctor:members!appointments_doctor_id_fkey(full_name), '
      'appointment_services(procedure_id, procedures(name, duration_min, base_price))';

  static Future<List<Appointment>> fetchAppointments(String patientId) async {
    final rows = await SupabaseService.client
        .from('appointments')
        .select(_appointmentColumns)
        .eq('patient_id', patientId)
        // The clinic archives a booking to take it off every list; the web
        // portal hides those, so the app does too.
        .isFilter('archived_at', null)
        .order('appointment_date', ascending: false)
        .order('appointment_time', ascending: false);

    return rows.map<Appointment>(_appointmentFrom).toList();
  }

  /// One of the patient's appointments, looked up by its id or by the
  /// confirmation code printed on it. Null when neither matches a row this
  /// session may read — row-level security answers a stranger's id with no
  /// rows, not an error.
  static Future<Appointment?> fetchAppointment(String patientId, String idOrCode) async {
    final key = idOrCode.trim();
    if (key.isEmpty) return null;
    final looksLikeId = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(key);

    final row = await SupabaseService.client
        .from('appointments')
        .select(_appointmentColumns)
        .eq('patient_id', patientId)
        .eq(looksLikeId ? 'id' : 'confirmation_code', key)
        .limit(1)
        .maybeSingle();

    return row == null ? null : _appointmentFrom(row);
  }

  static Appointment _appointmentFrom(Map<String, dynamic> row) {
    // A booking names its procedure either directly or through the join table
    // when the visit covers several. Both shapes have to fold into one list.
    final linked = (row['appointment_services'] as List?) ?? const [];
    final procedures = <Map<String, dynamic>>[];
    final serviceIds = <String>[];

    final direct = row['procedure'] as Map<String, dynamic>?;
    if (direct != null) {
      procedures.add(direct);
      final id = _nullableStr(_str(row['procedure_id']));
      if (id != null) serviceIds.add(id);
    }
    for (final entry in linked.cast<Map<String, dynamic>>()) {
      final procedure = entry['procedures'] as Map<String, dynamic>?;
      final id = _nullableStr(_str(entry['procedure_id']));
      // Guards the common case where the join table repeats the direct one.
      if (id != null && serviceIds.contains(id)) continue;
      if (procedure != null) procedures.add(procedure);
      if (id != null) serviceIds.add(id);
    }

    final names = procedures.map((p) => _str(p['name'])).where((n) => n.isNotEmpty).toList();
    final duration = procedures.fold<int>(
      0,
      (sum, p) => sum + (_int(p['duration_min']) ?? 0),
    );
    final summed = procedures.fold<double>(0, (sum, p) => sum + (_double(p['base_price']) ?? 0));
    // The clinic's own estimate wins: base prices are 0.00 on much of the menu.
    final estimated = _double(row['estimated_total']) ?? 0;
    final total = estimated > 0 ? estimated : summed;
    final paid = row['downpayment_paid_at'] != null ? (_double(row['downpayment_amount']) ?? 0) : 0.0;

    final doctor = row['doctor'] as Map<String, dynamic>?;

    return Appointment(
      id: _str(row['id']),
      serviceName: names.isEmpty ? 'Appointment' : names.join(', '),
      doctorName: _assignedDoctorName(doctor, row['doctor_id']),
      date: _date(row['appointment_date']) ?? DateTime.now(),
      timeSlot: _timeSlotFrom(row['appointment_time']),
      status: _statusFrom(_str(row['status'])),
      notes: _nullableStr(_str(row['notes'])),
      paymentMethod: _nullableStr(_str(row['payment_method'])),
      cancellationReason: _nullableStr(_str(row['cancellation_reason'])),
      serviceIds: serviceIds,
      durationMinutes: duration > 0 ? duration : 60,
      totalPrice: total,
      amountPaid: paid,
      confirmationCode: _nullableStr(_str(row['confirmation_code'])),
      qrToken: Appointment.normaliseQrToken(_str(row['qr_token'])),
      cancelledBy: _nullableStr(_str(row['cancelled_by'])),
      cancelledById: _nullableStr(_str(row['cancelled_by_id'])),
      rescheduleFeeTotal: _double(row['reschedule_fee_total']) ?? 0,
      downpaymentAmount: _double(row['downpayment_amount']) ?? 0,
      downpaymentPaidAt: _date(row['downpayment_paid_at']),
      doctorId: _nullableStr(_str(row['doctor_id'])),
      createdAt: _date(row['created_at']),
      statusChangedAt: _statusChangedAt(row),
      // Raw, untrimmed and unparsed: notice keys shared with the website are
      // built from these strings exactly as PostgREST returns them.
      rawDate: row['appointment_date']?.toString() ?? '',
      rawTime: row['appointment_time']?.toString() ?? '',
      rawStatus: row['status']?.toString() ?? '',
      isSelfBooked: _isSelfBooked(row),
    );
  }

  static List<Treatment> treatmentsFrom(List<Appointment> appointments) {
    return appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .map((a) => Treatment(
              id: a.id,
              procedure: a.serviceName,
              doctorName: a.doctorName,
              date: a.date,
              notes: a.notes ?? '',
            ))
        .toList();
  }

  static Future<TreatmentPlanData> fetchTreatmentPlan(String patientId) async {
    final rows = await SupabaseService.client
        .from('treatment_plans')
        .select('id, title, diagnosis, notes, status, created_at, updated_at, doctor_id, '
            'doctor:members!treatment_plans_doctor_id_fkey(full_name), '
            'treatment_plan_items(id, description, estimated_cost, status, sort_order, '
            'completed_at, procedures(name))')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

    final items = <TreatmentPlanItem>[];
    final plans = <TreatmentPlanSummary>[];
    for (final plan in rows.cast<Map<String, dynamic>>()) {
      // Only work still outstanding belongs on the plan; anything the clinic
      // has carried out shows up under treatment history instead.
      // Every plan raises its notice, including one already completed. The
      // stamp is the raw column text: the website keys on the same string.
      final createdAt = plan['created_at']?.toString() ?? '';
      final updatedAt = plan['updated_at']?.toString();
      final stamp = updatedAt ?? createdAt;
      plans.add(TreatmentPlanSummary(
        id: plan['id']?.toString() ?? '',
        title: _str(plan['title']),
        status: plan['status']?.toString() ?? '',
        stamp: stamp,
        wasUpdated: updatedAt != null && updatedAt != createdAt,
        updatedAt: _date(updatedAt),
        changedAt: _date(stamp) ?? DateTime.now(),
      ));

      if (_str(plan['status']).toLowerCase() == 'completed') continue;

      final doctorName = _doctorOf(plan);
      final planned = (plan['treatment_plan_items'] as List?) ?? const [];
      final sorted = planned.cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => (_int(a['sort_order']) ?? 0).compareTo(_int(b['sort_order']) ?? 0));

      for (final item in sorted) {
        if (item['completed_at'] != null) continue;
        if (_str(item['status']).toLowerCase() == 'completed') continue;

        final procedure = item['procedures'] as Map<String, dynamic>?;
        final name = _str(procedure?['name']);
        items.add(TreatmentPlanItem(
          id: _str(item['id']),
          procedure: name.isNotEmpty ? name : _str(item['description']),
          toothLabel: _str(plan['diagnosis']),
          doctorName: doctorName,
          plannedFor: _date(plan['created_at']),
          estimatedCost: _double(item['estimated_cost']) ?? 0,
          notes: _str(plan['notes']),
        ));
      }
    }
    return TreatmentPlanData(items: items, plans: plans);
  }

  /// The patient's statement, assembled the way the clinic's portal keeps it.
  ///
  /// `billing_records` is where the front desk bills (one row per charge,
  /// voided rows excluded). `invoices` carry the statement number, matched to a
  /// charge through `invoice_items.billing_record_id`, and `payment_receipts`
  /// carry the receipt number once a charge is paid. The older `billing` table
  /// is still read for charges the portal never re-recorded, so nothing billed
  /// before the move disappears from the patient's history.
  static Future<List<Payment>> fetchBilling(String patientId) async {
    const cols = 'id, billed_on, procedure_name, amount, status, payment_method, voided_at, '
        'appointment_id, created_at';
    const doctor = ', members!doctor_id(full_name)';
    // Through receipt_items, not payment_receipts.billing_record_id: a receipt
    // covering a whole visit leaves that column null.
    const receipts = ', receipt_items(payment_receipts(id, reference_no, issued_at))';
    const receiptsOld = ', payment_receipts(id, reference_no, issued_at)';
    const invoices = ', invoice_items(invoice_id, invoices(id, invoice_no))';

    Future<List<Map<String, dynamic>>> run(String select) async => (await SupabaseService.client
            .from('billing_records')
            .select(select)
            .eq('patient_id', patientId)
            .order('billed_on', ascending: false))
        .cast<Map<String, dynamic>>();

    // Each document table arrives with its own migration; a database without
    // one loses that reference, not the whole list.
    final attempts = [
      cols + doctor + receipts + invoices,
      cols + receipts + invoices,
      cols + receiptsOld + invoices,
      cols + receiptsOld,
      cols,
    ];
    List<Map<String, dynamic>>? rows;
    for (final select in attempts) {
      try {
        rows = await run(select);
        break;
      } on PostgrestException catch (e) {
        if (select == attempts.last || !_missingSchema.hasMatch(e.message)) rethrow;
      }
    }
    return [for (final row in rows ?? const <Map<String, dynamic>>[]) _chargeFrom(row)];
  }

  static Payment _chargeFrom(Map<String, dynamic> row) {
    Map<String, dynamic>? first(Object? v) {
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is List && v.isNotEmpty && v.first is Map) return Map<String, dynamic>.from(v.first as Map);
      return null;
    }

    final receiptItem = first(row['receipt_items']);
    final receipt = receiptItem != null ? first(receiptItem['payment_receipts']) : first(row['payment_receipts']);
    final invoiceItem = first(row['invoice_items']);
    final invoice = invoiceItem == null ? null : first(invoiceItem['invoices']);
    final member = first(row['members']);
    final id = _str(row['id']);
    final invoiceNo = _str(invoice?['invoice_no']);
    final receiptNo = _str(receipt?['reference_no']);
    final name = _str(row['procedure_name']);
    return Payment(
      id: id,
      referenceNo: invoiceNo.isNotEmpty ? invoiceNo : (receiptNo.isNotEmpty ? receiptNo : id),
      invoiceNo: invoiceNo,
      invoiceId: _nullableStr(_str(invoice?['id']).isNotEmpty ? _str(invoice?['id']) : _str(invoiceItem?['invoice_id'])),
      receiptNo: _nullableStr(receiptNo),
      receiptId: _nullableStr(_str(receipt?['id'])),
      receiptIssuedAt: _date(receipt?['issued_at']),
      procedureName: name.isEmpty ? 'Charge' : name,
      doctorName: _str(member?['full_name']),
      amount: _double(row['amount']) ?? 0,
      billedOn: _date(row['billed_on']) ?? _date(row['created_at']) ?? DateTime.now(),
      status: _str(row['status']).isEmpty ? 'Unpaid' : _str(row['status']),
      paymentMethod: _nullableStr(_str(row['payment_method'])),
      voidedAt: _date(row['voided_at']),
      appointmentId: _nullableStr(_str(row['appointment_id'])),
    );
  }

  /// Rows from a secondary source, or none when it cannot be read. Used for
  /// tables that add detail to a screen but must never fail the whole load.
  static Future<List<Map<String, dynamic>>> _optionalRows(
    Future<List<Map<String, dynamic>>> Function() query,
  ) async {
    try {
      return (await query()).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('PatientApi optional read failed: $e');
      return const [];
    }
  }

  /// Everything the bell is built from besides the record itself, fetched as
  /// one section. See [NotificationFeed] for the rules.
  static Future<NotificationSources> fetchNotificationSources(
    String userId,
    String patientId,
  ) async {
    final results = await Future.wait([
      fetchNotifications(userId),
      _fetchCoveredNotices(),
      _fetchReceiptNotices(patientId),
    ]);
    return NotificationSources(
      addressed: results[0] as List<NotificationItem>,
      covered: results[1] as Set<String>,
      receipts: results[2] as List<ReceiptNotice>,
    );
  }

  static const String _notificationColumns =
      'id, actor_name, actor_role, event, title, body, entity, entity_id, read_at, created_at';

  /// `notifications` rows addressed to this account: the newest
  /// [NotificationFeed.addressedLimit] plus every unread one, once each — the
  /// website's `loadDbNotifs`. The unread query is what keeps the count right
  /// when there are more unread rows than one page holds.
  static Future<List<NotificationItem>> fetchNotifications(String userId) async {
    Future<List<Map<String, dynamic>>> recent() async => (await SupabaseService.client
            .from('notifications')
            .select(_notificationColumns)
            .eq('recipient_id', userId)
            .order('created_at', ascending: false)
            .limit(NotificationFeed.addressedLimit))
        .cast<Map<String, dynamic>>();

    Future<List<Map<String, dynamic>>> unread() async {
      try {
        return (await SupabaseService.client
                .from('notifications')
                .select(_notificationColumns)
                .eq('recipient_id', userId)
                .isFilter('read_at', null)
                .order('created_at', ascending: false)
                .limit(1000))
            .cast<Map<String, dynamic>>();
      } catch (e) {
        // Costs the older unread rows, not the whole feed.
        debugPrint('Unread notifications unavailable: $e');
        return const [];
      }
    }

    final pages = await Future.wait([recent(), unread()]);
    final byId = <String, Map<String, dynamic>>{};
    for (final row in [...pages[0], ...pages[1]]) {
      byId.putIfAbsent(_str(row['id']), () => row);
    }
    return [for (final row in byId.values) _addressedNotice(row)];
  }

  static NotificationItem _addressedNotice(Map<String, dynamic> row) {
    final event = _str(row['event']);
    final title = _str(row['title']);
    final actor = _str(row['actor_name']).trim();
    final readAt = _date(row['read_at']);
    return NotificationItem(
      id: 'db|${_str(row['id'])}',
      title: title.isEmpty ? 'Notification' : title,
      body: _str(row['body']),
      createdAt: _date(row['created_at']) ?? DateTime.now(),
      isRead: readAt != null,
      readAt: readAt,
      event: event,
      actorName: actor.isEmpty ? null : actor,
      category: NotificationFeed.categoryOf(event),
      target: NotificationFeed.targetOf(
        event: event,
        entity: _str(row['entity']),
        entityId: _str(row['entity_id']),
      ),
    );
  }

  /// `<event>|<entity id>` for every addressed row that restates a derived
  /// notice. Empty on failure, which keeps both notices rather than losing one.
  static Future<Set<String>> _fetchCoveredNotices() async {
    try {
      final rows = await SupabaseService.client
          .from('notifications')
          .select('event, entity_id')
          .inFilter('event', NotificationFeed.coverEvents)
          .limit(1000);
      return {
        for (final row in rows.cast<Map<String, dynamic>>())
          if (_str(row['event']).isNotEmpty && _str(row['entity_id']).isNotEmpty)
            '${_str(row['event'])}|${_str(row['entity_id'])}',
      };
    } catch (e) {
      debugPrint('Notification duplicate check unavailable: $e');
      return const {};
    }
  }

  /// The newest receipts, read the way the website's receipt notices are.
  static Future<List<ReceiptNotice>> _fetchReceiptNotices(String patientId) async {
    try {
      final rows = await SupabaseService.client
          .from('payment_receipts')
          .select('id, reference_no, procedure_name, amount_due, payment_method, issued_at')
          .eq('patient_id', patientId)
          .order('issued_at', ascending: false)
          .limit(NotificationFeed.maxReceipts);
      return [
        for (final row in rows.cast<Map<String, dynamic>>())
          ReceiptNotice(
            id: _str(row['id']),
            referenceNo: _str(row['reference_no']),
            procedureName: _str(row['procedure_name']),
            amountDue: _double(row['amount_due']) ?? 0,
            paymentMethod: _str(row['payment_method']),
            issuedAt: _date(row['issued_at']) ?? DateTime.now(),
          ),
      ];
    } catch (e) {
      debugPrint('Receipt notices unavailable: $e');
      return const [];
    }
  }

  // --- Read, dismissed and settings state ---
  //
  // `notification_state` and `notification_prefs` are the record; the device
  // keeps a cache of what it wrote. The cache is what paints a tap at once and
  // what survives a write that could not reach the server: every sync sends up
  // whatever the server does not have yet, so a read made offline lands the
  // next time the app is online.

  /// What this account has read or dismissed, keyed by notice key. Sends up
  /// any read or dismissal this device made that has not reached the server.
  static Future<Map<String, NotificationState>> fetchNotificationState(String userId) async {
    final localRead = <String>{};
    final localGone = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      localRead.addAll((prefs.getStringList(_localReadKey(userId)) ?? const []).where(_isSharedKey));
      localGone.addAll((prefs.getStringList(_localDismissedKey(userId)) ?? const []).where(_isSharedKey));
    } catch (e) {
      debugPrint('Local notification state unreadable: $e');
    }

    final state = <String, NotificationState>{};
    var serverAnswered = false;
    try {
      final rows = await SupabaseService.client
          .from('notification_state')
          .select('notif_key, read_at, dismissed_at')
          .eq('user_id', userId);
      for (final row in rows.cast<Map<String, dynamic>>()) {
        state[_str(row['notif_key'])] = NotificationState(
          readAt: _date(row['read_at']),
          dismissedAt: _date(row['dismissed_at']),
        );
      }
      serverAnswered = true;
    } catch (e) {
      debugPrint('notification_state unreadable: $e');
    }

    // Anything this device did that the account does not know yet.
    final unsentGone = localGone.where((k) => !(state[k]?.isDismissed ?? false)).toList();
    final unsentRead = localRead
        .where((k) => !(state[k]?.isRead ?? false) && !unsentGone.contains(k))
        .toList();
    if (serverAnswered) {
      if (unsentGone.isNotEmpty) await _sendNoticeState(unsentGone, dismiss: true);
      if (unsentRead.isNotEmpty) await _sendNoticeState(unsentRead, dismiss: false);
    }

    // The device's own writes count until the server has them.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final key in localRead) {
      final saved = state[key];
      if (saved?.isRead ?? false) continue;
      state[key] = NotificationState(readAt: epoch, dismissedAt: saved?.dismissedAt);
    }
    for (final key in localGone) {
      final saved = state[key];
      if (saved?.isDismissed ?? false) continue;
      state[key] = NotificationState(readAt: saved?.readAt ?? epoch, dismissedAt: epoch);
    }
    return state;
  }

  /// Marks notice [keys] read for this account, as the website does: the
  /// shared key through `notif_mark_read`, and an addressed row's own
  /// `read_at` through `notif_mark_read_ids`. Cached first, so a failed write
  /// is retried by the next [fetchNotificationState]. Never throws.
  static Future<bool> markNoticesRead(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, dismiss: false);

  /// Dismisses notice [keys] through `notif_dismiss`, which also marks them
  /// read. Never throws.
  static Future<bool> dismissNotices(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, dismiss: true);

  static Future<bool> _writeNoticeState(
    String userId,
    Iterable<String> keys, {
    required bool dismiss,
  }) async {
    final list = keys.where(_isSharedKey).toSet().toList();
    if (list.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final read = {...?prefs.getStringList(_localReadKey(userId)), ...list};
      await prefs.setStringList(_localReadKey(userId), read.toList());
      if (dismiss) {
        final gone = {...?prefs.getStringList(_localDismissedKey(userId)), ...list};
        await prefs.setStringList(_localDismissedKey(userId), gone.toList());
      }
    } catch (e) {
      debugPrint('Local notification state not saved: $e');
    }
    return _sendNoticeState(list, dismiss: dismiss);
  }

  static Future<bool> _sendNoticeState(List<String> keys, {required bool dismiss}) async {
    final rowIds = [
      for (final k in keys)
        if (k.startsWith('db|')) k.substring(3),
    ];
    var ok = true;
    if (rowIds.isNotEmpty) {
      try {
        await SupabaseService.client.rpc('notif_mark_read_ids', params: {'p_ids': rowIds});
      } catch (e) {
        ok = false;
        debugPrint('notif_mark_read_ids failed: $e');
      }
    }
    final rpc = dismiss ? 'notif_dismiss' : 'notif_mark_read';
    try {
      await SupabaseService.client.rpc(rpc, params: {'p_keys': keys});
    } catch (e) {
      ok = false;
      debugPrint('$rpc failed: $e');
    }
    return ok;
  }

  /// Keys the website shares. Older builds of the app cached `local:` keys for
  /// notices only the app had; those never go to the server.
  static bool _isSharedKey(String key) => key.isNotEmpty && !key.startsWith('local:');

  static String _localReadKey(String userId) => 'mbNotifRead_app_v2_$userId';
  static String _localDismissedKey(String userId) => 'mbNotifGone_app_v2_$userId';
  static String _localPrefsKey(String userId) => 'mbNotifPrefs_app_$userId';
  static String _localPrefsDirtyKey(String userId) => 'mbNotifPrefsDirty_app_$userId';

  /// The account's Settings → Notifications switches, shared with the website.
  /// A change this device could not send yet is sent now instead of being
  /// overwritten. Falls back to the device's copy (all on by default) when the
  /// table is not there yet.
  static Future<NotificationPrefs> fetchNotificationPrefs(String userId) async {
    SharedPreferences? prefs;
    var local = const NotificationPrefs();
    var dirty = false;
    try {
      prefs = await SharedPreferences.getInstance();
      local = _prefsFrom(prefs.getStringList(_localPrefsKey(userId))) ?? local;
      dirty = prefs.getBool(_localPrefsDirtyKey(userId)) ?? false;
    } catch (e) {
      debugPrint('Local notification settings unreadable: $e');
    }
    if (dirty) {
      await _sendPrefs(userId, local, prefs);
      return local;
    }
    try {
      final row = await SupabaseService.client
          .from('notification_prefs')
          .select('enabled, cat_appointment, cat_plan, cat_billing')
          .eq('user_id', userId)
          .maybeSingle();
      final server = NotificationPrefs(
        enabled: row?['enabled'] != false,
        appointment: row?['cat_appointment'] != false,
        plan: row?['cat_plan'] != false,
        billing: row?['cat_billing'] != false,
      );
      await prefs?.setStringList(_localPrefsKey(userId), _prefsTo(server));
      return server;
    } catch (e) {
      debugPrint('notification_prefs unreadable: $e');
      return local;
    }
  }

  /// Saves the switches on the device at once and on the account when it can.
  static Future<bool> saveNotificationPrefs(String userId, NotificationPrefs value) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_localPrefsKey(userId), _prefsTo(value));
      await prefs.setBool(_localPrefsDirtyKey(userId), true);
    } catch (e) {
      debugPrint('Local notification settings not saved: $e');
    }
    return _sendPrefs(userId, value, prefs);
  }

  static Future<bool> _sendPrefs(
    String userId,
    NotificationPrefs value,
    SharedPreferences? prefs,
  ) async {
    try {
      await SupabaseService.client.from('notification_prefs').upsert({
        'user_id': userId,
        'enabled': value.enabled,
        'cat_appointment': value.appointment,
        'cat_plan': value.plan,
        'cat_billing': value.billing,
      }, onConflict: 'user_id');
      await prefs?.setBool(_localPrefsDirtyKey(userId), false);
      return true;
    } catch (e) {
      debugPrint('notification_prefs not saved: $e');
      return false;
    }
  }

  static List<String> _prefsTo(NotificationPrefs p) => [
        if (!p.enabled) 'off',
        if (!p.appointment) 'appointment',
        if (!p.plan) 'plan',
        if (!p.billing) 'billing',
      ];

  static NotificationPrefs? _prefsFrom(List<String>? off) => off == null
      ? null
      : NotificationPrefs(
          enabled: !off.contains('off'),
          appointment: !off.contains('appointment'),
          plan: !off.contains('plan'),
          billing: !off.contains('billing'),
        );

  /// The Postgres error code behind [e].
  ///
  /// `PostgrestException.code` is the HTTP status for anything Postgres itself
  /// raised — a `42703` or a `raise ... using errcode` arrives as `400` with the
  /// real code inside the JSON message. PostgREST's own errors (`PGRST202`,
  /// `PGRST205`) do land in `code`. Both shapes have to be read, or a fallback
  /// meant for a missing column swallows nothing and the whole load fails.
  static String pgCode(PostgrestException e) {
    final match = RegExp(r'"code"\s*:\s*"([^"]+)"').firstMatch(e.message);
    if (match != null) return match.group(1)!;
    return e.code ?? '';
  }

  /// True when the last wallet read found no ledger table or balance function
  /// on this database yet. The wallet then shows as empty with a short note
  /// instead of an error.
  static bool walletUnavailable = false;

  static final RegExp _missingSchema =
      RegExp(r'schema cache|does not exist|relationship|function', caseSensitive: false);

  /// Rows per ledger request, and the most this device reads. The website
  /// shows its first 50; the app reads on until the ledger ends, so every date
  /// range filters the whole history. The balance never comes from these rows.
  static const int _ledgerPage = 500;
  static const int _ledgerMax = 5000;

  static Future<List<WalletTransaction>> fetchTransactions(String patientId) async {
    final rows = <Map<String, dynamic>>[];
    try {
      while (rows.length < _ledgerMax) {
        final page = await SupabaseService.client
            .from('wallet_transactions')
            .select('id, direction, amount, method, description, reference_no, billing_record_id, created_at')
            .eq('patient_id', patientId)
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(rows.length, rows.length + _ledgerPage - 1);
        rows.addAll(page.cast<Map<String, dynamic>>());
        if (page.length < _ledgerPage) break;
      }
      walletUnavailable = false;
    } on PostgrestException catch (e) {
      if (!_missingSchema.hasMatch(e.message)) rethrow;
      walletUnavailable = true;
      return const [];
    }

    return rows.map((row) {
      final type = _transactionTypeFrom(_str(row['direction']));
      final description = _str(row['description']);
      return WalletTransaction(
        id: _str(row['id']),
        title: description.isNotEmpty
            ? description
            : (type == TransactionType.credit ? 'Wallet Top-up' : 'Payment'),
        subtitle: type == TransactionType.credit ? 'Top-up' : 'Payment',
        amount: (_double(row['amount']) ?? 0).abs(),
        type: type,
        icon: type == TransactionType.credit
            ? CupertinoIcons.creditcard
            : CupertinoIcons.sparkles,
        dateTime: _date(row['created_at']) ?? DateTime.now(),
        referenceNo: _str(row['reference_no']),
        method: _str(row['method']),
        description: description,
      );
    }).toList();
  }

  // --- Payments from the wallet and the clinic's requests ---

  /// Pending bills the clinic sent to the patient's account, newest first —
  /// the website's `loadVisitPayRequests`. Empty on a database without them.
  static Future<List<VisitPaymentRequest>> fetchVisitRequests(String patientId) async {
    Future<List<Map<String, dynamic>>> run(String cols) async => (await SupabaseService.client
            .from('visit_payment_requests')
            .select(cols)
            .eq('patient_id', patientId)
            .eq('status', 'pending')
            .order('created_at', ascending: false))
        .cast<Map<String, dynamic>>();
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await run(_visitRequestCols);
      } on PostgrestException {
        // `breakdown` arrives with 20261022000001; without it the requests are
        // still listed, just not itemised.
        rows = await run(_visitRequestColsBasic);
      }
      return rows.map(_visitRequestFrom).toList();
    } catch (e) {
      debugPrint('visit_payment_requests unavailable: $e');
      return const [];
    }
  }

  static const _visitRequestCols =
      'id, amount, status, created_at, appointment_id, breakdown, appointments(appointment_date)';
  static const _visitRequestColsBasic =
      'id, amount, status, created_at, appointment_id, appointments(appointment_date)';

  /// One request by id, whatever its status, so a link or notice to a paid or
  /// withdrawn one can say so. Null when it is not this patient's.
  static Future<VisitPaymentRequest?> fetchVisitRequest(String id) async {
    Future<Map<String, dynamic>?> run(String cols) =>
        SupabaseService.client.from('visit_payment_requests').select(cols).eq('id', id).maybeSingle();
    Map<String, dynamic>? row;
    try {
      row = await run(_visitRequestCols);
    } on PostgrestException {
      row = await run(_visitRequestColsBasic);
    }
    return row == null ? null : _visitRequestFrom(row);
  }

  /// The pending request for a visit — what the clinic's Wallet QR carries
  /// (`?vpa=<appointment id>`). Null when none has been sent, or it is paid.
  static Future<String?> pendingVisitRequestFor(String appointmentId, String patientId) async {
    final rows = await SupabaseService.client
        .from('visit_payment_requests')
        .select('id')
        .eq('appointment_id', appointmentId)
        .eq('patient_id', patientId)
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : _str(rows.first['id']);
  }

  static VisitPaymentRequest _visitRequestFrom(Map<String, dynamic> row) {
    final appt = row['appointments'];
    final visit = appt is Map ? appt : (appt is List && appt.isNotEmpty ? appt.first : null);
    final breakdown = row['breakdown'];
    return VisitPaymentRequest(
      id: _str(row['id']),
      amount: _double(row['amount']) ?? 0,
      status: _str(row['status']),
      createdAt: _date(row['created_at']) ?? DateTime.now(),
      appointmentId: _nullableStr(_str(row['appointment_id'])),
      visitDate: visit is Map ? _str(visit['appointment_date']) : '',
      breakdown: breakdown is Map ? Map<String, dynamic>.from(breakdown) : null,
    );
  }

  /// One charge's current state, read again right before paying it so a
  /// charge settled or voided elsewhere is not paid twice.
  static Future<Payment?> fetchCharge(String billId) async {
    final row = await SupabaseService.client
        .from('billing_records')
        .select('id, billed_on, procedure_name, amount, status, payment_method, voided_at, appointment_id')
        .eq('id', billId)
        .maybeSingle();
    return row == null ? null : _chargeFrom(row);
  }

  /// Settles one charge from the balance through `wallet_pay_bill` — the
  /// website's call. It pays the charge, debits the wallet and issues the
  /// receipt together, or does none of it.
  static Future<void> payBillWithWallet(String billId) async {
    await SupabaseService.client.rpc('wallet_pay_bill', params: {'p_bill_id': billId});
  }

  /// Pays a clinic request from the balance through `wallet_pay_visit_request`.
  static Future<void> payVisitRequestWithWallet(String requestId) async {
    await SupabaseService.client.rpc('wallet_pay_visit_request', params: {'p_request_id': requestId});
  }

  /// The per-tooth chart entries behind the odontogram and the Treatment Notes
  /// page. Shaped as the string maps those screens already read, so the chart's
  /// rendering did not have to change to take real data.
  ///
  /// `dental_records` is the chart the website draws: one row per tooth,
  /// holding its condition now. `tooth_records` is the older per-entry log, and
  /// reading it painted teeth with conditions the clinic had since changed or
  /// cleared. The log is only used when the current chart cannot be read or has
  /// nothing for this patient.
  static Future<List<Map<String, String>>> fetchToothRecords(String patientId) async {
    final current = await _optionalRows(() => SupabaseService.client
        .from('dental_records')
        .select('id, tooth_id, condition, notes, updated_at, updated_by, '
            'doctor:profiles!dental_records_updated_by_fkey(full_name, first_name, last_name)')
        .eq('patient_id', patientId)
        .order('updated_at', ascending: false, nullsFirst: false));
    if (current.isNotEmpty) {
      return current.map((row) {
        final recordedOn = _date(row['updated_at']);
        final condition = _str(row['condition']);
        return <String, String>{
          'date': recordedOn == null ? '' : _dateLabel(recordedOn),
          'tooth': _toothLabelFrom(_str(row['tooth_id'])),
          'condition': condition,
          'procedure': condition,
          'notes': _str(row['notes']),
          'doctor': _doctorOf(row),
        };
      }).toList();
    }

    final rows = await SupabaseService.client
        .from('tooth_records')
        .select('id, tooth_id, condition, notes, doctor_id, created_at, updated_at, '
            'doctor:members!tooth_records_doctor_id_fkey(full_name)')
        .eq('patient_id', patientId)
        // Newest edit first: the chart keeps the first row it meets per tooth,
        // and a row the clinic re-edited is the current one.
        .order('updated_at', ascending: false, nullsFirst: false)
        .order('created_at', ascending: false);

    return rows.cast<Map<String, dynamic>>().map((row) {
      final recordedOn = _date(row['updated_at']) ?? _date(row['created_at']);
      final condition = _str(row['condition']);
      return <String, String>{
        'date': recordedOn == null ? '' : _dateLabel(recordedOn),
        'tooth': _toothLabelFrom(_str(row['tooth_id'])),
        'condition': condition,
        // The chart has no separate procedure column, so the condition doubles
        // as the heading rather than leaving the card blank.
        'procedure': condition,
        'notes': _str(row['notes']),
        'doctor': _doctorOf(row),
      };
    }).toList();
  }

  /// The clinic's treatment history from `treatment_notes`, newest first, in
  /// the same map shape as [fetchToothRecords]. Unlike the chart, each entry
  /// names the procedure that was actually done. Empty rather than failing
  /// when the table cannot be read.
  /// The patient's active treatment notes, newest first — the website's
  /// `_loadTreatmentNotes`. `patient_id` is the chart id, and row-level
  /// security checks it belongs to the signed-in account.
  ///
  /// The attribution columns (`attending_dentist_id`, `recorded_by_id`,
  /// `recorded_by_role`) arrive with migration 20261009000001; a database
  /// without them falls back to the legacy `doctor_id` read. Throws when the
  /// notes cannot be read at all, so the screen can tell that from "none".
  static Future<List<TreatmentNote>> fetchTreatmentNotes(String patientId) async {
    const base = 'id, created_at, tooth_id, condition, notes, appointment_id, doctor_id, '
        'members!doctor_id(full_name)';
    const attributed = '$base, attending_dentist_id, recorded_by_id, recorded_by_role, '
        'attending_dentist:members!treatment_notes_attending_dentist_id_fkey(full_name), '
        'recorded_by:profiles!treatment_notes_recorded_by_id_fkey(full_name, role)';

    Future<List<Map<String, dynamic>>> run(String cols, {required bool active}) async {
      var q = SupabaseService.client.from('treatment_notes').select(cols).eq('patient_id', patientId);
      if (active) q = q.isFilter('archived_at', null);
      return (await q.order('created_at', ascending: false)).cast<Map<String, dynamic>>();
    }

    bool schemaGap(PostgrestException e) =>
        pgCode(e) == '42703' || pgCode(e) == 'PGRST200' || _missingSchema.hasMatch(e.message);

    List<Map<String, dynamic>>? rows;
    for (final cols in [attributed, base]) {
      try {
        rows = await run(cols, active: true);
        break;
      } on PostgrestException catch (e) {
        if (!schemaGap(e)) rethrow;
        if (RegExp('archived_at').hasMatch(e.message)) {
          // No archive column yet: nothing has been archived.
          try {
            rows = await run(cols, active: false);
            break;
          } on PostgrestException catch (e2) {
            if (!schemaGap(e2) || cols == base) rethrow;
          }
        } else if (cols == base) {
          rethrow;
        }
      }
    }
    return [for (final row in rows ?? const <Map<String, dynamic>>[]) _noteFrom(row)];
  }

  static TreatmentNote _noteFrom(Map<String, dynamic> row) {
    String nameIn(Object? v) {
      final m = v is List ? (v.isEmpty ? null : v.first) : v;
      return m is Map ? _str(m['full_name']) : '';
    }

    // A patient session may not be allowed to read `members`; the dentist is
    // then named from the clinic roster by id, as elsewhere in the app. The
    // recorder has no such fallback: a name that cannot be read is not guessed.
    final attendingId = _str(row['attending_dentist_id']);
    final doctorId = _str(row['doctor_id']);
    var attending = nameIn(row['attending_dentist']);
    if (attending.isEmpty && attendingId.isNotEmpty) attending = dentistById(attendingId)?.name ?? '';
    var legacy = nameIn(row['members']);
    if (legacy.isEmpty && doctorId.isNotEmpty) legacy = dentistById(doctorId)?.name ?? '';
    final notes = row.containsKey('clinical_notes') && _str(row['clinical_notes']).isNotEmpty
        ? row['clinical_notes'].toString()
        : (row['notes']?.toString() ?? '');

    return TreatmentNote(
      id: _str(row['id']),
      createdAt: _date(row['created_at']),
      toothId: _str(row['tooth_id']),
      condition: _str(row['condition']),
      // Verbatim: line breaks and punctuation are the clinic's.
      notes: notes,
      appointmentId: _nullableStr(_str(row['appointment_id'])),
      attribution: NoteAttribution.resolve(
        attendingName: attending,
        legacyDoctorName: legacy,
        recorderName: nameIn(row['recorded_by']),
        recordedByRole: _str(row['recorded_by_role']),
      ),
    );
  }

  /// The chart matches entries by leading `#<number>`, so a bare tooth id has
  /// to be written in that shape. Anything not numeric is passed through as the
  /// clinic wrote it (`Full Mouth`, for instance).
  static String _toothLabelFrom(String toothId) {
    if (toothId.isEmpty) return '';
    if (toothId.startsWith('#')) return toothId;
    return int.tryParse(toothId) == null ? toothId : '#$toothId';
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dateLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';

  static Future<List<PatientDocument>> fetchDocuments(String patientId) async {
    // Two columns point at the uploader, so both are asked for by their
    // foreign-key name — `profiles` on its own is ambiguous here and errors.
    final rows = await SupabaseService.client
        .from('patient_files')
        .select('id, file_name, file_type, file_size, file_path, storage_path, uploaded_at, '
            'created_at, archived_at, uploaded_by, uploaded_by_profile, '
            'uploader:profiles!patient_files_uploaded_by_fkey(full_name, first_name, last_name), '
            'uploader_profile:profiles!patient_files_uploaded_by_profile_fkey'
            '(full_name, first_name, last_name)')
        .eq('patient_id', patientId)
        .isFilter('archived_at', null)
        .order('uploaded_at', ascending: false);

    return rows.cast<Map<String, dynamic>>().map((row) {
      final name = _str(row['file_name']);
      // A file the patient uploaded carries their own id here, and labelling
      // that "Doctor: <the patient>" would be plainly wrong — only credit
      // somebody else.
      final userId = SupabaseService.currentUserId ?? '';
      final uploadedBySelf = userId.isNotEmpty &&
          (_str(row['uploaded_by']) == userId || _str(row['uploaded_by_profile']) == userId);
      final byProfile = _doctorNameFrom(row['uploader_profile'] as Map<String, dynamic>?);
      final byUploader = _doctorNameFrom(row['uploader'] as Map<String, dynamic>?);

      return PatientDocument(
        id: _str(row['id']),
        name: name,
        kind: _documentKindFrom(_str(row['file_type']), name),
        uploadedOn: _date(row['uploaded_at']) ?? _date(row['created_at']) ?? DateTime.now(),
        path: _nullableStr(
          _str(row['storage_path']).isNotEmpty ? _str(row['storage_path']) : _str(row['file_path']),
        ),
        uploadedBy: uploadedBySelf ? '' : (byProfile.isNotEmpty ? byProfile : byUploader),
        fileType: _str(row['file_type']),
        fileSizeBytes: _int(row['file_size']),
      );
    }).toList();
  }

  /// The support thread, oldest first — the order a chat is read in.
  static Future<List<PatientMessage>> fetchMessages(String patientId) async {
    final rows = await SupabaseService.client
        .from('patient_messages')
        .select('id, body, sender_id, sender_role, created_at, read_at')
        .eq('patient_id', patientId)
        .order('created_at', ascending: true);

    return rows.cast<Map<String, dynamic>>().map((row) {
      final role = _str(row['sender_role']).toLowerCase();
      return PatientMessage(
        id: _str(row['id']),
        body: _str(row['body']),
        // Falls back to comparing the sender against the signed-in account, so
        // a row the clinic wrote without a role is not mistaken for the
        // patient's own message.
        senderRole: role,
        fromPatient: role.isNotEmpty
            ? role == 'patient'
            : _str(row['sender_id']) == (SupabaseService.currentUserId ?? ''),
        sentAt: _date(row['created_at']) ?? DateTime.now(),
        readAt: _date(row['read_at']),
      );
    }).toList();
  }

  static Future<PatientMessage> sendMessage({
    required String patientId,
    required String body,
  }) async {
    final inserted = await SupabaseService.client
        .from('patient_messages')
        .insert({
          'patient_id': patientId,
          'body': body.trim(),
          'sender_role': 'patient',
          if (SupabaseService.currentUserId != null)
            'sender_id': SupabaseService.currentUserId,
        })
        .select('id, body, created_at, read_at')
        .single();

    return PatientMessage(
      id: _str(inserted['id']),
      body: _str(inserted['body']),
      fromPatient: true,
      senderRole: 'patient',
      sentAt: _date(inserted['created_at']) ?? DateTime.now(),
      readAt: _date(inserted['read_at']),
    );
  }

  /// Stamps the clinic's unread messages as seen. Only the clinic's side is
  /// touched: the patient marking their own messages read would be meaningless.
  static Future<void> markMessagesRead(String patientId) async {
    await SupabaseService.client
        .from('patient_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('patient_id', patientId)
        .eq('sender_role', 'clinic')
        .isFilter('read_at', null);
  }

  /// Stamps one message read on its own row. `patient_messages.read_at` is the
  /// read state the website reads too, so nothing else needs writing.
  static Future<void> markMessageRead(String messageId) async {
    await SupabaseService.client
        .from('patient_messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', messageId)
        .isFilter('read_at', null);
  }

  /// A short-lived link the patient can open or download. Patient files are
  /// private, so there is no permanent public URL to hand out.
  static Future<String?> signedUrlForDocument(PatientDocument document) async {
    final path = document.path;
    if (path == null || path.isEmpty) return null;
    return SupabaseService.client.storage.from(filesBucket).createSignedUrl(path, _signedUrlTtl);
  }

  /// One hour. Long enough to open a file and read it, short enough that a
  /// link copied out of the app stops working quickly.
  static const int _signedUrlTtl = 60 * 60;

  /// Links for a whole list in one request, keyed by document id.
  ///
  /// Signing per row would fire a request for every thumbnail in the list; the
  /// batch endpoint does them together. A failure here is not fatal — the rows
  /// fall back to their icon and the viewer signs on demand.
  static Future<Map<String, String>> signedUrlsForDocuments(
    List<PatientDocument> documents,
  ) async {
    final withPaths = documents.where((d) => (d.path ?? '').isNotEmpty).toList();
    if (withPaths.isEmpty) return const {};

    try {
      final signed = await SupabaseService.client.storage
          .from(filesBucket)
          .createSignedUrlsResult(withPaths.map((d) => d.path!).toList(), _signedUrlTtl);

      // The response comes back keyed by storage path, so it has to be mapped
      // back onto document ids before the UI can use it. A row whose object is
      // missing from the bucket fails on its own without losing the others.
      final byPath = <String, String>{};
      for (final entry in signed) {
        switch (entry) {
          case SignedUrlSuccess(:final path, :final signedUrl):
            byPath[path] = signedUrl;
          case SignedUrlFailure(:final path, :final error):
            debugPrint('Could not sign $path: $error');
        }
      }

      return {
        for (final document in withPaths)
          if (byPath[document.path] != null) document.id: byPath[document.path]!,
      };
    } catch (e) {
      debugPrint('Could not sign document URLs: $e');
      return const {};
    }
  }

  /// The raw bytes of a file, for rendering a PDF inside the app.
  static Future<Uint8List?> downloadDocument(PatientDocument document) async {
    final path = document.path;
    if (path == null || path.isEmpty) return null;
    return SupabaseService.client.storage.from(filesBucket).download(path);
  }

  /// Uploads a file the patient picked and records it against their chart.
  ///
  /// The object path starts with the patient id so a storage policy can scope
  /// access by folder, the same way the table policies scope rows.
  static Future<PatientDocument> uploadDocument({
    required String patientId,
    required File file,
    required String fileName,
  }) async {
    final client = SupabaseService.client;
    final extension = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    final objectPath =
        '$patientId/${DateTime.now().millisecondsSinceEpoch}${extension.isEmpty ? '' : '.$extension'}';

    await client.storage.from(filesBucket).upload(objectPath, file);

    final now = DateTime.now();
    final inserted = await client
        .from('patient_files')
        .insert({
          'patient_id': patientId,
          'file_name': fileName,
          'file_path': objectPath,
          'storage_path': objectPath,
          'file_type': extension,
          'file_size': await file.length(),
          'uploaded_at': now.toUtc().toIso8601String(),
          if (SupabaseService.currentUserId != null)
            'uploaded_by': SupabaseService.currentUserId,
        })
        .select('id')
        .single();

    return PatientDocument(
      id: _str(inserted['id']),
      name: fileName,
      kind: _documentKindFrom(extension, fileName),
      uploadedOn: now,
      path: objectPath,
    );
  }

  /// Uploads a new profile photo and returns the public URL stored on the
  /// profile. Avatars are the one patient-supplied file that is not private —
  /// they are shown wherever the patient's name appears.
  /// A displayable URL for `profiles.avatar_url`. The web portal stores the
  /// bucket's public URL; an object path is turned into one here.
  static String? avatarUrlFrom(String stored) {
    if (stored.isEmpty) return null;
    if (stored.startsWith('http://') || stored.startsWith('https://')) return stored;
    final objectPath =
        stored.startsWith('$avatarsBucket/') ? stored.substring(avatarsBucket.length + 1) : stored;
    return SupabaseService.client.storage.from(avatarsBucket).getPublicUrl(objectPath);
  }

  static Future<String> uploadAvatar({
    required String userId,
    required File file,
  }) async {
    final client = SupabaseService.client;
    final extension = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : 'jpg';
    final objectPath = '$userId/avatar.$extension';

    await client.storage.from(avatarsBucket).upload(
          objectPath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = client.storage.from(avatarsBucket).getPublicUrl(objectPath);
    // Cache-busted: the path never changes, so without this the old photo
    // stays on screen after an upload.
    final busted = '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    await updateAvatarUrl(userId: userId, url: busted);
    return busted;
  }

  // --- Writes ---

  // `appointments.status` is the Postgres enum `appointment_status`, whose
  // values are capitalised (`Pending`, `Confirmed`, `Ongoing`, `Completed`,
  // `Cancelled`, `No-Show`). A lowercase literal is rejected outright, which is
  // what made every booking, cancellation and reschedule from the app fail.
  static const String _statusPending = 'Pending';

  /// Cancels one of the patient's own bookings through
  /// `cancel_my_appointment()`, the function the website's Cancel dialog
  /// calls. It checks the booking is theirs and still cancellable, records
  /// the reason, stamps who cancelled and when, releases the slot, and applies
  /// the clinic's deposit policy — all on the server, so the app never writes
  /// the row directly (which RLS refuses, silently, as zero rows changed).
  static Future<void> cancelAppointment(String id, {required String reason}) async {
    try {
      await SupabaseService.client.rpc('cancel_my_appointment', params: {
        'p_appointment_id': id,
        'p_reason': reason.trim().isEmpty ? null : reason.trim(),
      });
    } on PostgrestException catch (e) {
      throw _changeRefused(e) ?? e;
    }
  }

  /// Moves one of the patient's own bookings through
  /// `reschedule_my_appointment()`, as the website does. The server checks the
  /// clinic hours, the dentist's diary, capacity, the one-day lead time and the
  /// same-day cutoff; for a booking with a paid deposit it takes the 5% fee
  /// off the deposit and confirms the new time in the same transaction.
  static Future<RescheduleResult> rescheduleMyAppointment(
    String id, {
    required DateTime date,
    required String timeSlot,
  }) async {
    try {
      final result = await SupabaseService.client.rpc('reschedule_my_appointment', params: {
        'p_appointment_id': id,
        'p_date': _dateOnly(date),
        'p_time': _timeValue(timeSlot),
      });
      final payload = result is Map ? result.cast<String, dynamic>() : const <String, dynamic>{};
      return RescheduleResult(
        paid: payload['paid'] == true,
        fee: _double(payload['fee']) ?? 0,
        depositCredit: _double(payload['deposit_credit']) ?? 0,
      );
    } on PostgrestException catch (e) {
      throw _changeRefused(e) ?? e;
    }
  }

  /// The database's own refusal, when it is one the patient can act on — the
  /// same messages the website passes through. Null for anything else.
  static AppointmentChangeRefusedException? _changeRefused(PostgrestException e) {
    final m = e.message;
    if (pgCode(e) == 'PGRST202' || RegExp('could not find the function', caseSensitive: false).hasMatch(m)) {
      return const AppointmentChangeRefusedException(
          "This is not set up on the clinic's system yet. Please contact the clinic.");
    }
    if (RegExp('clinic is closed', caseSensitive: false).hasMatch(m)) {
      return const AppointmentChangeRefusedException(
          'The clinic is closed at that date and time. Please pick another slot.');
    }
    if (RegExp(
      'same-day|in advance|different date|no longer available|fully booked|only a pending|'
      'cannot be cancelled|cannot be rescheduled|already',
      caseSensitive: false,
    ).hasMatch(m)) {
      return AppointmentChangeRefusedException(m);
    }
    return null;
  }

  static Future<String> createAppointment({
    required String patientId,
    required DateTime date,
    required String timeSlot,
    required List<String> procedureIds,
    String? doctorId,
    double estimatedTotal = 0,
    String? notes,
    String? paymentMethod,
  }) async {
    final client = SupabaseService.client;
    final dentist = _uuidOrNull(doctorId);
    final inserted = await client
        .from('appointments')
        .insert({
          'patient_id': patientId,
          'appointment_date': _dateOnly(date),
          'appointment_time': _timeValue(timeSlot),
          'status': _statusPending,
          if (dentist != null) 'doctor_id': dentist,
          if (estimatedTotal > 0) 'estimated_total': estimatedTotal,
          if (SupabaseService.currentUserId != null) 'created_by': SupabaseService.currentUserId,
          if (procedureIds.isNotEmpty) 'procedure_id': procedureIds.first,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (paymentMethod != null && paymentMethod.isNotEmpty) 'payment_method': paymentMethod,
        })
        .select('id')
        .single();

    final appointmentId = _str(inserted['id']);

    // Visits covering more than one procedure record the rest in the join
    // table; the first stays on the booking itself as the headline service.
    if (procedureIds.length > 1) {
      await client.from('appointment_services').insert([
        for (final procedureId in procedureIds.skip(1))
          {
            'appointment_id': appointmentId,
            'procedure_id': procedureId,
            if (dentist != null) 'doctor_id': dentist,
            'service_date': _dateOnly(date),
            'service_time': _timeValue(timeSlot),
          },
      ]);
    }
    return appointmentId;
  }

  /// [value] when it is a database id, otherwise null. The built-in fallback
  /// roster uses ids like `doc-bolasoc`, which a `uuid` column rejects.
  static String? _uuidOrNull(String? value) {
    if (value == null) return null;
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
            .hasMatch(value)
        ? value
        : null;
  }

  // --- Wallet checkout ---

  /// SQLSTATEs `book_appointment_with_wallet` raises. See
  /// `docs/realtime_data_sync_migration.sql`.
  static const String _insufficientFunds = 'P0002';
  static const String _slotTaken = 'P0003';
  static const String _notApproved = 'P0005';

  /// Books a visit and pays for it from the wallet in **one** database
  /// transaction.
  ///
  /// The old path wrote the ledger entry and the booking separately, from the
  /// client: a failure between the two left a debit with no appointment, and two
  /// devices could both pass a balance check read before either wrote. The
  /// function locks the wallet row, so the second one queues and then fails
  /// honestly.
  ///
  /// [referenceNo] makes a retry safe: the same reference returns the first
  /// result instead of debiting twice.
  ///
  /// Throws [InsufficientWalletBalanceException] when the balance will not cover
  /// [amountToPay], and [SlotTakenException] when the slot went in the meantime.
  ///
  /// There is intentionally no direct-insert fallback. A failed or unavailable
  /// wallet checkout has not verified payment, so it cannot create a booking
  /// from the patient paid-booking flow.
  static Future<WalletCheckoutResult> bookAppointmentWithWallet({
    required String patientId,
    required List<String> procedureIds,
    required DateTime date,
    required String timeSlot,
    required int durationMinutes,
    required double totalAmount,
    required double amountToPay,
    String? doctorId,
    String? notes,
    String? referenceNo,
    String? paymentRequestId,
    String paymentMethod = 'Wallet',
  }) async {
    return _bookAppointmentWithWalletOnce(
      paymentRequestId: paymentRequestId,
      paymentMethod: paymentMethod,
      patientId: patientId,
      procedureIds: procedureIds,
      date: date,
      timeSlot: timeSlot,
      durationMinutes: durationMinutes,
      totalAmount: totalAmount,
      amountToPay: amountToPay,
      doctorId: doctorId,
      notes: notes,
      referenceNo: referenceNo,
    );
  }

  static Future<WalletCheckoutResult> _bookAppointmentWithWalletOnce({
    required String patientId,
    required List<String> procedureIds,
    required DateTime date,
    required String timeSlot,
    required int durationMinutes,
    required double totalAmount,
    required double amountToPay,
    String? doctorId,
    String? notes,
    String? referenceNo,
    String? paymentRequestId,
    String paymentMethod = 'Wallet',
  }) async {
    // The website's two booking functions, so a booking made in the app is
    // the same booking the website makes: the server prices the services,
    // takes the 20% down payment, stamps the confirmation code and QR token,
    // confirms the visit once paid, and sends the confirmation notice.
    //   * Wallet → book_appointment_v5 deducts the deposit from the ledger.
    //   * GCash / GrabPay → book_appointment_v6 settles against the PayMongo
    //     payment request the patient already paid; the wallet is not touched.
    final params = <String, dynamic>{
      'p_procedure_ids': procedureIds,
      'p_date': _dateOnly(date),
      'p_time': _timeValue(timeSlot),
      'p_doctor_id': _uuidOrNull(doctorId),
      'p_payment_method': paymentMethod,
      'p_notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      'p_group_id': null,
    };
    final fn = paymentRequestId == null ? 'book_appointment_v5' : 'book_appointment_v6';
    if (paymentRequestId != null) params['p_payment_request_id'] = paymentRequestId;

    try {
      final result = await SupabaseService.client.rpc(fn, params: params);
      if (result is! Map) throw const InvalidWalletCheckoutResultException();
      final payload = result.cast<String, dynamic>();
      final checkout = WalletCheckoutResult(
        appointmentId: _str(payload['appointment_id']),
        walletBalance: _double(payload['wallet_balance']) ?? 0,
        referenceNo: _str(payload['reference_no']),
        status: _str(payload['status']),
      );
      if (!checkout.hasBookingConfirmation) {
        throw const InvalidWalletCheckoutResultException();
      }
      return checkout;
    } on PostgrestException catch (e) {
      final m = e.message;
      if (pgCode(e) == '42883' || pgCode(e) == 'PGRST202') {
        debugPrint('$fn is not installed on this database');
        throw const BookingPaymentServiceUnavailableException();
      }
      // The same messages the website's booking wizard reads (_bwBookError).
      if (pgCode(e) == _insufficientFunds || RegExp('wallet balance', caseSensitive: false).hasMatch(m)) {
        throw _insufficientFrom(e);
      }
      if (pgCode(e) == _slotTaken ||
          RegExp('no longer available|fully booked', caseSensitive: false).hasMatch(m)) {
        throw const SlotTakenException();
      }
      if (pgCode(e) == _notApproved || RegExp('approval', caseSensitive: false).hasMatch(m)) {
        throw const PatientNotApprovedException();
      }
      rethrow;
    }
  }

  /// Settles (or part-settles) a booking that already exists.
  static Future<WalletCheckoutResult?> payAppointmentFromWallet({
    required String appointmentId,
    required double amount,
    String method = 'Wallet',
    String? referenceNo,
  }) async {
    try {
      final result = await SupabaseService.client.rpc(
        'pay_appointment_from_wallet',
        params: {
          'p_appointment_id': appointmentId,
          'p_amount': amount,
          'p_method': method,
          'p_reference_no': referenceNo,
        },
      );

      final payload = (result as Map).cast<String, dynamic>();
      return WalletCheckoutResult(
        appointmentId: _str(payload['appointment_id']),
        walletBalance: _double(payload['wallet_balance']) ?? 0,
        referenceNo: _str(payload['reference_no']),
        wasIdempotentReplay: payload['idempotent'] == true,
      );
    } on PostgrestException catch (e) {
      switch (pgCode(e)) {
        case _insufficientFunds:
          throw _insufficientFrom(e);
        case '42883':
        case 'PGRST202':
          return null;
        default:
          rethrow;
      }
    }
  }

  /// Pulls the two figures out of the function's message, so the screen can name
  /// the shortfall. Zeroes when the message is not in the expected shape — the
  /// payment is still refused, just without the numbers.
  static InsufficientWalletBalanceException _insufficientFrom(PostgrestException e) {
    final numbers = RegExp(r'-?\d+(?:\.\d+)?')
        .allMatches(e.message)
        .map((m) => double.tryParse(m.group(0)!) ?? 0)
        .toList();
    return InsufficientWalletBalanceException(
      available: numbers.isNotEmpty ? numbers.first : 0,
      required: numbers.length > 1 ? numbers[1] : 0,
    );
  }

  /// Writes to both halves of the record: the clinic's chart and the patient's
  /// own profile, so neither view goes stale after an edit.
  static Future<void> updatePatient({
    required String patientId,
    required String userId,
    String? firstName,
    String? lastName,
    String? username,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? bloodType,
    String? address,
    String? maritalStatus,
    String? medicalHistory,
  }) async {
    final client = SupabaseService.client;

    final patientUpdate = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'date_of_birth': _dateOnly(dateOfBirth),
      if (bloodType != null) 'blood_type': bloodType,
      if (address != null) 'address': address,
      if (maritalStatus != null) 'civil_status': maritalStatus,
    };
    if (patientUpdate.isNotEmpty) {
      await client.from('patients').update(patientUpdate).eq('id', patientId);
    }

    final profileUpdate = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (firstName != null || lastName != null)
        'full_name': [firstName ?? '', lastName ?? ''].join(' ').trim(),
      if (username != null) 'username': username,
      if (phone != null) 'phone': phone,
      if (gender != null) 'gender': gender,
      if (dateOfBirth != null) 'birthdate': _dateOnly(dateOfBirth),
      if (bloodType != null) 'blood_type': bloodType,
      if (address != null) 'address': address,
      if (maritalStatus != null) 'marital_status': maritalStatus,
      if (medicalHistory != null) 'medical_history': medicalHistory,
    };
    if (profileUpdate.isNotEmpty) {
      await client.from('profiles').update(profileUpdate).eq('id', userId);
    }
  }

  static Future<void> updateAvatarUrl({required String userId, required String url}) async {
    await SupabaseService.client.from('profiles').update({'avatar_url': url}).eq('id', userId);
  }

  // --- Parsing helpers ---
  //
  // PostgREST hands back whatever Postgres column type it found, and a nullable
  // column is null rather than absent. These keep that from reaching the models.

  static String _str(Object? value) => value?.toString().trim() ?? '';

  static String? _nullableStr(String value) => value.isEmpty ? null : value;

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_str(value));
  }

  static double? _double(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(_str(value));
  }

  static DateTime? _date(Object? value) {
    if (value is DateTime) return value.toLocal();
    final text = _str(value);
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    // A plain `date` column carries no zone, so converting it to local time
    // would shift the appointment onto the wrong day.
    if (text.length == 10) return DateTime(parsed.year, parsed.month, parsed.day);
    return parsed.toLocal();
  }

  /// Postgres `time` arrives as `13:30:00`; the app formats slots as `01:30 PM`.
  static String _timeSlotFrom(Object? value) {
    final text = _str(value);
    if (text.isEmpty) return '';
    final parts = text.split(':');
    if (parts.length < 2) return text;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return text;
    return formatMinuteOfDay(hour * 60 + minute);
  }

  /// Inverse of [_timeSlotFrom], for writes.
  static String _timeValue(String timeSlot) {
    final minuteOfDay = parseMinuteOfDay(timeSlot) ?? 0;
    final hour = (minuteOfDay ~/ 60).toString().padLeft(2, '0');
    final minute = (minuteOfDay % 60).toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// The clinic's statuses (`Confirmed`, `Ongoing`, `Completed`, `Cancelled`,
  /// `No-Show`, …) folded onto the app's four. A visit already under way is
  /// still upcoming to the patient; a no-show no longer holds its slot.
  /// Whether the patient booked the visit, rather than the clinic for them.
  ///
  /// The website's rule, exactly: a booking is the clinic's only when
  /// `booked_by === 'clinic'`. Anything else, empty included, is self-booked.
  static bool _isSelfBooked(Map<String, dynamic> row) => row['booked_by'] != 'clinic';
  /// When the booking reached its current status, for dating its notice.
  static DateTime? _statusChangedAt(Map<String, dynamic> row) {
    switch (_statusFrom(_str(row['status']))) {
      case AppointmentStatus.cancelled:
        return _date(row['cancelled_at']);
      case AppointmentStatus.confirmed:
        return _date(row['confirmed_at']) ?? _date(row['arrived_at']);
      default:
        return null;
    }
  }

  static AppointmentStatus _statusFrom(String value) {
    switch (value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '')) {
      case 'confirmed':
      case 'approved':
      case 'ongoing':
      case 'inprogress':
      case 'arrived':
      case 'checkedin':
        return AppointmentStatus.confirmed;
      case 'cancelled':
      case 'canceled':
      case 'declined':
      case 'rejected':
      case 'noshow':
        return AppointmentStatus.cancelled;
      case 'completed':
      case 'done':
      case 'finished':
        return AppointmentStatus.completed;
      default:
        return AppointmentStatus.pending;
    }
  }

  static TransactionType _transactionTypeFrom(String value) {
    switch (value.toLowerCase()) {
      case 'credit':
      case 'in':
      case 'topup':
      case 'top_up':
      case 'deposit':
        return TransactionType.credit;
      default:
        return TransactionType.debit;
    }
  }

  static DocumentKind _documentKindFrom(String fileType, String fileName) {
    final haystack = '$fileType $fileName'.toLowerCase();
    if (haystack.contains('prescription')) return DocumentKind.prescription;
    if (haystack.contains('referral') || haystack.contains('request')) {
      return DocumentKind.referral;
    }
    if (haystack.contains('xray') || haystack.contains('x-ray') || haystack.contains('radiograph')) {
      return DocumentKind.xray;
    }
    if (haystack.contains('insurance')) return DocumentKind.insurance;
    return DocumentKind.other;
  }

  /// The doctor's name, distinguishing a visit nobody is assigned to from one
  /// whose staff record this patient is not allowed to read.
  ///
  /// `members` is row-level-security protected, so a patient session can come
  /// back with a `doctor_id` set but the embedded row null. Calling that "to be
  /// assigned" would tell the patient something untrue.
  static String _assignedDoctorName(Map<String, dynamic>? doctor, Object? doctorId) {
    final name = _doctorNameFrom(doctor);
    if (name.isNotEmpty) return name;
    // A patient session cannot read `members`, so the embed is often empty;
    // the roster from `patient_doctor_roster()` still knows the name.
    final rostered = dentistById(_str(doctorId))?.name ?? '';
    if (rostered.isNotEmpty) return rostered;
    return _str(doctorId).isEmpty ? '' : kDoctorAssignedUnnamed;
  }

  /// The dentist named on [row]: its embedded `doctor` members row when RLS let
  /// it through, otherwise the clinic roster entry for its `doctor_id`.
  static String _doctorOf(Map<String, dynamic> row) {
    final embedded = _doctorNameFrom(row['doctor'] as Map<String, dynamic>?);
    if (embedded.isNotEmpty) return embedded;
    return dentistById(_str(row['doctor_id']))?.name ?? '';
  }

  static String _doctorNameFrom(Map<String, dynamic>? row) {
    if (row == null) return '';
    final full = _str(row['full_name']);
    if (full.isNotEmpty) return full;
    return [_str(row['first_name']), _str(row['last_name'])].where((p) => p.isNotEmpty).join(' ');
  }

  /// Top-ups less payments. There is no stored balance column, so the ledger
  /// is the only source of truth for it.
  static double balanceFrom(List<WalletTransaction> transactions) {
    var balance = 0.0;
    for (final txn in transactions) {
      balance += txn.isCredit ? txn.amount : -txn.amount;
    }
    return balance;
  }
}
