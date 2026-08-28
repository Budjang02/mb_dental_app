/// Represents system and appointment alerts for patients.
class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

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
    this.relatedAppointmentId,
    this.relatedTransactionId,
  });
}