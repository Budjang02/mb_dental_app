import 'package:flutter/cupertino.dart';
import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/models/notification.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/services/push_notification_service.dart';

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
  late List<TreatmentPlanItem> _treatmentPlan;
  late List<Payment> _billing;
  late List<NotificationItem> _notifications;
  late List<WalletTransaction> _transactions;
  final List<_ScheduledReminder> _reminders = [];
  double _walletBalance = 1500.0;
  int _appointmentSeq = 4;
  int _transactionSeq = 4;
  int _notificationSeq = 4;
  int _patientSeq = 101;

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
        serviceIds: const ['svc-prophylaxis'],
        durationMinutes: 45,
        totalPrice: 1000,
        amountPaid: 200,
      ),
      Appointment(
        id: 'app-02',
        serviceName: 'Tooth Filling (Composite)',
        doctorName: 'Dr. Jenneline Mariano',
        date: DateTime(2026, 9, 12),
        timeSlot: '01:30 PM',
        status: AppointmentStatus.pending,
        serviceIds: const ['svc-filling'],
        durationMinutes: 45,
        totalPrice: 2000,
      ),
      Appointment(
        id: 'app-03',
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. John Paul Mariano',
        date: DateTime(2026, 5, 10),
        timeSlot: '11:00 AM',
        status: AppointmentStatus.completed,
        serviceIds: const ['svc-checkup'],
        durationMinutes: 30,
        totalPrice: 500,
        amountPaid: 500,
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

    _treatmentPlan = [];

    _billing = [
      Payment(
        id: 'bill-01',
        referenceNo: 'REC-2026-8801',
        invoiceNo: 'INV-2026-0114',
        receiptNo: 'RCPT-2026-0114',
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
        invoiceNo: 'INV-2026-0228',
        procedureName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        amount: 1000.0,
        billedOn: DateTime(2026, 8, 28),
        status: 'Unpaid',
      ),
      Payment(
        id: 'bill-03',
        referenceNo: 'REC-2025-7714',
        invoiceNo: 'INV-2025-0912',
        receiptNo: 'RCPT-2025-0912',
        procedureName: 'Dental X-Ray',
        doctorName: 'Dr. Jenneline Mariano',
        amount: 500.0,
        billedOn: DateTime(2025, 12, 10),
        status: 'Paid',
        paymentMethod: 'Wallet',
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

  /// The procedures the clinic has planned but not yet carried out.
  /// Drawn up chairside and pushed to the patient, so it is empty until
  /// a dentist actually proposes something.
  List<TreatmentPlanItem> get treatmentPlan => List.unmodifiable(_treatmentPlan);

  List<Payment> get billing => List.unmodifiable(_billing);

  List<NotificationItem> get notifications {
    _materializeDueReminders();
    // Newest first. `List.sort` is not stable, so insertion order breaks ties
    // explicitly — two alerts raised in the same millisecond (a payment and
    // the booking it paid for) must not swap places between reads.
    final indexed = List<(int, NotificationItem)>.generate(
      _notifications.length,
      (i) => (i, _notifications[i]),
    )..sort((a, b) {
        final byTime = b.$2.createdAt.compareTo(a.$2.createdAt);
        return byTime != 0 ? byTime : b.$1.compareTo(a.$1);
      });
    return List.unmodifiable(indexed.map((e) => e.$2));
  }

  int get unreadNotificationCount {
    _materializeDueReminders();
    return _notifications.where((n) => !n.isRead).length;
  }

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

  // --- Slot availability ---

  /// Whether a [durationMinutes] block starting at [startMinute] on [day] is
  /// free. A slot is unavailable when the clinic is closed that day, when the
  /// block would run past closing, or when it overlaps a booking that still
  /// holds its slot. [excludeAppointmentId] lets a reschedule ignore the
  /// booking it is moving.
  bool isSlotAvailable({
    required DateTime day,
    required int startMinute,
    required int durationMinutes,
    String? excludeAppointmentId,
  }) {
    if (!isClinicOpenOn(day)) return false;
    if (startMinute < kClinicOpenMinute) return false;
    if (startMinute + durationMinutes > kClinicCloseMinute) return false;

    final endMinute = startMinute + durationMinutes;
    for (final booked in _appointments) {
      if (!booked.holdsSlot) continue;
      if (booked.id == excludeAppointmentId) continue;
      if (!_isSameDay(booked.date, day)) continue;

      final bookedStart = booked.startMinuteOfDay;
      if (bookedStart == null) continue;
      final bookedEnd = bookedStart + booked.durationMinutes;

      // Half-open intervals: a block may start exactly when another ends.
      if (startMinute < bookedEnd && bookedStart < endMinute) return false;
    }
    return true;
  }

  /// Every 15-minute start on [day] that can still fit a [durationMinutes]
  /// block, with the taken ones flagged rather than dropped — the picker greys
  /// them out so the patient can see the day is filling up.
  List<SlotOption> slotOptionsFor({
    required DateTime day,
    required int durationMinutes,
    String? excludeAppointmentId,
  }) {
    final now = DateTime.now();
    return slotStartsFor(day, durationMinutes).map((startMinute) {
      final isPast = _isSameDay(day, now) && startMinute <= now.hour * 60 + now.minute;
      final available = !isPast &&
          isSlotAvailable(
            day: day,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            excludeAppointmentId: excludeAppointmentId,
          );
      return SlotOption(
        startMinute: startMinute,
        durationMinutes: durationMinutes,
        isAvailable: available,
      );
    }).toList();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// [status] defaults to pending — the clinic confirms manually. Bookings
  /// paid with a 20% down payment come in already confirmed.
  Appointment addAppointment({
    required String serviceName,
    required String doctorName,
    required DateTime date,
    required String timeSlot,
    String? notes,
    String? paymentMethod,
    AppointmentStatus status = AppointmentStatus.pending,
    List<String> serviceIds = const [],
    int durationMinutes = 60,
    double totalPrice = 0,
    double amountPaid = 0,
  }) {
    final appointment = Appointment(
      id: 'app-${(_appointmentSeq++).toString().padLeft(2, '0')}',
      serviceName: serviceName,
      doctorName: doctorName,
      date: date,
      timeSlot: timeSlot,
      status: status,
      notes: notes,
      paymentMethod: paymentMethod,
      serviceIds: serviceIds,
      durationMinutes: durationMinutes,
      totalPrice: totalPrice,
      amountPaid: amountPaid,
    );
    _appointments = [..._appointments, appointment];

    if (status == AppointmentStatus.confirmed) {
      _raise(
        title: 'Appointment Confirmed',
        body: 'Your $serviceName on ${_dateLabel(date)} at $timeSlot is confirmed. '
            'The ${formatPeso(amountPaid)} down payment has been received.',
        channel: PushChannel.statusUpdate,
        appointmentId: appointment.id,
      );
    } else {
      _raise(
        title: 'Booking Request Received',
        body: 'Your $serviceName on ${_dateLabel(date)} at $timeSlot is pending approval. '
            'We will confirm it shortly.',
        channel: PushChannel.statusUpdate,
        appointmentId: appointment.id,
      );
    }

    _scheduleRemindersFor(appointment);
    notifyListeners();
    return appointment;
  }

  void cancelAppointment(String id, {required String reason}) {
    Appointment? cancelled;
    _appointments = _appointments.map((a) {
      if (a.id != id) return a;
      cancelled = a.copyWith(status: AppointmentStatus.cancelled, cancellationReason: reason);
      return cancelled!;
    }).toList();

    _clearRemindersFor(id);
    final item = cancelled;
    if (item != null) {
      _raise(
        title: 'Appointment Cancelled',
        body: 'Your ${item.serviceName} on ${_dateLabel(item.date)} has been cancelled.',
        channel: PushChannel.statusUpdate,
        appointmentId: id,
      );
    }
    notifyListeners();
  }

  /// Moves an existing appointment to a new date/time in place (does not
  /// create a new appointment) and resets it to pending re-confirmation.
  void rescheduleAppointment(String id, {required DateTime date, required String timeSlot, String? notes}) {
    Appointment? moved;
    _appointments = _appointments.map((a) {
      if (a.id != id) return a;
      moved = a.copyWith(
        date: date,
        timeSlot: timeSlot,
        status: AppointmentStatus.pending,
        notes: notes,
      );
      return moved!;
    }).toList();

    _clearRemindersFor(id);
    final item = moved;
    if (item != null) {
      _scheduleRemindersFor(item);
      _raise(
        title: 'Appointment Rescheduled',
        body: 'Your ${item.serviceName} has moved to ${_dateLabel(date)} at $timeSlot, '
            'pending clinic approval.',
        channel: PushChannel.statusUpdate,
        appointmentId: id,
      );
    }
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

    _raise(
      title: type == TransactionType.credit ? 'Wallet Top-up Successful' : 'Receipt Generated',
      body: type == TransactionType.credit
          ? '${formatPeso(amount)} was added to your wallet via $method. '
              'New balance: ${formatPeso(_walletBalance)}.'
          : '${AppMessages.paymentProcessed} ${formatPeso(amount)} paid for $title — '
              'receipt ${txn.referenceNo} is in your transaction history.',
      channel: PushChannel.payment,
      transactionId: txn.id,
    );

    notifyListeners();
    return txn;
  }

  NotificationItem _copyRead(NotificationItem n) => NotificationItem(
        id: n.id,
        title: n.title,
        body: n.body,
        createdAt: n.createdAt,
        isRead: true,
        relatedAppointmentId: n.relatedAppointmentId,
        relatedTransactionId: n.relatedTransactionId,
      );

  void markAllNotificationsRead() {
    if (unreadNotificationCount == 0) return;
    _notifications = _notifications.map((n) => n.isRead ? n : _copyRead(n)).toList();
    notifyListeners();
  }

  void markNotificationRead(String id) {
    _notifications = _notifications.map((n) => n.id == id ? _copyRead(n) : n).toList();
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

  // --- Notifications & reminders ---

  /// Records an alert in the notification centre and hands it to the push
  /// service for real-time delivery. Muted channels still land in the centre,
  /// so nothing is silently lost — only the banner is suppressed.
  NotificationItem _raise({
    required String title,
    required String body,
    required PushChannel channel,
    String? appointmentId,
    String? transactionId,
    DateTime? createdAt,
  }) {
    final item = NotificationItem(
      id: 'notif-${(_notificationSeq++).toString().padLeft(2, '0')}',
      title: title,
      body: body,
      createdAt: createdAt ?? DateTime.now(),
      relatedAppointmentId: appointmentId,
      relatedTransactionId: transactionId,
    );
    _notifications = [..._notifications, item];
    PushNotificationService().deliver(item, channel: channel);
    return item;
  }

  /// Countdown alerts for a booking: one five days out and one two hours out.
  /// A lead time that has already passed is skipped rather than firing late.
  void _scheduleRemindersFor(Appointment appointment) {
    if (appointment.status == AppointmentStatus.cancelled) return;
    final startsAt = appointment.startsAt;
    final now = DateTime.now();

    void schedule(Duration lead, String label) {
      final fireAt = startsAt.subtract(lead);
      if (!fireAt.isAfter(now)) return;
      _reminders.add(_ScheduledReminder(
        appointmentId: appointment.id,
        fireAt: fireAt,
        title: 'Appointment Reminder',
        body: 'Your ${appointment.serviceName} with ${appointment.doctorName} is $label — '
            '${_dateLabel(appointment.date)} at ${appointment.timeSlot}.',
      ));
    }

    schedule(const Duration(days: 5), 'in 5 days');
    schedule(const Duration(hours: 2), 'in 2 hours');
  }

  void _clearRemindersFor(String appointmentId) {
    _reminders.removeWhere((r) => r.appointmentId == appointmentId);
  }

  /// Fires any scheduled reminder whose time has come. Called on every read of
  /// the notification list, which is how this mock scheduler stands in for a
  /// server-side job without a background isolate.
  void _materializeDueReminders() {
    if (_reminders.isEmpty) return;
    final now = DateTime.now();
    final due = _reminders.where((r) => !r.fireAt.isAfter(now)).toList();
    if (due.isEmpty) return;
    _reminders.removeWhere((r) => !r.fireAt.isAfter(now));

    for (final reminder in due) {
      _raise(
        title: reminder.title,
        body: reminder.body,
        channel: PushChannel.reminder,
        appointmentId: reminder.appointmentId,
        createdAt: reminder.fireAt,
      );
    }
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dateLabel(DateTime date) =>
      '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

  // --- Account ---

  /// Streamlined sign-up: name, email and phone only. Everything else stays
  /// null until the patient completes their profile or checks in at the
  /// clinic. Mock only — a real backend call replaces the body, not the shape.
  Future<Patient> registerPatient({
    required String fullName,
    required String email,
    required String phone,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final parts = fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? fullName.trim() : parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final year = DateTime.now().year;

    _patientSeq++;
    _patient = Patient(
      id: 'p-$_patientSeq',
      patientCode: 'PAT-$year-${_patientSeq.toString().padLeft(4, '0')}',
      firstName: firstName,
      lastName: lastName,
      username: email.split('@').first,
      email: email.trim(),
      phone: phone.trim(),
    );

    // A brand-new account starts on a clean slate rather than inheriting the
    // seeded demo history, so the app never shows another patient's records.
    _appointments = [];
    _treatments = [];
    _treatmentPlan = [];
    _billing = [];
    _transactions = [];
    _notifications = [];
    _reminders.clear();
    _walletBalance = 0;

    _raise(
      title: 'Welcome to $kClinicName',
      body: 'Your account is ready. Complete your profile to speed up your first visit.',
      channel: PushChannel.statusUpdate,
    );

    notifyListeners();
    return _patient;
  }

  // --- Legacy-named getters kept for call-site compatibility ---
  Patient getMockPatient() => patient;
  List<Appointment> getMockAppointments() => appointments;
  List<Treatment> getMockTreatments() => treatments;
  List<Payment> getMockBilling() => billing;
}

/// One pending countdown alert. Held in memory only: a real build hands these
/// to the platform scheduler (or the clinic's push backend) instead.
class _ScheduledReminder {
  final String appointmentId;
  final DateTime fireAt;
  final String title;
  final String body;

  _ScheduledReminder({
    required this.appointmentId,
    required this.fireAt,
    required this.title,
    required this.body,
  });
}

/// A 15-minute start time offered by the schedule step, and whether the block
/// behind it is still free.
class SlotOption {
  final int startMinute;
  final int durationMinutes;
  final bool isAvailable;

  const SlotOption({
    required this.startMinute,
    required this.durationMinutes,
    required this.isAvailable,
  });

  String get label => formatMinuteOfDay(startMinute);

  String get rangeLabel => '$label – ${formatMinuteOfDay(startMinute + durationMinutes)}';
}
