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
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/services/push_notification_service.dart';
import 'package:mb_dental_app/services/supabase_service.dart';

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

  PatientRepository._internal();

  Patient? _patient;
  List<Appointment> _appointments = const [];
  List<Treatment> _treatments = const [];
  List<TreatmentPlanItem> _treatmentPlan = const [];
  List<Payment> _billing = const [];
  List<NotificationItem> _notifications = const [];
  List<WalletTransaction> _transactions = const [];
  List<PatientDocument> _documents = const [];
  List<Map<String, String>> _toothRecords = const [];
  List<PatientMessage> _messages = const [];

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
      final snapshot = await PatientApi.loadAll();
      _announceNew(snapshot.notifications, isFirstLoad: isFirstLoad);
      _patient = snapshot.patient;
      _appointments = snapshot.appointments;
      _treatments = snapshot.treatments;
      _treatmentPlan = snapshot.treatmentPlan;
      _billing = snapshot.billing;
      _notifications = snapshot.notifications;
      _transactions = snapshot.transactions;
      _documents = snapshot.documents;
      _toothRecords = snapshot.toothRecords;
      _messages = snapshot.messages;
      _walletBalance = snapshot.walletBalance;
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

  /// Re-reads just the alerts, so a banner can appear without pulling the whole
  /// record down again.
  Future<void> refreshNotifications() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || _patient == null) return;
    final incoming = await PatientApi.fetchNotifications(userId);
    _announceNew(incoming, isFirstLoad: false);
    _notifications = incoming;
    notifyListeners();
  }

  /// Drops everything held for the previous account. Called on sign-out so the
  /// next patient to use the device never sees the last one's chart.
  void clear() {
    _patient = null;
    _appointments = const [];
    _treatments = const [];
    _treatmentPlan = const [];
    _billing = const [];
    _notifications = const [];
    _transactions = const [];
    _documents = const [];
    _toothRecords = const [];
    _messages = const [];
    _documentUrls = const {};
    _walletBalance = 0;
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
    double walletBalance = 0,
  }) {
    _patient = patient;
    _appointments = List.of(appointments);
    _treatments = const [];
    _treatmentPlan = const [];
    _billing = const [];
    _notifications = const [];
    _transactions = List.of(transactions);
    _documents = const [];
    _toothRecords = const [];
    _messages = const [];
    _documentUrls = const {};
    _walletBalance = walletBalance;
    _isLoading = false;
    _loadError = null;
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

  List<Appointment> get appointments => List.unmodifiable(_appointments);

  Appointment? get nextUpcomingAppointment {
    final upcoming = _appointments
        .where((a) =>
            a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
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
  /// colours each tooth from and what the Treatment Notes page lists.
  List<Map<String, String>> get toothRecords => List.unmodifiable(_toothRecords);

  /// The support conversation with the clinic, oldest first.
  List<PatientMessage> get messages => List.unmodifiable(_messages);

  /// Messages from the clinic the patient has not opened yet — what the chat
  /// bubble badges.
  int get unreadMessageCount =>
      _messages.where((m) => !m.fromPatient && !m.isRead).length;

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
  /// free. A slot is unavailable when the clinic is closed that day, when the
  /// block would run past closing, or when it overlaps a booking that still
  /// holds its slot. [excludeAppointmentId] lets a reschedule ignore the
  /// booking it is moving.
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
    if (startMinute < kClinicOpenMinute) return false;
    if (startMinute + durationMinutes > kClinicCloseMinute) return false;

    final endMinute = startMinute + durationMinutes;
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

  /// Books a visit. [status] defaults to pending — the clinic confirms bookings
  /// itself, and nothing the app sends can grant a confirmed slot.
  ///
  /// Reloads afterwards rather than guessing the stored row, because the
  /// clinic's own triggers decide the reference numbers and any alert raised.
  Future<Appointment?> addAppointment({
    required String serviceName,
    required String doctorName,
    required DateTime date,
    required String timeSlot,
    String? notes,
    String? paymentMethod,
    AppointmentStatus status = AppointmentStatus.pending,
    List<String> serviceIds = const [],
    int durationMinutes = 60,
    double totalPrice = 0,
    double amountPaid = 0,
  }) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;

    final id = await PatientApi.createAppointment(
      patientId: patientId,
      date: date,
      timeSlot: timeSlot,
      procedureIds: serviceIds,
      notes: notes,
      paymentMethod: paymentMethod,
    );

    await load(force: true);
    for (final appointment in _appointments) {
      if (appointment.id == id) return appointment;
    }
    return null;
  }

  Future<void> cancelAppointment(String id, {required String reason}) async {
    await PatientApi.cancelAppointment(id, reason: reason);
    _appointments = _appointments
        .map((a) => a.id == id
            ? a.copyWith(status: AppointmentStatus.cancelled, cancellationReason: reason)
            : a)
        .toList();
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
    notifyListeners();
  }

  Future<WalletTransaction?> addWalletTransaction({
    required String title,
    required String subtitle,
    required double amount,
    required TransactionType type,
    required IconData icon,
    required String method,
  }) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;

    await PatientApi.addWalletTransaction(
      patientId: patientId,
      amount: amount,
      type: type,
      method: method,
      description: title,
    );

    // The ledger is the balance, so re-reading it is what keeps the two in step.
    await load(force: true);
    return _transactions.isEmpty ? null : _transactions.first;
  }

  Future<void> markAllNotificationsRead() async {
    if (unreadNotificationCount == 0) return;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    await PatientApi.markAllNotificationsRead(userId);
    _notifications = _notifications.map((n) => n.isRead ? n : _copyRead(n)).toList();
    notifyListeners();
  }

  Future<void> markNotificationRead(String id) async {
    await PatientApi.markNotificationRead(id);
    _notifications = _notifications.map((n) => n.id == id ? _copyRead(n) : n).toList();
    notifyListeners();
  }

  NotificationItem _copyRead(NotificationItem n) => NotificationItem(
        id: n.id,
        title: n.title,
        body: n.body,
        createdAt: n.createdAt,
        isRead: true,
        relatedAppointmentId: n.relatedAppointmentId,
        relatedTransactionId: n.relatedTransactionId,
      );

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
  Future<void> refreshMessages() async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return;
    _messages = await PatientApi.fetchMessages(patientId);
    notifyListeners();
  }

  Future<PatientMessage?> sendMessage(String body) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;
    if (body.trim().isEmpty) return null;

    final message = await PatientApi.sendMessage(patientId: patientId, body: body);
    _messages = [..._messages, message];
    notifyListeners();
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
      _messages = _messages
          .map((m) => m.fromPatient || m.isRead
              ? m
              : PatientMessage(
                  id: m.id,
                  body: m.body,
                  fromPatient: m.fromPatient,
                  sentAt: m.sentAt,
                  readAt: now,
                ))
          .toList();
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
    _documents = [..._documents, document];
    notifyListeners();
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
