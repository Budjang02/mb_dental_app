import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repositories/clinic_api.dart';
import '../repositories/patient_repository.dart';
import 'supabase_service.dart';

/// Keeps this device's copy of the patient's record in step with the database
/// while the app is open.
///
/// The clinic's admin web platform and the patient web build write to the same
/// rows this app reads. Every table a screen displays is subscribed here, so a
/// status change at the front desk, a new charge, a chart mark or a reply in
/// the chat lands on an open screen without a reload.
///
/// A table only pushes changes once it is in the `supabase_realtime`
/// publication — `docs/realtime_data_sync_migration.sql` adds them all. Until
/// then its channel simply stays quiet, and [PatientRepository.refreshOnResume]
/// is the fallback.
class RealtimeSyncService {
  static final RealtimeSyncService _instance = RealtimeSyncService._internal();
  factory RealtimeSyncService() => _instance;
  RealtimeSyncService._internal();

  /// Tables whose rows carry `patient_id`, filtered server-side to this
  /// patient, and the part of the record each one refreshes.
  static const Map<String, SyncSection> _patientTables = {
    'appointments': SyncSection.appointments,
    'billing_records': SyncSection.billing,
    'billing': SyncSection.billing,
    'invoices': SyncSection.billing,
    'payment_receipts': SyncSection.billing,
    'wallet_transactions': SyncSection.wallet,
    'tooth_records': SyncSection.chart,
    'treatment_notes': SyncSection.chart,
    'treatment_plans': SyncSection.treatmentPlan,
    'patient_files': SyncSection.documents,
    'patient_messages': SyncSection.messages,
  };

  /// Child tables with no `patient_id` column. Subscribed unfiltered; RLS
  /// limits the events to rows this patient may read.
  static const Map<String, SyncSection> _childTables = {
    'appointment_services': SyncSection.appointments,
    'invoice_items': SyncSection.billing,
    'treatment_plan_items': SyncSection.treatmentPlan,
  };

  /// The clinic's reference data behind the menu, roster and schedule.
  static const List<String> _clinicTables = [
    'procedures',
    'specializations',
    'booking_categories',
    'booking_category_services',
    'members',
    'member_services',
    'doctor_schedules',
    'doctor_schedule_exceptions',
    'clinics',
    'clinic_settings',
    'clinic_closures',
  ];

  /// Account-level subscriptions: alerts, read state, profile and chart header.
  final List<RealtimeChannel> _channels = [];

  /// Subscriptions scoped to the loaded patient chart.
  final List<RealtimeChannel> _patientChannels = [];

  /// Not patient-specific, so these outlive a sign-out.
  final List<RealtimeChannel> _clinicChannels = [];

  String? _userId;
  String? _patientId;
  bool _listeningToRepository = false;

  /// Collapses a burst of profile edits into one reload.
  Timer? _profileDebounce;

  /// Same, for read-state writes: "mark all read" on the web is one row each.
  Timer? _notificationDebounce;

  /// Same, for the clinic's own tables: editing a service in the admin portal
  /// touches several rows at once.
  Timer? _catalogDebounce;

  /// One per section, so a burst on one table does not delay another.
  final Map<SyncSection, Timer> _sectionDebounce = {};

  /// True while channels are subscribed for [userId].
  bool isRunningFor(String userId) => _channels.isNotEmpty && _userId == userId;

  /// Subscribes for [userId]. Safe to call repeatedly — an existing channel for
  /// the same account is left alone, and one for a different account is torn
  /// down first so a signed-out patient's rows stop arriving.
  ///
  /// The patient-scoped tables follow once [PatientRepository] has resolved
  /// which chart belongs to the account.
  Future<void> start(String userId) async {
    if (isRunningFor(userId)) {
      _onRepositoryChanged();
      return;
    }
    await stop();
    _userId = userId;

    // One channel per table, not one channel for all of them: Supabase errors
    // the whole channel when any single binding is refused, which would take
    // the working bindings down with it.
    _channels.addAll([
      _subscribe(
        name: 'patient-notifications-insert:$userId',
        table: 'notifications',
        event: PostgresChangeEvent.insert,
        column: 'recipient_id',
        value: userId,
        callback: _onNotificationInsert,
      ),
      _subscribe(
        name: 'patient-notifications-update:$userId',
        table: 'notifications',
        event: PostgresChangeEvent.update,
        column: 'recipient_id',
        value: userId,
        callback: _onNotificationUpdate,
      ),
      _subscribe(
        name: 'patient-notification-state:$userId',
        table: 'notification_state',
        event: PostgresChangeEvent.all,
        column: 'user_id',
        value: userId,
        callback: (_) => _scheduleNotificationRefresh(),
      ),
      _subscribe(
        name: 'patient-chart:$userId',
        table: 'patients',
        event: PostgresChangeEvent.all,
        column: 'profile_id',
        value: userId,
        callback: (_) => _scheduleProfileReload(),
      ),
      _subscribe(
        name: 'patient-profile:$userId',
        table: 'profiles',
        event: PostgresChangeEvent.update,
        column: 'id',
        value: userId,
        callback: (_) => _scheduleProfileReload(),
      ),
    ]);

    if (!_listeningToRepository) {
      PatientRepository().addListener(_onRepositoryChanged);
      _listeningToRepository = true;
    }
    _onRepositoryChanged();
  }

  /// Follows the loaded chart: subscribes its tables once a patient id is
  /// known, and re-subscribes if the account resolves to a different chart.
  void _onRepositoryChanged() {
    if (_userId == null) return;
    final patientId = PatientRepository().patient.id;
    if (patientId.isEmpty || patientId == _patientId) return;
    _patientId = patientId;
    unawaited(_subscribePatient(patientId));
  }

  Future<void> _subscribePatient(String patientId) async {
    await _removeAll(_patientChannels);
    // Another chart may have been resolved while the old channels closed.
    if (_patientId != patientId) return;

    _patientTables.forEach((table, section) {
      _patientChannels.add(_subscribe(
        name: 'patient-$table:$patientId',
        table: table,
        event: PostgresChangeEvent.all,
        column: 'patient_id',
        value: patientId,
        callback: (_) => _scheduleSection(section),
      ));
    });
    _childTables.forEach((table, section) {
      _patientChannels.add(_subscribe(
        name: 'patient-$table:$patientId',
        table: table,
        event: PostgresChangeEvent.all,
        callback: (_) => _scheduleSection(section),
      ));
    });
  }

  /// Subscribes one channel to one table, optionally filtered server-side on
  /// [column].
  ///
  /// A refused binding — Realtime not enabled for the table — is logged and
  /// leaves every other channel running.
  RealtimeChannel _subscribe({
    required String name,
    required String table,
    required PostgresChangeEvent event,
    required void Function(PostgresChangePayload payload) callback,
    String? column,
    String? value,
  }) {
    final channel = SupabaseService.client.channel(name);
    channel.onPostgresChanges(
      event: event,
      schema: 'public',
      table: table,
      filter: column == null || value == null
          ? null
          : PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: column,
              value: value,
            ),
      callback: callback,
    );
    channel.subscribe((status, error) {
      if (error != null) debugPrint('Realtime ($table) unavailable: $error');
    });
    return channel;
  }

  /// Subscribes to the clinic's reference tables, so a service, dentist,
  /// schedule or closure the admin portal changes reaches an open app without
  /// a restart.
  ///
  /// Separate from [start]: this is public reference data, so it runs for as
  /// long as the app does, whoever is signed in.
  Future<void> startClinicSync() async {
    if (_clinicChannels.isNotEmpty) return;
    for (final table in _clinicTables) {
      _clinicChannels.add(_subscribe(
        name: 'clinic-$table',
        table: table,
        event: PostgresChangeEvent.all,
        callback: (_) => _scheduleCatalogReload(),
      ));
    }
  }

  /// Reloads the menu, roster and schedule together: a service is only
  /// bookable through the doctors credentialed for it on the days the clinic
  /// is open, so the three must never be half-refreshed.
  void _scheduleCatalogReload() {
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(ClinicCatalog().load(force: true));
    });
  }

  void _scheduleSection(SyncSection section) {
    _sectionDebounce[section]?.cancel();
    _sectionDebounce[section] = Timer(const Duration(milliseconds: 400), () {
      _sectionDebounce.remove(section);
      unawaited(PatientRepository().refreshSection(section));
    });
  }

  void _scheduleNotificationRefresh() {
    _notificationDebounce?.cancel();
    _notificationDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(PatientRepository().refreshNotifications());
    });
  }

  Future<void> stopClinicSync() async {
    _catalogDebounce?.cancel();
    _catalogDebounce = null;
    await _removeAll(_clinicChannels);
  }

  Future<void> stop() async {
    _profileDebounce?.cancel();
    _profileDebounce = null;
    _notificationDebounce?.cancel();
    _notificationDebounce = null;
    for (final timer in _sectionDebounce.values) {
      timer.cancel();
    }
    _sectionDebounce.clear();
    if (_listeningToRepository) {
      PatientRepository().removeListener(_onRepositoryChanged);
      _listeningToRepository = false;
    }
    _userId = null;
    _patientId = null;
    await _removeAll(_channels);
    await _removeAll(_patientChannels);
  }

  Future<void> _removeAll(List<RealtimeChannel> channels) async {
    final closing = List.of(channels);
    channels.clear();
    for (final channel in closing) {
      await SupabaseService.client.removeChannel(channel);
    }
  }

  void _onNotificationInsert(PostgresChangePayload payload) {
    final id = payload.newRecord['id']?.toString();
    if (id == null || id.isEmpty) return;
    unawaited(PatientRepository().applyRemoteNotification(id));
  }

  /// An alert changed on the row — most often marked read on the other platform.
  void _onNotificationUpdate(PostgresChangePayload payload) {
    final record = payload.newRecord;
    final id = record['id']?.toString();
    if (id == null || id.isEmpty) return;
    PatientRepository().applyNotificationReadState(
      id,
      isRead: record['is_read'] == true,
      readAt: DateTime.tryParse(record['read_at']?.toString() ?? '')?.toUtc(),
    );
  }

  /// A profile or chart edit (including the clinic approving the account).
  /// Reloads the whole record rather than patching fields: the chart feeds the
  /// appointments, billing and odontogram views too.
  void _scheduleProfileReload() {
    _profileDebounce?.cancel();
    _profileDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(PatientRepository().load(force: true));
    });
  }
}
