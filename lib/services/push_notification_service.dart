import 'package:flutter/foundation.dart';

import '../app/notification_settings.dart';
import '../models/notification.dart';

/// The kind of alert a notification is, so the per-device toggles in
/// Profile → Notifications can mute a category without muting everything.
enum PushChannel {
  /// Booking confirmations, reschedules, cancellations.
  statusUpdate,

  /// Countdown alerts ahead of a visit (5 days out, 2 hours out).
  reminder,

  /// Digital receipts and wallet movements.
  payment,
}

/// Delivers real-time alerts to the running app.
///
/// The clinic's server-side push (FCM/APNs) is not wired up in this build, so
/// this stands in for it end to end: the repository raises an alert here, the
/// banner mounted at the app root shows it, and the same item lands in the
/// notification centre. Swapping in a real push provider means forwarding
/// [deliver] to it — every call site above this layer stays as it is.
class PushNotificationService extends ChangeNotifier {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  NotificationItem? _latest;

  /// The most recent alert that has not yet been shown and dismissed. The
  /// root-level banner watches this.
  NotificationItem? get latest => _latest;

  /// True when the device's own toggles allow an alert on [channel].
  bool allows(PushChannel channel) {
    final settings = NotificationSettings();
    switch (channel) {
      case PushChannel.reminder:
        return settings.appointmentReminders;
      case PushChannel.statusUpdate:
      case PushChannel.payment:
        return settings.statusUpdates;
    }
  }

  /// Raises [item] as a real-time alert. Muted channels are dropped here
  /// rather than at the call site, so the notification centre and the banner
  /// never disagree about what the patient asked to see.
  void deliver(NotificationItem item, {required PushChannel channel}) {
    if (!allows(channel)) return;
    _latest = item;
    notifyListeners();
  }

  /// Called by the banner once it has finished animating out.
  void clear(String id) {
    if (_latest?.id != id) return;
    _latest = null;
    notifyListeners();
  }
}
