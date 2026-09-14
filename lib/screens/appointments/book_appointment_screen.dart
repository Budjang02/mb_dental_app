import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/messages.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../data/clinic_catalog.dart';
import '../../data/service_categories.dart';
import '../../models/dental_service.dart';
import '../../models/dentist.dart';
import '../../repositories/clinic_api.dart';
import '../../repositories/patient_api.dart';
import '../../repositories/patient_repository.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/schedule_picker.dart';

/// Placeholder doctor value for bookings left to the clinic to staff. Aliases
/// the app-wide constant so the booking summary and the appointment screens
/// cannot drift apart on the wording.
const String unassignedDoctor = kUnassignedDoctor;

/// The three stages of the guided booking flow — one per node of the stepper
/// pinned to the top of the screen.
///
/// Patients do not choose a dentist. The clinic staffs each visit from the
/// credentials the selected procedures demand, so booking asks only what it
/// needs: what, when, and how it is paid for.
enum BookingStep { services, booking, summary }

extension on BookingStep {
  /// The word printed under this step's node in the header stepper.
  String get nodeLabel {
    switch (this) {
      case BookingStep.services:
        return 'Services';
      case BookingStep.booking:
        return 'Booking';
      case BookingStep.summary:
        return 'Summary';
    }
  }

}

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final PatientRepository _repository = PatientRepository();
  final _notesController = TextEditingController();

  BookingStep _step = BookingStep.services;

  final Set<DentalService> _selectedServices = {};

  DateTime? _selectedDate;
  int? _selectedStartMinute;
  bool _isSubmitting = false;

  /// Idempotency key for this checkout. Held on the state, not generated per
  /// call, so a retry after a timeout cannot debit the wallet a second time.
  String? _checkoutReference;

  // --- Derived booking totals ---

  /// Chair time for the whole visit — the sum the schedule step books against.
  int get _totalDuration =>
      _selectedServices.fold(0, (sum, service) => sum + service.durationMinutes);

  double get _totalPrice =>
      _selectedServices.fold(0.0, (sum, service) => sum + service.price);

  double get _downPayment => downPaymentFor(_totalPrice);

  /// Who the clinic would put in the chair, resolved from the procedures and
  /// the chosen day. Null until a date is picked, or when nobody credentialed
  /// holds clinic that weekday.
  Dentist? get _assignedDentist => _selectedDate == null
      ? null
      : assignedDentistFor(
          _selectedServices,
          _selectedDate!,
          startMinute: _selectedStartMinute,
          durationMinutes: _totalDuration,
        );

  /// The day's start times, with every time no clinic dentist credentialed for
  /// all the selected procedures is working for the whole visit marked taken.
  /// That is what guarantees the summary always names the dentist, their
  /// specialization and the time.
  List<SlotOption> _slotsWithDentist(DateTime day) {
    if (!hasClinicRoster || !hasEligibleDentistOn(_selectedServices, day)) return const [];
    return [
      for (final slot in _repository.slotOptionsFor(day: day, durationMinutes: _totalDuration))
        slot.isAvailable &&
                assignedDentistFor(
                      _selectedServices,
                      day,
                      startMinute: slot.startMinute,
                      durationMinutes: _totalDuration,
                    ) !=
                    null
            ? slot
            : SlotOption(
                startMinute: slot.startMinute,
                durationMinutes: slot.durationMinutes,
                isAvailable: false,
              ),
    ];
  }

  /// Why no clinic dentist can take the selected procedures, split the way the
  /// website's booking wizard words it (`_bwSplitNote`): the reason, shown in
  /// bold, then what happens next. Null while a dentist covers the selection,
  /// and while the roster is still loading.
  (String, String)? get _noDentistNote {
    if (_selectedServices.isEmpty) return null;
    final catalog = ClinicCatalog();
    if (!hasClinicRoster) {
      if (catalog.isLoading) return null;
      if (catalog.rosterFailed) {
        return ("We couldn't load the clinic's dentists.", 'Check your connection and try again.');
      }
      return ('No dentists are available right now.', 'Please contact the clinic to book this visit.');
    }
    if (eligibleDentists(_selectedServices).isNotEmpty) return null;
    for (final service in _selectedServices) {
      if (eligibleDentists([service]).isEmpty) {
        return (
          'No dentist currently offers ${specializationLabelFor(service.specializationCode)}.',
          'Please contact the clinic about ${service.name}.',
        );
      }
    }
    return (
      'No one dentist covers all of these procedures.',
      'Book them as separate visits, or contact the clinic.',
    );
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
      case BookingStep.services:
        // A mix no single dentist is credentialed for is not bookable: a visit
        // is staffed by one dentist, so it must not reach the calendar.
        return _selectedServices.isNotEmpty && hasClinicRoster && _noDentistNote == null;
      case BookingStep.booking:
        // The booking only moves on with a real clinic dentist named for the
        // chosen time: an unannounced dentist is not a bookable visit.
        return _selectedDate != null &&
            _selectedStartMinute != null &&
            hasClinicRoster &&
            _assignedDentist != null;
      case BookingStep.summary:
        return true;
    }
  }

  String get _blockedReason {
    switch (_step) {
      case BookingStep.services:
        if (_selectedServices.isEmpty) {
          return 'Please select at least one dental service.';
        }
        final note = _noDentistNote;
        if (note != null) return '${note.$1} ${note.$2}';
        return "Loading the clinic's dentists. Please try again in a moment.";
      case BookingStep.booking:
        if (_selectedDate == null) return 'Please select an appointment date.';
        if (_selectedStartMinute == null) return 'Please select a start time.';
        if (!hasClinicRoster) {
          return 'We could not load the clinic\'s dentists. Check your connection and try again.';
        }
        return 'No dentist for these procedures is working at that time. Please pick another time.';
      case BookingStep.summary:
        return '';
    }
  }

  void _next() {
    if (!_canAdvance) {
      showAppToast(context, _blockedReason, isError: true);
      return;
    }
    if (_step == BookingStep.summary) {
      _confirmBooking();
      return;
    }
    setState(() => _step = BookingStep.values[_step.index + 1]);
  }

  /// Steps back one stage. Only offered from Schedule onwards — on the first
  /// stage there is nothing behind it, and the close button leaves instead.
  void _back() {
    if (_step == BookingStep.services) return;
    setState(() => _step = BookingStep.values[_step.index - 1]);
  }

  /// Changing the service mix changes both the required credentials and the
  /// block length, so anything chosen downstream of it stops being valid.
  void _toggleService(DentalService service) {
    setState(() {
      if (!_selectedServices.remove(service)) _selectedServices.add(service);
      _invalidateDownstream();
    });
  }

  /// The ✕ on a selected-service card. Separate from [_toggleService] so the
  /// card's remove button never accidentally re-adds a service.
  void _removeService(DentalService service) {
    setState(() {
      _selectedServices.remove(service);
      _invalidateDownstream();
    });
  }

  /// The visit's block length changes with the service mix, so a start time
  /// chosen against the old length may no longer have room behind it.
  void _invalidateDownstream() {
    _selectedStartMinute = null;
  }

  // --- Service & attachment pickers ---

  Future<void> _openServicePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServicePickerSheet(
        selected: _selectedServices,
        onToggle: _toggleService,
      ),
    );
  }

  // --- Confirmation ---

  Future<void> _confirmBooking() async {
    final date = _selectedDate!;
    final startMinute = _selectedStartMinute!;

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
        _step = BookingStep.booking;
      });
      return;
    }

    // A local check first, so an obviously short wallet never leaves the screen.
    // It is not the one that protects the balance — the database re-checks it
    // under a row lock, because this figure can be stale by the time it is read.
    if (_repository.walletBalance < _downPayment) {
      _reportInsufficientFunds(
        available: _repository.walletBalance,
        required: _downPayment,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final timeSlot = formatMinuteOfDay(startMinute);

    final typed = _notesController.text.trim();
    final notes = typed.isEmpty ? null : typed;

    // Stable for the life of this attempt, so a retry after a dropped
    // connection settles onto the first booking instead of paying twice.
    _checkoutReference ??= 'REF-${DateTime.now().millisecondsSinceEpoch}';

    try {
      // One transaction: balance check, debit, ledger entry and the booking
      // itself. The booking arrives pending whatever was paid — only the clinic
      // may confirm a slot, so the app never asks for a confirmed one.
      await _repository.checkoutWithWallet(
        serviceIds: _selectedServices.map((s) => s.id).toList(),
        date: date,
        timeSlot: timeSlot,
        durationMinutes: _totalDuration,
        totalPrice: _totalPrice,
        amountToPay: _downPayment,
        doctorId: _assignedDentist?.id,
        notes: notes,
        method: 'GCash',
        referenceNo: _checkoutReference,
      );
    } on InsufficientWalletBalanceException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // The wallet moved since this screen last read it, so show the figures the
      // database refused on rather than the ones on screen.
      _reportInsufficientFunds(
        available: e.available,
        required: e.required > 0 ? e.required : _downPayment,
      );
      return;
    } on SlotTakenException {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _selectedStartMinute = null;
        _step = BookingStep.booking;
        // Nothing was charged, but the next attempt is a new booking.
        _checkoutReference = null;
      });
      showAppToast(context, AppMessages.slotUnavailable, isError: true);
      return;
    } on PatientNotApprovedException {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(context, AppMessages.accountPendingApproval, isError: true);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(context, 'We could not complete your booking. Please try again.',
          isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // The wallet debit above already raised its own receipt alert, so this
    // only reports the booking itself.
    showAppToast(context, AppMessages.appointmentScheduled);

    Navigator.pop(context);
  }

  /// Says how short the wallet is and offers the top-up screen, rather than only
  /// refusing. Nothing has been charged at this point.
  void _reportInsufficientFunds({required double available, required double required}) {
    final shortfall = (required - available).clamp(0, double.infinity);
    showAppToast(
      context,
      '${AppMessages.insufficientBalance} '
      'Balance ${formatPeso(available)}, ${formatPeso(required)} due — '
      'top up ${formatPeso(shortfall.toDouble())} to continue.',
      isError: true,
    );
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
          // Closes the whole flow. Stepping back between stages is the job of
          // the Back button beside the CTA, so this one is unambiguous: it
          // leaves booking rather than rewinding it.
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          ),
        ),
        body: Column(
          children: [
            _StepperHeader(current: _step),
            Expanded(
              // The CTA floats over the content rather than sitting in a bar
              // of its own, so the bottom padding here reserves the room it
              // covers — the last card can still be scrolled clear of it.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                child: _buildStepBody(),
              ),
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: _buildFloatingCta(),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case BookingStep.services:
        return _ServiceStep(
          selected: _selectedServices,
          onRemoveService: _removeService,
          onAddServices: _openServicePicker,
          note: _noDentistNote,
        );

      case BookingStep.booking:
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SchedulePicker(
              durationMinutes: _totalDuration,
              selectedDate: _selectedDate,
              selectedStartMinute: _selectedStartMinute,
              firstDay: DateTime(now.year, now.month, now.day),
              lastDay: DateTime(now.year, now.month, now.day).add(const Duration(days: 180)),
              // A free chair is not enough: the day must also be one a dentist
              // credentialed for every selected procedure holds clinic, or the
              // summary would name nobody for a visit already paid on.
              hasOpenSlot: (day) => _slotsWithDentist(day).any((slot) => slot.isAvailable),
              slotsFor: _slotsWithDentist,
              onDateSelected: (day) => setState(() {
                _selectedDate = day;
                _selectedStartMinute = null;
              }),
              onSlotSelected: (minute) => setState(() => _selectedStartMinute = minute),
            ),
          ],
        );

      case BookingStep.summary:
        return _PaymentStep(
          services: _selectedServices,
          dentist: _assignedDentist,
          date: _selectedDate!,
          startMinute: _selectedStartMinute!,
          totalDuration: _totalDuration,
          totalPrice: _totalPrice,
          downPayment: _downPayment,
          walletBalance: _repository.walletBalance,
          notesController: _notesController,
        );
    }
  }

  // --- Floating action button ---

  /// Height of every action button in the wizard, footer and sheets alike.
  /// At the 44pt floor for a comfortable touch target — no lower.
  static const double _actionButtonHeight = 44;

  Widget _buildFloatingCta() {
    final isSummary = _step == BookingStep.summary;
    final label = isSummary ? 'PAY' : 'CONTINUE';
    // Nothing to go back to on the first stage, so Back only appears from the
    // Schedule stage onwards.
    final showBack = _step != BookingStep.services;

    final primary = SizedBox(
      height: _actionButtonHeight,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _next,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, _actionButtonHeight),
          // A floating button needs its own lift: there is no bar behind it
          // separating it from whatever it happens to be sitting over.
          elevation: 6,
          shadowColor: AppColors.primary.withOpacity(0.45),
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              ),
      ),
    );

    return Padding(
      // Clears the screen edges on the sides; the FAB location handles the
      // bottom inset for us.
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: showBack
          ? Row(
              children: [
                // Filled surface, not transparent: this floats over the page,
                // and an outline alone would let the content show through it.
                SizedBox(
                  height: _actionButtonHeight,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _back,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, _actionButtonHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      elevation: 6,
                      shadowColor: Colors.black.withOpacity(0.25),
                      side: BorderSide(color: AppColors.border),
                    ),
                    child: const Text(
                      'BACK',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // The primary action keeps the remaining width, so Back never
                // grows to rival it.
                Expanded(child: primary),
              ],
            )
          : SizedBox(width: double.infinity, child: primary),
    );
  }
}

/// The three-node progress indicator pinned under the app bar.
///
/// A node is a numbered circle over its label: filled in the brand teal once
/// the step is reached, a hairline outline while it is still ahead. The rules
/// between them carry the same distinction, so the whole strip reads as one
/// line of travel rather than three separate badges.
class _StepperHeader extends StatelessWidget {
  final BookingStep current;

  const _StepperHeader({required this.current});

  /// The rule between two nodes. Deliberately fainter than [AppColors.border]
  /// in dark mode: at this length a full-strength border competes with the
  /// nodes it is only meant to connect.
  Color get _idleTrack => ThemeController().isDark
      ? const Color(0xFFFFFFFF).withOpacity(0.12)
      : AppColors.border;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in BookingStep.values) ...[
            if (step.index > 0)
              Expanded(
                child: Padding(
                  // Sits on the circles' centre line, not the label's.
                  padding: const EdgeInsets.only(top: 15, left: 6, right: 6),
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      color: step.index <= current.index ? AppColors.primary : _idleTrack,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
            _node(step),
          ],
        ],
      ),
    );
  }

  Widget _node(BookingStep step) {
    final isDone = step.index < current.index;
    final isCurrent = step == current;
    final isReached = isDone || isCurrent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 32,
          width: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isReached ? AppColors.primary : Colors.transparent,
            border: Border.all(
              color: isReached ? AppColors.primary : AppColors.border,
              width: 1.5,
            ),
            // The active node glows; a finished one has already had its turn.
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: isDone
              ? const Icon(CupertinoIcons.checkmark, size: 15, color: Colors.white)
              : Text(
                  '${step.index + 1}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isReached ? Colors.white : AppColors.textSecondary,
                  ),
                ),
        ),
        const SizedBox(height: 7),
        Text(
          step.nodeLabel,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            color: isReached ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// --- Step 1: Services ---

/// The service step is a list of what the patient has already committed to,
/// followed by the two ways to add to it. Browsing the full catalog happens in
/// a sheet ([_ServicePickerSheet]) rather than inline, so this screen only
/// ever shows the visit the patient is actually building.
class _ServiceStep extends StatelessWidget {
  final Set<DentalService> selected;
  final ValueChanged<DentalService> onRemoveService;
  final VoidCallback onAddServices;

  /// Why nobody can take the selection (reason, then next step), or null.
  final (String, String)? note;

  const _ServiceStep({
    required this.selected,
    required this.onRemoveService,
    required this.onAddServices,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final service in selected) ...[
          _SelectedServiceCard(
            service: service,
            onRemove: () => onRemoveService(service),
          ),
          const SizedBox(height: 10),
        ],
        if (note != null) ...[
          _NoDentistNote(reason: note!.$1, next: note!.$2),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 6),
        _ActionCard(
          title: selected.isEmpty ? 'Select services' : 'Select more services',
          subtitle: 'From our provided dental procedures',
          onTap: onAddServices,
        ),
      ],
    );
  }
}

/// One committed procedure, with the ✕ that takes it back out of the visit.
class _SelectedServiceCard extends StatelessWidget {
  final DentalService service;
  final VoidCallback onRemove;

  const _SelectedServiceCard({required this.service, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      service.priceLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(CupertinoIcons.clock, size: 11, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      service.durationLabel,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // The specialization this procedure carries, and how many of the
                // clinic's dentists hold it. A zero here is why the calendar
                // will offer nothing.
                Text(
                  '${specializationLabelFor(service.specializationCode)} · '
                  '${_doctorCountLabel(doctorsForService(service).length)}',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RemoveButton(
            onTap: onRemove,
            semanticLabel: 'Remove ${service.name}',
          ),
        ],
      ),
    );
  }
}

String _doctorCountLabel(int count) {
  if (count == 0) return 'no dentist available';
  return count == 1 ? '1 dentist' : '$count dentists';
}

/// The ✕ circle on the trailing edge of every selected-item card.
class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticLabel;

  const _RemoveButton({required this.onTap, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            height: 30,
            width: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(CupertinoIcons.xmark, size: 13, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// A + card: the two ways to add something to the visit.
class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.12),
                ),
                child: Icon(CupertinoIcons.plus, size: 19, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}


/// The full service menu, opened from the "select more services" card.
///
/// It toggles the caller's live selection as the patient taps, so closing the
/// sheet is never a commit step — what they see behind it is already current.
class _ServicePickerSheet extends StatefulWidget {
  final Set<DentalService> selected;
  final ValueChanged<DentalService> onToggle;

  const _ServicePickerSheet({required this.selected, required this.onToggle});

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  /// Which groups are open. Empty to begin with: seven headings on one screen
  /// is a far easier thing to scan than every procedure the clinic offers.
  final Set<String> _expanded = {};

  String _query = '';

  @override
  void initState() {
    super.initState();
    // The menu is normally already in memory from sign-in; this covers a
    // failed or not-yet-finished load without making the sheet wait on it.
    ClinicCatalog().load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  /// Matches on the procedure name and its description, so "whitening" and
  /// "enamel" both find the same row.
  bool _matches(DentalService service) {
    if (!_isSearching) return true;
    final needle = _query.trim().toLowerCase();
    return service.name.toLowerCase().contains(needle) ||
        service.description.toLowerCase().contains(needle);
  }

  /// The menu with the search applied, groups that match nothing dropped.
  Map<ServiceGroup, List<DentalService>> get _visibleGroups {
    final result = <ServiceGroup, List<DentalService>>{};
    servicesByCategory.forEach((group, services) {
      final matching = services.where(_matches).toList();
      if (matching.isNotEmpty) result[group] = matching;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClinicCatalog(),
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final catalog = ClinicCatalog();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            _SheetHandle(
              title: 'Dental Procedures',
              subtitle: '${widget.selected.length} selected',
            ),
            if (catalog.hasLoaded) _buildSearchField(),
            if (!catalog.hasLoaded && catalog.isLoading)
              Expanded(
                child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (!catalog.hasLoaded)
              Expanded(child: _buildUnavailable(catalog))
            else
              Expanded(child: _buildGroupList(scrollController)),
            _SheetFooter(
              label: 'DONE',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search procedures',
          hintStyle: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          prefixIcon: Icon(CupertinoIcons.search, size: 18, color: AppColors.textSecondary),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: Icon(CupertinoIcons.clear_circled_solid,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable(ClinicCatalog catalog) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              catalog.loadError ?? 'The service menu is not available right now.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => catalog.load(force: true),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupList(ScrollController scrollController) {
    final groups = _visibleGroups;

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No procedure matches that search.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        for (final entry in groups.entries) ...[
          // A group that books one procedure outright has no submenu to open:
          // a patient who does not know what they need should not have to pick
          // from a list to say so.
          if (entry.key.isDirectPick)
            Builder(builder: (context) {
              final service = directPickService(entry.key, entry.value)!;
              return _DirectPickSection(
                group: entry.key,
                service: service,
                isSelected: widget.selected.contains(service),
                onTap: () => setState(() => widget.onToggle(service)),
              );
            })
          else
            _CategorySection(
              group: entry.key,
              services: entry.value,
              selected: widget.selected,
              // A search is already a filter, so its results open on their own
              // — making the patient expand each group to see what matched
              // would defeat the search.
              isExpanded: _isSearching || _expanded.contains(entry.key.code),
              canCollapse: !_isSearching,
              onToggleExpanded: () => setState(() {
                if (!_expanded.remove(entry.key.code)) _expanded.add(entry.key.code);
              }),
              onToggleService: (service) => setState(() => widget.onToggle(service)),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// One collapsible group: a tappable heading, and the procedures under it.
class _CategorySection extends StatelessWidget {
  final ServiceGroup group;
  final List<DentalService> services;
  final Set<DentalService> selected;
  final bool isExpanded;
  final bool canCollapse;
  final VoidCallback onToggleExpanded;
  final ValueChanged<DentalService> onToggleService;

  const _CategorySection({
    required this.group,
    required this.services,
    required this.selected,
    required this.isExpanded,
    required this.canCollapse,
    required this.onToggleExpanded,
    required this.onToggleService,
  });

  int get _selectedCount => services.where(selected.contains).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selectedCount > 0 ? AppColors.primary : AppColors.border,
          width: _selectedCount > 0 ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: canCollapse ? onToggleExpanded : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (group.blurb.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              group.blurb,
                              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // How many are picked in here, so a collapsed group still
                    // shows it is contributing to the booking.
                    if (_selectedCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$_selectedCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Text(
                        '${services.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (canCollapse) ...[
                      const SizedBox(width: 6),
                      Icon(
                        isExpanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  for (final service in services) ...[
                    _ServiceTile(
                      service: service,
                      isSelected: selected.contains(service),
                      onTap: () => onToggleService(service),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A group that books one procedure outright: the heading *is* the choice.
///
/// Used by "Other / not sure", which books a dental checkup. The procedure it
/// books is named on the card so the patient still knows what they committed
/// to, and the chair time and price are the same ones a submenu tile shows.
class _DirectPickSection extends StatelessWidget {
  final ServiceGroup group;
  final DentalService service;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectPickSection({
    required this.group,
    required this.service,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (group.blurb.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        group.blurb,
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(CupertinoIcons.clock, size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${service.name} · ${service.durationLabel}',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          service.priceLabel,
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
              const SizedBox(width: 10),
              Icon(
                isSelected ? CupertinoIcons.checkmark_circle : CupertinoIcons.circle,
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

class _SheetHandle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SheetHandle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Column(
        children: [
          Container(
            height: 4,
            width: 40,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
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
              _RemoveButton(
                onTap: () => Navigator.pop(context),
                semanticLabel: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The sheet equivalent of the screen's sticky action bar.
class _SheetFooter extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SheetFooter({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ),
      ),
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
                          service.priceLabel,
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
                isSelected ? CupertinoIcons.checkmark_circle : CupertinoIcons.circle,
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

// --- Step 3: Summary & payment ---

class _PaymentStep extends StatelessWidget {
  final Set<DentalService> services;

  /// The dentist the clinic assigned. Null when nobody credentialed for the
  /// selection holds clinic that day.
  final Dentist? dentist;

  final DateTime date;
  final int startMinute;
  final int totalDuration;
  final double totalPrice;
  final double downPayment;
  final double walletBalance;
  final TextEditingController notesController;

  const _PaymentStep({
    required this.services,
    required this.dentist,
    required this.date,
    required this.startMinute,
    required this.totalDuration,
    required this.totalPrice,
    required this.downPayment,
    required this.walletBalance,
    required this.notesController,
  });

  @override
  Widget build(BuildContext context) {
    final canAffordDownPayment = walletBalance >= downPayment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusBanner(),
        const SizedBox(height: 20),
        _summaryCard(),
        const SizedBox(height: 22),
        Text(
          'Payment Option',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 10),
        _PaymentOptionTile(
          title: 'E-Wallet — GCash',
          subtitle: 'Balance: ${formatPeso(walletBalance)}',
          // The only note left is the one that stops the patient submitting:
          // everything else the tile used to spell out is on the card above.
          note: canAffordDownPayment ? null : AppMessages.insufficientBalance,
          isSelected: true,
          onTap: () {},
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

  /// The step opens on what the patient still owes, not on a description of
  /// the step. Red because it is a condition on the booking, not a receipt.
  Widget _statusBanner() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 30,
          color: AppColors.error,
        ),
        const SizedBox(height: 10),
        const Text(
          'Your Booking is For Payment',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Please pay ${formatPeso(downPayment)} to confirm your booking.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
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
          Center(
            child: Text(
              'Booking Request',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _providerRow(),
          Divider(color: AppColors.border, height: 30),
          _row('Service', services.map((s) => s.name).join(', ')),
          const SizedBox(height: 16),
          _row('Date', _dateLabel(date)),
          const SizedBox(height: 16),
          _row(
            'Time',
            '${formatMinuteOfDay(startMinute)} – ${formatMinuteOfDay(startMinute + totalDuration)}'
                '  (${formatDuration(totalDuration)})',
          ),
          Divider(color: AppColors.border, height: 22),
          _amountRow('Procedures total', formatPeso(totalPrice)),
          const SizedBox(height: 8),
          _amountRow('Mandatory 20% Downpayment', formatPeso(downPayment)),
          const SizedBox(height: 14),
          _totalRow(),
        ],
      ),
    );
  }

  /// Which doctor the clinic assigned, against what the patient still owes.
  Widget _providerRow() {
    final assigned = dentist;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 42,
          width: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withOpacity(0.12),
          ),
          child: assigned == null
              ? Icon(kDoctorIcon, size: 19, color: AppColors.primary)
              : assigned.avatarUrl != null
              // The dentist's own photo from their clinic profile.
              ? CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.transparent,
                  backgroundImage: NetworkImage(assigned.avatarUrl!),
                )
              : Text(
                  assigned.initials,
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
              // No glyph before the name: the avatar beside it already says
              // whose name this is.
              Text(
                doctorLabel(assigned?.name),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              if (assigned != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    assigned.title,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else
                Text(
                  'The clinic will staff this visit',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Payment Status',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: const Text(
                'Unpaid',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
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

  Widget _amountRow(String label, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// What the CTA is about to charge, set apart from the breakdown above it.
  Widget _totalRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // The amount is the point of the row, so the label is what gives way
        // when a five-figure visit needs the width.
        Flexible(
          child: Text(
            'TOTAL DUE NOW',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatPeso(downPayment),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
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
  final String title;
  final String subtitle;

  /// Shown only when something blocks paying with this method — an empty
  /// wallet, say. Null on the happy path, where the card above already says
  /// what will be charged.
  final String? note;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.title,
    required this.subtitle,
    required this.note,
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
                        ? CupertinoIcons.checkmark_circle
                        : CupertinoIcons.circle,
                    color: isSelected ? AppColors.primary : AppColors.border,
                    size: 22,
                  ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 10),
                Text(
                  note!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The empty state for a selection no clinic dentist can take: the reason in
/// bold, then what happens next, the way the website's booking wizard shows
/// it. Never a made-up dentist.
class _NoDentistNote extends StatelessWidget {
  final String reason;
  final String next;

  const _NoDentistNote({required this.reason, required this.next});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.35)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textPrimary),
          children: [
            TextSpan(text: reason, style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: ' $next'),
          ],
        ),
      ),
    );
  }
}