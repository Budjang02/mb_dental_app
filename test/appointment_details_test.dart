import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/screens/appointments/appointment_details_screen.dart';
import 'package:mb_dental_app/screens/appointments/reschedule_appointment_screen.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';

Appointment _appointment({
  String? confirmationCode,
  String? qrToken,
  double total = 1500,
  double paid = 300,
  String? method = 'Wallet',
  AppointmentStatus status = AppointmentStatus.confirmed,
}) =>
    Appointment(
      id: '6f1c2b1e-8a57-4c1e-9d0a-1b2c3d4e5f60',
      serviceName: 'Dental Checkup',
      doctorName: 'Dr. Rey Vincent Bolasoc',
      date: DateTime(2026, 10, 2),
      timeSlot: '10:00 AM',
      status: status,
      totalPrice: total,
      amountPaid: paid,
      paymentMethod: method,
      confirmationCode: confirmationCode,
      qrToken: qrToken,
      downpaymentPaidAt: paid > 0 ? DateTime(2026, 9, 20) : null,
    );

void main() {
  group('payment summary', () {
    test('payment method reads as the website names it', () {
      expect(paymentMethodLabel('Wallet', paid: true), 'E-Wallet');
      expect(paymentMethodLabel('GCash', paid: true), 'GCash');
      expect(paymentMethodLabel('Cash', paid: false), 'Cash (pay at clinic)');
      expect(paymentMethodLabel('', paid: false), '—');
    });

    test('price shows as a range only when the rate card has one', () {
      // The website's `_padPeso`: no .00 on whole pesos, centavos kept.
      expect(pesoRange(1500, 1500), '₱1,500');
      expect(pesoRange(1500, 2000), '₱1,500 – ₱2,000');
      expect(padPeso(1250.5), '₱1,250.50');
    });

    test('an estimate owes the price less the paid deposit', () {
      final m = AppointmentMoney.compute(
        method: 'Wallet',
        downpaymentAmount: 300,
        downpaymentPaid: true,
        rescheduleFeeTotal: 0,
        estimateMin: 1500,
        estimateMax: 1500,
      );
      expect(m.paid, isTrue);
      expect(m.credited, 300);
      expect(m.balanceMin, 1200);
      expect(m.billed, isFalse);
    });

    test('an unpaid deposit is not credited', () {
      final m = AppointmentMoney.compute(
        method: 'GCash',
        downpaymentAmount: 300,
        downpaymentPaid: false,
        rescheduleFeeTotal: 0,
        estimateMin: 1500,
        estimateMax: 1500,
      );
      expect(m.paid, isFalse);
      expect(m.balanceMin, 1500);
    });

    test('reschedule fees come off the deposit before it is credited', () {
      final m = AppointmentMoney.compute(
        method: 'Wallet',
        downpaymentAmount: 300,
        downpaymentPaid: true,
        rescheduleFeeTotal: 75,
        estimateMin: 1500,
        estimateMax: 1500,
      );
      expect(m.feeTotal, 75);
      expect(m.credited, 225);
      expect(m.balanceMin, 1275);
    });

    test('a filed bill uses its charges, and the deposit is taken off once', () {
      final open = AppointmentMoney.compute(
        method: 'Wallet',
        downpaymentAmount: 300,
        downpaymentPaid: true,
        rescheduleFeeTotal: 0,
        estimateMin: 1500,
        estimateMax: 1500,
        billTotal: 1800,
        billUnpaid: 1800,
      );
      expect(open.billed, isTrue);
      expect(open.priceMin, 1800);
      expect(open.balanceMin, 1500);

      // Settling the bill applied the deposit already: nothing more is owed,
      // and the deposit is not subtracted a second time.
      final settled = AppointmentMoney.compute(
        method: 'Wallet',
        downpaymentAmount: 300,
        downpaymentPaid: true,
        rescheduleFeeTotal: 0,
        estimateMin: 1500,
        estimateMax: 1500,
        billTotal: 1800,
        billUnpaid: 0,
      );
      expect(settled.balanceMin, 0);
    });

    test('balance due is total minus what was paid', () {
      expect(_appointment().balanceDue, 1200);
      expect(_appointment().downpaymentPercent, 20);
    });

    test('percent is zero when the visit has no price yet', () {
      expect(_appointment(total: 0, paid: 0).downpaymentPercent, 0);
    });
  });

  group('check-in payload', () {
    test('prefers the confirmation code', () {
      expect(_appointment(confirmationCode: 'MB-7Q2K9').checkInPayload, 'MB-7Q2K9');
    });

    test('falls back to the appointment id before a code is issued', () {
      expect(_appointment(confirmationCode: '  ').checkInPayload, _appointment().id);
    });

    test('survives copyWith', () {
      final copy = _appointment(confirmationCode: 'MB-7Q2K9').copyWith(status: AppointmentStatus.cancelled);
      expect(copy.confirmationCode, 'MB-7Q2K9');
      expect(copy.downpaymentPaidAt, DateTime(2026, 9, 20));
    });
  });

  group('check-in QR', () {
    const token = '0123456789abcdef0123456789abcdef';

    test('carries the verification link for qr_token, never the confirmation code', () {
      final a = _appointment(confirmationCode: 'E3XZSR', qrToken: token);
      expect(a.checkInQrPayload, 'https://mbdentalcenter.web.app/verify/?t=$token');
      expect(a.checkInQrPayload, isNot(contains('E3XZSR')));
    });

    test('a legacy booking with no token uses the website\'s ?code= link', () {
      expect(_appointment(confirmationCode: 'e3xzsr').checkInQrPayload,
          'https://mbdentalcenter.web.app/verify?code=E3XZSR');
      expect(_appointment().checkInQrPayload, isNull);
    });

    test('a token is read the way the website reads it', () {
      expect(Appointment.normaliseQrToken(' 0123456789ABCDEF0123456789ABCDEF '), token);
      expect(Appointment.normaliseQrToken('E3XZSR'), isNull);
      expect(Appointment.normaliseQrToken('${token}00'), isNull);
      expect(Appointment.normaliseQrToken(''), isNull);
      expect(Appointment.normaliseQrToken(null), isNull);
    });

    test('the confirmation code shown on the page is unchanged', () {
      expect(_appointment(confirmationCode: 'E3XZSR', qrToken: token).confirmationCode, 'E3XZSR');
    });

    test('survives copyWith', () {
      final copy = _appointment(qrToken: token).copyWith(status: AppointmentStatus.cancelled);
      expect(copy.qrToken, token);
    });
  });

  group('cancellation reason', () {
    Appointment cancelled({String? reason, String? by, String? byId, double down = 0, DateTime? paidAt, DateTime? at}) =>
        Appointment(
          id: 'x',
          serviceName: 'Dental Checkup',
          doctorName: '',
          date: DateTime(2026, 10, 2),
          timeSlot: '10:00 AM',
          status: AppointmentStatus.cancelled,
          cancellationReason: reason,
          cancelledBy: by,
          cancelledById: byId,
          downpaymentAmount: down,
          downpaymentPaidAt: paidAt,
          statusChangedAt: at,
        );

    test('the saved reason wins, whoever recorded it', () {
      expect(cancelled(reason: 'Schedule Conflict').cancellationReasonLabel(), 'Schedule Conflict');
      expect(cancelled(reason: 'Other: moving away', by: 'System').cancellationReasonLabel(), 'Other: moving away');
    });

    test('without one, it is worked out as the website does', () {
      expect(cancelled(by: 'System', down: 300).cancellationReasonLabel(),
          'Automatically cancelled: the down payment was not completed in time');
      expect(cancelled(by: 'System', at: DateTime(2026, 10, 2, 11)).cancellationReasonLabel(),
          'Automatically cancelled: the patient did not check in for the appointment');
      expect(cancelled(by: 'System', at: DateTime(2026, 9, 28)).cancellationReasonLabel(),
          'Automatically cancelled by the system');
      expect(cancelled(by: 'Front Desk', byId: 'staff-1').cancellationReasonLabel(myUserId: 'me'),
          'Cancelled by the clinic');
      expect(cancelled(byId: 'me').cancellationReasonLabel(myUserId: 'me'), 'Cancelled by patient');
    });

    test('shown only for a cancelled appointment', () {
      expect(_appointment().cancellationReasonLabel(), isNull);
    });
  });

  group('cancel and reschedule rules', () {
    test('a reason is required, and Other needs a note', () {
      expect(cancellationReasonValue(null, ''), isNull);
      expect(cancellationReasonValue('Schedule Conflict', ''), 'Schedule Conflict');
      expect(cancellationReasonValue('Other', '  '), isNull);
      expect(cancellationReasonValue('Other', ' moving   away '), 'Other: moving away');
      expect(cancellationReasonValue('Something else', 'x'), isNull);
    });

    test('only Scheduled or Confirmed visits can be changed', () {
      final future = DateTime.now().add(const Duration(days: 10));
      Appointment at(AppointmentStatus status) =>
          Appointment(id: 'x', serviceName: 's', doctorName: '', date: future, timeSlot: '10:00 AM', status: status);
      expect(canPatientChange(at(AppointmentStatus.pending)), isTrue);
      expect(canPatientChange(at(AppointmentStatus.confirmed)), isTrue);
      expect(canPatientChange(at(AppointmentStatus.completed)), isFalse);
      expect(canPatientChange(at(AppointmentStatus.cancelled)), isFalse);
    });

    test('rescheduling closes on the appointment day', () {
      final today = DateTime.now();
      Appointment on(DateTime day) => Appointment(
          id: 'x', serviceName: 's', doctorName: '', date: day, timeSlot: '10:00 AM', status: AppointmentStatus.confirmed);
      expect(canRescheduleOnline(on(today.add(const Duration(days: 3)))), isTrue);
      expect(canRescheduleOnline(on(today.subtract(const Duration(days: 1)))), isFalse);
    });

    test('the reschedule fee is 5% of the price, capped by what is left of the deposit', () {
      expect(rescheduleFeeFor(_appointment()), 75); // 5% of 1,500
      expect(rescheduleFeeFor(_appointment(paid: 0)), 0);
    });
  });
}
