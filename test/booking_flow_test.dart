import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

/// The next occurrence of [weekday] strictly after today, so tests never book
/// into the past regardless of when they run.
DateTime nextWeekday(int weekday) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day);
}

void main() {
  group('clinic schedule', () {
    test('opens Wednesday through Sunday and closes Monday and Tuesday', () {
      expect(isClinicOpenOn(nextWeekday(DateTime.wednesday)), isTrue);
      expect(isClinicOpenOn(nextWeekday(DateTime.sunday)), isTrue);
      expect(isClinicOpenOn(nextWeekday(DateTime.monday)), isFalse);
      expect(isClinicOpenOn(nextWeekday(DateTime.tuesday)), isFalse);
    });

    test('offers 15-minute starts that leave room for the whole block', () {
      final wednesday = nextWeekday(DateTime.wednesday);
      final starts = slotStartsFor(wednesday, 45);

      expect(starts.first, kClinicOpenMinute);
      expect(starts[1] - starts[0], kSlotStepMinutes);
      // The last start must still finish by closing time.
      expect(starts.last + 45, lessThanOrEqualTo(kClinicCloseMinute));
      expect(starts.last + 45 + kSlotStepMinutes, greaterThan(kClinicCloseMinute));
    });

    test('offers nothing on a closed day', () {
      expect(slotStartsFor(nextWeekday(DateTime.monday), 30), isEmpty);
    });

    test('a block too long for the clinic day has no valid start', () {
      expect(slotStartsFor(nextWeekday(DateTime.wednesday), 10 * 60), isEmpty);
    });

    test('time labels round-trip through parsing', () {
      expect(formatMinuteOfDay(9 * 60), '09:00 AM');
      expect(formatMinuteOfDay(12 * 60), '12:00 PM');
      expect(formatMinuteOfDay(13 * 60 + 30), '01:30 PM');
      expect(parseMinuteOfDay('01:30 PM'), 13 * 60 + 30);
      expect(parseMinuteOfDay('12:00 PM'), 12 * 60);
      expect(parseMinuteOfDay('not a time'), isNull);
    });
  });

  group('doctor filtering', () {
    test('braces narrow the roster to orthodontists', () {
      final braces = serviceById('svc-braces')!;
      final eligible = eligibleDentists([braces]);

      expect(eligible, isNotEmpty);
      expect(eligible.every((d) => d.specializations.contains(kOrthodontics)), isTrue);
      expect(eligible.map((d) => d.name), contains('Dr. John Paul Mariano'));
    });

    test('a dentist must cover every selected procedure, not just one', () {
      final braces = serviceById('svc-braces')!;
      final veneers = serviceById('svc-veneers')!;

      // No one on the roster holds both Orthodontics and Cosmetic Dentistry.
      expect(eligibleDentists([braces, veneers]), isEmpty);
    });

    test('an empty selection leaves the whole roster available', () {
      expect(eligibleDentists(const <DentalService>[]).length, kDentists.length);
    });
  });

  group('booking totals', () {
    test('durations and prices sum across a multi-service visit', () {
      final services = [
        serviceById('svc-prophylaxis')!, // 45 min
        serviceById('svc-xray')!, //        15 min
        serviceById('svc-filling')!, //     45 min
      ];

      final duration = services.fold(0, (sum, s) => sum + s.durationMinutes);
      final total = services.fold(0.0, (sum, s) => sum + s.price);

      expect(duration, 105);
      expect(total, 3500);
      expect(downPaymentFor(total), 700);
    });

    test('formats durations and peso amounts for display', () {
      expect(formatDuration(45), '45 min');
      expect(formatDuration(60), '1 hr');
      expect(formatDuration(105), '1 hr 45 min');
      expect(formatPeso(3500), '₱3,500.00');
      expect(formatPeso(45000), '₱45,000.00');
    });
  });

  group('slot availability', () {
    late PatientRepository repository;
    late DateTime day;

    setUp(() async {
      // registerPatient clears the seeded demo history, giving each test an
      // empty schedule to book against.
      repository = PatientRepository();
      await repository.registerPatient(
        fullName: 'Test Patient',
        email: 'test@example.com',
        phone: '+63 900 000 0000',
      );
      day = nextWeekday(DateTime.wednesday);
    });

    test('a booked block makes overlapping starts unavailable', () {
      repository.addAppointment(
        serviceName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 45,
      );

      // 10:00–10:45 is taken, so a 30-minute visit cannot start at 10:15…
      expect(
        repository.isSlotAvailable(day: day, startMinute: 10 * 60 + 15, durationMinutes: 30),
        isFalse,
      );
      // …nor at 09:45, which would run into it…
      expect(
        repository.isSlotAvailable(day: day, startMinute: 9 * 60 + 45, durationMinutes: 30),
        isFalse,
      );
      // …but 10:45 butts up against the end and is fine.
      expect(
        repository.isSlotAvailable(day: day, startMinute: 10 * 60 + 45, durationMinutes: 30),
        isTrue,
      );
    });

    test('a cancelled booking releases its slot', () {
      final booking = repository.addAppointment(
        serviceName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 45,
      );

      expect(
        repository.isSlotAvailable(day: day, startMinute: 10 * 60, durationMinutes: 45),
        isFalse,
      );

      repository.cancelAppointment(booking.id, reason: 'Changed my mind');

      expect(
        repository.isSlotAvailable(day: day, startMinute: 10 * 60, durationMinutes: 45),
        isTrue,
      );
    });

    test('a reschedule may keep its own slot but not take another booking\'s', () {
      final first = repository.addAppointment(
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 30,
      );
      repository.addAppointment(
        serviceName: 'Composite Filling',
        doctorName: 'Dr. Jenneline Mariano',
        date: day,
        timeSlot: formatMinuteOfDay(14 * 60),
        durationMinutes: 45,
      );

      expect(
        repository.isSlotAvailable(
          day: day,
          startMinute: 10 * 60,
          durationMinutes: 30,
          excludeAppointmentId: first.id,
        ),
        isTrue,
      );
      expect(
        repository.isSlotAvailable(
          day: day,
          startMinute: 14 * 60,
          durationMinutes: 30,
          excludeAppointmentId: first.id,
        ),
        isFalse,
      );
    });

    test('slot options mark taken starts unavailable rather than hiding them', () {
      final beforeBooking = repository.slotOptionsFor(day: day, durationMinutes: 30);
      repository.addAppointment(
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(11 * 60),
        durationMinutes: 30,
      );
      final afterBooking = repository.slotOptionsFor(day: day, durationMinutes: 30);

      expect(afterBooking.length, beforeBooking.length);
      expect(
        afterBooking.where((s) => s.isAvailable).length,
        lessThan(beforeBooking.where((s) => s.isAvailable).length),
      );
      expect(
        afterBooking.firstWhere((s) => s.startMinute == 11 * 60).isAvailable,
        isFalse,
      );
    });

    test('a closed day yields no slot options at all', () {
      expect(
        repository.slotOptionsFor(day: nextWeekday(DateTime.monday), durationMinutes: 30),
        isEmpty,
      );
    });
  });

  group('booking outcomes', () {
    late PatientRepository repository;
    late DateTime day;

    setUp(() async {
      repository = PatientRepository();
      await repository.registerPatient(
        fullName: 'Test Patient',
        email: 'test@example.com',
        phone: '+63 900 000 0000',
      );
      day = nextWeekday(DateTime.thursday);
    });

    test('a wallet downpayment confirms the booking instantly', () {
      final booking = repository.addAppointment(
        serviceName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 45,
        totalPrice: 1000,
        amountPaid: 200,
        paymentMethod: 'Wallet',
        status: AppointmentStatus.confirmed,
      );

      expect(booking.status, AppointmentStatus.confirmed);
      expect(booking.balanceDue, 800);
      expect(booking.timeRangeLabel, '10:00 AM – 10:45 AM');
    });

    test('a cash booking is held for approval with nothing paid', () {
      final booking = repository.addAppointment(
        serviceName: 'Oral Prophylaxis',
        doctorName: unassignedDoctorForTest,
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 45,
        totalPrice: 1000,
        paymentMethod: 'Cash',
      );

      expect(booking.status, AppointmentStatus.pending);
      expect(booking.amountPaid, 0);
      expect(booking.balanceDue, 1000);
    });

    test('every booking raises a status notification', () {
      final before = repository.notifications.length;
      repository.addAppointment(
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: day,
        timeSlot: formatMinuteOfDay(10 * 60),
        durationMinutes: 30,
      );

      expect(repository.notifications.length, before + 1);
      expect(repository.notifications.first.title, 'Booking Request Received');
    });

    test('a wallet payment generates a receipt notification', () {
      repository.addWalletTransaction(
        title: 'Wallet Top-up',
        subtitle: 'GCash',
        amount: 1000,
        type: TransactionType.credit,
        icon: CupertinoIcons.creditcard,
        method: 'GCash',
      );

      expect(repository.walletBalance, 1000);
      expect(repository.notifications.first.title, 'Wallet Top-up Successful');
    });
  });

  group('registration', () {
    test('splits the full name and leaves optional details for later', () async {
      final repository = PatientRepository();
      final patient = await repository.registerPatient(
        fullName: 'Maria Clara Santos',
        email: 'maria.santos@example.com',
        phone: '+63 917 555 0100',
      );

      expect(patient.firstName, 'Maria');
      expect(patient.lastName, 'Clara Santos');
      expect(patient.fullName, 'Maria Clara Santos');
      expect(patient.username, 'maria.santos');
      expect(patient.dateOfBirth, isNull);
      expect(patient.gender, isNull);
      expect(patient.isProfileComplete, isFalse);
      expect(patient.missingProfileFields, ['Gender', 'Date of Birth', 'Address']);
    });
  });

  group('standard messages', () {
    test('use the exact wording the spec fixes', () {
      expect(AppMessages.appointmentScheduled, 'Appointment scheduled successfully!');
      expect(AppMessages.paymentProcessed, 'Payment processed and receipt generated.');
      expect(AppMessages.insufficientBalance,
          'Insufficient wallet balance for 20% downpayment.');
      expect(AppMessages.slotUnavailable, 'Selected time slot is no longer available.');
    });
  });
}

/// Kept local so the test file does not depend on the booking screen's UI
/// imports just to name the unassigned-doctor placeholder.
const String unassignedDoctorForTest = 'To be assigned';
