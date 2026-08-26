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

  Appointment({
    required this.id,
    required this.serviceName,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
    required this.status,
    this.notes,
    this.paymentMethod,
  });

  Appointment copyWith({AppointmentStatus? status}) {
    return Appointment(
      id: id,
      serviceName: serviceName,
      doctorName: doctorName,
      date: date,
      timeSlot: timeSlot,
      status: status ?? this.status,
      notes: notes,
      paymentMethod: paymentMethod,
    );
  }
}