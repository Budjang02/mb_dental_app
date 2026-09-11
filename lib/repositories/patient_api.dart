import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
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

/// Everything the signed-in patient owns, fetched in one pass so the screens
/// can keep reading plain synchronous getters.
class PatientSnapshot {
  final Patient patient;
  final List<Appointment> appointments;
  final List<Treatment> treatments;
  final List<TreatmentPlanItem> treatmentPlan;
  final List<Payment> billing;
  final List<NotificationItem> notifications;
  final List<WalletTransaction> transactions;
  final List<PatientDocument> documents;

  /// Per-tooth chart entries, keyed the way the odontogram reads them.
  final List<Map<String, String>> toothRecords;

  /// The support conversation with the clinic, oldest first.
  final List<PatientMessage> messages;
  final double walletBalance;

  const PatientSnapshot({
    required this.patient,
    required this.appointments,
    required this.treatments,
    required this.treatmentPlan,
    required this.billing,
    required this.notifications,
    required this.transactions,
    required this.documents,
    required this.toothRecords,
    required this.messages,
    required this.walletBalance,
  });
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

    final patientRow = await client
        .from('patients')
        .select('id, patient_code, patient_number, first_name, last_name, email, phone, '
            'gender, date_of_birth, address, blood_type, civil_status, allergies, '
            'medications, conditions, status, last_visit_at')
        .eq('profile_id', userId)
        .maybeSingle();

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
      _fetchAppointments(patientId),
      _fetchTreatmentPlan(patientId),
      _fetchBilling(patientId),
      fetchNotifications(userId),
      _fetchTransactions(patientId),
      _fetchDocuments(patientId),
      _fetchToothRecords(patientId),
      fetchMessages(patientId),
    ]);

    final appointments = results[0] as List<Appointment>;
    final treatmentPlan = results[1] as List<TreatmentPlanItem>;
    final billing = results[2] as List<Payment>;
    final notifications = results[3] as List<NotificationItem>;
    final transactions = results[4] as List<WalletTransaction>;
    final documents = results[5] as List<PatientDocument>;
    final toothRecords = results[6] as List<Map<String, String>>;
    final messages = results[7] as List<PatientMessage>;

    return PatientSnapshot(
      patient: _patientFrom(patientRow, profileRow),
      appointments: appointments,
      // Treatment history is the record of visits that actually happened, so
      // it is derived from completed appointments rather than stored twice.
      treatments: _treatmentsFrom(appointments),
      treatmentPlan: treatmentPlan,
      billing: billing,
      notifications: notifications,
      transactions: transactions,
      documents: documents,
      toothRecords: toothRecords,
      messages: messages,
      walletBalance: _balanceFrom(transactions),
    );
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
      avatarPath: _nullableStr(_str(profile?['avatar_url'])),
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

  static Future<List<Appointment>> _fetchAppointments(String patientId) async {
    final rows = await SupabaseService.client
        .from('appointments')
        .select('id, appointment_date, appointment_time, status, notes, payment_method, '
            'cancellation_reason, procedure_id, doctor_id, '
            'procedure:procedures!appointments_procedure_id_fkey(name, duration_min, base_price), '
            // `doctor_id` points at `members` (clinic staff); `created_by`
            // is the one that points at `profiles`. Embedding plain
            // `profiles` here silently resolved to whoever booked the visit
            // instead of the dentist seeing the patient.
            'doctor:members!appointments_doctor_id_fkey(full_name), '
            'appointment_services(procedure_id, procedures(name, duration_min, base_price))')
        .eq('patient_id', patientId)
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
    final total = procedures.fold<double>(0, (sum, p) => sum + (_double(p['base_price']) ?? 0));

    final doctor = row['doctor'] as Map<String, dynamic>?;

    return Appointment(
      id: _str(row['id']),
      serviceName: names.isEmpty ? 'Dental Visit' : names.join(', '),
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
    );
  }

  static List<Treatment> _treatmentsFrom(List<Appointment> appointments) {
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

  static Future<List<TreatmentPlanItem>> _fetchTreatmentPlan(String patientId) async {
    final rows = await SupabaseService.client
        .from('treatment_plans')
        .select('id, title, diagnosis, notes, status, created_at, '
            'doctor:members!treatment_plans_doctor_id_fkey(full_name), '
            'treatment_plan_items(id, description, estimated_cost, status, sort_order, '
            'completed_at, procedures(name))')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

    final items = <TreatmentPlanItem>[];
    for (final plan in rows.cast<Map<String, dynamic>>()) {
      // Only work still outstanding belongs on the plan; anything the clinic
      // has carried out shows up under treatment history instead.
      if (_str(plan['status']).toLowerCase() == 'completed') continue;

      final doctorName = _doctorNameFrom(plan['doctor'] as Map<String, dynamic>?);
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
    return items;
  }

  static Future<List<Payment>> _fetchBilling(String patientId) async {
    final client = SupabaseService.client;

    // The doctor's name is on the visit, not the charge, so the appointment is
    // pulled through to stop every statement reading "billed by (nobody)".
    final billingRows = await client
        .from('billing')
        .select('id, appointment_id, procedure_name, amount, payment_method, payment_status, '
            'paid_at, notes, created_at, '
            'appointments(appointment_date, '
            'doctor:members!appointments_doctor_id_fkey(full_name))')
        .eq('patient_id', patientId)
        .order('created_at', ascending: false);

    final invoiceRows = await client
        .from('invoices')
        .select('id, appointment_id, invoice_no, total_amount, billed_on, issued_at, '
            'invoice_items(id, description, amount), '
            'appointments(appointment_date, '
            'doctor:members!appointments_doctor_id_fkey(full_name))')
        .eq('patient_id', patientId);

    // Invoice numbers live on their own table, keyed by the visit they cover.
    final invoiceByAppointment = <String, Map<String, dynamic>>{};
    final unmatchedInvoices = <Map<String, dynamic>>[];
    for (final invoice in invoiceRows.cast<Map<String, dynamic>>()) {
      final appointmentId = _nullableStr(_str(invoice['appointment_id']));
      if (appointmentId == null) {
        unmatchedInvoices.add(invoice);
      } else {
        invoiceByAppointment[appointmentId] = invoice;
      }
    }

    final payments = <Payment>[];
    final claimedInvoiceIds = <String>{};

    for (final row in billingRows.cast<Map<String, dynamic>>()) {
      final appointmentId = _nullableStr(_str(row['appointment_id']));
      final invoice = appointmentId == null ? null : invoiceByAppointment[appointmentId];
      if (invoice != null) claimedInvoiceIds.add(_str(invoice['id']));

      final isPaid = _str(row['payment_status']).toLowerCase() == 'paid' || row['paid_at'] != null;
      final id = _str(row['id']);
      final invoiceNo = _str(invoice?['invoice_no']);

      payments.add(Payment(
        id: id,
        referenceNo: invoiceNo.isNotEmpty ? invoiceNo : id,
        invoiceNo: invoiceNo,
        // The clinic issues a receipt number only once money has changed hands.
        receiptNo: isPaid && invoiceNo.isNotEmpty ? invoiceNo : null,
        procedureName: _str(row['procedure_name']).isNotEmpty
            ? _str(row['procedure_name'])
            : _invoiceSummary(invoice),
        doctorName: _doctorOfVisit(row['appointments']) ?? _doctorOfVisit(invoice?['appointments']) ?? '',
        amount: _double(row['amount']) ?? _double(invoice?['total_amount']) ?? 0,
        billedOn: _date(row['created_at']) ??
            _date(invoice?['billed_on']) ??
            _date(invoice?['issued_at']) ??
            DateTime.now(),
        status: isPaid ? 'Paid' : 'Unpaid',
        paymentMethod: _nullableStr(_str(row['payment_method'])),
      ));
    }

    // A clinic can raise an invoice without a matching `billing` row. Dropping
    // those would hide money the patient actually owes, so they are listed too.
    for (final invoice in [...invoiceByAppointment.values, ...unmatchedInvoices]) {
      final invoiceId = _str(invoice['id']);
      if (claimedInvoiceIds.contains(invoiceId)) continue;

      final invoiceNo = _str(invoice['invoice_no']);
      payments.add(Payment(
        id: invoiceId,
        referenceNo: invoiceNo.isNotEmpty ? invoiceNo : invoiceId,
        invoiceNo: invoiceNo,
        receiptNo: null,
        procedureName: _invoiceSummary(invoice),
        doctorName: _doctorOfVisit(invoice['appointments']) ?? '',
        amount: _double(invoice['total_amount']) ?? 0,
        billedOn: _date(invoice['billed_on']) ?? _date(invoice['issued_at']) ?? DateTime.now(),
        // Nothing in `billing` settled it, so it is still outstanding.
        status: 'Unpaid',
        paymentMethod: null,
      ));
    }

    payments.sort((a, b) => b.billedOn.compareTo(a.billedOn));
    return payments;
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
    final name = _doctorNameFrom(appointment['doctor'] as Map<String, dynamic>?);
    return name.isEmpty ? null : name;
  }

  /// Keyed on the profile, not the patient chart: notifications are addressed
  /// to the person holding the account.
  static Future<List<NotificationItem>> fetchNotifications(String userId) async {
    final rows = await SupabaseService.client
        .from('notifications')
        .select('id, title, body, type, is_read, created_at')
        .eq('recipient_id', userId)
        .order('created_at', ascending: false);

    return rows.cast<Map<String, dynamic>>().map((row) {
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
      );
    }).toList();
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

  static Future<List<WalletTransaction>> _fetchTransactions(String patientId) async {
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
  static Future<List<Map<String, String>>> _fetchToothRecords(String patientId) async {
    final rows = await SupabaseService.client
        .from('tooth_records')
        .select('id, tooth_id, condition, notes, created_at, updated_at, '
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
        'doctor': _doctorNameFrom(row['doctor'] as Map<String, dynamic>?),
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

  static Future<List<PatientDocument>> _fetchDocuments(String patientId) async {
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
        .order('created_at');

    return rows.cast<Map<String, dynamic>>().map((row) {
      final role = _str(row['sender_role']).toLowerCase();
      return PatientMessage(
        id: _str(row['id']),
        body: _str(row['body']),
        // Falls back to comparing the sender against the signed-in account, so
        // a row the clinic wrote without a role is not mistaken for the
        // patient's own message.
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
        .neq('sender_role', 'patient')
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

  static Future<void> markNotificationRead(String id) async {
    await SupabaseService.client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  static Future<void> markAllNotificationsRead(String userId) async {
    await SupabaseService.client
        .from('notifications')
        .update({'is_read': true})
        .eq('recipient_id', userId)
        .eq('is_read', false);
  }

  static Future<void> cancelAppointment(String id, {required String reason}) async {
    await SupabaseService.client.from('appointments').update({
      'status': 'cancelled',
      'cancellation_reason': reason,
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
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
      'status': 'pending',
      'confirmed_at': null,
      if (notes != null) 'notes': notes,
    }).eq('id', id);
  }

  static Future<String> createAppointment({
    required String patientId,
    required DateTime date,
    required String timeSlot,
    required List<String> procedureIds,
    String? notes,
    String? paymentMethod,
    String status = 'pending',
  }) async {
    final client = SupabaseService.client;
    final inserted = await client
        .from('appointments')
        .insert({
          'patient_id': patientId,
          'appointment_date': _dateOnly(date),
          'appointment_time': _timeValue(timeSlot),
          'status': status,
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
          {'appointment_id': appointmentId, 'procedure_id': procedureId},
      ]);
    }
    return appointmentId;
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
      'direction': type == TransactionType.credit ? 'credit' : 'debit',
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

  static AppointmentStatus _statusFrom(String value) {
    switch (value.toLowerCase()) {
      case 'confirmed':
      case 'approved':
        return AppointmentStatus.confirmed;
      case 'cancelled':
      case 'canceled':
      case 'declined':
      case 'rejected':
      case 'no_show':
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
    return _str(doctorId).isEmpty ? '' : kDoctorAssignedUnnamed;
  }

  static String _doctorNameFrom(Map<String, dynamic>? row) {
    if (row == null) return '';
    final full = _str(row['full_name']);
    if (full.isNotEmpty) return full;
    return [_str(row['first_name']), _str(row['last_name'])].where((p) => p.isNotEmpty).join(' ');
  }

  /// Top-ups less payments. There is no stored balance column, so the ledger
  /// is the only source of truth for it.
  static double _balanceFrom(List<WalletTransaction> transactions) {
    var balance = 0.0;
    for (final txn in transactions) {
      balance += txn.isCredit ? txn.amount : -txn.amount;
    }
    return balance;
  }
}
