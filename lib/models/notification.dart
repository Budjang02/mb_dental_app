/// Represents system and appointment alerts for patients.
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// Whether the patient has read it, on any device. The flag lives on the row
  /// rather than on the device, so marking it read on the web is the same fact
  /// the app reads back.
  final bool isRead;

  /// When it was read, or null while unread. Kept alongside [isRead] so two
  /// devices reporting a read at once can be ordered, and so the clinic can
  /// tell "never read" from "read a while ago".
  final DateTime? readAt;

  /// When set, tapping this notification's detail dialog navigates to the
  /// Appointments screen and opens this specific appointment.
  final String? relatedAppointmentId;

  /// When set, tapping this notification's detail dialog navigates to the
  /// Transaction History screen and opens this specific transaction.
  final String? relatedTransactionId;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.relatedAppointmentId,
    this.relatedTransactionId,
  });

  /// Marks "argument not given", so `copyWith(readAt: null)` can clear the
  /// timestamp — which is what marking an alert unread again has to do.
  static const Object _unset = Object();

  NotificationItem copyWith({bool? isRead, Object? readAt = _unset}) => NotificationItem(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        readAt: readAt == _unset ? this.readAt : readAt as DateTime?,
        relatedAppointmentId: relatedAppointmentId,
        relatedTransactionId: relatedTransactionId,
      );
}