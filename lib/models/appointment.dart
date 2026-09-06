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
  });

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
    );
  }
}
