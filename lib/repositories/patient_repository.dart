import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/treatment_note.dart';
import 'package:mb_dental_app/models/patient_document.dart';
import 'package:mb_dental_app/models/patient_message.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';
import 'package:mb_dental_app/repositories/notification_feed.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/services/push_notification_service.dart';
import 'package:mb_dental_app/services/supabase_service.dart';

import 'load_state.dart';

// `SyncSection` and the per-section load states live in `load_state.dart` so
// `PatientApi` can report against them without importing this file back. Every
// screen already imports this one, so they are re-exported rather than made a
// second import everywhere.
export 'load_state.dart'
    show SyncSection, LoadPhase, LoadFailure, SectionStatus, kRequestTimeout;

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
  List<TreatmentNote> _treatmentNotes = const [];

  /// Whether the treatment notes were read, apart from the chart: a failed
  /// read shows an error with Retry, never an empty history.
  SectionStatus _treatmentNotesStatus = SectionStatus.idle;
  List<PatientMessage> _messages = const [];
  bool _isApprovedForBooking = true;

  /// Addressed `notifications` rows, receipts and the duplicate check — what
  /// the bell needs besides the record.
  NotificationSources _notificationSources = const NotificationSources();

  /// What this account has read or dismissed (`notification_state`).
  Map<String, NotificationState> _notificationState = const {};

  /// Settings → Notifications, shared with the website.
  NotificationPrefs _notificationPrefs = const NotificationPrefs();

  /// Everything the bell shows, in the website's order, dismissed notices and
  /// switched-off categories already left out. Rebuilt by
  /// [_rebuildNotifications].
  List<NotificationItem> _notifications = const [];

  /// Signed preview links, keyed by document id. Fetched in one batch after a
  /// load so the file list can show thumbnails without a request per row.
  Map<String, String> _documentUrls = const {};
  double _walletBalance = 0;

  /// Bills the clinic sent to be paid from this account, still pending.
  List<VisitPaymentRequest> _visitRequests = const [];

  bool _isLoading = false;
  String? _loadError;
  Future<void>? _inFlight;

  /// Where each part of the record has got to, independently of the others.
  ///
  /// This is what the screens read. A section is only allowed to draw an empty
  /// state once its status is [LoadPhase.ready]; while it is pending it shows a
  /// skeleton, and when it has failed it shows its own inline message — never a
  /// blank list the patient would read as "you have none".
  final Map<SyncSection, SectionStatus> _sections = {
    for (final section in SyncSection.values) section: SectionStatus.idle,
  };

  /// Retries already running, keyed by section, so pressing a retry button
  /// repeatedly joins the request in flight instead of starting another.
  final Map<SyncSection, Future<void>> _sectionRetries = {};

  /// Why identity resolution failed, or null. Identity is the one thing the
  /// rest of the record cannot be fetched without: no chart means no patient id
  /// to query by. It still never blanks a page — the screens show it inline.
  SectionStatus _identity = SectionStatus.idle;

  /// Alert ids already shown to this patient in this session. A refresh that
  /// brings the same rows back must not re-raise banners for them.
  final Set<String> _announcedNotificationIds = {};

  // --- Load state ---

  /// True while the first load is still running, so screens can show a spinner
  /// instead of an empty chart the patient might mistake for a real one.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null. Set when the account has no linked
  /// patient record as well as on network failures.
  ///
  /// Kept for the sign-in and unlinked-account cases only. No screen may blank
  /// itself on this — read [statusOf] for the section being drawn instead.
  String? get loadError => _loadError;

  bool get hasLoaded => _patient != null;

  /// How [section] last fared. The single call every screen makes to decide
  /// between a skeleton, the data, an empty state and an inline error.
  SectionStatus statusOf(SyncSection section) =>
      _sections[section] ?? SectionStatus.idle;

  /// How the account-to-chart lookup fared. Failing here leaves every section
  /// unfetchable, so the screens show this message in place of their own.
  SectionStatus get identityStatus => _identity;

  /// The status a screen should honour for [section]: the identity failure when
  /// there is one, since nothing could be fetched, otherwise the section's own.
  SectionStatus effectiveStatusOf(SyncSection section) =>
      _identity.hasFailed ? _identity : statusOf(section);

  /// True once a chart has actually been resolved for this account.
  bool get hasPatientRecord => _patient != null;

  /// False when the wallet figure below could not be confirmed on the last
  /// load. A zero that means "we could not check" must never be printed as a
  /// balance, so the wallet card reads this before showing a number.
  bool get isWalletBalanceKnown => _isWalletBalanceKnown;
  bool _isWalletBalanceKnown = false;

  /// True when nobody is signed in. The only state that still justifies sending
  /// the patient somewhere else rather than showing the page.
  bool get isSignedOut => !SupabaseService.isSignedIn;

  void _setSection(SyncSection section, SectionStatus status) {
    _sections[section] = status;
  }

  void _setAllSections(SectionStatus status) {
    for (final section in SyncSection.values) {
      _sections[section] = status;
    }
  }

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
    _identity = SectionStatus.loading;
    _setAllSections(SectionStatus.loading);
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
        if (userId != null) PatientApi.fetchNotificationPrefs(userId),
      ]);
      final snapshot = results[0] as PatientSnapshot;

      _patient = snapshot.patient;
      _appointments = snapshot.appointments;
      _treatments = snapshot.treatments;
      _treatmentPlan = snapshot.treatmentPlan;
      _treatmentPlans = snapshot.treatmentPlans;
      _billing = snapshot.billing;
      _notificationSources = snapshot.notifications;
      _notificationState =
          results.length > 1 ? results[1] as Map<String, NotificationState> : const {};
      _notificationPrefs =
          results.length > 2 ? results[2] as NotificationPrefs : const NotificationPrefs();
      _transactions = snapshot.transactions;
      _documents = snapshot.documents;
      _toothRecords = snapshot.toothRecords;
      _treatmentNotes = snapshot.treatmentNotes ?? const [];
      _treatmentNotesStatus = snapshot.treatmentNotes == null
          ? SectionStatus.failed(LoadFailure.server, 'Unable to load treatment notes.')
          : SectionStatus.ready;
      _messages = snapshot.messages;
      _walletBalance = snapshot.walletBalance;
      _visitRequests = snapshot.visitRequests;
      _isWalletBalanceKnown = snapshot.isWalletBalanceKnown;
      _isApprovedForBooking = snapshot.isApprovedForBooking;

      // The chart resolved, so identity is good even where sections did not.
      _identity = SectionStatus.ready;
      _setAllSections(SectionStatus.ready);
      // Only the sections that actually failed are marked failed. Everything
      // else is ready, which is what lets an empty list mean "no rows" rather
      // than "we could not tell".
      snapshot.failures.forEach(_setSection);

      _rebuildNotifications(isFirstLoad: isFirstLoad);
      // Deliberately after the record is in place: thumbnails are a nicety and
      // must never hold up the rest of the chart, nor fail the load.
      unawaited(_refreshDocumentUrls());
    } on NoPatientRecordException catch (e) {
      // Either nobody is signed in, or the account has no chart behind it.
      // Both are real states with their own explanation, and neither is worth
      // retrying — but neither blanks a page any more.
      _loadError = e.message;
      _identity = SectionStatus.failed(
        SupabaseService.isSignedIn
            ? LoadFailure.noPatientRecord
            : LoadFailure.unauthenticated,
        e.message,
      );
      _setAllSections(_identity);
      _isWalletBalanceKnown = false;
    } catch (e) {
      final status = classifyFailure(e, context: 'PatientRepository.load');
      _loadError = status.message;
      _identity = status;
      _setAllSections(status);
      _isWalletBalanceKnown = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Re-runs one section's read and nothing else.
  ///
  /// This is what every inline retry button calls. It does not restart the app,
  /// does not sign the patient out, does not touch the page they are on, and
  /// does not disturb the sections that loaded. Pressing it again while it is
  /// running joins the request already out rather than starting a second.
  Future<void> retrySection(SyncSection section) {
    final running = _sectionRetries[section];
    if (running != null) return running;

    // Identity is what everything else is keyed on. When that is what failed,
    // the only thing worth retrying is the whole resolution.
    if (_identity.hasFailed || _patient == null) {
      final request = load(force: true);
      _sectionRetries[section] = request;
      return request.whenComplete(() => _sectionRetries.remove(section));
    }

    _setSection(section, SectionStatus.loading);
    notifyListeners();

    final request = refreshSection(section, reportFailure: true)
        .whenComplete(() => _sectionRetries.remove(section));
    _sectionRetries[section] = request;
    return request;
  }

  /// True while [section] has a retry in flight, so its button can show a
  /// spinner and refuse further presses.
  bool isRetrying(SyncSection section) => _sectionRetries.containsKey(section);

  /// Recomposes the bell from the addressed rows and the record, then raises
  /// a banner for anything new since the last composition.
  void _rebuildNotifications({required bool isFirstLoad}) {
    _notifications = NotificationFeed.build(
      addressed: _notificationSources.addressed,
      covered: _notificationSources.covered,
      appointments: _appointments,
      receipts: _notificationSources.receipts,
      plans: _treatmentPlans,
      state: _notificationState,
      prefs: _notificationPrefs,
    );
    if (_notificationPrefs.enabled) _announceNew(_notifications, isFirstLoad: isFirstLoad);
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
        channel: NotificationFeed.channelOf(item),
      );
    }
  }

  /// Re-reads the alerts and the read state, so a banner can appear without
  /// pulling the whole record down again.
  Future<void> refreshNotifications() => _refreshNotifications();

  Future<void> _refreshNotifications({bool reportFailure = false}) async {
    final userId = SupabaseService.currentUserId;
    final patientId = _patient?.id;
    if (userId == null || patientId == null) return;
    try {
      final results = await runWithRetry(
        () => Future.wait([
          PatientApi.fetchNotificationSources(userId, patientId),
          PatientApi.fetchNotificationState(userId),
          PatientApi.fetchNotificationPrefs(userId),
        ]),
        context: 'PatientRepository.refreshNotifications',
      );
      if (_patient?.id != patientId) return;
      _notificationSources = results[0] as NotificationSources;
      _notificationState = results[1] as Map<String, NotificationState>;
      _notificationPrefs = results[2] as NotificationPrefs;
      _setSection(SyncSection.notifications, SectionStatus.ready);
      _rebuildNotifications(isFirstLoad: false);
      notifyListeners();
    } catch (e) {
      final status =
          classifyFailure(e, context: 'PatientRepository.refreshNotifications');
      if (!reportFailure) return;
      _setSection(SyncSection.notifications, status);
      notifyListeners();
    }
  }

  /// Re-reads one part of the record after a realtime change to the tables
  /// behind it.
  ///
  /// A realtime refresh that fails is logged and leaves the copy already on
  /// screen alone: the next change, resume or full load brings it back in step,
  /// and a dropped socket must not turn a loaded page into an error. A refresh
  /// the patient asked for passes [reportFailure], so their retry either
  /// succeeds visibly or says why it did not.
  Future<void> refreshSection(SyncSection section, {bool reportFailure = false}) async {
    // Neither of these is a narrower read of a table: the chart header comes
    // back only with a full resolution, and the bell has its own refresh.
    if (section == SyncSection.profile) {
      await load(force: true);
      return;
    }
    if (section == SyncSection.notifications) {
      await _refreshNotifications(reportFailure: reportFailure);
      return;
    }

    final patientId = _patient?.id;
    final userId = SupabaseService.currentUserId;
    if (patientId == null || patientId.isEmpty || userId == null) return;

    // A sign-out or account switch while the request was out must not write
    // the previous patient's rows back in.
    bool stillCurrent() => _patient?.id == patientId;

    try {
      // Returns false when the account changed under the request, so the rows
      // are dropped rather than written over the patient now signed in — and
      // the section is left as it was rather than marked freshly loaded.
      final applied = await runWithRetry<bool>(
        () async {
          switch (section) {
            case SyncSection.appointments:
              final appointments = await PatientApi.fetchAppointments(patientId);
              if (!stillCurrent()) return false;
              _appointments = appointments;
              _treatments = PatientApi.treatmentsFrom(appointments);
            case SyncSection.billing:
              final billing = await PatientApi.fetchBilling(patientId);
              if (!stillCurrent()) return false;
              _billing = billing;
            case SyncSection.wallet:
              final wallet = await PatientApi.fetchWallet(patientId);
              if (!stillCurrent()) return false;
              _transactions = wallet.transactions;
              _visitRequests = wallet.visitRequests;
              // Only a balance `wallet_balance()` answered with is shown.
              _walletBalance = wallet.balance ?? _walletBalance;
              _isWalletBalanceKnown = wallet.balance != null;
            case SyncSection.chart:
              final records = await PatientApi.fetchToothRecords(patientId);
              if (!stillCurrent()) return false;
              _toothRecords = records;
              // The notes refresh on their own, keeping their own status.
              unawaited(refreshTreatmentNotes());
            case SyncSection.treatmentPlan:
              final plan = await PatientApi.fetchTreatmentPlan(patientId);
              if (!stillCurrent()) return false;
              _treatmentPlan = plan.items;
              _treatmentPlans = plan.plans;
            case SyncSection.documents:
              final documents = await PatientApi.fetchDocuments(patientId);
              if (!stillCurrent()) return false;
              _documents = documents;
              unawaited(_refreshDocumentUrls());
            case SyncSection.messages:
              final messages = await PatientApi.fetchMessages(patientId);
              if (!stillCurrent()) return false;
              _messages = messages;
            case SyncSection.profile:
            case SyncSection.notifications:
              // Handled above, before the patient id was even read.
              return false;
          }
          return true;
        },
        context: 'PatientRepository.refreshSection($section)',
      );
      if (!applied) return;

      _setSection(section, SectionStatus.ready);
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
      final status = classifyFailure(e, context: 'PatientRepository.refreshSection($section)');
      // A realtime refresh leaves what is on screen alone; only a refresh the
      // patient asked for is allowed to turn the section into an error.
      if (!reportFailure) return;
      _setSection(section, status);
      if (section == SyncSection.wallet) _isWalletBalanceKnown = false;
      notifyListeners();
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
    _notificationSources = const NotificationSources();
    _notificationState = const {};
    _notificationPrefs = const NotificationPrefs();
    _notifications = const [];
    _transactions = const [];
    _documents = const [];
    _toothRecords = const [];
    _treatmentNotes = const [];
    _treatmentNotesStatus = SectionStatus.idle;
    _messages = const [];
    _documentUrls = const {};
    _walletBalance = 0;
    _visitRequests = const [];
    _isApprovedForBooking = true;
    _announcedNotificationIds.clear();
    _loadError = null;
    _isLoading = false;
    _isWalletBalanceKnown = false;
    _identity = SectionStatus.idle;
    _setAllSections(SectionStatus.idle);
    _sectionRetries.clear();
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
    List<TreatmentNote> treatmentNotes = const [],
    Map<String, NotificationState> notificationState = const {},
    NotificationPrefs notificationPrefs = const NotificationPrefs(),
    double walletBalance = 0,
    bool isWalletBalanceKnown = true,
    List<Payment> billing = const [],
    List<VisitPaymentRequest> visitRequests = const [],
    bool isApprovedForBooking = true,
  }) {
    _patient = patient;
    _appointments = List.of(appointments);
    _treatments = const [];
    _treatmentPlan = const [];
    _treatmentPlans = const [];
    _billing = List.of(billing);
    _notificationSources = NotificationSources(addressed: List.of(notifications));
    _notificationState = Map.of(notificationState);
    _notificationPrefs = notificationPrefs;
    _transactions = List.of(transactions);
    _documents = const [];
    _toothRecords = const [];
    _treatmentNotes = List.of(treatmentNotes);
    _treatmentNotesStatus = SectionStatus.ready;
    _messages = List.of(messages);
    _documentUrls = const {};
    _walletBalance = walletBalance;
    _visitRequests = List.of(visitRequests);
    _isApprovedForBooking = isApprovedForBooking;
    _isLoading = false;
    _loadError = null;
    _identity = SectionStatus.ready;
    _setAllSections(SectionStatus.ready);
    _isWalletBalanceKnown = isWalletBalanceKnown;
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

  /// The bell, in the website's order: addressed notices newest first, then
  /// the ones derived from the record.
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  /// Unread notices on the bell. Zero while notifications are switched off,
  /// which is also when the badge is hidden — the website's rule.
  int get unreadNotificationCount =>
      _notificationPrefs.enabled ? _notifications.where((n) => !n.isRead).length : 0;

  /// The shared Settings → Notifications switches.
  NotificationPrefs get notificationPrefs => _notificationPrefs;

  double get walletBalance => _walletBalance;

  /// The clinic's pending payment requests, newest first.
  List<VisitPaymentRequest> get visitRequests => List.unmodifiable(_visitRequests);

  /// Charges Pay Bill can settle: unpaid, not voided, oldest first — the
  /// website's `_loadUnpaidCharges`.
  List<Payment> get unpaidCharges =>
      _billing.where((b) => b.isOwed).toList()..sort((a, b) => a.billedOn.compareTo(b.billedOn));

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
  List<TreatmentNote> get treatmentNotes => List.unmodifiable(_treatmentNotes);

  SectionStatus get treatmentNotesStatus => _treatmentNotesStatus;

  /// Re-reads the treatment notes by themselves: on opening Treatment Notes,
  /// pull-to-refresh, Retry, a realtime change, resume or reconnect. Rows are
  /// replaced as a whole list keyed by id, so an edited note updates in place
  /// and an archived one leaves.
  Future<void> refreshTreatmentNotes({bool showLoading = false}) async {
    final patientId = _patient?.id;
    if (patientId == null) return;
    if (showLoading || _treatmentNotesStatus.hasFailed) {
      _treatmentNotesStatus = SectionStatus.loading;
      notifyListeners();
    }
    try {
      final notes = await PatientApi.fetchTreatmentNotes(patientId);
      if (_patient?.id != patientId) return;
      _treatmentNotes = notes;
      _treatmentNotesStatus = SectionStatus.ready;
    } catch (e) {
      if (_patient?.id != patientId) return;
      _treatmentNotesStatus = classifyFailure(e, context: 'PatientRepository.refreshTreatmentNotes');
    }
    notifyListeners();
  }

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
    // The clinic's clock, not the phone's: a phone on another time zone must
    // not treat a Manila morning slot as still ahead (or already gone).
    final today = clinicToday();
    final nowMinute = clinicMinuteNow();
    return slotStartsFor(day, durationMinutes).map((startMinute) {
      final isPast = day.isBefore(today) || (_isSameDay(day, today) && startMinute <= nowMinute);
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
  Future<WalletCheckoutResult?> checkoutWithWallet({
    required List<String> serviceIds,
    required DateTime date,
    required String timeSlot,
    required int durationMinutes,
    required double totalPrice,
    required double amountToPay,
    String? doctorId,
    String? notes,
    String? referenceNo,
    String? paymentRequestId,
    String paymentMethod = 'Wallet',
  }) async {
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) return null;
    if (!_isApprovedForBooking) throw const PatientNotApprovedException();

    final result = await PatientApi.bookAppointmentWithWallet(
      paymentRequestId: paymentRequestId,
      paymentMethod: paymentMethod,
      patientId: patientId,
      procedureIds: serviceIds,
      date: date,
      timeSlot: timeSlot,
      durationMinutes: durationMinutes,
      totalAmount: totalPrice,
      amountToPay: amountToPay,
      doctorId: doctorId,
      notes: notes,
      referenceNo: referenceNo,
    );

    // book_appointment_v5 does not report the balance; the reload below reads
    // it. When it does, show it at once so the wallet never reads high.
    if (result.walletBalance > 0) {
      _walletBalance = result.walletBalance;
      notifyListeners();
    }

    await load(force: true);
    return result;
  }

  /// Settles an existing booking from the wallet. Same guarantees as
  /// [checkoutWithWallet].
  Future<bool> payAppointmentFromWallet({
    required String appointmentId,
    required double amount,
    String method = 'Wallet',
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

  /// Reads one appointment fresh from Supabase, by id or confirmation code,
  /// for the details page. The copy in [appointments] is replaced with it so
  /// the lists behind the page agree with what it shows. Null when no booking
  /// of this patient's matches.
  Future<Appointment?> fetchAppointment(String idOrCode) async {
    if (_patient == null) await load();
    final patientId = _patient?.id;
    if (patientId == null || patientId.isEmpty) {
      throw StateError('No patient record is loaded');
    }

    final fresh = await runWithRetry(
      () => PatientApi.fetchAppointment(patientId, idOrCode),
      context: 'appointment',
    );
    if (fresh == null || _patient?.id != patientId) return fresh;

    final index = _appointments.indexWhere((a) => a.id == fresh.id);
    if (index >= 0) {
      _appointments = [..._appointments]..[index] = fresh;
      notifyListeners();
    }
    return fresh;
  }

  /// Cancels through `cancel_my_appointment()` on the server, then reads the
  /// row back, so the app shows exactly what the database (and so the
  /// website) now holds — status, reason, who cancelled and when.
  Future<void> cancelAppointment(String id, {required String reason}) async {
    await PatientApi.cancelAppointment(id, reason: reason);
    await _rereadAppointment(id);
  }

  /// Moves a visit through `reschedule_my_appointment()`, then reads the row
  /// back: a paid booking comes back confirmed at its new time, less the fee.
  Future<RescheduleResult> rescheduleAppointment(
    String id, {
    required DateTime date,
    required String timeSlot,
  }) async {
    final result = await PatientApi.rescheduleMyAppointment(id, date: date, timeSlot: timeSlot);
    await _rereadAppointment(id);
    return result;
  }

  /// Replaces this appointment with a fresh read and refreshes the bell, or
  /// reloads the whole list if the single read fails.
  Future<void> _rereadAppointment(String id) async {
    try {
      await fetchAppointment(id);
      _rebuildNotifications(isFirstLoad: false);
      notifyListeners();
    } catch (_) {
      await refreshSection(SyncSection.appointments);
    }
  }

  /// Marks everything on the bell read — only what the bell shows, as the
  /// website's "Mark all as read" does.
  Future<void> markAllNotificationsRead() async {
    final keys = [for (final n in _notifications) if (!n.isRead) n.id];
    await _markRead(keys);
  }

  /// Marks one notice read on this account, so the website and the patient's
  /// other devices see the same. Shown read at once; the write follows.
  Future<void> markNotificationRead(String id) => _markRead([id]);

  Future<void> _markRead(List<String> keys) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || keys.isEmpty) return;
    final now = DateTime.now().toUtc();
    _notificationState = {
      ..._notificationState,
      for (final key in keys)
        key: NotificationState(
          // First read time wins, the rule `notif_mark_read` applies too.
          readAt: _notificationState[key]?.readAt ?? now,
          dismissedAt: _notificationState[key]?.dismissedAt,
        ),
    };
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
    await PatientApi.markNoticesRead(userId, keys);
  }

  /// Removes a notice from the bell here and on the website, through
  /// `notif_dismiss` (which also marks it read).
  Future<void> dismissNotification(String id) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    final now = DateTime.now().toUtc();
    _notificationState = {
      ..._notificationState,
      id: NotificationState(readAt: _notificationState[id]?.readAt ?? now, dismissedAt: now),
    };
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
    await PatientApi.dismissNotices(userId, [id]);
  }

  /// Changes the shared Settings → Notifications switches. Applied at once;
  /// saved on the account so the website's bell counts the same.
  Future<void> setNotificationPrefs(NotificationPrefs prefs) async {
    final userId = SupabaseService.currentUserId;
    if (userId == null || prefs == _notificationPrefs) return;
    _notificationPrefs = prefs;
    _rebuildNotifications(isFirstLoad: false);
    notifyListeners();
    await PatientApi.saveNotificationPrefs(userId, prefs);
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
