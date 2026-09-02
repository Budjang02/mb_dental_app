import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device push notification preferences, persisted locally. Singleton for
/// the same reason as [ThemeController]: any screen can read or toggle these
/// without a BuildContext or a provider hookup.
class NotificationSettings extends ChangeNotifier {
  static final NotificationSettings _instance = NotificationSettings._internal();
  factory NotificationSettings() => _instance;
  NotificationSettings._internal();

  static const _remindersKey = 'notif_appointment_reminders';
  static const _statusUpdatesKey = 'notif_status_updates';

  bool _appointmentReminders = true;
  bool _statusUpdates = true;

  /// Reminders ahead of an upcoming visit.
  bool get appointmentReminders => _appointmentReminders;

  /// Confirmations, reschedules and cancellations on existing bookings.
  bool get statusUpdates => _statusUpdates;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final reminders = prefs.getBool(_remindersKey) ?? _appointmentReminders;
    final updates = prefs.getBool(_statusUpdatesKey) ?? _statusUpdates;
    if (reminders == _appointmentReminders && updates == _statusUpdates) return;
    _appointmentReminders = reminders;
    _statusUpdates = updates;
    notifyListeners();
  }

  Future<void> setAppointmentReminders(bool value) async {
    if (_appointmentReminders == value) return;
    _appointmentReminders = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_remindersKey, value);
  }

  Future<void> setStatusUpdates(bool value) async {
    if (_statusUpdates == value) return;
    _statusUpdates = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_statusUpdatesKey, value);
  }
}
