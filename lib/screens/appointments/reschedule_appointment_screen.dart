import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/clinic_api.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/schedule_picker.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';

/// The reschedule fee, as a percent of the estimated service total. Twin of
/// `reschedule_my_appointment()` and the website's `RS_FEE_PCT`.
const int kRescheduleFeePercent = 5;

/// Online rescheduling closes at the start of the appointment's own day, on
/// the clinic's (Manila) calendar — the website's `mbCanRescheduleOnline`.
bool canRescheduleOnline(Appointment appointment) =>
    clinicToday().isBefore(DateTime(appointment.date.year, appointment.date.month, appointment.date.day));

const String kSameDayRescheduleMessage =
    'Same-day online rescheduling is closed. For urgent schedule changes, please call the clinic directly at 09458550225.';

/// The fee rescheduling [appointment] would take from its deposit: 5% of the
/// estimated service total (or of the total its 20% deposit implies), never
/// more than is left of the deposit. Zero without a paid deposit.
double rescheduleFeeFor(Appointment appointment) {
  final down = appointment.amountPaid;
  if (down <= 0 || appointment.downpaymentPaidAt == null) return 0;
  final base = appointment.totalPrice > 0 ? appointment.totalPrice : down / 0.20;
  final fee = (base * kRescheduleFeePercent).round() / 100;
  final left = (down - appointment.rescheduleFeeTotal).clamp(0, double.infinity).toDouble();
  return fee < left ? fee : left;
}

/// Moves an existing appointment to a new date and time through
/// `reschedule_my_appointment()`, the database function the website uses.
/// The times offered are the server's own free slots for this visit, with the
/// visit itself left out of the count.
class RescheduleAppointmentScreen extends StatefulWidget {
  final Appointment appointment;

  const RescheduleAppointmentScreen({super.key, required this.appointment});

  @override
  State<RescheduleAppointmentScreen> createState() => _RescheduleAppointmentScreenState();
}

class _RescheduleAppointmentScreenState extends State<RescheduleAppointmentScreen> {
  final PatientRepository _repository = PatientRepository();

  DateTime? _selectedDate;

  /// Start of the new block, as minutes from midnight.
  int? _selectedStartMinute;
  bool _isSubmitting = false;

  /// Free starts on [_selectedDate] from the server, or null while loading.
  List<ServerSlot>? _serverSlots;
  String? _slotsError;
  int _slotRequest = 0;

  /// The moved appointment keeps its original chair time.
  int get _duration => widget.appointment.durationMinutes;

  Appointment get _appointment => widget.appointment;

  Future<void> _loadSlots(DateTime day) async {
    final request = ++_slotRequest;
    setState(() {
      _serverSlots = null;
      _slotsError = null;
    });
    // A legacy booking with no procedures on record cannot be looked up; the
    // clinic's own hours are then the guide, and the server still checks.
    if (_appointment.serviceIds.isEmpty) {
      setState(() => _serverSlots = const []);
      return;
    }
    try {
      final slots = await ClinicApi.availableSlotsForServices(
        procedureIds: _appointment.serviceIds,
        date: day,
        exceptAppointmentId: _appointment.id,
      );
      if (!mounted || request != _slotRequest) return;
      setState(() => _serverSlots = slots);
    } catch (e) {
      debugPrint('Reschedule slots failed: $e');
      if (!mounted || request != _slotRequest) return;
      setState(() {
        _serverSlots = const [];
        _slotsError = 'Could not read the calendar for that day. Pick the date again to retry.';
      });
    }
  }

  List<SlotOption> _slotsFor(DateTime day) {
    final local = _repository.slotOptionsFor(
      day: day,
      durationMinutes: _duration,
      excludeAppointmentId: _appointment.id,
    );
    final selected = _selectedDate;
    if (selected == null || !_sameDay(day, selected) || _appointment.serviceIds.isEmpty) return local;
    final free = {for (final s in _serverSlots ?? const <ServerSlot>[]) s.startMinute};
    return [
      for (final slot in local)
        SlotOption(
          startMinute: slot.startMinute,
          durationMinutes: slot.durationMinutes,
          isAvailable: slot.isAvailable && free.contains(slot.startMinute),
        ),
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _confirm() async {
    if (_selectedDate == null) {
      showAppToast(context, 'Please pick a new date.', isError: true);
      return;
    }
    if (_selectedStartMinute == null) {
      showAppToast(context, 'Please pick a new time.', isError: true);
      return;
    }
    if (!canRescheduleOnline(_appointment)) {
      showAppToast(context, kSameDayRescheduleMessage, isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    RescheduleResult result;
    try {
      result = await _repository.rescheduleAppointment(
        _appointment.id,
        date: _selectedDate!,
        timeSlot: formatMinuteOfDay(_selectedStartMinute!),
      );
    } catch (e) {
      debugPrint('Reschedule failed: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final refused = e is AppointmentChangeRefusedException;
      showAppToast(
        context,
        refused ? e.message : 'Could not reschedule. Please try again.',
        isError: true,
      );
      // A time that went meanwhile: show the day's fresh list.
      if (refused && RegExp('no longer available|fully booked', caseSensitive: false).hasMatch(e.message)) {
        setState(() => _selectedStartMinute = null);
        _loadSlots(_selectedDate!);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    showAppToast(
      context,
      result.paid
          ? 'Appointment rescheduled and confirmed. ${formatPeso(result.fee)} fee deducted — '
              '${formatPeso(result.depositCredit)} deposit credited to your final bill.'
          : 'Appointment rescheduled — the clinic will confirm your new time.',
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Tomorrow in Manila: a patient may not move a visit to today, the same
    // rule the database enforces and the website applies.
    final firstDay = firstPatientBookableDay;
    final fee = rescheduleFeeFor(_appointment);
    final paid = _appointment.amountPaid > 0 && _appointment.downpaymentPaidAt != null;
    final credit = (_appointment.amountPaid - _appointment.rescheduleFeeTotal - fee).clamp(0, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Reschedule Appointment')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_appointment.serviceName,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          'Doctor: ${doctorLabel(_appointment.doctorName)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Currently: ${formatAppointmentDate(_appointment.date)} at ${_appointment.timeRangeLabel}',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _requiredLabel('New Date & Time'),
                  const SizedBox(height: 8),
                  SchedulePicker(
                    durationMinutes: _duration,
                    selectedDate: _selectedDate,
                    selectedStartMinute: _selectedStartMinute,
                    firstDay: firstDay,
                    lastDay: firstDay.add(const Duration(days: 179)),
                    // The appointment being moved must not block itself.
                    hasOpenSlot: (day) => _repository.hasOpenSlotOn(
                      day: day,
                      durationMinutes: _duration,
                      excludeAppointmentId: _appointment.id,
                    ),
                    slotsFor: _slotsFor,
                    isLoadingSlots: _selectedDate != null && _serverSlots == null,
                    slotsError: _slotsError,
                    onDateSelected: (day) {
                      setState(() {
                        _selectedDate = day;
                        _selectedStartMinute = null;
                      });
                      _loadSlots(day);
                    },
                    onSlotSelected: (minute) => setState(() => _selectedStartMinute = minute),
                  ),
                  const SizedBox(height: 20),
                  _FeeBreakdown(
                    paid: paid,
                    deposit: _appointment.amountPaid,
                    previousFees: _appointment.rescheduleFeeTotal,
                    fee: fee,
                    credit: credit,
                    total: _appointment.totalPrice,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 46)),
                  onPressed: _isSubmitting ? null : _confirm,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Confirm & Reschedule'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What rescheduling costs, stated before the patient commits — the
/// website's fee breakdown.
class _FeeBreakdown extends StatelessWidget {
  final bool paid;
  final double deposit;
  final double previousFees;
  final double fee;
  final double credit;
  final double total;

  const _FeeBreakdown({
    required this.paid,
    required this.deposit,
    required this.previousFees,
    required this.fee,
    required this.credit,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: color ?? AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: !paid
          ? Text(
              'No deposit has been paid on this booking, so there is no fee. '
              'The clinic will confirm your new time.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row('Paid Deposit', formatPeso(deposit)),
                if (previousFees > 0) row('Previous Reschedule Fees', '-${formatPeso(previousFees)}', color: AppColors.error),
                row('Rescheduling Administrative Fee ($kRescheduleFeePercent%)', '-${formatPeso(fee)}',
                    color: AppColors.error),
                Divider(color: AppColors.border, height: 12),
                row('Remaining Credited Deposit', formatPeso(credit), bold: true),
                if (total > 0)
                  row('Revised Estimated Balance Due at Clinic',
                      formatPeso((total - credit).clamp(0, double.infinity).toDouble()),
                      color: AppColors.primary, bold: true),
              ],
            ),
    );
  }
}

Widget _requiredLabel(String label) {
  return RichText(
    text: TextSpan(
      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 14),
      children: [
        TextSpan(text: label),
        const TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
      ],
    ),
  );
}
