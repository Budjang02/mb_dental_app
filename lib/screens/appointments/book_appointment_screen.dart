import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/messages.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../data/clinic_catalog.dart';
import '../../models/appointment.dart';
import '../../models/dental_service.dart';
import '../../models/dentist.dart';
import '../../models/wallet_transaction.dart';
import '../../repositories/patient_repository.dart';
import '../../widgets/app_calendar.dart';
import '../../widgets/app_toast.dart';

/// Placeholder doctor value for bookings left to the clinic to staff.
const String unassignedDoctor = 'To be assigned';

/// The four stages of the guided booking flow.
enum BookingStep { service, doctor, schedule, payment }

extension on BookingStep {
  String get title {
    switch (this) {
      case BookingStep.service:
        return 'Select Services';
      case BookingStep.doctor:
        return 'Choose a Dentist';
      case BookingStep.schedule:
        return 'Pick a Schedule';
      case BookingStep.payment:
        return 'Payment';
    }
  }

  String get shortLabel {
    switch (this) {
      case BookingStep.service:
        return 'Service';
      case BookingStep.doctor:
        return 'Doctor';
      case BookingStep.schedule:
        return 'Schedule';
      case BookingStep.payment:
        return 'Payment';
    }
  }

  String get subtitle {
    switch (this) {
      case BookingStep.service:
        return 'Pick every procedure you need this visit. We add up the chair time for you.';
      case BookingStep.doctor:
        return 'Only dentists credentialed for your selection are listed.';
      case BookingStep.schedule:
        return 'The clinic is open $clinicOperatingDaysLabel, $clinicHoursLabel.';
      case BookingStep.payment:
        return 'Pay the 20% downpayment now to confirm instantly, or settle at the clinic.';
    }
  }
}

enum _PaymentOption { wallet, cash }

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final PatientRepository _repository = PatientRepository();
  final _notesController = TextEditingController();

  BookingStep _step = BookingStep.service;

  final Set<DentalService> _selectedServices = {};
  Dentist? _selectedDentist;
  DateTime? _selectedDate;
  DateTime _focusedDay = _firstBookableDay();
  int? _selectedStartMinute;
  _PaymentOption _paymentOption = _PaymentOption.wallet;
  bool _isSubmitting = false;

  // --- Derived booking totals ---

  /// Chair time for the whole visit — the sum the schedule step books against.
  int get _totalDuration =>
      _selectedServices.fold(0, (sum, service) => sum + service.durationMinutes);

  double get _totalPrice =>
      _selectedServices.fold(0.0, (sum, service) => sum + service.price);

  double get _downPayment => downPaymentFor(_totalPrice);

  String get _serviceSummary =>
      _selectedServices.map((s) => s.name).join(', ');

  /// The first day the clinic is actually open, starting from today — the
  /// calendar opens here rather than on a closed Monday.
  static DateTime _firstBookableDay() {
    var day = DateTime.now();
    for (var i = 0; i < 7; i++) {
      if (isClinicOpenOn(day)) return DateTime(day.year, day.month, day.day);
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // --- Step navigation ---

  /// Whether the current step has everything it needs to advance.
  bool get _canAdvance {
    switch (_step) {
      case BookingStep.service:
        return _selectedServices.isNotEmpty;
      case BookingStep.doctor:
        return _selectedDentist != null;
      case BookingStep.schedule:
        return _selectedDate != null && _selectedStartMinute != null;
      case BookingStep.payment:
        return true;
    }
  }

  String get _blockedReason {
    switch (_step) {
      case BookingStep.service:
        return 'Please select at least one dental service.';
      case BookingStep.doctor:
        return 'Please choose a dentist, or pick "Any Available Doctor".';
      case BookingStep.schedule:
        return _selectedDate == null
            ? 'Please select an appointment date.'
            : 'Please select a start time.';
      case BookingStep.payment:
        return '';
    }
  }

  void _next() {
    if (!_canAdvance) {
      showAppToast(context, _blockedReason, isError: true);
      return;
    }
    if (_step == BookingStep.payment) {
      _confirmBooking();
      return;
    }
    setState(() => _step = BookingStep.values[_step.index + 1]);
  }

  void _back() {
    if (_step == BookingStep.service) {
      Navigator.pop(context);
      return;
    }
    setState(() => _step = BookingStep.values[_step.index - 1]);
  }

  /// Changing the service mix changes both the required credentials and the
  /// block length, so anything chosen downstream of it stops being valid.
  void _toggleService(DentalService service) {
    setState(() {
      if (!_selectedServices.remove(service)) _selectedServices.add(service);

      final stillEligible = _selectedDentist == null ||
          _selectedDentist!.isAnyAvailable ||
          _selectedDentist!.canPerformAll(_selectedServices);
      if (!stillEligible) _selectedDentist = null;

      _selectedStartMinute = null;
    });
  }

  // --- Confirmation ---

  Future<void> _confirmBooking() async {
    final date = _selectedDate!;
    final startMinute = _selectedStartMinute!;
    final payingFromWallet = _paymentOption == _PaymentOption.wallet;

    // Re-check the slot at submit time: it may have been taken while the
    // patient was working through the wizard.
    if (!_repository.isSlotAvailable(
      day: date,
      startMinute: startMinute,
      durationMinutes: _totalDuration,
    )) {
      showAppToast(context, AppMessages.slotUnavailable, isError: true);
      setState(() {
        _selectedStartMinute = null;
        _step = BookingStep.schedule;
      });
      return;
    }

    if (payingFromWallet && _repository.walletBalance < _downPayment) {
      showAppToast(context, AppMessages.insufficientBalance, isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final timeSlot = formatMinuteOfDay(startMinute);
    final notes = _notesController.text.trim();

    if (payingFromWallet) {
      _repository.addWalletTransaction(
        title: 'Appointment Downpayment',
        subtitle: _serviceSummary,
        amount: _downPayment,
        type: TransactionType.debit,
        icon: CupertinoIcons.calendar_badge_plus,
        method: 'Wallet',
      );
    }

    // A settled downpayment secures the slot, so the booking arrives already
    // confirmed. Cash bookings stay pending until the clinic approves them.
    _repository.addAppointment(
      serviceName: _serviceSummary,
      doctorName: _selectedDentist!.isAnyAvailable ? unassignedDoctor : _selectedDentist!.name,
      date: date,
      timeSlot: timeSlot,
      notes: notes.isEmpty ? null : notes,
      paymentMethod: payingFromWallet ? 'Wallet' : 'Cash',
      status: payingFromWallet ? AppointmentStatus.confirmed : AppointmentStatus.pending,
      serviceIds: _selectedServices.map((s) => s.id).toList(),
      durationMinutes: _totalDuration,
      totalPrice: _totalPrice,
      amountPaid: payingFromWallet ? _downPayment : 0,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // The wallet debit above already raised its own receipt alert, so this
    // only reports the booking itself.
    showAppToast(context, AppMessages.appointmentScheduled);

    Navigator.pop(context);
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repository, ThemeController()]),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Book Appointment'),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_back),
            onPressed: _isSubmitting ? null : _back,
          ),
        ),
        body: Column(
          children: [
            _WizardProgress(current: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _step.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _step.subtitle,
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 18),
                    _buildStepBody(),
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case BookingStep.service:
        return _ServiceStep(
          selected: _selectedServices,
          onToggle: _toggleService,
        );
      case BookingStep.doctor:
        return _DoctorStep(
          services: _selectedServices,
          selected: _selectedDentist,
          onSelect: (dentist) => setState(() {
            _selectedDentist = dentist;
            _selectedStartMinute = null;
          }),
        );
      case BookingStep.schedule:
        return _ScheduleStep(
          totalDuration: _totalDuration,
          focusedDay: _focusedDay,
          selectedDate: _selectedDate,
          selectedStartMinute: _selectedStartMinute,
          slotsFor: (day) => _repository.slotOptionsFor(
            day: day,
            durationMinutes: _totalDuration,
          ),
          onDateSelected: (selected, focused) => setState(() {
            _selectedDate = selected;
            _focusedDay = focused;
            _selectedStartMinute = null;
          }),
          onPageChanged: (focused) => _focusedDay = focused,
          onSlotSelected: (minute) => setState(
            () => _selectedStartMinute = _selectedStartMinute == minute ? null : minute,
          ),
        );
      case BookingStep.payment:
        return _PaymentStep(
          services: _selectedServices,
          dentist: _selectedDentist!,
          date: _selectedDate!,
          startMinute: _selectedStartMinute!,
          totalDuration: _totalDuration,
          totalPrice: _totalPrice,
          downPayment: _downPayment,
          walletBalance: _repository.walletBalance,
          option: _paymentOption,
          notesController: _notesController,
          onOptionChanged: (option) => setState(() => _paymentOption = option),
        );
    }
  }

  Widget _buildFooter() {
    final hasSelection = _selectedServices.isNotEmpty;
    final isLastStep = _step == BookingStep.payment;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasSelection) ...[
                Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '  ·  ${_selectedServices.length} service${_selectedServices.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      formatPeso(_totalPrice),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  if (_step != BookingStep.service) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isSubmitting ? null : _back,
                        child: Text(
                          'Back',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _next,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              isLastStep
                                  ? (_paymentOption == _PaymentOption.wallet
                                      ? 'Pay ${formatPeso(_downPayment)} & Confirm'
                                      : 'Submit Request')
                                  : 'Continue',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The four-segment progress strip pinned under the app bar.
class _WizardProgress extends StatelessWidget {
  final BookingStep current;

  const _WizardProgress({required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        children: [
          for (final step in BookingStep.values) ...[
            if (step.index > 0) const SizedBox(width: 8),
            Expanded(child: _segment(step)),
          ],
        ],
      ),
    );
  }

  Widget _segment(BookingStep step) {
    final isDone = step.index < current.index;
    final isCurrent = step == current;
    final accent = isDone || isCurrent ? AppColors.primary : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(
              isDone ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
              size: 12,
              color: isDone || isCurrent ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                step.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isDone || isCurrent ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- Step 1: Service selection ---

class _ServiceStep extends StatelessWidget {
  final Set<DentalService> selected;
  final ValueChanged<DentalService> onToggle;

  const _ServiceStep({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final grouped = servicesByCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in ServiceCategory.values) ...[
          _categoryHeader(category, grouped[category]!.length),
          const SizedBox(height: 10),
          for (final service in grouped[category]!) ...[
            _ServiceTile(
              service: service,
              isSelected: selected.contains(service),
              onTap: () => onToggle(service),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _categoryHeader(ServiceCategory category, int count) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(category.icon, size: 16, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                category.blurb,
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '$count',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ServiceTile extends StatelessWidget {
  final DentalService service;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.service,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(service.icon, size: 19, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      service.description,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(CupertinoIcons.clock, size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          service.durationLabel,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatPeso(service.price),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                size: 21,
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Step 2: Doctor filtering ---

class _DoctorStep extends StatelessWidget {
  final Set<DentalService> services;
  final Dentist? selected;
  final ValueChanged<Dentist> onSelect;

  const _DoctorStep({
    required this.services,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final eligible = eligibleDentists(services);
    final required = requiredSpecializations(services).toList()..sort();
    final excluded = kDentists.where((d) => !eligible.contains(d)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _requirementBanner(required),
        const SizedBox(height: 14),
        _DentistTile(
          dentist: Dentist.anyAvailable,
          isSelected: selected?.id == Dentist.anyAvailable.id,
          onTap: () => onSelect(Dentist.anyAvailable),
        ),
        const SizedBox(height: 14),
        if (eligible.isEmpty)
          _noMatchNotice()
        else ...[
          Text(
            'Available for your selection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          for (final dentist in eligible) ...[
            _DentistTile(
              dentist: dentist,
              isSelected: selected?.id == dentist.id,
              onTap: () => onSelect(dentist),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (excluded.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${excluded.length} other dentist${excluded.length == 1 ? '' : 's'} '
            '${excluded.length == 1 ? 'is' : 'are'} not credentialed for every procedure '
            'you selected, so they are not listed.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _requirementBanner(List<String> required) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.checkmark_seal, size: 17, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Required specialization${required.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  required.join(' · '),
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noMatchNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle, size: 17, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No single dentist covers every procedure you picked. Continue with '
              '"Any Available Doctor" and the clinic will staff the visit, or go back '
              'and book the procedures separately.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DentistTile extends StatelessWidget {
  final Dentist dentist;
  final bool isSelected;
  final VoidCallback onTap;

  const _DentistTile({
    required this.dentist,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAny = dentist.isAnyAvailable;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isAny
                    ? Icon(CupertinoIcons.person_2, size: 20, color: AppColors.primary)
                    : Text(
                        dentist.initials,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dentist.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dentist.title,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    if (!isAny) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Clinic days: ${(dentist.clinicDays.toList()..sort()).map(weekdayLabel).join(', ')}',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                size: 21,
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Step 3: Schedule selection ---

class _ScheduleStep extends StatelessWidget {
  final int totalDuration;
  final DateTime focusedDay;
  final DateTime? selectedDate;
  final int? selectedStartMinute;
  final List<SlotOption> Function(DateTime day) slotsFor;
  final void Function(DateTime selected, DateTime focused) onDateSelected;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<int> onSlotSelected;

  const _ScheduleStep({
    required this.totalDuration,
    required this.focusedDay,
    required this.selectedDate,
    required this.selectedStartMinute,
    required this.slotsFor,
    required this.onDateSelected,
    required this.onPageChanged,
    required this.onSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.time, size: 17, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your visit needs a ${formatDuration(totalDuration)} block. '
                  'Only start times with room for it are offered.',
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCalendar(
          focusedDay: focusedDay,
          selectedDay: selectedDate,
          firstDay: DateTime(now.year, now.month, now.day),
          lastDay: DateTime(now.year, now.month, now.day).add(const Duration(days: 180)),
          // Mondays and Tuesdays are closed, so they are never selectable.
          enabledDayPredicate: isClinicOpenOn,
          onDaySelected: onDateSelected,
          onPageChanged: onPageChanged,
        ),
        const SizedBox(height: 18),
        if (selectedDate == null)
          _hint('Select an open day to see available start times.')
        else
          _buildSlots(context),
      ],
    );
  }

  Widget _buildSlots(BuildContext context) {
    final slots = slotsFor(selectedDate!);
    final openCount = slots.where((s) => s.isAvailable).length;

    if (slots.isEmpty) {
      return _hint(
        'No ${formatDuration(totalDuration)} block fits within clinic hours on this day. '
        'Try another date.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Start Time',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              '$openCount of ${slots.length} open',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Times are 15 minutes apart.',
          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        if (openCount == 0)
          _hint('This day is fully booked. Please choose another date.')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const columns = 3;
              const gap = 10.0;
              final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final slot in slots)
                    SizedBox(width: itemWidth, child: _slotChip(slot)),
                ],
              );
            },
          ),
        if (selectedStartMinute != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.calendar_badge_plus, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reserved block: '
                    '${formatMinuteOfDay(selectedStartMinute!)} – '
                    '${formatMinuteOfDay(selectedStartMinute! + totalDuration)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _slotChip(SlotOption slot) {
    final isSelected = selectedStartMinute == slot.startMinute;
    final enabled = slot.isAvailable;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: isSelected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => onSlotSelected(slot.startMinute) : null,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
            ),
            child: Text(
              slot.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                decoration: enabled ? null : TextDecoration.lineThrough,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
      ),
    );
  }
}

// --- Step 4: Payment ---

class _PaymentStep extends StatelessWidget {
  final Set<DentalService> services;
  final Dentist dentist;
  final DateTime date;
  final int startMinute;
  final int totalDuration;
  final double totalPrice;
  final double downPayment;
  final double walletBalance;
  final _PaymentOption option;
  final TextEditingController notesController;
  final ValueChanged<_PaymentOption> onOptionChanged;

  const _PaymentStep({
    required this.services,
    required this.dentist,
    required this.date,
    required this.startMinute,
    required this.totalDuration,
    required this.totalPrice,
    required this.downPayment,
    required this.walletBalance,
    required this.option,
    required this.notesController,
    required this.onOptionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final canAffordDownPayment = walletBalance >= downPayment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryCard(),
        const SizedBox(height: 22),
        Text(
          'Payment Option',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        _PaymentOptionTile(
          icon: CupertinoIcons.creditcard,
          title: 'E-Wallet — 20% Downpayment',
          subtitle: 'Balance: ${formatPeso(walletBalance)}',
          note: canAffordDownPayment
              ? '${formatPeso(downPayment)} is deducted now and your booking is '
                  'confirmed instantly. The ${formatPeso(totalPrice - downPayment)} '
                  'balance is settled at the clinic.'
              : AppMessages.insufficientBalance,
          noteColor: canAffordDownPayment ? AppColors.primary : AppColors.error,
          isSelected: option == _PaymentOption.wallet,
          onTap: () => onOptionChanged(_PaymentOption.wallet),
        ),
        const SizedBox(height: 12),
        _PaymentOptionTile(
          icon: Icons.payments_rounded,
          title: 'Cash at Clinic',
          subtitle: 'Pay the full amount in person',
          note: 'Your request is submitted as Pending Approval. We will remind you '
              '5 days and 2 hours before your slot.',
          noteColor: AppColors.textSecondary,
          isSelected: option == _PaymentOption.cash,
          onTap: () => onOptionChanged(_PaymentOption.cash),
        ),
        const SizedBox(height: 22),
        Text(
          'Additional Notes (Optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: notesController,
          maxLines: 3,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Describe any symptoms or specific requests...',
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Booking Summary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          for (final service in services) ...[
            Row(
              children: [
                Icon(service.icon, size: 15, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    service.name,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                  ),
                ),
                Text(
                  service.durationLabel,
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Text(
                  formatPeso(service.price),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Divider(color: AppColors.border, height: 22),
          _row(CupertinoIcons.person, 'Dentist',
              dentist.isAnyAvailable ? 'Any Available Doctor' : dentist.name),
          const SizedBox(height: 10),
          _row(CupertinoIcons.calendar, 'Date', _dateLabel(date)),
          const SizedBox(height: 10),
          _row(
            CupertinoIcons.clock,
            'Time',
            '${formatMinuteOfDay(startMinute)} – ${formatMinuteOfDay(startMinute + totalDuration)}'
                '  (${formatDuration(totalDuration)})',
          ),
          Divider(color: AppColors.border, height: 22),
          _amountRow('Total', formatPeso(totalPrice), emphasize: false),
          const SizedBox(height: 8),
          _amountRow('20% Downpayment', formatPeso(downPayment), emphasize: true),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 66,
          child: Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _amountRow(String label, String amount, {required bool emphasize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: emphasize ? 13 : 12.5,
            fontWeight: emphasize ? FontWeight.bold : FontWeight.w500,
            color: emphasize ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: emphasize ? 16 : 13,
            fontWeight: FontWeight.bold,
            color: emphasize ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dateLabel(DateTime date) =>
      '${weekdayLabel(date.weekday)}, ${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

class _PaymentOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Spells out what this option means for confirmation — a downpayment taken
  /// now versus a request that waits on the clinic.
  final String note;
  final Color noteColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.noteColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.circle,
                    color: isSelected ? AppColors.primary : AppColors.border,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(note, style: TextStyle(fontSize: 11.5, height: 1.35, color: noteColor)),
            ],
          ),
        ),
      ),
    );
  }
}
