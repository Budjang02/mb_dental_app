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
import '../models/wallet_transaction.dart';
import '../services/push_notification_service.dart';
import '../services/supabase_service.dart';
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
  final List<NotificationItem> notifications;
  final List<WalletTransaction> transactions;
  final List<PatientDocument> documents;

  /// Per-tooth chart entries, keyed the way the odontogram reads them.
  final List<Map<String, String>> toothRecords;

  /// Every entry the clinic has written in `treatment_notes`, newest first —
  /// the history behind the chart, which [toothRecords] only holds the present
  /// state of. Same map shape as [toothRecords].
  final List<Map<String, String>> treatmentNotes;

  /// The support conversation with the clinic, oldest first.
  final List<PatientMessage> messages;
  final double walletBalance;

  /// False while `patients.approved_at` is null: the clinic has not approved a
  /// self-registered account yet, and the clinic's booking rules refuse it.
  final bool isApprovedForBooking;

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
    required this.isApprovedForBooking,
  });
}

/// The outstanding plan items the Records screen lists, and the plans
/// themselves for the notification feed.
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

/// What a completed wallet checkout returns.
class WalletCheckoutResult {
  final String appointmentId;
  final double walletBalance;
  final String referenceNo;

  /// True when the call matched an earlier one by reference and changed
  /// nothing — a retry after a dropped connection, not a second booking.
  final bool wasIdempotentReplay;

  const WalletCheckoutResult({
    required this.appointmentId,
    required this.walletBalance,
    required this.referenceNo,
    this.wasIdempotentReplay = false,
  });
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

  static Future<PatientSnapshot> loadAll() async {
    final client = SupabaseService.client;
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      throw const NoPatientRecordException('You are signed out. Please sign in again.');
    }

    final profileRow = await client
        .from('profiles')
        .select('id, username, full_name, first_name, last_name, email, phone, gender, '
            'birthdate, address, blood_type, marital_status, medical_history, avatar_url')
        .eq('id', userId)
        .maybeSingle();

    var patientRow = await _patientRowFor(userId);

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
    // beats eight sequential ones on a phone connection.
    final results = await Future.wait([
      fetchAppointments(patientId),
      fetchTreatmentPlan(patientId),
      fetchBilling(patientId),
      fetchNotifications(userId),
      fetchTransactions(patientId),
      fetchDocuments(patientId),
      fetchToothRecords(patientId),
      fetchMessages(patientId),
      fetchTreatmentNotes(patientId),
    ]);

    final appointments = results[0] as List<Appointment>;
    final planData = results[1] as TreatmentPlanData;
    final treatmentPlan = planData.items;
    final billing = results[2] as List<Payment>;
    final notifications = results[3] as List<NotificationItem>;
    final transactions = results[4] as List<WalletTransaction>;
    final documents = results[5] as List<PatientDocument>;
    final toothRecords = results[6] as List<Map<String, String>>;
    final messages = results[7] as List<PatientMessage>;
    final treatmentNotes = results[8] as List<Map<String, String>>;

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
      // A stored column wins where one exists; the live schema has none, so the
      // ledger is the balance — the same sum `wallet_balance_of()` checks
      // checkout against.
      walletBalance: _double(patientRow['wallet_balance']) ?? balanceFrom(transactions),
      isApprovedForBooking: patientRow['approved_at'] != null,
    );
  }

  /// The wallet balance as it stands now: the stored column when the database
  /// has one, otherwise the sum of [transactions].
  static Future<double> walletBalanceFor({
    required String userId,
    required List<WalletTransaction> transactions,
  }) async {
    if (_hasWalletBalanceColumn) {
      final row = await _patientRowFor(userId);
      final stored = _double(row?['wallet_balance']);
      if (stored != null) return stored;
    }
    return balanceFrom(transactions);
  }

  /// True until `patients.wallet_balance` is seen to be missing. Production has
  /// no such column — the ledger is the balance — so the first load drops it
  /// and every later one sums `wallet_transactions` instead.
  static bool _hasWalletBalanceColumn = true;

  static Future<Map<String, dynamic>?> _patientRowFor(String userId) async {
    const base = 'id, patient_code, patient_number, first_name, last_name, email, phone, '
        'gender, date_of_birth, address, blood_type, civil_status, allergies, '
        'medications, conditions, status, last_visit_at, approved_at';

    Future<Map<String, dynamic>?> run(String columns) => SupabaseService.client
        .from('patients')
        .select(columns)
        .eq('profile_id', userId)
        .maybeSingle();

    if (_hasWalletBalanceColumn) {
      try {
        return await run('$base, wallet_balance');
      } on PostgrestException catch (e) {
        if (pgCode(e) != _undefinedColumn) rethrow;
        _hasWalletBalanceColumn = false;
      }
    }
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

  static Future<List<Appointment>> fetchAppointments(String patientId) async {
    final rows = await SupabaseService.client
        .from('appointments')
        .select('id, appointment_date, appointment_time, status, notes, payment_method, '
            'cancellation_reason, procedure_id, doctor_id, '
            'estimated_total, downpayment_amount, downpayment_paid_at, '
            'created_at, confirmed_at, cancelled_at, arrived_at, booked_by, '
            'procedure:procedures!appointments_procedure_id_fkey(name, duration_min, base_price), '
            // `doctor_id` points at `members` (clinic staff); `created_by`
            // is the one that points at `profiles`. Embedding plain
            // `profiles` here silently resolved to whoever booked the visit
            // instead of the dentist seeing the patient.
            'doctor:members!appointments_doctor_id_fkey(full_name), '
            'appointment_services(procedure_id, procedures(name, duration_min, base_price))')
        .eq('patient_id', patientId)
        // The clinic archives a booking to take it off every list; the web
        // portal hides those, so the app does too.
        .isFilter('archived_at', null)
        .order('appointment_date', ascending: false);

    return rows.map<Appointment>(_appointmentFrom).toList();
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
    final client = SupabaseService.client;

    final results = await Future.wait<List<Map<String, dynamic>>>([
      client
          .from('billing_records')
          .select('id, appointment_id, procedure_name, amount, status, billed_on, created_at, doctor_id, '
              'payment_method, '
              'doctor:members!billing_records_doctor_id_fkey(full_name), '
              'appointments(appointment_date, doctor_id, '
              'doctor:members!appointments_doctor_id_fkey(full_name))')
          .eq('patient_id', patientId)
          .isFilter('voided_at', null)
          .order('billed_on', ascending: false)
          .then((rows) => rows.cast<Map<String, dynamic>>()),
      _optionalRows(() => client
          .from('billing')
          .select('id, appointment_id, procedure_name, amount, payment_method, payment_status, '
              'paid_at, created_at, '
              'appointments(appointment_date, doctor_id, '
              'doctor:members!appointments_doctor_id_fkey(full_name))')
          .eq('patient_id', patientId)
          .order('created_at', ascending: false)),
      _optionalRows(() => client
          .from('invoices')
          .select('id, appointment_id, invoice_no, total_amount, billed_on, issued_at, doctor_name, '
              'invoice_items(billing_record_id, description, amount), '
              'appointments(appointment_date, doctor_id, '
              'doctor:members!appointments_doctor_id_fkey(full_name))')
          .eq('patient_id', patientId)),
      _optionalRows(() => client
          .from('payment_receipts')
          .select('id, billing_record_id, reference_no, paid_on, issued_at, payment_method')
          .eq('patient_id', patientId)),
    ]);

    final records = results[0];
    final legacy = results[1];
    final invoices = results[2];
    final receipts = results[3];

    final invoiceByRecord = <String, Map<String, dynamic>>{};
    final invoiceByAppointment = <String, Map<String, dynamic>>{};
    for (final invoice in invoices) {
      for (final item in ((invoice['invoice_items'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final recordId = _str(item['billing_record_id']);
        if (recordId.isNotEmpty) invoiceByRecord[recordId] = invoice;
      }
      final appointmentId = _str(invoice['appointment_id']);
      if (appointmentId.isNotEmpty) invoiceByAppointment.putIfAbsent(appointmentId, () => invoice);
    }

    final receiptByRecord = <String, Map<String, dynamic>>{
      for (final receipt in receipts)
        if (_str(receipt['billing_record_id']).isNotEmpty) _str(receipt['billing_record_id']): receipt,
    };

    final payments = <Payment>[];
    final claimedInvoiceIds = <String>{};
    final billedAppointments = <String>{};

    for (final row in records) {
      final id = _str(row['id']);
      final appointmentId = _str(row['appointment_id']);
      if (appointmentId.isNotEmpty) billedAppointments.add(appointmentId);

      final invoice = invoiceByRecord[id] ??
          (appointmentId.isEmpty ? null : invoiceByAppointment[appointmentId]);
      if (invoice != null) claimedInvoiceIds.add(_str(invoice['id']));
      final receipt = receiptByRecord[id];

      final isPaid = _str(row['status']).toLowerCase() == 'paid' || receipt != null;
      final invoiceNo = _str(invoice?['invoice_no']);
      final receiptNo = _str(receipt?['reference_no']);
      final doctor = _doctorOf(row);

      payments.add(Payment(
        id: id,
        referenceNo: invoiceNo.isNotEmpty ? invoiceNo : (receiptNo.isNotEmpty ? receiptNo : id),
        invoiceNo: invoiceNo,
        receiptNo: isPaid && receiptNo.isNotEmpty ? receiptNo : null,
        receiptId: _nullableStr(_str(receipt?['id'])),
        receiptIssuedAt: _date(receipt?['issued_at']) ?? _date(receipt?['paid_on']),
        procedureName: _str(row['procedure_name']).isNotEmpty
            ? _str(row['procedure_name'])
            : _invoiceSummary(invoice),
        doctorName: doctor.isNotEmpty
            ? doctor
            : _doctorOfVisit(row['appointments']) ??
                _doctorOfVisit(invoice?['appointments']) ??
                _str(invoice?['doctor_name']),
        amount: _double(row['amount']) ?? 0,
        billedOn: _date(row['billed_on']) ??
            _date(row['created_at']) ??
            _date(invoice?['billed_on']) ??
            DateTime.now(),
        status: isPaid ? 'Paid' : 'Unpaid',
        paymentMethod: _nullableStr(_str(row['payment_method']).isNotEmpty
            ? _str(row['payment_method'])
            : _str(receipt?['payment_method'])),
      ));
    }

    // Legacy charges, only where the portal has not re-recorded that visit.
    for (final row in legacy) {
      final appointmentId = _str(row['appointment_id']);
      if (appointmentId.isNotEmpty && billedAppointments.contains(appointmentId)) continue;
      if (appointmentId.isEmpty && records.isNotEmpty) continue;

      final invoice = appointmentId.isEmpty ? null : invoiceByAppointment[appointmentId];
      if (invoice != null) claimedInvoiceIds.add(_str(invoice['id']));
      final isPaid = _str(row['payment_status']).toLowerCase() == 'paid' || row['paid_at'] != null;
      final id = _str(row['id']);
      final invoiceNo = _str(invoice?['invoice_no']);

      payments.add(Payment(
        id: id,
        referenceNo: invoiceNo.isNotEmpty ? invoiceNo : id,
        invoiceNo: invoiceNo,
        receiptNo: null,
        procedureName: _str(row['procedure_name']).isNotEmpty
            ? _str(row['procedure_name'])
            : _invoiceSummary(invoice),
        doctorName: _doctorOfVisit(row['appointments']) ?? _doctorOfVisit(invoice?['appointments']) ?? '',
        amount: _double(row['amount']) ?? _double(invoice?['total_amount']) ?? 0,
        billedOn: _date(row['created_at']) ?? _date(invoice?['billed_on']) ?? DateTime.now(),
        status: isPaid ? 'Paid' : 'Unpaid',
        paymentMethod: _nullableStr(_str(row['payment_method'])),
      ));
    }

    // An invoice no charge points at is still money owed, so it is listed.
    for (final invoice in invoices) {
      final invoiceId = _str(invoice['id']);
      if (claimedInvoiceIds.contains(invoiceId)) continue;
      claimedInvoiceIds.add(invoiceId);

      final invoiceNo = _str(invoice['invoice_no']);
      payments.add(Payment(
        id: invoiceId,
        referenceNo: invoiceNo.isNotEmpty ? invoiceNo : invoiceId,
        invoiceNo: invoiceNo,
        receiptNo: null,
        procedureName: _invoiceSummary(invoice),
        doctorName: _doctorOfVisit(invoice['appointments']) ?? _str(invoice['doctor_name']),
        amount: _double(invoice['total_amount']) ?? 0,
        billedOn: _date(invoice['billed_on']) ?? _date(invoice['issued_at']) ?? DateTime.now(),
        status: 'Unpaid',
        paymentMethod: null,
      ));
    }

    payments.sort((a, b) => b.billedOn.compareTo(a.billedOn));
    return payments;
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

  /// What an invoice is for, taken from its line items. Falls back to the
  /// invoice number so a statement is never labelled with an empty string.
  static String _invoiceSummary(Map<String, dynamic>? invoice) {
    if (invoice == null) return 'Dental Services';
    final items = (invoice['invoice_items'] as List?) ?? const [];
    final descriptions = items
        .cast<Map<String, dynamic>>()
        .map((item) => _str(item['description']))
        .where((d) => d.isNotEmpty)
        .toList();
    if (descriptions.isEmpty) return 'Dental Services';
    if (descriptions.length == 1) return descriptions.first;
    return '${descriptions.first} +${descriptions.length - 1} more';
  }

  /// The dentist named on the visit an embedded `appointments` row describes.
  static String? _doctorOfVisit(Object? appointment) {
    if (appointment is! Map<String, dynamic>) return null;
    final name = _doctorOf(appointment);
    return name.isEmpty ? null : name;
  }

  /// Keyed on the profile, not the patient chart: notifications are addressed
  /// to the person holding the account.
  static Future<List<NotificationItem>> fetchNotifications(String userId) async {
    final rows = await _selectNotifications(userId);

    return rows.map((row) {
      final id = _str(row['id']);
      // Remembered alongside the item so the banner can respect the patient's
      // per-category mutes: `NotificationItem` itself carries no channel.
      notificationChannels[id] = channelFor(_str(row['type']));
      return NotificationItem(
        id: id,
        title: _str(row['title']),
        body: _str(row['body']),
        createdAt: _date(row['created_at']) ?? DateTime.now(),
        isRead: row['is_read'] == true,
        readAt: _date(row['read_at']),
      );
    }).toList();
  }

  /// One alert by id, for applying a realtime change without refetching the
  /// whole list. Null when the row is not the signed-in patient's.
  static Future<NotificationItem?> fetchNotification({
    required String id,
    required String userId,
  }) async {
    final rows = await _selectNotifications(userId, id: id);
    if (rows.isEmpty) return null;
    final row = rows.first;
    notificationChannels[_str(row['id'])] = channelFor(_str(row['type']));
    return NotificationItem(
      id: _str(row['id']),
      title: _str(row['title']),
      body: _str(row['body']),
      createdAt: _date(row['created_at']) ?? DateTime.now(),
      isRead: row['is_read'] == true,
      readAt: _date(row['read_at']),
    );
  }

  /// True once `notifications.read_at` has been seen on this connection.
  ///
  /// The column arrives with `docs/realtime_data_sync_migration.sql`. Until that has run the
  /// app must not fail to read or mark alerts, so the first request that hits
  /// `42703 undefined_column` drops the column and every later one skips it.
  static bool _hasReadAtColumn = true;

  static Future<List<Map<String, dynamic>>> _selectNotifications(
    String userId, {
    String? id,
  }) async {
    Future<List<Map<String, dynamic>>> run(String columns) async {
      var query = SupabaseService.client
          .from('notifications')
          .select(columns)
          .eq('recipient_id', userId);
      if (id != null) query = query.eq('id', id);
      final rows = await query.order('created_at', ascending: false);
      return rows.cast<Map<String, dynamic>>();
    }

    const base = 'id, title, body, type, is_read, created_at';
    if (_hasReadAtColumn) {
      try {
        return await run('$base, read_at');
      } on PostgrestException catch (e) {
        if (pgCode(e) != _undefinedColumn) rethrow;
        _hasReadAtColumn = false;
      }
    }
    return run(base);
  }

  /// Postgres `undefined_column`.
  static const String _undefinedColumn = '42703';

  /// What this account has read or dismissed, keyed by notice key.
  ///
  /// Read straight from `notification_state`, the table the website shares.
  /// A device-local copy is merged underneath, so a read still sticks when the
  /// write could not reach the server; a server row wins over it.
  static Future<Map<String, NotificationState>> fetchNotificationState(String userId) async {
    final state = <String, NotificationState>{};
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getStringList(_localReadKey(userId)) ?? const <String>[]) {
        state[key] = NotificationState(readAt: epoch);
      }
      for (final key in prefs.getStringList(_localDismissedKey(userId)) ?? const <String>[]) {
        state[key] = NotificationState(readAt: state[key]?.readAt ?? epoch, dismissedAt: epoch);
      }
    } catch (e) {
      debugPrint('Local notification state unreadable: $e');
    }
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
    } catch (e) {
      debugPrint('notification_state unreadable: $e');
    }
    return state;
  }

  /// Marks shared notice [keys] read through `notif_mark_read(p_keys)`, the
  /// website's own RPC: it upserts `(user_id, notif_key)` and keeps the first
  /// read time. Never writes `notification_state` directly. Never throws.
  static Future<void> markSharedNoticesRead(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, rpc: 'notif_mark_read', dismiss: false);

  /// Dismisses shared notice [keys] through `notif_dismiss(p_keys)`, which also
  /// stamps `read_at`. Never throws.
  static Future<void> dismissSharedNotices(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, rpc: 'notif_dismiss', dismiss: true);

  /// Marks app-only notice [keys] read on this device. The website has no
  /// such notices, so nothing is sent to `notification_state`.
  static Future<void> markLocalNoticesRead(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, rpc: null, dismiss: false);

  /// Dismisses app-only notice [keys] on this device.
  static Future<void> dismissLocalNotices(String userId, Iterable<String> keys) =>
      _writeNoticeState(userId, keys, rpc: null, dismiss: true);

  static Future<void> _writeNoticeState(
    String userId,
    Iterable<String> keys, {
    required String? rpc,
    required bool dismiss,
  }) async {
    final list = keys.where((k) => k.isNotEmpty).toSet().toList();
    if (list.isEmpty) return;

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

    if (rpc == null) return;
    try {
      await SupabaseService.client.rpc(rpc, params: {'p_keys': list});
    } catch (e) {
      debugPrint('$rpc failed: $e');
    }
  }
  /// Clears a read on this device only. The website has no "mark unread", so
  /// the shared row keeps its read time and the next load reads it back.
  static Future<void> forgetLocalRead(String userId, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final read = {...?prefs.getStringList(_localReadKey(userId))}..remove(key);
      await prefs.setStringList(_localReadKey(userId), read.toList());
    } catch (e) {
      debugPrint('Local notification state not saved: $e');
    }
  }

  // v2: the keys changed to the website's format, so reads recorded under the
  // app's earlier keys are not carried over.
  static String _localReadKey(String userId) => 'mbNotifRead_app_v2_$userId';
  static String _localDismissedKey(String userId) => 'mbNotifGone_app_v2_$userId';

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

  /// Which mute toggle each alert answers to, keyed by notification id.
  static final Map<String, PushChannel> notificationChannels = {};

  /// Maps the clinic's `notifications.type` onto the app's mute categories.
  /// Anything unrecognised counts as a status update, so a new type the clinic
  /// introduces is shown rather than silently swallowed.
  static PushChannel channelFor(String type) {
    final value = type.toLowerCase();
    if (value.contains('remind')) return PushChannel.reminder;
    if (value.contains('pay') || value.contains('receipt') || value.contains('invoice')) {
      return PushChannel.payment;
    }
    return PushChannel.statusUpdate;
  }

  static Future<List<WalletTransaction>> fetchTransactions(String patientId) async {
    final rows = await SupabaseService.client
        .from('wallet_transactions')
        .select('id, amount, direction, method, reference_no, description, created_at')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

    return rows.cast<Map<String, dynamic>>().map((row) {
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
      );
    }).toList();
  }

  /// The per-tooth chart entries behind the odontogram and the Treatment Notes
  /// page. Shaped as the string maps those screens already read, so the chart's
  /// rendering did not have to change to take real data.
  static Future<List<Map<String, String>>> fetchToothRecords(String patientId) async {
    final rows = await SupabaseService.client
        .from('tooth_records')
        .select('id, tooth_id, condition, notes, doctor_id, created_at, updated_at, '
            'doctor:members!tooth_records_doctor_id_fkey(full_name)')
        .eq('patient_id', patientId)
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
  static Future<List<Map<String, String>>> fetchTreatmentNotes(String patientId) async {
    final rows = await _optionalRows(() => SupabaseService.client
        .from('treatment_notes')
        .select('id, tooth_id, condition, procedure, notes, doctor_id, created_at, updated_at, '
            'doctor:members!treatment_notes_doctor_id_fkey(full_name)')
        .eq('patient_id', patientId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false));

    return rows.map((row) {
      final recordedOn = _date(row['created_at']) ?? _date(row['updated_at']);
      final condition = _str(row['condition']);
      final procedure = _str(row['procedure']);
      return <String, String>{
        'date': recordedOn == null ? '' : _dateLabel(recordedOn),
        'tooth': _toothLabelFrom(_str(row['tooth_id'])),
        'condition': condition,
        'procedure': procedure.isNotEmpty ? procedure : condition,
        'notes': _str(row['notes']),
        'doctor': _doctorOf(row),
      };
    }).toList();
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

  /// Marks one alert read **in the database**, not just on this device: the
  /// web and the app both read `is_read` back off the row, so a local-only
  /// flag is what leaves the two disagreeing.
  ///
  /// Scoped to [userId] as well as the id so a stale id from another account
  /// cannot write to a row this patient does not own.
  static Future<void> markNotificationRead(String id, {required String userId}) async {
    await _updateReadState((payload) => SupabaseService.client
        .from('notifications')
        .update(payload)
        .eq('id', id)
        .eq('recipient_id', userId));
  }

  static Future<void> markAllNotificationsRead(String userId) async {
    await _updateReadState((payload) => SupabaseService.client
        .from('notifications')
        .update(payload)
        .eq('recipient_id', userId)
        .eq('is_read', false));
  }

  /// Runs [update] with `read_at` set, and again without it on a database that
  /// has not had `docs/realtime_data_sync_migration.sql` applied yet.
  static Future<void> _updateReadState(
    PostgrestFilterBuilder<dynamic> Function(Map<String, dynamic> payload) update,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    if (_hasReadAtColumn) {
      try {
        await update({'is_read': true, 'read_at': now});
        return;
      } on PostgrestException catch (e) {
        if (pgCode(e) != _undefinedColumn) rethrow;
        _hasReadAtColumn = false;
      }
    }
    await update({'is_read': true});
  }

  /// Marks one alert unread again, so an "unread" toggle on either platform is
  /// also a row change rather than device-local state.
  static Future<void> markNotificationUnread(String id, {required String userId}) async {
    Future<void> run(Map<String, dynamic> payload) => SupabaseService.client
        .from('notifications')
        .update(payload)
        .eq('id', id)
        .eq('recipient_id', userId);

    if (_hasReadAtColumn) {
      try {
        await run({'is_read': false, 'read_at': null});
        return;
      } on PostgrestException catch (e) {
        if (pgCode(e) != _undefinedColumn) rethrow;
        _hasReadAtColumn = false;
      }
    }
    await run({'is_read': false});
  }

  // `appointments.status` is the Postgres enum `appointment_status`, whose
  // values are capitalised (`Pending`, `Confirmed`, `Ongoing`, `Completed`,
  // `Cancelled`, `No-Show`). A lowercase literal is rejected outright, which is
  // what made every booking, cancellation and reschedule from the app fail.
  static const String _statusPending = 'Pending';
  static const String _statusCancelled = 'Cancelled';

  static Future<void> cancelAppointment(String id, {required String reason}) async {
    final client = SupabaseService.client;
    final base = <String, dynamic>{
      'status': _statusCancelled,
      'cancellation_reason': reason,
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      // Tells the front desk who cancelled, the way the portal records it.
      await client.from('appointments').update({...base, 'cancelled_by': 'patient'}).eq('id', id);
    } on PostgrestException catch (e) {
      // `cancelled_by` is descriptive only; a constraint on its values must not
      // stop the cancellation itself.
      if (!const {'23514', '22P02', '42703'}.contains(pgCode(e))) rethrow;
      await client.from('appointments').update(base).eq('id', id);
    }
  }

  static Future<void> rescheduleAppointment(
    String id, {
    required DateTime date,
    required String timeSlot,
    String? notes,
  }) async {
    await SupabaseService.client.from('appointments').update({
      'appointment_date': _dateOnly(date),
      'appointment_time': _timeValue(timeSlot),
      'status': _statusPending,
      'confirmed_at': null,
      if (notes != null) 'notes': notes,
    }).eq('id', id);
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
  /// Returns null when `book_appointment_with_wallet` is not installed, which
  /// tells the caller to use the unpaid booking path instead.
  static Future<WalletCheckoutResult?> bookAppointmentWithWallet({
    required String patientId,
    required List<String> procedureIds,
    required DateTime date,
    required String timeSlot,
    required int durationMinutes,
    required double totalAmount,
    required double amountToPay,
    String? doctorId,
    String? notes,
    String method = 'GCash',
    String? referenceNo,
  }) async {
    try {
      final result = await SupabaseService.client.rpc(
        'book_appointment_with_wallet',
        params: {
          'p_patient_id': patientId,
          'p_procedure_ids': procedureIds,
          'p_appointment_date': _dateOnly(date),
          'p_appointment_time': _timeValue(timeSlot),
          'p_duration_minutes': durationMinutes,
          'p_total_amount': totalAmount,
          'p_amount_to_pay': amountToPay,
          'p_doctor_id': _uuidOrNull(doctorId),
          'p_notes': notes,
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
        case _slotTaken:
          throw const SlotTakenException();
        case _notApproved:
          throw const PatientNotApprovedException();
        // Not installed yet: the caller falls back to booking without payment
        // rather than failing the patient's checkout outright.
        case '42883':
        case 'PGRST202':
          debugPrint('book_appointment_with_wallet is not installed; '
              'see docs/realtime_data_sync_migration.sql');
          return null;
        default:
          rethrow;
      }
    }
  }

  /// Settles (or part-settles) a booking that already exists.
  static Future<WalletCheckoutResult?> payAppointmentFromWallet({
    required String appointmentId,
    required double amount,
    String method = 'GCash',
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

  /// Credits the wallet through `wallet_topup(p_amount, p_method, p_reference)`,
  /// the RPC the website's "Add money" button calls. The function writes the
  /// ledger row; nothing is inserted from the app.
  ///
  /// [method] is one of the website's fixed values: 'GCash', 'Maya', 'Card',
  /// 'Bank Transfer' or 'Cash'. [reference] is null when the patient left it
  /// blank, never an empty string, matching the website.
  static Future<void> topUpWallet({
    required double amount,
    required String method,
    String? reference,
  }) async {
    final trimmed = reference?.trim() ?? '';
    await SupabaseService.client.rpc(
      'wallet_topup',
      params: {
        'p_amount': amount,
        'p_method': method,
        'p_reference': trimmed.isEmpty ? null : trimmed,
      },
    );
  }

  static Future<void> addWalletTransaction({
    required String patientId,
    required double amount,
    required TransactionType type,
    required String method,
    required String description,
  }) async {
    await SupabaseService.client.from('wallet_transactions').insert({
      'patient_id': patientId,
      'amount': amount.abs(),
      // The clinic's ledger records `in` / `out`, which is what the portal's
      // wallet and `wallet_balance_of()` read.
      'direction': type == TransactionType.credit ? 'in' : 'out',
      'method': method,
      'description': description,
      'reference_no': 'REF-${DateTime.now().millisecondsSinceEpoch}',
    });
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
