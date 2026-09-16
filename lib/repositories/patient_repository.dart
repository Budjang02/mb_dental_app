import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/patient_document.dart';
import 'package:mb_dental_app/models/patient_message.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/services/push_notification_service.dart';
import 'package:mb_dental_app/services/supabase_service.dart';

/// The parts of the record a realtime change can refresh on their own, so an
/// edit on one table does not pull the whole chart down again.
enum SyncSection { appointments, billing, wallet, chart, treatmentPlan, documents, messages }

/// The signed-in patient's record, held in memory and backed by Supabase.
///
/// Screens read it synchronously through the getters below and rebuild on
/// [notifyListeners], so nothing here returns a future to the widget tree.
/// [load] refills everything from the server; mutations write through to
/// Supabase first and only then update the local copy, so the screens never
/// show a change the database rejected.
class PatientRepository extends ChangeNotifier {
  static final PatientRepository _instance = PatientRepository._internal();
  factory PatientRepository() => _instance;

  PatientRepository._internal() {
    ClinicCatalog().addListener(_onCatalogChanged);
  }

  /// Dentists in the clinic roster when the record was last resolved.
  int _rosterSize = 0;

  /// A patient session cannot read `members`, so every visit, charge, chart
  /// entry and plan names its dentist from the roster `patient_doctor_roster()`
  /// returns. When that roster arrives or changes after the record was
  /// fetched, the parts that print a dentist's name are read again — otherwise
  /// they stay on "Assigned by the clinic" until the next full load.
  void _onCatalogChanged() {
    final size = ClinicCatalog().doctors.length;
    if (size == _rosterSize) return;
    _rosterSize = size;
    if (_patient == null || _isLoading) return;
    for (final section in const [
      SyncSection.appointments,
      SyncSection.billing,
      SyncSection.chart,
      SyncSection.treatmentPlan,
    ]) {
      unawaited(refreshSection(section));
    }
  }

  Patient? _patient;
  List<Appointment> _appointments = const [];
  List<Treatment> _treatments = const [];
  List<TreatmentPlanItem> _treatmentPlan = const [];
  List<TreatmentPlanSummary> _treatmentPlans = const [];
  List<Payment> _billing = const [];
  List<WalletTransaction> _transactions = const [];
  List<PatientDocument> _documents = const [];
  List<Map<String, String>> _toothRecords = const [];
  List<Map<String, String>> _treatmentNotes = const [];
  List<PatientMessage> _messages = const [];
  bool _isApprovedForBooking = true;

  /// Rows from the `notifications` table, addressed to this account.
  List<NotificationItem> _tableNotifications = const [];

  /// What this account has read or dismissed in the derived feed.
  Map<String, NotificationState> _notificationState = const {};

  /// Everything the bell shows: [_tableNotifications] plus the notices built
  /// from the record by [NotificationFeed]. Rebuilt by [_rebuildNotifications].
  List<NotificationItem> _notifications = const [];

  /// Signed preview links, keyed by document id. Fetched in one batch after a
  /// load so the file list can show thumbnails without a request per row.
  Map<String, String> _documentUrls = const {};
  double _walletBalance = 0;

  bool _isLoading = false;
  String? _loadError;
  Future<void>? _inFlight;

  /// Alert ids already shown to this patient in this session. A refresh that
  /// brings the same rows back must not re-raise banners for them.
  final Set<String> _announcedNotificationIds = {};

  // --- Load state ---

  /// True while the first load is still running, so screens can show a spinner
  /// instead of an empty chart the patient might mistake for a real one.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null. Set when the account has no linked
  /// patient record as well as on network failures.
  String? get loadError => _loadError;

  bool get hasLoaded => _patient != null;

  /// Pulls the whole record from Supabase. Concurrent calls share one request,
  /// so several screens appearing at once do not each hit the network.
  Future<void> load({bool force = false}) {
    if (_inFlight != null && !force) return _inFlight!;
    final request = _load();
    _inFlight = request;
    return request.whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    // Read before anything is assigned: nothing announced yet means this is
    // the patient's first load of the session.
    final isFirstLoad = _announcedNotificationIds.isEmpty;

    try {
      // The roster first: a patient session cannot read `members`, so the
      // dentist on each visit, charge and chart entry is named from it.
      try {
        await ClinicCatalog().load();
      } catch (e) {
        debugPrint('Clinic roster unavailable for doctor names: $e');
      }

      _rosterSize = ClinicCatalog().doctors.length;

      final userId = SupabaseService.currentUserId;
      final results = await Future.wait([
        PatientApi.loadAll(),
        if (userId != null) PatientApi.fetchNotificationState(userId),
      ]);
      final snapshot = results[0] as PatientSnapshot;

      _patient = snapshot.patient;
      _appointments = snapshot.appointments;
      _treatments = snapshot.treatments;
      _treatmentPlan = snapshot.treatmentPlan;
      _treatmentPlans = snapshot.treatmentPlans;
      _billing = snapshot.billing;
      _tableNotifications = snapshot.notifications;
      _notificationState =
          results.length > 1 ? results[1] as Map<String, NotificationState> : const {};
      _transactions = snapshot.transactions;
      _documents = snapshot.documents;
      _toothRecords = snapshot.toothRecords;
      _treatmentNotes = snapshot.treatmentNotes;
      _messages = snapshot.messages;
      _walletBalance = snapshot.walletBalance;
      _isApprovedForBooking = snapshot.isApprovedForBooking;
      _rebuildNotifications(isFirstLoad: isFirstLoad);
      // Deliberately after the record is in place: thumbnails are a nicety and
      // must never hold up the rest of the chart, nor fail the load.
      unawaited(_refreshDocumentUrls());
    } on NoPatientRecordException catch (e) {
      _loadError = e.message;
    } catch (e) {
      _loadError = 'We could not load your records. Check your connection and try again.';
      debugPrint('PatientRepository.load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Recomposes the bell from the table rows and the record, then raises a
  /// banner for anything new since the last composition.
  void _rebuildNotifications({required bool isFirstLoad}) {
    final feed = NotificationFeed.build(
      appointments: _appointments,
      billing: _billing,
      transactions: _transactions,
      plans: _treatmentPlans,
      state: _notificationState,
    );
    for (final notice in feed) {
      PatientApi.notificationChannels[notice.item.id] = notice.channel;
    }
    _notifications = [..._tableNotifications, for (final notice in feed) notice.item];
    _announceNew(_notifications, isFirstLoad: isFirstLoad);
  }

  /// Raises a banner for alerts that have arrived since the last read.
  ///
  /// Skipped on the very first load: a patient opening the app is not "sent"
  /// every unread alert they already had, they just see the badge.
  void _announceNew(List<NotificationItem> incoming, {required bool isFirstLoad}) {
    for (final item in incoming) {
      if (!_announcedNotificationIds.add(item.id)) continue;
      if (isFirstLoad || item.isRead) continue;
      PushNotificationService().deliver(
        item,
        channel: PatientApi.notificationChannels[item.id] ?? PushChannel.statusUpdate,
      );
    }
  }

  /// Re-reads the alerts and the read state, so a banner can appear without
  /// pulling the whole record down again.
  Future<void> refreshNotifications() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || _patient == null) return;
    try {
      final results = await Future.wait([
        PatientApi.fetchNotifications(userId),
        PatientApi.fetchNotificationState(userId),
      ]);
      if (_patient == null) return;
      _tableNotifications = results[0] as List<NotificationItem>;
      _notificationState = results[1] as Map<String, NotificationState>;
      _rebuildNotifications(isFirstLoad: false);
      notifyListeners();
    } catch (e) {
      debugPrint('PatientRepository.refreshNotifications failed: $e');
    }
  }

  /// Re-reads one part of the record after a realtime change to the tables
  /// behind it. Failures are logged and leave the current copy on screen: the
  /// next change, resume or full load brings it back in step.
  Future<void> refreshSection(SyncSection section) async {
    final patientId = _patient?.id;
    final userId = SupabaseService.currentUserId;
    if (patientId == null || patientId.isEmpty || userId == null) return;

    // A sign-out or account switch while the request was out must not write
    // the previous patient's rows back in.
    bool stillCurrent() => _patient?.id == patientId;

    try {
      switch (section) {
        case SyncSection.appointments:
          final appointments = await PatientApi.fetchAppointments(patientId);
          if (!stillCurrent()) return;
          _appointments = appointments;
          _treatments = PatientApi.treatmentsFrom(appointments);
        case SyncSection.billing:
          final billing = await PatientApi.fetchBilling(patientId);
          if (!stillCurrent()) return;
          _billing = billing;
        case SyncSection.wallet:
          final transactions = await PatientApi.fetchTransactions(patientId);
          final balance =
              await PatientApi.walletBalanceFor(userId: userId, transactions: transactions);
          if (!stillCurrent()) return;
          _transactions = transactions;
          _walletBalance = balance;
        case SyncSection.chart:
          final results = await Future.wait([
            PatientApi.fetchToothRecords(patientId),
            PatientApi.fetchTreatmentNotes(patientId),
          ]);
          if (!stillCurrent()) return;
          _toothRecords = results[0];
          _treatmentNotes = results[1];
        case SyncSection.treatmentPlan:
          final plan = await PatientApi.fetchTreatmentPlan(patientId);
          if (!stillCurrent()) return;
          _treatmentPlan = plan.items;
          _treatmentPlans = plan.plans;
        case SyncSection.documents:
          final documents = await PatientApi.fetchDocuments(patientId);
          if (!stillCurrent()) return;
          _documents = documents;
          unawaited(_refreshDocumentUrls());
        case SyncSection.messages:
          final messages = await PatientApi.fetchMessages(patientId);
          if (!stillCurrent()) return;
          _messages = messages;
      }
      // Appointments, messages, charges and wallet movements are what the
      // notification feed is built from.
      if (section == SyncSection.appointments ||
          section == SyncSection.billing ||
          section == SyncSection.wallet ||
          section == SyncSection.treatmentPlan) {
        _rebuildNotifications(isFirstLoad: false);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('PatientRepository.refreshSection($section) failed: $e');
    }
  }

  /// Drops everything held for the previous account. Called on sign-out so the
  /// next patient to use the device never sees the last one's chart.
  void clear() {
    _patient = null;
    _appointments = const [];
    _treatments = const [];
    _treatmentPlan = const [];
    _treatmentPlans = const [];
    _billing = const [];
    _tableNotifications = const [];
    _notificationState = const {};
    _notifications = const [];
    _transactions = const [];
    _documents = const [];
    _toothRecords = const [];
    _treatmentNotes = const [];
    _messages = const [];
    _documentUrls = const {};
    _walletBalance = 0;
    _isApprovedForBooking = true;
    _announcedNotificationIds.clear();
    _loadError = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Installs a record directly, bypassing Supabase, so the slot and booking
  /// rules can be tested without a live session.
  @visibleForTesting
  void seedForTest({
    required Patient patient,
    List<Appointment> appointments = const [],
    List<WalletTransaction> transactions = const [],
    List<NotificationItem> notifications = const [],
    List<PatientMessage> messages = const [],
    Map<String, NotificationState> notificationState = const {},
    double walletBalance = 0,
    bool isApprovedForBooking = true,
  }) {
    _patient = patient;
    _appointments = List.of(appointments);
    _treatments = const [];
    _treatmentPlan = const [];
    _treatmentPlans = const [];
    _billing = const [];
    _tableNotifications = List.of(notifications);
    _notificationState = Map.of(notificationState);
    _transactions = List.of(transactions);
    _documents = const [];
    _toothRecords = const [];
    _treatmentNotes = const [];
    _messages = List.of(messages);
    _documentUrls = const {};
    _walletBalance = walletBalance;
    _isApprovedForBooking = isApprovedForBooking;
    _isLoading = false;
    _loadError = null;
    _rebuildNotifications(isFirstLoad: true);
    notifyListeners();
  }

  /// Adds a booking to the in-memory schedule only. Test-only counterpart to
  /// [addAppointment], which always writes through to Supabase.
  @visibleForTesting
  void addAppointmentForTest(Appointment appointment) {
    _appointments = [..._appointments, appointment];
    notifyListeners();
  }

  // --- Reads ---

  /// Empty placeholder until [load] completes, so screens that build before the
  /// first frame of data can read `.firstName` without a null check.
  static final Patient _empty = Patient(
    id: '',
    patientCode: '',
    firstName: '',
    lastName: '',
    username: '',
    email: '',
    phone: '',
  );

  Patient get patient => _patient ?? _empty;

  /// False until the clinic approves a self-registered account
  /// (`patients.approved_at`). Booking is refused while false.
  bool get isApprovedForBooking => _isApprovedForBooking;

  List<Appointment> get appointments => List.unmodifiable(_appointments);

  /// The website's next-appointment rule (js/render-patient.js): from every
  /// appointment, keep `appointment_date >= today` whose status is `Confirmed`
  /// or `Pending` (case-insensitive), sort ascending by date then time, take
  /// the first. `Ongoing`, `Completed`, `Cancelled` and `No-Show` never appear.
  Appointment? get nextUpcomingAppointment {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = _appointments.where((a) {
      final status = a.rawStatus.toLowerCase();
      if (status != 'confirmed' && status != 'pending') return false;
      return !DateTime(a.date.year, a.date.month, a.date.day).isBefore(today);
    }).toList()
      ..sort((a, b) => '${a.rawDate} ${a.rawTime}'.compareTo('${b.rawDate} ${b.rawTime}'));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<Treatment> get treatments => List.unmodifiable(_treatments);

  /// The procedures the clinic has planned but not yet carried out.
  List<TreatmentPlanItem> get treatmentPlan => List.unmodifiable(_treatmentPlan);

  List<Payment> get billing => List.unmodifiable(_billing);

  /// Newest first. `List.sort` is not stable, so insertion order breaks ties
  /// explicitly — two alerts raised in the same millisecond (a payment and the
  /// booking it paid for) must not swap places between reads.
  List<NotificationItem> get notifications {
    final indexed = List<(int, NotificationItem)>.generate(
      _notifications.length,
      (i) => (i, _notifications[i]),
    )..sort((a, b) {
        final byTime = b.$2.createdAt.compareTo(a.$2.createdAt);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return List.unmodifiable(indexed.map((e) => e.$2));
  }

  int get unreadNotificationCount => _notifications.where((n) => !n.isRead).length;

  double get walletBalance => _walletBalance;

  List<WalletTransaction> get transactions {
    final sorted = List<WalletTransaction>.from(_transactions)
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return List.unmodifiable(sorted);
  }

  /// The patient's uploaded files, newest first — what the booking wizard
  /// offers when a visit needs a prescription or referral attached.
  List<PatientDocument> get documents {
    final sorted = List<PatientDocument>.from(_documents)
      ..sort((a, b) => b.uploadedOn.compareTo(a.uploadedOn));
    return List.unmodifiable(sorted);
  }

  /// The clinic's per-tooth chart entries, newest first — what the odontogram
  /// colours each tooth from.
  List<Map<String, String>> get toothRecords => List.unmodifiable(_toothRecords);

  /// The clinic's treatment history from `treatment_notes`, newest first —
  /// what the Treatment Notes page lists. Falls back to the chart entries for a
  /// patient with no history written yet, so the page is not blank beside a
  /// chart that has marks on it.
  List<Map<String, String>> get treatmentNotes =>
      List.unmodifiable(_treatmentNotes.isNotEmpty ? _treatmentNotes : _toothRecords);

  /// The support conversation with the clinic, oldest first and newest at the
  /// bottom — the order a chat is read in, whatever order the rows arrived in.
  List<PatientMessage> get messages {
    final sorted = List<PatientMessage>.from(_messages)
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return List.unmodifiable(sorted);
  }

  /// Messages from the clinic the patient has not opened yet — what the chat
  /// bubble badges.
  int get unreadMessageCount =>
      _messages.where((m) => m.isFromClinic && !m.isRead).length;

  /// A cached signed link for [document], or null when one is not ready. Used
  /// for the thumbnail in the file list; the viewer signs on demand when this
  /// is missing.
  String? previewUrlFor(PatientDocument document) => _documentUrls[document.id];

  Future<void> _refreshDocumentUrls() async {
    if (_documents.isEmpty) {
      _documentUrls = const {};
      return;
    }
    final urls = await PatientApi.signedUrlsForDocuments(_documents);
    _documentUrls = urls;
    notifyListeners();
  }

  /// The bytes of a file, for rendering a PDF inside the app.
  Future<Uint8List?> documentBytes(PatientDocument document) =>
      PatientApi.downloadDocument(document);

  /// A temporary link to open or download [document]. Patient files are private
  /// in storage, so this has to be fetched per view rather than stored.
  Future<String?> documentUrl(PatientDocument document) =>
      PatientApi.signedUrlForDocument(document);

  // --- Slot availability ---

  /// Whether a [durationMinutes] block starting at [startMinute] on [day] is
  /// free. A slot is unavailable when the clinic is closed that day or during
  /// the block, when the block would run past closing, or when it overlaps a
  /// booking that still holds its slot. [excludeAppointmentId] lets a
  /// reschedule ignore the booking it is moving.
  ///
  /// Checked against this patient's own bookings only — their chart is all RLS
  /// lets the app see. The clinic confirms against the full diary, which is why
  /// a new booking lands as pending rather than confirmed.
  bool isSlotAvailable({
    required DateTime day,
    required int startMinute,
    required int durationMinutes,
    String? excludeAppointmentId,
  }) {
    if (!isClinicOpenOn(day)) return false;
    if (startMinute < clinicOpenMinute) return false;
    if (startMinute + durationMinutes > clinicCloseMinute) return false;

    final endMinute = startMinute + durationMinutes;
    if (isClinicClosedDuring(day, startMinute, endMinute)) return false;

    for (final booked in _appointments) {
      if (!booked.holdsSlot) continue;
      if (booked.id == excludeAppointmentId) continue;
      if (!_isSameDay(booked.date, day)) continue;

      final bookedStart = booked.startMinuteOfDay;
      if (bookedStart == null) continue;
      final bookedEnd = bookedStart + booked.durationMinutes;

      // Half-open intervals: a block may start exactly when another ends.
      if (startMinute < bookedEnd && bookedStart < endMinute) return false;
    }
    return true;
  }

  /// Every 15-minute start on [day] that can still fit a [durationMinutes]
  /// block, with the taken ones flagged rather than dropped — the picker greys
  /// them out so the patient can see the day is filling up.
  List<SlotOption> slotOptionsFor({
    required DateTime day,
    required int durationMinutes,
    String? excludeAppointmentId,
  }) {
    final now = DateTime.now();
    return slotStartsFor(day, durationMinutes).map((startMinute) {
      final isPast = _isSameDay(day, now) && startMinute <= now.hour * 60 + now.minute;
      final available = !isPast &&
          isSlotAvailable(
            day: day,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            excludeAppointmentId: excludeAppointmentId,
          );
      return SlotOption(
        startMinute: startMinute,
        durationMinutes: durationMinutes,
        isAvailable: available,
      );
    }).toList();
  }

  /// Whether [day] has at least one bookable start left for a
  /// [durationMinutes] visit. The schedule picker calls this per rendered
  /// day to grey out dates that are closed or already full, so a patient
  /// never taps into an empty slot list.
  bool hasOpenSlotOn({
    required DateTime day,
    required int durationMinutes,
    String? excludeAppointmentId,
  }) {
    for (final startMinute in slotStartsFor(day, durationMinutes)) {
      if (isSlotAvailable(
        day: day,
        startMinute: startMinute,
        durationMinutes: durationMinutes,
        excludeAppointmentId: excludeAppointmentId,
      )) {
        return true;
      }
    }
    return false;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --- Mutations ---

  /// Books a visit. It always lands as `Pending` — the clinic confirms bookings
  /// itself, and nothing the app sends can grant a confirmed slot.
  ///
  /// Reloads afterwards rather than guessing the stored row, because the
  /// clinic's own triggers decide the reference numbers and any alert raised.
  ///
  /// Throws [PatientNotApprovedException] before touching the network while
  /// the clinic has not approved the account.
  Future<Appointment?> addAppointment({
    required String serviceName,
    required String doctorName,
    required DateTime date,
    required String timeSlot,
    String? doctorId,
    String? notes,
    String? paymentMethod,
    List<String> serviceIds = const [],
    int durationMinutes = 60,
    double totalPrice = 0,
    double amountPaid = 0,
  }) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;
    if (!_isApprovedForBooking) throw const PatientNotApprovedException();

    final id = await PatientApi.createAppointment(
      patientId: patientId,
      date: date,
      timeSlot: timeSlot,
      procedureIds: serviceIds,
      doctorId: doctorId,
      estimatedTotal: totalPrice,
      notes: notes,
      paymentMethod: paymentMethod,
    );

    await load(force: true);
    for (final appointment in _appointments) {
      if (appointment.id == id) return appointment;
    }
    return null;
  }

  /// Books a visit and pays the downpayment from the wallet in one database
  /// transaction.
  ///
  /// The balance check, the debit, the ledger entry and the booking all happen
  /// inside `book_appointment_with_wallet`, so the whole thing commits or none
  /// of it does.
  ///
  /// Throws [InsufficientWalletBalanceException] when the wallet will not cover
  /// [amountToPay] — the caller prompts a top-up — [SlotTakenException] when
  /// the slot went while the patient was on the summary step, and
  /// [PatientNotApprovedException] while the clinic has not approved the
  /// account.
  Future<Appointment?> checkoutWithWallet({
    required List<String> serviceIds,
    required DateTime date,
    required String timeSlot,
    required int durationMinutes,
    required double totalPrice,
    required double amountToPay,
    String? doctorId,
    String? notes,
    String method = 'GCash',
    String? referenceNo,
  }) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;
    if (!_isApprovedForBooking) throw const PatientNotApprovedException();

    final result = await PatientApi.bookAppointmentWithWallet(
      patientId: patientId,
      procedureIds: serviceIds,
      date: date,
      timeSlot: timeSlot,
      durationMinutes: durationMinutes,
      totalAmount: totalPrice,
      amountToPay: amountToPay,
      doctorId: doctorId,
      notes: notes,
      method: method,
      referenceNo: referenceNo,
    );

    // The function is not installed yet. Book it unpaid rather than charging
    // through a non-atomic path: an unpaid booking the clinic can settle is
    // recoverable, a debit with no booking is not.
    if (result == null) {
      return addAppointment(
        serviceName: '',
        doctorName: '',
        date: date,
        timeSlot: timeSlot,
        doctorId: doctorId,
        notes: notes,
        paymentMethod: method,
        serviceIds: serviceIds,
        durationMinutes: durationMinutes,
        totalPrice: totalPrice,
      );
    }

    // The balance the database now holds, before the reload lands, so the
    // wallet on screen never reads high for a frame.
    _walletBalance = result.walletBalance;
    notifyListeners();

    await load(force: true);
    for (final appointment in _appointments) {
      if (appointment.id == result.appointmentId) return appointment;
    }
    return null;
  }

  /// Settles an existing booking from the wallet. Same guarantees as
  /// [checkoutWithWallet].
  Future<bool> payAppointmentFromWallet({
    required String appointmentId,
    required double amount,
    String method = 'GCash',
  }) async {
    final result = await PatientApi.payAppointmentFromWallet(
      appointmentId: appointmentId,
      amount: amount,
      method: method,
    );
    if (result == null) return false;
    _walletBalance = result.walletBalance;
    notifyListeners();
    await load(force: true);
    return true;
  }

  Future<void> cancelAppointment(String id, {required String reason}) async {
    await PatientApi.cancelAppointment(id, reason: reason);
    _appointments = _appointments
        .map((a) => a.id == id
            ? a.copyWith(
                status: AppointmentStatus.cancelled,
                cancellationReason: reason,
                statusChangedAt: DateTime.now(),
              )
            : a)
        .toList();
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
  }

  /// Moves an existing appointment to a new date/time in place (does not
  /// create a new appointment) and resets it to pending re-confirmation.
  Future<void> rescheduleAppointment(
    String id, {
    required DateTime date,
    required String timeSlot,
    String? notes,
  }) async {
    await PatientApi.rescheduleAppointment(id, date: date, timeSlot: timeSlot, notes: notes);
    _appointments = _appointments
        .map((a) => a.id == id
            ? a.copyWith(
                date: date,
                timeSlot: timeSlot,
                status: AppointmentStatus.pending,
                notes: notes,
              )
            : a)
        .toList();
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
  }

  /// Marks everything on the bell read, each kind where it keeps its state:
  /// shared notices through `notif_mark_read`, app-only notices on the device,
  /// and `notifications` rows on that table. Messages are not on the bell.
  Future<void> markAllNotificationsRead() async {
    if (unreadNotificationCount == 0) return;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    final unread = [for (final n in _notifications) if (!n.isRead) n.id];
    final shared = unread.where(NotificationFeed.isShared).toList();
    final local = unread.where(NotificationFeed.isLocal).toList();
    final hasTableRows = unread.any((id) => !NotificationFeed.isDerived(id));

    if (hasTableRows) await PatientApi.markAllNotificationsRead(userId);

    final readAt = DateTime.now().toUtc();
    _tableNotifications = _tableNotifications
        .map((n) => n.isRead ? n : n.copyWith(isRead: true, readAt: readAt))
        .toList();
    _notificationState = {
      ..._notificationState,
      for (final key in [...shared, ...local])
        key: NotificationState(
          readAt: _notificationState[key]?.readAt ?? readAt,
          dismissedAt: _notificationState[key]?.dismissedAt,
        ),
    };
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();

    await Future.wait([
      PatientApi.markSharedNoticesRead(userId, shared),
      PatientApi.markLocalNoticesRead(userId, local),
    ]);
  }

  /// Marks one notice read where its kind keeps its read state, so the web
  /// platform and the patient's other devices see the same thing.
  Future<void> markNotificationRead(String id) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    if (NotificationFeed.isShared(id)) {
      _setNoticeState(id, read: true);
      await PatientApi.markSharedNoticesRead(userId, [id]);
      return;
    }
    if (NotificationFeed.isLocal(id)) {
      _setNoticeState(id, read: true);
      await PatientApi.markLocalNoticesRead(userId, [id]);
      return;
    }
    await PatientApi.markNotificationRead(id, userId: userId);
    applyNotificationReadState(id, isRead: true, readAt: DateTime.now().toUtc());
  }

  Future<void> markNotificationUnread(String id) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    if (NotificationFeed.isDerived(id)) {
      // The website's RPCs offer no unread write, so this only changes the
      // device copy.
      _setNoticeState(id, read: false);
      await PatientApi.forgetLocalRead(userId, id);
      return;
    }
    await PatientApi.markNotificationUnread(id, userId: userId);
    applyNotificationReadState(id, isRead: false, readAt: null);
  }

  /// Removes a notice from the bell: through `notif_dismiss` for a shared
  /// notice (the website hides it too), on the device for anything else.
  /// A `notifications` row has no dismissed state.
  Future<void> dismissNotification(String id) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || !NotificationFeed.isDerived(id)) return;
    final now = DateTime.now().toUtc();
    _notificationState = {
      ..._notificationState,
      id: NotificationState(readAt: _notificationState[id]?.readAt ?? now, dismissedAt: now),
    };
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
    if (NotificationFeed.isShared(id)) {
      await PatientApi.dismissSharedNotices(userId, [id]);
    } else {
      await PatientApi.dismissLocalNotices(userId, [id]);
    }
  }

  /// Marks one clinic message read on its `patient_messages` row.
  Future<void> markMessageRead(String messageId) async {
    final target = _messages.where((m) => m.id == messageId && !m.isRead);
    if (target.isEmpty) return;
    final now = DateTime.now();
    _messages = _messages.map((m) => m.id == messageId ? m.markedRead(now) : m).toList();
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
    try {
      await PatientApi.markMessageRead(messageId);
    } catch (e) {
      debugPrint('Could not mark message read: $e');
    }
  }

  void _setNoticeState(String key, {required bool read}) {
    _notificationState = {
      ..._notificationState,
      key: NotificationState(
        // First read time wins, the same rule `notif_mark_read` applies.
        readAt: read ? (_notificationState[key]?.readAt ?? DateTime.now().toUtc()) : null,
        dismissedAt: _notificationState[key]?.dismissedAt,
      ),
    };
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
  }
  /// Applies a read-state change that came from the database rather than from a
  /// tap here — a realtime `UPDATE` raised by the web platform, or this device's
  /// own write echoing back. No network call: the row is already the truth.
  ///
  /// Silently ignores an id this session does not hold, so an alert created
  /// elsewhere does not appear half-built; [refreshNotifications] brings that in
  /// whole instead.
  void applyNotificationReadState(String id, {required bool isRead, DateTime? readAt}) {
    var changed = false;
    _tableNotifications = _tableNotifications.map((n) {
      if (n.id != id || (n.isRead == isRead && n.readAt == readAt)) return n;
      changed = true;
      return n.copyWith(isRead: isRead, readAt: readAt);
    }).toList();
    if (!changed) return;
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
  }

  /// Pulls one alert in by id, for a realtime `INSERT` — cheaper than refetching
  /// the whole list, and it keeps the banner behaviour of [refreshNotifications].
  Future<void> applyRemoteNotification(String id) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || _patient == null) return;
    if (_tableNotifications.any((n) => n.id == id)) return;
    final item = await PatientApi.fetchNotification(id: id, userId: userId);
    if (item == null) return;
    _tableNotifications = [item, ..._tableNotifications];
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
  }

  /// Re-reads everything the clinic may have changed while the app was in the
  /// background. Called when the app comes back to the foreground, which is the
  /// fallback for any realtime event the device missed while asleep.
  Future<void> refreshOnResume() async {
    if (SupabaseService.currentUserId == null) return;
    await load(force: true);
  }

  Future<void> updatePatient({
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
    final patientId = _patient?.id;
    final userId = SupabaseService.currentUserId;
    if (patientId == null || userId == null) return;

    await PatientApi.updatePatient(
      patientId: patientId,
      userId: userId,
      firstName: firstName,
      lastName: lastName,
      username: username,
      phone: phone,
      gender: gender,
      dateOfBirth: dateOfBirth,
      bloodType: bloodType,
      address: address,
      maritalStatus: maritalStatus,
      medicalHistory: medicalHistory,
    );

    _patient = patient.copyWith(
      firstName: firstName,
      lastName: lastName,
      username: username,
      phone: phone,
      gender: gender,
      dateOfBirth: dateOfBirth,
      bloodType: bloodType,
      address: address,
      maritalStatus: maritalStatus,
      medicalHistory: medicalHistory,
    );
    notifyListeners();
  }

  /// Shows the picked image immediately, then replaces it with the stored URL
  /// once the upload lands. Showing the local file first keeps the profile
  /// responsive on a slow connection; the upload is what makes the photo
  /// survive a reinstall or appear on another device.
  Future<void> updateAvatar(String path) async {
    _patient = patient.copyWith(avatarPath: path);
    notifyListeners();

    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    try {
      final url = await PatientApi.uploadAvatar(userId: userId, file: File(path));
      _patient = patient.copyWith(avatarPath: url);
      notifyListeners();
    } catch (e) {
      // The local preview stays; the next load falls back to the stored photo.
      debugPrint('Avatar upload failed: $e');
      rethrow;
    }
  }

  /// Re-reads just the conversation. The chat screen calls this on open and
  /// after sending, rather than reloading the patient's whole record.
  Future<void> refreshMessages() => refreshSection(SyncSection.messages);

  Future<PatientMessage?> sendMessage(String body) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;
    if (body.trim().isEmpty) return null;

    final message = await PatientApi.sendMessage(patientId: patientId, body: body);
    // The realtime echo of this insert may already have refreshed the thread.
    if (!_messages.any((m) => m.id == message.id)) {
      _messages = [..._messages, message];
      notifyListeners();
    }
    return message;
  }

  /// Marks the clinic's messages as seen. Failures are swallowed: not clearing
  /// a badge is not worth an error in front of the patient.
  Future<void> markMessagesRead() async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return;
    if (unreadMessageCount == 0) return;

    try {
      await PatientApi.markMessagesRead(patientId);
      final now = DateTime.now();
      _messages = _messages.map((m) => m.isFromClinic && !m.isRead ? m.markedRead(now) : m).toList();
      _rebuildNotifications(isFirstLoad: false);
      notifyListeners();
    } catch (e) {
      debugPrint('Could not mark messages read: $e');
    }
  }

  /// Stores a file the patient picked against their chart, so the clinic and
  /// the booking flow can both see it.
  Future<PatientDocument?> addDocument({required String path, required String name}) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;

    final document = await PatientApi.uploadDocument(
      patientId: patientId,
      file: File(path),
      fileName: name,
    );
    if (!_documents.any((d) => d.id == document.id)) {
      _documents = [..._documents, document];
      notifyListeners();
    }
    return document;
  }
}

/// A 15-minute start time offered by the schedule step, and whether the block
/// behind it is still free.
class SlotOption {
  final int startMinute;
  final int durationMinutes;
  final bool isAvailable;

  const SlotOption({
    required this.startMinute,
    required this.durationMinutes,
    required this.isAvailable,
  });

  String get label => formatMinuteOfDay(startMinute);

  String get rangeLabel => '$label – ${formatMinuteOfDay(startMinute + durationMinutes)}';
}
