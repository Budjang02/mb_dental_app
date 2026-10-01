/// Where tapping a notice goes. The same kinds the website's
/// `openPatientNotifTarget` understands (js/render-patient.js).
enum NotificationTargetType { appointment, billing, plan, visitPayment, slotOffer }

class NotificationTarget {
  final NotificationTargetType type;

  /// The row it is about: an appointment id, a receipt id, a plan id, a
  /// payment request id or a slot offer id.
  final String id;

  const NotificationTarget(this.type, this.id);

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);
}

/// One notice on the bell.
///
/// [id] is the key the website uses for the same notice — `db|<uuid>` for a
/// `notifications` row, `booked|…`, `confirmed|…`, `awaiting|…`, `reminder|…`,
/// `rcpt|…` or `plan|…` for one derived from the record — so the read and
/// dismissed state in `notification_state` means the same thing on both.
class NotificationItem {
  final String id;
  final String title;
  final String body;

  /// When the notice was created: the `notifications` row's `created_at`, or
  /// the moment a derived notice describes. Drives "5m ago".
  final DateTime createdAt;

  /// Whether the patient has read it, on any device.
  final bool isRead;

  /// When it was read, or null while unread.
  final DateTime? readAt;

  /// The stable event key (`appointment.cancelled`, `billing.paid`, …) the
  /// icon and colour are chosen from.
  final String event;

  /// Who did it, for addressed notices — "Dr Reyes". Null when unknown.
  final String? actorName;

  /// The byline a derived notice carries instead of an actor and an age —
  /// "Tomorrow" on a reminder, a receipt's reference number. Null for
  /// addressed notices, whose byline is [actorName] and the age.
  final String? meta;

  /// The Settings category that decides whether it is shown: `appointment`,
  /// `plan` or `billing`.
  final String category;

  /// What tapping it opens, or null when it has nowhere to go.
  final NotificationTarget? target;

  /// The moment the website groups it under ("Today", "Tomorrow", …): the
  /// creation time for an addressed notice, the visit day for a reminder.
  final DateTime sortAt;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.readAt,
    this.event = '',
    this.actorName,
    this.meta,
    this.category = 'appointment',
    this.target,
    DateTime? sortAt,
  }) : sortAt = sortAt ?? createdAt;

  /// A `notifications` row rather than a notice derived from the record.
  bool get isAddressed => id.startsWith('db|');

  /// The `notifications.id` behind an addressed notice.
  String? get rowId => isAddressed ? id.substring(3) : null;

  /// Marks "argument not given", so `copyWith(readAt: null)` can clear the
  /// timestamp.
  static const Object _unset = Object();

  NotificationItem copyWith({bool? isRead, Object? readAt = _unset}) => NotificationItem(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        readAt: readAt == _unset ? this.readAt : readAt as DateTime?,
        event: event,
        actorName: actorName,
        meta: meta,
        category: category,
        target: target,
        sortAt: sortAt,
      );
}
