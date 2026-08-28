import 'package:flutter/cupertino.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';

/// In-memory mock data layer, shared across every screen for this session.
///
/// This is the single seam where a real backend/API integration will slot in
/// later: every method here keeps the same signature it would need against a
/// real service, it just resolves from memory instead of a network call.
class PatientRepository extends ChangeNotifier {
  static final PatientRepository _instance = PatientRepository._internal();
  factory PatientRepository() => _instance;

  PatientRepository._internal() {
    _seed();
  }

  late Patient _patient;
  late List<Appointment> _appointments;
  late List<Treatment> _treatments;
  late List<Payment> _billing;
  late List<NotificationItem> _notifications;
  late List<WalletTransaction> _transactions;
  double _walletBalance = 1500.0;
  int _appointmentSeq = 4;
  int _transactionSeq = 4;

  void _seed() {
    _patient = Patient(
      id: 'p-101',
      patientCode: 'PAT-2026-0089',
      firstName: 'John Wilson',
      lastName: 'Salvador',
      username: 'jwsalvador',
      email: 'salvadorjohnwilson55@gmail.com',
      phone: '+63 992 299 0844',
      gender: 'Male',
      dateOfBirth: DateTime(2002, 5, 14),
    );

    _appointments = [
      Appointment(
        id: 'app-01',
        serviceName: 'Oral Prophylaxis (Cleaning)',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: DateTime(2026, 8, 28),
        timeSlot: '10:00 AM',
        status: AppointmentStatus.confirmed,
        notes: 'Regular checkup and cleaning.',
      ),
      Appointment(
        id: 'app-02',
        serviceName: 'Tooth Filling (Composite)',
        doctorName: 'Dr. Jenneline Mariano',
        date: DateTime(2026, 9, 12),
        timeSlot: '01:30 PM',
        status: AppointmentStatus.pending,
      ),
      Appointment(
        id: 'app-03',
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. John Paul Mariano',
        date: DateTime(2026, 5, 10),
        timeSlot: '11:00 AM',
        status: AppointmentStatus.completed,
      ),
    ];

    _treatments = [
      Treatment(
        id: 'treat-01',
        procedure: 'Tooth #17 Composite Filling',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: DateTime(2026, 1, 15),
        notes: 'Restoration complete. Patient advised regarding oral hygiene.',
      ),
      Treatment(
        id: 'treat-02',
        procedure: 'Full Prophylaxis',
        doctorName: 'Dr. Jenneline Mariano',
        date: DateTime(2025, 12, 10),
        notes: 'Routine cleaning performed without complications.',
      ),
    ];

    _billing = [
      Payment(
        id: 'bill-01',
        referenceNo: 'REC-2026-8801',
        procedureName: 'Tooth Filling',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        amount: 2000.0,
        billedOn: DateTime(2026, 1, 15),
        status: 'Paid',
        paymentMethod: 'GCash',
      ),
      Payment(
        id: 'bill-02',
        referenceNo: 'REC-2026-9042',
        procedureName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        amount: 1000.0,
        billedOn: DateTime(2026, 8, 28),
        status: 'Unpaid',
      ),
    ];

    _notifications = [
      NotificationItem(
        id: 'notif-01',
        title: 'Appointment Confirmed',
        body: 'Your Oral Prophylaxis on Aug 28, 2026 at 10:00 AM is confirmed.',
        createdAt: DateTime(2026, 8, 23, 9, 0),
        relatedAppointmentId: 'app-01',
      ),
      NotificationItem(
        id: 'notif-02',
        title: 'Payment Received',
        body: 'We received your payment of ₱800.00 for Dental Cleaning.',
        createdAt: DateTime(2026, 8, 20, 10, 20),
        relatedTransactionId: 'txn-01',
      ),
      NotificationItem(
        id: 'notif-03',
        title: 'Reminder',
        body: 'Your next visit is coming up in 5 days. See you soon!',
        createdAt: DateTime(2026, 8, 18, 8, 0),
        isRead: true,
        relatedAppointmentId: 'app-01',
      ),
    ];

    _transactions = [
      WalletTransaction(
        id: 'txn-01',
        title: 'Dental Cleaning',
        subtitle: 'Payment',
        amount: 800.0,
        type: TransactionType.debit,
        icon: CupertinoIcons.sparkles,
        dateTime: DateTime(2026, 8, 23, 10, 15),
        referenceNo: 'PAY-2026-0231',
        method: 'Wallet',
      ),
      WalletTransaction(
        id: 'txn-02',
        title: 'Wallet Top-up',
        subtitle: 'GCash',
        amount: 2000.0,
        type: TransactionType.credit,
        icon: CupertinoIcons.creditcard,
        dateTime: DateTime(2026, 8, 22, 15, 20),
        referenceNo: 'TOPUP-2026-0198',
        method: 'GCash',
      ),
      WalletTransaction(
        id: 'txn-03',
        title: 'Dental X-Ray',
        subtitle: 'Payment',
        amount: 500.0,
        type: TransactionType.debit,
        icon: CupertinoIcons.bandage,
        dateTime: DateTime(2026, 8, 18, 11, 5),
        referenceNo: 'PAY-2026-0187',
        method: 'Wallet',
      ),
    ];

    _autoCompletePastAppointments();
  }

  // --- Reads ---

  Patient get patient => _patient;

  List<Appointment> get appointments {
    _autoCompletePastAppointments();
    return List.unmodifiable(_appointments);
  }

  Appointment? get nextUpcomingAppointment {
    final upcoming = appointments
        .where((a) =>
            a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<Treatment> get treatments => List.unmodifiable(_treatments);

  List<Payment> get billing => List.unmodifiable(_billing);

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  int get unreadNotificationCount => _notifications.where((n) => !n.isRead).length;

  double get walletBalance => _walletBalance;

  List<WalletTransaction> get transactions {
    final sorted = List<WalletTransaction>.from(_transactions)
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return List.unmodifiable(sorted);
  }

  // --- Mutations ---

  /// Any pending/confirmed appointment whose date has passed is automatically
  /// marked completed — patients cannot mark an appointment complete themselves.
  void _autoCompletePastAppointments() {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    bool changed = false;
    _appointments = _appointments.map((a) {
      final isOpen = a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed;
      if (isOpen && a.date.isBefore(startOfToday)) {
        changed = true;
        return a.copyWith(status: AppointmentStatus.completed);
      }
      return a;
    }).toList();
    if (changed) notifyListeners();
  }

  Appointment addAppointment({
    required String serviceName,
    required String doctorName,
    required DateTime date,
    required String timeSlot,
    String? notes,
    String? paymentMethod,
  }) {
    final appointment = Appointment(
      id: 'app-${(_appointmentSeq++).toString().padLeft(2, '0')}',
      serviceName: serviceName,
      doctorName: doctorName,
      date: date,
      timeSlot: timeSlot,
      status: AppointmentStatus.pending,
      notes: notes,
      paymentMethod: paymentMethod,
    );
    _appointments = [..._appointments, appointment];
    notifyListeners();
    return appointment;
  }

  void cancelAppointment(String id, {required String reason}) {
    _appointments = _appointments
        .map((a) => a.id == id
            ? a.copyWith(status: AppointmentStatus.cancelled, cancellationReason: reason)
            : a)
        .toList();
    notifyListeners();
  }

  /// Moves an existing appointment to a new date/time in place (does not
  /// create a new appointment) and resets it to pending re-confirmation.
  void rescheduleAppointment(String id, {required DateTime date, required String timeSlot, String? notes}) {
    _appointments = _appointments
        .map((a) => a.id == id
            ? a.copyWith(date: date, timeSlot: timeSlot, status: AppointmentStatus.pending, notes: notes)
            : a)
        .toList();
    notifyListeners();
  }

  WalletTransaction addWalletTransaction({
    required String title,
    required String subtitle,
    required double amount,
    required TransactionType type,
    required IconData icon,
    required String method,
  }) {
    final txn = WalletTransaction(
      id: 'txn-${(_transactionSeq++).toString().padLeft(2, '0')}',
      title: title,
      subtitle: subtitle,
      amount: amount,
      type: type,
      icon: icon,
      dateTime: DateTime.now(),
      referenceNo: 'REF-${DateTime.now().millisecondsSinceEpoch % 1000000}',
      method: method,
    );
    _transactions = [..._transactions, txn];
    if (type == TransactionType.credit) {
      _walletBalance += amount;
    } else {
      _walletBalance -= amount;
    }
    notifyListeners();
    return txn;
  }

  void markNotificationRead(String id) {
    _notifications = _notifications
        .map((n) => n.id == id
            ? NotificationItem(
                id: n.id,
                title: n.title,
                body: n.body,
                createdAt: n.createdAt,
                isRead: true,
                relatedAppointmentId: n.relatedAppointmentId,
                relatedTransactionId: n.relatedTransactionId,
              )
            : n)
        .toList();
    notifyListeners();
  }

  void updatePatient({
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
  }) {
    _patient = _patient.copyWith(
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

  void updateAvatar(String path) {
    _patient = _patient.copyWith(avatarPath: path);
    notifyListeners();
  }

  /// Mock only — swap for a real backend call when auth/account APIs exist.
  Future<bool> changePassword({required String currentPassword, required String newPassword}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return true;
  }

  // --- Legacy-named getters kept for call-site compatibility ---
  Patient getMockPatient() => patient;
  List<Appointment> getMockAppointments() => appointments;
  List<Treatment> getMockTreatments() => treatments;
  List<Payment> getMockBilling() => billing;
}
