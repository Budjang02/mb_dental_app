import '../data/clinic_catalog.dart';

/// Strict status terminology from the documentation: Pending, Confirmed, Cancelled, Completed.
enum AppointmentStatus { pending, confirmed, cancelled, completed }

/// Represents a booked or past dental appointment.
class Appointment {
  final String id;
  final String serviceName;
  final String doctorName;
  final DateTime date;
  final String timeSlot;
  final AppointmentStatus status;
  final String? notes;
  final String? paymentMethod;
  final String? cancellationReason;

  /// Catalog ids of every procedure in this visit. Empty for the legacy
  /// records seeded before the wizard tracked individual services.
  final List<String> serviceIds;

  /// Summed chair time of those procedures — what sizes the booked block.
  final int durationMinutes;

  /// Full cost of the visit, and the share of it already settled (the 20%
  /// downpayment for wallet bookings, zero for pay-at-clinic).
  final double totalPrice;
  final double amountPaid;

  /// `appointments.confirmation_code`: the booking reference the patient
  /// quotes at the front desk and the payload of the check-in QR code. Null on
  /// bookings made before the clinic issued codes.
  final String? confirmationCode;

  /// `appointments.qr_token`: the random token the database issued for this
  /// visit's check-in QR (32 lowercase hex characters). Read, never made, by
  /// the app. Null while the database has not issued one, or when what it
  /// holds is not a well-formed token.
  final String? qrToken;

  /// Who cancelled, as `appointments.cancelled_by` records it: 'System' for
  /// the automatic sweeps, a staff name for the clinic. Null when not set.
  final String? cancelledBy;

  /// `appointments.cancelled_by_id`: the auth user id of whoever cancelled.
  final String? cancelledById;

  /// Reschedule fees already taken from the deposit
  /// (`appointments.reschedule_fee_total`). Less of the deposit then counts
  /// toward the final bill.
  final double rescheduleFeeTotal;

  /// `appointments.downpayment_amount` as stored, paid or not — the deposit
  /// the booking asked for. [amountPaid] is only the part actually received.
  final double downpaymentAmount;

  /// When the downpayment was settled (`downpayment_paid_at`). Null while
  /// nothing has been paid, which is also what hides the deposit receipt.
  final DateTime? downpaymentPaidAt;

  /// `appointments.doctor_id`, for finding the dentist's roster entry (photo,
  /// credentials). Null while the clinic has not assigned anyone.
  final String? doctorId;

  /// When the booking was made.
  final DateTime? createdAt;

  /// When it last moved to its current status (`confirmed_at`,
  /// `cancelled_at`, `arrived_at`). What the notification feed dates a status
  /// notice by.
  final DateTime? statusChangedAt;

  /// `appointments.appointment_date` exactly as the database returned it
  /// (`2026-09-20`). Notification keys shared with the website are built from
  /// this string rather than from [date], so both sides spell them the same.
  final String rawDate;

  /// `appointments.appointment_time` exactly as the database returned it
  /// (`10:00:00`), for the same reason as [rawDate].
  final String rawTime;

  /// `appointments.status` as stored: `Pending`, `Confirmed`, `Ongoing`,
  /// `Completed`, `Cancelled` or `No-Show`. [status] folds these onto four.
  final String rawStatus;

  /// True when the patient booked the visit themselves; false when the clinic
  /// booked it for them.
  final bool isSelfBooked;

  Appointment({
    required this.id,
    required this.serviceName,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
    required this.status,
    this.notes,
    this.paymentMethod,
    this.cancellationReason,
    this.serviceIds = const [],
    this.durationMinutes = 60,
    this.totalPrice = 0,
    this.amountPaid = 0,
    this.confirmationCode,
    this.qrToken,
    this.cancelledBy,
    this.cancelledById,
    this.rescheduleFeeTotal = 0,
    this.downpaymentAmount = 0,
    this.downpaymentPaidAt,
    this.doctorId,
    this.createdAt,
    this.statusChangedAt,
    String? rawDate,
    String? rawTime,
    String? rawStatus,
    this.isSelfBooked = true,
  })  : rawDate = rawDate ?? dbDate(date),
        rawTime = rawTime ?? dbTime(timeSlot),
        rawStatus = rawStatus ?? statusLiteral(status);

  /// A date as Postgres `date` prints it: `2026-09-20`.
  static String dbDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// A slot label as Postgres `time` prints it: `10:00:00`.
  static String dbTime(String timeSlot) {
    final minute = parseMinuteOfDay(timeSlot);
    if (minute == null) return timeSlot;
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:'
        '${(minute % 60).toString().padLeft(2, '0')}:00';
  }

  /// The `appointment_status` enum value the app writes for [status].
  static String statusLiteral(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.pending:
        return 'Pending';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case AppointmentStatus.completed:
        return 'Completed';
    }
  }

  /// Start of the booked block as minutes from midnight, or null when the slot
  /// label predates the 15-minute grid and cannot be parsed.
  int? get startMinuteOfDay => parseMinuteOfDay(timeSlot);

  /// Exclusive end of the booked block, in minutes from midnight.
  int? get endMinuteOfDay {
    final start = startMinuteOfDay;
    return start == null ? null : start + durationMinutes;
  }

  /// The slot's full span, e.g. `10:00 AM – 11:15 AM`.
  String get timeRangeLabel {
    final end = endMinuteOfDay;
    return end == null ? timeSlot : '$timeSlot – ${formatMinuteOfDay(end)}';
  }

  /// The wall-clock start of this appointment, for reminder scheduling.
  DateTime get startsAt {
    final start = startMinuteOfDay ?? 0;
    return DateTime(date.year, date.month, date.day).add(Duration(minutes: start));
  }

  double get balanceDue => (totalPrice - amountPaid).clamp(0, double.infinity);

  /// Share of [totalPrice] already paid, as a whole percent (20 for the usual
  /// wallet downpayment). Zero when there is no price to measure against.
  int get downpaymentPercent =>
      totalPrice > 0 ? (amountPaid / totalPrice * 100).round().clamp(0, 100) : 0;

  /// The production web app the verification link opens.
  static const String verifyHost = 'mbdentalcenter.web.app';

  /// [raw] as a QR token, or null when it is not one: trimmed, lower-cased
  /// and required to be exactly 32 hex characters — the same rule the
  /// website's `public-verification.js` applies before it looks a token up.
  static String? normaliseQrToken(String? raw) {
    final token = (raw ?? '').trim().toLowerCase();
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(token) ? token : null;
  }

  /// The public verification link for [qrToken]:
  /// `https://mbdentalcenter.web.app/verify/?t=<qr_token>`, the URL the
  /// website's own QR carries. Opening it only shows the clinic name, the
  /// confirmation code and whether the booking is valid; check-in stays with
  /// the clinic staff's scanner.
  static String verifyUrlFor(String qrToken) => Uri.https(
        verifyHost,
        '/verify/',
        {'t': qrToken},
      ).toString();

  /// What the check-in QR encodes: the verification link for [qrToken]. Null
  /// when there is no valid token — the app then shows no QR rather than one
  /// that would not verify, and never builds one from the confirmation code.
  String? get checkInQrPayload {
    final token = qrToken;
    return token == null ? null : verifyUrlFor(token);
  }

  /// The reference printed on the receipt and in saved file names: the
  /// confirmation code, or the appointment id before one is issued.
  String get checkInPayload {
    final code = confirmationCode?.trim() ?? '';
    return code.isNotEmpty ? code : id;
  }

  /// Why this booking was cancelled, as the website's details dialog words it
  /// (`_padCancelReason`): the reason saved on the row — by the patient, the
  /// clinic or the system — or, when none was saved, one worked out from who
  /// cancelled and when. [myUserId] is the signed-in user, to recognise the
  /// patient's own cancellation. Null unless the booking is cancelled.
  String? cancellationReasonLabel({String? myUserId}) {
    if (status != AppointmentStatus.cancelled) return null;
    final saved = cancellationReason?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    final by = cancelledBy?.trim() ?? '';
    if (by == 'System' || (by.isEmpty && (cancelledById ?? '').isEmpty)) {
      if (downpaymentAmount > 0 && downpaymentPaidAt == null) {
        return 'Automatically cancelled: the down payment was not completed in time';
      }
      final cancelledOn = statusChangedAt;
      if (cancelledOn != null && !cancelledOn.isBefore(DateTime(date.year, date.month, date.day))) {
        return 'Automatically cancelled: the patient did not check in for the appointment';
      }
      return 'Automatically cancelled by the system';
    }
    if (myUserId != null && cancelledById == myUserId) return 'Cancelled by patient';
    return 'Cancelled by the clinic';
  }

  /// A booking still occupies its slot unless it was cancelled.
  bool get holdsSlot => status != AppointmentStatus.cancelled;

  Appointment copyWith({
    AppointmentStatus? status,
    DateTime? date,
    String? timeSlot,
    String? notes,
    String? cancellationReason,
    String? doctorName,
    double? amountPaid,
    DateTime? statusChangedAt,
  }) {
    return Appointment(
      id: id,
      serviceName: serviceName,
      doctorName: doctorName ?? this.doctorName,
      date: date ?? this.date,
      timeSlot: timeSlot ?? this.timeSlot,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      serviceIds: serviceIds,
      durationMinutes: durationMinutes,
      totalPrice: totalPrice,
      amountPaid: amountPaid ?? this.amountPaid,
      confirmationCode: confirmationCode,
      qrToken: qrToken,
      cancelledBy: cancelledBy,
      cancelledById: cancelledById,
      rescheduleFeeTotal: rescheduleFeeTotal,
      downpaymentAmount: downpaymentAmount,
      downpaymentPaidAt: downpaymentPaidAt,
      doctorId: doctorId,
      createdAt: createdAt,
      statusChangedAt: statusChangedAt ?? this.statusChangedAt,
      // A local edit writes these columns exactly as the database will store
      // them, so a key built before the next reload already matches.
      rawDate: date != null ? dbDate(date) : rawDate,
      rawTime: timeSlot != null ? dbTime(timeSlot) : rawTime,
      rawStatus: status != null ? statusLiteral(status) : rawStatus,
      isSelfBooked: isSelfBooked,
    );
  }
}
