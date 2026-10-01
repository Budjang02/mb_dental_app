import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/clinic_catalog.dart';
import '../models/appointment.dart';
import '../services/clinic_pdf.dart';
import '../services/supabase_service.dart';

/// Which of an appointment's billing documents exist: the invoice issued for
/// its charges and the latest payment receipt covering them. Either is null
/// until the clinic has issued it.
class AppointmentDocuments {
  final String? invoiceId;
  final String? receiptId;

  const AppointmentDocuments({this.invoiceId, this.receiptId});

  static const none = AppointmentDocuments();
}

/// Every payment figure the Appointment Details page shows, worked out the
/// way the website's details dialog works them out (`_padMoney`), so the two
/// never disagree:
///
/// * the service price is the clinic's bill once one is filed, otherwise the
///   estimate (a range when the rate card has one);
/// * the down payment counts only when the server recorded it as paid;
/// * reschedule fees come off the deposit, so less of it counts toward the
///   bill ([credited]);
/// * the balance is the bill's unpaid part less the credited deposit — or
///   nothing once the bill is settled, since settling applied the deposit
///   already. The deposit is never taken off twice.
class AppointmentMoney {
  final String method;
  final double down;
  final bool paid;
  final double feeTotal;
  final double credited;
  final bool billed;
  final double priceMin;
  final double priceMax;
  final double balanceMin;
  final double balanceMax;

  /// The deposit was forfeited by a cancellation: paid, but not credited.
  final bool forfeited;

  /// The visit's charges could not be read. The figures are then the
  /// estimate, and the screen says the bill could not be checked rather than
  /// that nothing was billed.
  final bool billingFailed;

  const AppointmentMoney({
    required this.method,
    required this.down,
    required this.paid,
    required this.feeTotal,
    required this.credited,
    required this.billed,
    required this.priceMin,
    required this.priceMax,
    required this.balanceMin,
    required this.balanceMax,
    this.forfeited = false,
    this.billingFailed = false,
  });

  /// [estimateMin]/[estimateMax] are the estimated service cost; [billTotal]
  /// and [billUnpaid] the non-voided charges filed for the visit, if any.
  factory AppointmentMoney.compute({
    required String method,
    required double downpaymentAmount,
    required bool downpaymentPaid,
    required double rescheduleFeeTotal,
    required double estimateMin,
    required double estimateMax,
    double? billTotal,
    double? billUnpaid,
    bool depositForfeited = false,
    bool billingFailed = false,
  }) {
    // Paid and not forfeited — `_padMoney`'s rule, which Complete & Bill uses.
    final paid = downpaymentPaid && !depositForfeited && downpaymentAmount > 0;
    final feeTotal = paid ? (rescheduleFeeTotal < downpaymentAmount ? rescheduleFeeTotal : downpaymentAmount) : 0.0;
    final credited = paid ? downpaymentAmount - feeTotal : 0.0;
    final estMax = estimateMax < estimateMin ? estimateMin : estimateMax;
    final billed = billTotal != null && billTotal > 0;
    final settled = billed && (billUnpaid ?? 0) <= 0;
    double clamp0(double v) => v < 0 ? 0 : v;
    final balMin = billed ? (settled ? 0.0 : clamp0((billUnpaid ?? 0) - credited)) : clamp0(estimateMin - credited);
    final balMax = billed ? balMin : (balMin > estMax - credited ? balMin : estMax - credited);
    return AppointmentMoney(
      method: method,
      down: downpaymentAmount,
      paid: paid,
      feeTotal: feeTotal,
      credited: credited,
      billed: billed,
      priceMin: billed ? billTotal : estimateMin,
      priceMax: billed ? billTotal : estMax,
      balanceMin: balMin,
      balanceMax: balMax,
      forfeited: depositForfeited && downpaymentPaid && downpaymentAmount > 0,
      billingFailed: billingFailed,
    );
  }

  /// From the appointment alone, before the bill and rate card are read.
  factory AppointmentMoney.fromAppointment(Appointment a) => AppointmentMoney.compute(
        method: a.paymentMethod ?? '',
        downpaymentAmount: a.downpaymentAmount > 0 ? a.downpaymentAmount : a.amountPaid,
        downpaymentPaid: a.downpaymentPaidAt != null,
        rescheduleFeeTotal: a.rescheduleFeeTotal,
        estimateMin: a.totalPrice,
        estimateMax: a.totalPrice,
      );
}

/// Reads the saved records behind the Invoice, Payment Receipt and Deposit
/// Receipt and turns them into [ClinicPdfSpec]s — a port of the website's
/// `js/pdf-records.js`, reading the same tables the same way, so both draw
/// the same document for the same visit.
///
/// Read-only. Nothing here writes to the database: downloading a document can
/// never file a second invoice or receipt, only redraw the one on record.
///
/// Access runs on the patient's own login session only — never a service-role
/// key — so row-level security decides what comes back. On top of that, each
/// lookup starts from the signed-in user (`auth.uid()` →
/// `patients.profile_id`) and refuses any appointment, invoice or receipt
/// whose `patient_id` is not that patient's, so a document can only be drawn
/// for its owner even if a policy were ever loosened.
class ClinicDocumentsApi {
  ClinicDocumentsApi._();

  static SupabaseClient get _db => SupabaseService.client;

  /// The signed-in patient's `patients.id`, from the session's user id.
  /// Throws [DocumentAccessException] with no session or no patient record.
  static Future<String> _signedInPatientId() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) throw const DocumentAccessException('Please sign in again to download this document.');
    final row = await _db.from('patients').select('id').eq('profile_id', userId).maybeSingle();
    final id = _str(row?['id']);
    if (id.isEmpty) throw const DocumentAccessException('We could not find your patient record.');
    return id;
  }

  /// True when [row] belongs to [patientId]. A row with no `patient_id` is
  /// treated as not theirs.
  static bool _ownedBy(Map<String, dynamic>? row, String patientId) =>
      row != null && _str(row['patient_id']) == patientId;

  static const _apptColumns = 'id,patient_id,doctor_id,confirmation_code,appointment_date,appointment_time,'
      'status,payment_method,estimated_total,downpayment_amount,downpayment_paid_at,'
      'members!doctor_id(full_name),'
      'appointment_services(procedures(name,min_rate,max_rate,duration_min)),'
      'procedures!procedure_id(name,min_rate,max_rate,duration_min)';

  // --- Payment figures ---------------------------------------------------------

  /// The payment figures for one of the patient's own appointments: the
  /// appointment row (method, estimate, deposit, reschedule fees, rate card)
  /// and the charges filed for it, read the way the website reads them.
  static Future<AppointmentMoney> moneyFor(Appointment appointment) async {
    final patientId = await _signedInPatientId();
    final a = await _loadAppointment(appointment.id);
    if (a == null || !_ownedBy(a, patientId)) return AppointmentMoney.fromAppointment(appointment);

    final services = _services(a);
    final rateMin = services.fold<double>(0, (s, p) => s + _num(p['min_rate']));
    final rateMax = services.fold<double>(0, (s, p) {
      final lo = _num(p['min_rate']);
      final hi = _num(p['max_rate']);
      return s + (hi > lo ? hi : lo);
    });
    final estimated = _num(a['estimated_total']);
    final estMin = estimated > 0 ? estimated : (rateMin > 0 ? rateMin : appointment.totalPrice);

    double? billTotal;
    double? billUnpaid;
    var billingFailed = false;
    try {
      final rows = await _db
          .from('billing_records')
          .select('amount,status,voided_at')
          .eq('appointment_id', appointment.id)
          .eq('patient_id', patientId);
      final live = (rows as List).cast<Map<String, dynamic>>().where((r) => r['voided_at'] == null).toList();
      if (live.isNotEmpty) {
        billTotal = live.fold<double>(0, (s, r) => s + _num(r['amount']));
        billUnpaid = live.where((r) => _str(r['status']) != 'Paid').fold<double>(0, (s, r) => s + _num(r['amount']));
      }
    } catch (e) {
      debugPrint('Billing lookup failed: $e');
      billingFailed = true;
    }

    return AppointmentMoney.compute(
      method: _str(a['payment_method']),
      downpaymentAmount: _num(a['downpayment_amount']),
      downpaymentPaid: a['downpayment_paid_at'] != null,
      rescheduleFeeTotal: _num(a['reschedule_fee_total']),
      estimateMin: estMin,
      estimateMax: rateMax > estMin ? rateMax : estMin,
      billTotal: billTotal,
      billUnpaid: billUnpaid,
      depositForfeited: a['deposit_forfeited_at'] != null,
      billingFailed: billingFailed,
    );
  }

  // --- Finding the documents -------------------------------------------------

  /// The invoice and latest receipt on file for [appointmentId]'s charges,
  /// found the way the website's bill overview finds them: the visit's
  /// `billing_records`, then `invoice_items` and `receipt_items` on those.
  static Future<AppointmentDocuments> findForAppointment(String appointmentId) async {
    final patientId = await _signedInPatientId();
    final appt = await _db.from('appointments').select('id,patient_id').eq('id', appointmentId).maybeSingle();
    if (!_ownedBy(appt, patientId)) return AppointmentDocuments.none;

    final bills = await _db
        .from('billing_records')
        .select('id')
        .eq('appointment_id', appointmentId)
        .eq('patient_id', patientId);
    final billIds = [for (final b in (bills as List)) _str(b['id'])]..removeWhere((id) => id.isEmpty);

    // An issued invoice is found either way the website files one: straight
    // on the appointment, or through its charges' invoice items. Errors are
    // not swallowed — "could not check" must not read as "none issued".
    final direct = await _db
        .from('invoices')
        .select('id')
        .eq('appointment_id', appointmentId)
        .eq('patient_id', patientId)
        .order('issued_at', ascending: false)
        .limit(1);
    var invoiceId = (direct as List).isEmpty ? '' : _str(direct.first['id']);
    if (invoiceId.isEmpty && billIds.isNotEmpty) {
      final invoiceRows = await _db.from('invoice_items').select('invoice_id').inFilter('billing_record_id', billIds);
      invoiceId = [for (final r in (invoiceRows as List)) _str(r['invoice_id'])].firstWhere(
        (id) => id.isNotEmpty,
        orElse: () => '',
      );
    }
    if (billIds.isEmpty) {
      return AppointmentDocuments(invoiceId: invoiceId.isEmpty ? null : invoiceId);
    }

    final receipts = await _receiptsFor(billIds);
    return AppointmentDocuments(
      invoiceId: invoiceId.isEmpty ? null : invoiceId,
      receiptId: receipts.isEmpty ? null : _str(receipts.last['id']),
    );
  }

  // --- Invoice -----------------------------------------------------------------

  /// The Invoice for [invoiceId], as `pdfInvoiceSpec` draws it. Null when no
  /// such invoice is visible to this patient.
  static Future<ClinicPdfSpec?> invoiceSpec(String invoiceId) async {
    final patientId = await _signedInPatientId();
    final inv = await _firstThatWorks([
      '*,invoice_items(id,description,amount,line_no,billing_record_id,'
          'billing_records(status,voided_at,amount,appointment_id,line_type))',
      '*,invoice_items(id,description,amount,line_no,billing_record_id,'
          'billing_records(status,voided_at,amount,appointment_id))',
    ], (cols) => _db.from('invoices').select(cols).eq('id', invoiceId).eq('patient_id', patientId).maybeSingle());
    if (inv == null || !_ownedBy(inv, patientId)) return null;

    final items = ((inv['invoice_items'] as List?) ?? const []).cast<Map<String, dynamic>>().toList()
      ..sort((x, y) => _num(x['line_no']).compareTo(_num(y['line_no'])));
    final billIds = [for (final i in items) _str(i['billing_record_id'])]..removeWhere((id) => id.isEmpty);
    final apptId = items
        .map((i) => _str(_one(i['billing_records'])?['appointment_id']))
        .firstWhere((id) => id.isNotEmpty, orElse: () => '');

    final results = await Future.wait([
      _loadAppointment(apptId),
      _loadPatient(_str(inv['patient_id'])),
      _receiptsFor(billIds),
    ]);
    final a = results[0] as Map<String, dynamic>?;
    final patient = results[1] as Map<String, dynamic>?;
    final receipts = results[2] as List<Map<String, dynamic>>;

    double subtotal = 0, adjust = 0, total = 0;
    final rows = <List<String>>[];
    for (final it in items) {
      final b = _one(it['billing_records']) ?? const {};
      final snap = _num(it['amount']);
      final live = b['amount'] == null ? snap : _num(b['amount']);
      final voided = b['voided_at'] != null;
      final status = voided ? 'Voided' : (_str(b['status']).toLowerCase() == 'paid' ? 'Paid' : 'Unpaid');
      subtotal += snap;
      if (voided) {
        adjust -= snap;
      } else {
        adjust += live - snap;
        total += live;
      }
      final lineType = _str(b['line_type']);
      final kind = lineType.isNotEmpty && lineType != 'service' ? ' ($lineType)' : '';
      final diff = voided ? -snap : live - snap;
      rows.add([
        '${_str(it['description']).isEmpty ? '-' : _str(it['description'])}$kind',
        status,
        pdfMoney(snap),
        diff != 0 ? '${diff > 0 ? '+' : ''}${pdfMoney(diff)}' : '-',
        voided ? '-' : pdfMoney(live),
      ]);
    }

    final covered = receipts.fold<double>(0, (s, r) => s + _num(r['amount_due']));
    final depApplied = receipts.fold<double>(0, (s, r) => s + _num(r['deposit_applied']));
    // A deposit not yet applied at a counter still belongs to this bill.
    final deposit = depApplied > 0 ? depApplied : _depositCredited(a);
    final balance = (total - deposit - covered).clamp(0, double.infinity).toDouble();

    final totals = <PdfTotal>[PdfTotal('Subtotal', pdfMoney(subtotal))];
    if (adjust.abs() > 0.004) {
      totals.add(PdfTotal('Adjustments / Discounts / Voids', pdfMoney(adjust), minus: adjust < 0));
    }
    totals.add(PdfTotal('Total Service Cost', pdfMoney(total)));
    if (deposit > 0) totals.add(PdfTotal('Less: Booking Deposit Credited', '-${pdfMoney(deposit)}', minus: true));
    if (covered > 0) {
      final refs = receipts.map((r) => _str(r['reference_no'])).join(', ');
      totals.add(PdfTotal('Less: Payments Received ($refs)', '-${pdfMoney(covered)}', minus: true));
    }
    totals.add(PdfTotal('Final Balance Due', pdfMoney(balance), strong: true));

    return ClinicPdfSpec(
      title: 'Invoice',
      numberLabel: 'Invoice No.',
      number: _str(inv['invoice_no']),
      dateLabel: 'Date Issued',
      date: pdfDate(inv['billed_on']),
      left: _people(a, patient, _str(inv['patient_name'])),
      right: [
        ('Attending Dentist', _doctorName(_str(inv['doctor_name']), a)),
        (
          'Services',
          a != null
              ? _nonEmpty(_services(a).map((p) => _str(p['name'])).join(', '))
              : items.map((i) => _str(i['description'])).join(', '),
        ),
        ('Invoice Status', balance <= 0 ? 'Paid in full' : 'Balance outstanding'),
      ],
      columns: const [
        PdfColumn('Description', 70),
        PdfColumn('Status', 22),
        PdfColumn('Rate', 32, alignRight: true),
        PdfColumn('Adjustment', 30, alignRight: true),
        PdfColumn('Amount', 32, alignRight: true),
      ],
      rows: rows,
      totals: totals,
      stamp: balance <= 0 ? 'PAID IN FULL' : '',
      note: 'This invoice is an official statement of charges for the visit above.',
      fileName: pdfFileName('Invoice', _str(a?['confirmation_code']).isNotEmpty ? _str(a!['confirmation_code']) : _str(inv['invoice_no'])),
    );
  }

  // --- Payment receipt ---------------------------------------------------------

  /// The Payment Receipt for [receiptId], as `pdfPaymentReceiptSpec` draws it.
  /// Its remaining balance counts only receipts issued up to and including
  /// this one, so a later payment never rewrites what it said.
  static Future<ClinicPdfSpec?> paymentReceiptSpec(String receiptId) async {
    final patientId = await _signedInPatientId();
    final r = await _db
        .from('payment_receipts')
        .select('*')
        .eq('id', receiptId)
        .eq('patient_id', patientId)
        .maybeSingle();
    if (r == null || !_ownedBy(r, patientId)) return null;

    final lineRows = await _db
        .from('receipt_items')
        .select('description,amount,line_no,billing_record_id')
        .eq('receipt_id', _str(r['id']));
    final lines = (lineRows as List).cast<Map<String, dynamic>>().toList()
      ..sort((x, y) => _num(x['line_no']).compareTo(_num(y['line_no'])));
    final billIds = [
      for (final l in lines) _str(l['billing_record_id']),
      _str(r['billing_record_id']),
    ]..removeWhere((id) => id.isEmpty);

    var apptId = '';
    if (billIds.isNotEmpty) {
      final bills = await _db.from('billing_records').select('appointment_id').inFilter('id', billIds);
      apptId = [for (final b in (bills as List)) _str(b['appointment_id'])]
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
    }

    // The invoice this payment settles, and every charge on it.
    var invId = _str(r['invoice_id']);
    if (invId.isEmpty && billIds.isNotEmpty) {
      final ii = await _db.from('invoice_items').select('invoice_id').inFilter('billing_record_id', billIds);
      invId = [for (final i in (ii as List)) _str(i['invoice_id'])]
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
    }
    Map<String, dynamic>? inv;
    if (invId.isNotEmpty) {
      inv = await _db
          .from('invoices')
          .select('invoice_no,invoice_items(amount,billing_record_id,billing_records(amount,voided_at))')
          .eq('id', invId)
          .maybeSingle();
    }
    final invBillIds = inv != null
        ? ([for (final i in ((inv['invoice_items'] as List?) ?? const [])) _str(i['billing_record_id'])]
          ..removeWhere((id) => id.isEmpty))
        : billIds;

    final results = await Future.wait([
      _loadAppointment(apptId),
      _loadPatient(_str(r['patient_id'])),
      _receiptsFor(invBillIds),
    ]);
    final a = results[0] as Map<String, dynamic>?;
    final patient = results[1] as Map<String, dynamic>?;
    final receipts = results[2] as List<Map<String, dynamic>>;

    var txRef = '';
    if (apptId.isNotEmpty && _str(r['payment_method']) != 'Cash') {
      try {
        final vp = await _db
            .from('visit_payment_requests')
            .select('payment_ref,status,paid_method')
            .eq('appointment_id', apptId)
            .inFilter('status', ['used', 'paid']);
        txRef = [for (final v in (vp as List)) _str(v['payment_ref'])]
            .firstWhere((ref) => ref.isNotEmpty, orElse: () => '');
      } catch (_) {
        // Table absent on older databases.
      }
    }

    final dep = _num(r['deposit_applied']);
    final due = _num(r['amount_due']);
    final received = _num(r['amount_received']);
    final rows = lines.isNotEmpty
        ? [for (final l in lines) [_nonEmpty(_str(l['description'])), pdfMoney(_num(l['amount']))]]
        : [[_nonEmpty(_str(r['procedure_name'])), pdfMoney(due + dep)]];

    double invTotal;
    if (inv != null) {
      invTotal = 0;
      for (final it in ((inv['invoice_items'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
        final b = _one(it['billing_records']) ?? const {};
        if (b['voided_at'] != null) continue;
        invTotal += b['amount'] == null ? _num(it['amount']) : _num(b['amount']);
      }
    } else {
      final sum = lines.fold<double>(0, (s, l) => s + _num(l['amount']));
      invTotal = sum != 0 ? sum : due + dep;
    }
    final issuedAt = _str(r['issued_at']);
    final upTo = receipts.where((x) => _str(x['issued_at']).compareTo(issuedAt) <= 0 || x['id'] == r['id']).toList();
    if (!upTo.any((x) => x['id'] == r['id'])) upTo.add(r);
    final coveredSoFar = upTo.fold<double>(0, (s, x) => s + _num(x['amount_due']) + _num(x['deposit_applied']));
    final remaining = (invTotal - coveredSoFar).clamp(0, double.infinity).toDouble();

    final totals = <PdfTotal>[PdfTotal('Charges Settled', pdfMoney(due + dep))];
    if (dep > 0) totals.add(PdfTotal('Less: Booking Deposit Credited', '-${pdfMoney(dep)}', minus: true));
    totals.add(PdfTotal('Amount Due', pdfMoney(due)));
    totals.add(PdfTotal('Amount Received', pdfMoney(received)));
    if (received > due) totals.add(PdfTotal('Change', pdfMoney(received - due)));
    totals.add(PdfTotal('Remaining Balance', pdfMoney(remaining), strong: true));

    final issuedBy = _str(r['issued_by_name']);
    return ClinicPdfSpec(
      title: 'Payment Receipt',
      numberLabel: 'Receipt No.',
      number: _str(r['reference_no']),
      dateLabel: 'Payment Date',
      date: pdfDate(_str(r['paid_on']).isNotEmpty ? r['paid_on'] : r['issued_at']),
      left: _people(a, patient, _str(r['patient_name'])),
      right: [
        ('Attending Dentist', _doctorName(_str(r['doctor_name']), a)),
        ('Related Invoice', _nonEmpty(_str(inv?['invoice_no']))),
        ('Payment Method', pdfMethod(_str(r['payment_method']))),
        ('Transaction Reference', txRef.isNotEmpty ? txRef : _str(r['reference_no'])),
        if (issuedBy.isNotEmpty) ('Received By', issuedBy),
      ],
      columns: const [PdfColumn('Service', 140), PdfColumn('Amount', 46, alignRight: true)],
      rows: rows,
      totals: totals,
      stamp: 'PAID',
      note: "This receipt is the clinic's official record of the payment above.",
      fileName: pdfFileName(
        'Payment-Receipt',
        _str(a?['confirmation_code']).isNotEmpty ? _str(a!['confirmation_code']) : _str(r['reference_no']),
      ),
    );
  }

  // --- Deposit receipt ---------------------------------------------------------

  /// The Deposit Receipt for a booking's down payment, on the same template.
  /// Built from the appointment row itself: a down payment has no receipt
  /// row of its own.
  static Future<ClinicPdfSpec?> depositReceiptSpec(Appointment appointment) async {
    final patientId = await _signedInPatientId();
    final a = await _loadAppointment(appointment.id);
    if (a == null || !_ownedBy(a, patientId)) return null;
    // Only a down payment the server recorded as paid has a receipt.
    if (a['downpayment_paid_at'] == null) return null;
    final patient = await _loadPatient(patientId);
    final paid = appointment.amountPaid;
    final code = appointment.checkInPayload;
    return ClinicPdfSpec(
      title: 'Deposit Receipt',
      numberLabel: 'Reference No.',
      number: code,
      dateLabel: 'Payment Date',
      date: pdfDate(appointment.downpaymentPaidAt),
      left: _people(a, patient, ''),
      right: [
        ('Attending Dentist', appointment.doctorName.isEmpty ? 'Assigned by the clinic' : appointment.doctorName),
        ('Services', appointment.serviceName),
        ('Payment Method', pdfMethod(appointment.paymentMethod)),
      ],
      columns: const [PdfColumn('Description', 140), PdfColumn('Amount', 46, alignRight: true)],
      rows: [
        [
          'Booking down payment'
              '${appointment.downpaymentPercent > 0 ? ' (${appointment.downpaymentPercent}%)' : ''}',
          pdfMoney(paid),
        ],
      ],
      totals: [
        PdfTotal('Estimated Service Cost', pdfMoney(appointment.totalPrice)),
        PdfTotal('Down Payment Received', '-${pdfMoney(paid)}', minus: true),
        PdfTotal('Estimated Balance Due at Clinic', pdfMoney(appointment.balanceDue), strong: true),
      ],
      stamp: 'PAID',
      note: 'This receipt confirms the down payment that reserves the appointment above. '
          'The remaining balance is settled at the clinic.',
      fileName: pdfFileName('Deposit-Receipt', code),
    );
  }

  // --- Shared loaders and helpers -----------------------------------------------

  static Future<Map<String, dynamic>?> _loadAppointment(String id) async {
    if (id.isEmpty) return null;
    return _firstThatWorks([
      '$_apptColumns,payment_request_id,reschedule_fee_total,deposit_forfeited_at',
      '$_apptColumns,payment_request_id,reschedule_fee_total',
      '$_apptColumns,payment_request_id',
      _apptColumns,
    ], (cols) => _db.from('appointments').select(cols).eq('id', id).maybeSingle());
  }

  static Future<Map<String, dynamic>?> _loadPatient(String id) async {
    if (id.isEmpty) return null;
    try {
      return await _db.from('patients').select('first_name,last_name,patient_number').eq('id', id).maybeSingle();
    } catch (_) {
      return null;
    }
  }

  /// Every receipt covering any of [billIds], oldest first.
  static Future<List<Map<String, dynamic>>> _receiptsFor(List<String> billIds) async {
    if (billIds.isEmpty) return [];
    try {
      final items = await _db.from('receipt_items').select('receipt_id').inFilter('billing_record_id', billIds);
      final ids = {for (final i in (items as List)) _str(i['receipt_id'])}..remove('');
      if (ids.isEmpty) return [];
      final rows = await _db.from('payment_receipts').select('*').inFilter('id', ids.toList());
      return (rows as List).cast<Map<String, dynamic>>().toList()
        ..sort((x, y) => _str(x['issued_at']).compareTo(_str(y['issued_at'])));
    } catch (e) {
      debugPrint('receipts lookup failed: $e');
      return [];
    }
  }

  /// Tries each column list in turn — older databases lack some columns —
  /// and throws the last error if none works.
  static Future<Map<String, dynamic>?> _firstThatWorks(
    List<String> selects,
    Future<dynamic> Function(String cols) run,
  ) async {
    Object? last;
    for (final cols in selects) {
      try {
        return await run(cols) as Map<String, dynamic>?;
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('no query ran');
  }

  static List<Map<String, dynamic>> _services(Map<String, dynamic> a) {
    final list = [
      for (final s in ((a['appointment_services'] as List?) ?? const []))
        if (_one((s as Map)['procedures']) != null) _one(s['procedures'])!,
    ];
    if (list.isNotEmpty) return list;
    final direct = _one(a['procedures']);
    return direct == null ? [] : [direct];
  }

  static int _minutes(Map<String, dynamic> a) => _services(a).fold(0, (s, p) {
        final d = _num(p['duration_min']);
        return s + (d > 0 ? d.toInt() : 30);
      });

  /// The booking deposit that counts toward the bill: paid, less any
  /// reschedule fees taken from it.
  static double _depositCredited(Map<String, dynamic>? a) {
    if (a == null) return 0;
    final down = _num(a['downpayment_amount']);
    if (a['downpayment_paid_at'] == null || down <= 0) return 0;
    final fees = _num(a['reschedule_fee_total']);
    return down - (fees < down ? fees : down);
  }

  static List<(String, String)> _people(Map<String, dynamic>? a, Map<String, dynamic>? patient, String snapName) {
    final fromPatient = patient == null ? '' : '${_str(patient['first_name'])} ${_str(patient['last_name'])}'.trim();
    final name = snapName.isNotEmpty ? snapName : fromPatient;
    return [
      ('Patient Name', _nonEmpty(name)),
      ('Patient ID', pdfPatientNo(patient?['patient_number'])),
      ('Appointment Reference', _nonEmpty(_str(a?['confirmation_code']))),
      (
        'Appointment Schedule',
        a == null ? '-' : pdfSchedule(a['appointment_date'], a['appointment_time'], _minutes(a)),
      ),
    ];
  }

  /// A patient session often cannot read `members`, so the embedded name can
  /// come back empty; the clinic roster already in memory fills it in.
  static String _doctorName(String snap, Map<String, dynamic>? a) {
    if (snap.isNotEmpty) return snap;
    final embedded = _str(_one(a?['members'])?['full_name']);
    if (embedded.isNotEmpty) return embedded;
    final rostered = dentistById(_str(a?['doctor_id']))?.name ?? '';
    return rostered.isNotEmpty ? rostered : 'Assigned by the clinic';
  }

  static Map<String, dynamic>? _one(Object? v) {
    if (v is List) return v.isEmpty ? null : Map<String, dynamic>.from(v.first as Map);
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static String _str(Object? v) => v?.toString().trim() ?? '';
  static double _num(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  static String _nonEmpty(String s) => s.isEmpty ? '-' : s;
}

/// A document request refused before any data was read: no session, or no
/// patient record for it. [message] is safe to show.
class DocumentAccessException implements Exception {
  final String message;
  const DocumentAccessException(this.message);

  @override
  String toString() => message;
}
