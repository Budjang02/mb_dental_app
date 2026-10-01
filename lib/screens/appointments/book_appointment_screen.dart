import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/screens/wallet/cash_in_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/messages.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../data/clinic_catalog.dart';
import '../../data/service_categories.dart';
import '../../models/appointment.dart';
import '../../models/dental_service.dart';
import '../../models/dentist.dart';
import '../../repositories/clinic_api.dart';
import '../../repositories/patient_api.dart';
import '../../repositories/patient_repository.dart';
import '../../repositories/wallet_topup_api.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/schedule_picker.dart';
import '../../widgets/skeleton.dart';
import 'appointment_confirmed_screen.dart';

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
  String _paymentMethod = _BookingPaymentMethod.wallet;
  bool _isSubmitting = false;

  /// Free starts for [_selectedDate] from the server's scheduling engine —
  /// the same `available_slots_for_services` call the website makes. Null
  /// while the request is out; empty when the day has nothing free.
  List<ServerSlot>? _serverSlots;

  /// Set when that request failed, so the time card can say so.
  String? _serverSlotsError;

  /// Which request is current: a late reply for a day the patient has left,
  /// or a service mix they have changed, must not repaint the times.
  int _slotRequest = 0;

  /// A GCash/GrabPay booking payment PayMongo has confirmed paid but no
  /// booking has used yet — the slot went while the patient was paying, say.
  /// PAY then books against it again instead of charging a second time, as
  /// the website's wizard does.
  String? _paidRequestId;
  String? _paidWith;

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

  /// Who the clinic would put in the chair. Once a time is picked this is the
  /// dentist the server's engine named for it; before that, and if the
  /// engine named someone outside the loaded roster, it falls back to the
  /// app's own match on credentials and hours.
  Dentist? get _assignedDentist {
    if (_selectedDate == null) return null;
    final start = _selectedStartMinute;
    if (start != null) {
      for (final slot in _serverSlots ?? const <ServerSlot>[]) {
        if (slot.startMinute == start) {
          final named = dentistById(slot.doctorId);
          if (named != null) return named;
          break;
        }
      }
    }
    return assignedDentistFor(
      _selectedServices,
      _selectedDate!,
      startMinute: start,
      durationMinutes: _totalDuration,
    );
  }

  /// Asks the server which starts are free on [day]. The website does the
  /// same: the app alone only sees this patient's own bookings, so it would
  /// offer times other patients have already taken.
  Future<void> _loadServerSlots(DateTime day) async {
    final request = ++_slotRequest;
    setState(() {
      _serverSlots = null;
      _serverSlotsError = null;
    });
    try {
      final slots = await ClinicApi.availableSlotsForServices(
        procedureIds: _selectedServices.map((s) => s.id).toList(),
        date: day,
      );
      if (!mounted || request != _slotRequest) return;
      setState(() => _serverSlots = slots);
    } catch (e) {
      debugPrint('available_slots_for_services failed: $e');
      if (!mounted || request != _slotRequest) return;
      setState(() {
        _serverSlots = const [];
        _serverSlotsError = 'Could not read the calendar for that day. Pick the date again to retry.';
      });
    }
  }

  /// The day's start times, with every time no clinic dentist credentialed for
  /// all the selected procedures is working for the whole visit marked taken.
  /// That is what guarantees the summary always names the dentist, their
  /// specialization and the time.
  List<SlotOption> _slotsWithDentist(DateTime day) {
    if (!hasClinicRoster || !hasEligibleDentistOn(_selectedServices, day)) return const [];
    // The chosen day's times are the server's: only a start its engine lists
    // as free is offered. Other days keep the app's own quick check, which
    // is only used to grey out dates on the calendar.
    final selected = _selectedDate;
    if (selected != null && _isSameDay(day, selected)) {
      final free = {for (final slot in _serverSlots ?? const <ServerSlot>[]) slot.startMinute};
      return [
        for (final slot in _repository.slotOptionsFor(day: day, durationMinutes: _totalDuration))
          SlotOption(
            startMinute: slot.startMinute,
            durationMinutes: slot.durationMinutes,
            isAvailable: slot.isAvailable && free.contains(slot.startMinute),
          ),
      ];
    }
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
        // The Terms and Conditions are agreed to on their own screen, opened
        // by PAY before any money moves — see [_startPayment].
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
      _startPayment();
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

  /// Adds one procedure to the visit. A visit can hold several, but they are
  /// added one per trip to the picker, which leaves out anything already in
  /// the visit. Changing the mix changes both the credentials required and
  /// the block length, so anything chosen downstream stops being valid.
  void _addService(DentalService service) {
    setState(() {
      if (_selectedServices.add(service)) _invalidateDownstream();
    });
  }

  /// The ✕ on a selected-service card.
  void _removeService(DentalService service) {
    setState(() {
      _selectedServices.remove(service);
      _invalidateDownstream();
    });
  }

  /// The visit's block length changes with the service mix, so a start time
  /// chosen against the old length may no longer have room behind it — and
  /// the server's free times were worked out for the old mix.
  void _invalidateDownstream() {
    _selectedStartMinute = null;
    final day = _selectedDate;
    if (day != null && _selectedServices.isNotEmpty) {
      _loadServerSlots(day);
    } else {
      _slotRequest++;
      _serverSlots = null;
    }
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // --- Service & attachment pickers ---

  Future<void> _openServicePicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServicePickerSheet(
        selected: _selectedServices,
        onPick: _addService,
      ),
    );
  }

  // --- Confirmation ---

  /// PAY: check the booking still stands, have the patient read and accept
  /// the Terms and Conditions and Privacy Policy, then take the down payment
  /// the way they chose.
  Future<void> _startPayment() async {
    // The button is disabled during checkout, and this guard also protects
    // against a second invocation before Flutter rebuilds the button.
    if (_isSubmitting) return;
    if (!_bookingStillValid()) return;

    // Already paid through PayMongo (and already agreed to the terms): book
    // against that payment.
    if (_paidRequestId != null) {
      await _confirmBooking();
      return;
    }

    // A short wallet is reported before the terms, so the patient is not
    // asked to agree to a payment that cannot go through.
    final rail = _BookingPaymentMethod.railFor(_paymentMethod);
    if (rail == null && _repository.walletBalance < _downPayment) {
      _reportInsufficientFunds(available: _repository.walletBalance, required: _downPayment);
      return;
    }

    final agreed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const BookingTermsScreen()),
    );
    if (agreed != true || !mounted) return;

    if (rail == null || _downPayment <= 0) {
      await _confirmBooking();
    } else {
      await _payWithPayMongo(rail);
    }
  }

  /// The date and slot checks run before anything is charged. False (with a
  /// toast, and the patient sent back to the calendar) when the booking no
  /// longer stands.
  bool _bookingStillValid({bool quiet = false}) {
    final date = _selectedDate!;
    final startMinute = _selectedStartMinute!;
    final firstBookableDay = firstPatientBookableDay;

    // The calendar prevents same-day booking, but retain the rule at checkout
    // so a stale selection can never turn into a same-day request.
    if (DateTime(date.year, date.month, date.day).isBefore(firstBookableDay)) {
      if (!quiet) {
        showAppToast(context, 'Appointments must be booked at least one day in advance.',
            isError: true);
      }
      setState(() => _step = BookingStep.booking);
      return false;
    }

    // Re-check the slot: it may have been taken while the patient was working
    // through the wizard. The database makes the final call at checkout.
    if (!_repository.isSlotAvailable(
          day: date,
          startMinute: startMinute,
          durationMinutes: _totalDuration,
        ) ||
        !(_serverSlots ?? const <ServerSlot>[]).any((slot) => slot.startMinute == startMinute)) {
      if (!quiet) showAppToast(context, AppMessages.slotUnavailable, isError: true);
      setState(() => _step = BookingStep.booking);
      return false;
    }
    return true;
  }

  /// GCash or GrabPay, through PayMongo — the website's flow. The app opens a
  /// PayMongo checkout for the down payment, marked as a booking payment (the
  /// webhook records it paid without crediting the wallet). Once the server
  /// says PayMongo authorized it, `book_appointment_v6` books the visit
  /// against that payment request and confirms it.
  ///
  /// Nothing is booked on the app's word: if the payment fails, times out or
  /// the patient gives up waiting, no appointment is made.
  Future<void> _payWithPayMongo(CashInRail rail) async {
    setState(() => _isSubmitting = true);
    final amountCentavos = (_downPayment * 100).round().clamp(WalletTopupApi.minCentavos, WalletTopupApi.maxCentavos);

    String requestId;
    try {
      final (url, id) = await WalletTopupApi.createBookingCheckout(
        amountCentavos: amountCentavos,
        paymentMethod: rail.id,
      );
      requestId = id;
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched) throw const CashInException('The payment page could not be opened.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(
        context,
        e is CashInException ? e.message : 'The payment page could not be opened. Please try again.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;

    final outcome = await showDialog<_PayMongoOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayMongoWaitDialog(requestId: requestId, railLabel: rail.label),
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    switch (outcome) {
      case _PayMongoOutcome.paid:
        _paidRequestId = requestId;
        _paidWith = rail.id == 'grab_pay' ? _BookingPaymentMethod.grabPay : _BookingPaymentMethod.gcash;
        await _confirmBooking();
      case _PayMongoOutcome.failed:
        showAppToast(context, 'The ${rail.label} payment did not go through. You were not booked.',
            isError: true);
      case _PayMongoOutcome.stillPending:
      case null:
        showAppToast(
          context,
          'We have not heard back from ${rail.label} yet, so you were not booked. '
          'If you were charged, please contact the clinic with your payment reference.',
          isError: true,
        );
    }
  }

  /// Books the visit through the website's own functions: `book_appointment_v5`
  /// takes the down payment from the wallet; `book_appointment_v6` settles it
  /// against a GCash/GrabPay payment already made ([_paidRequestId]). Either
  /// way the server prices the visit, stamps the confirmation code and QR,
  /// confirms it once paid and sends the confirmation — in one transaction.
  Future<void> _confirmBooking() async {
    if (_isSubmitting) return;
    final paidThroughPayMongo = _paidRequestId != null;

    final date = _selectedDate!;
    final startMinute = _selectedStartMinute!;

    // After a PayMongo payment the one message that matters is where the
    // money went, so the usual slot toast is held back.
    if (!_bookingStillValid(quiet: paidThroughPayMongo)) {
      if (paidThroughPayMongo) _reportPaidButNotBooked();
      return;
    }

    // A local check first, so an obviously short wallet never leaves the screen.
    // It is not the one that protects the balance — the database re-checks it
    // under a row lock, because this figure can be stale by the time it is read.
    if (!paidThroughPayMongo && _repository.walletBalance < _downPayment) {
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

    String? bookedId;
    try {
      // One transaction on the server. The app never sets the status: the
      // booking function confirms a paid visit, and the reload that follows
      // reads back whatever the database stored.
      final checkout = await _repository.checkoutWithWallet(
        paymentRequestId: _paidRequestId,
        paymentMethod: _paidWith ?? _BookingPaymentMethod.wallet,
        serviceIds: _selectedServices.map((s) => s.id).toList(),
        date: date,
        timeSlot: timeSlot,
        durationMinutes: _totalDuration,
        totalPrice: _totalPrice,
        amountToPay: _downPayment,
        doctorId: _assignedDentist?.id,
        notes: notes,
        referenceNo: _checkoutReference,
      );
      if (checkout == null || !checkout.hasBookingConfirmation) {
        throw const InvalidWalletCheckoutResultException();
      }
      bookedId = checkout.appointmentId;
      // Used: the payment now belongs to this booking.
      _paidRequestId = null;
      _paidWith = null;
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
        _step = BookingStep.booking;
      });
      if (paidThroughPayMongo) {
        _reportPaidButNotBooked();
      } else {
        showAppToast(context, AppMessages.slotUnavailable, isError: true);
      }
      return;
    } on BookingPaymentServiceUnavailableException {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(
        context,
        'Payment service is unavailable. Your appointment was not booked. Please try again later.',
        isError: true,
      );
      return;
    } on PatientNotApprovedException {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(context, AppMessages.accountPendingApproval, isError: true);
      return;
    } catch (e, stack) {
      debugPrint('Booking checkout failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      showAppToast(context, 'Booking could not be completed. Please try again.',
          isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // The status Supabase gave the booking decides what comes next. A visit
    // the server confirmed on a paid deposit gets the Appointment Confirmed
    // screen, in place of this one so Back cannot re-run the checkout. A
    // booking still waiting on the clinic only gets a note.
    Appointment? booked;
    for (final a in _repository.appointments) {
      if (a.id == bookedId) booked = a;
    }
    final confirmedAndPaid = booked != null &&
        booked.status == AppointmentStatus.confirmed &&
        booked.downpaymentPaidAt != null;
    if (confirmedAndPaid) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AppointmentConfirmedScreen(appointmentId: booked!.id)),
      );
      return;
    }
    showAppToast(context, AppMessages.appointmentScheduled);
    Navigator.pop(context);
  }

  /// The GCash/GrabPay payment went through but the slot went in the meantime.
  /// The payment is kept for this booking, so picking another time and
  /// pressing PAY books against it without charging again.
  void _reportPaidButNotBooked() {
    showAppToast(
      context,
      'Your payment was received, but that time was just taken. Pick another time and press '
      'PAY — you will not be charged again.',
      isError: true,
    );
  }

  /// Says how short the wallet is and offers the top-up screen, rather than only
  /// refusing. Nothing has been charged at this point.
  void _reportInsufficientFunds({required double available, required double required}) {
    final shortfall = (required - available).clamp(0, double.infinity).toDouble();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text(
          '${AppMessages.insufficientBalance} '
          'Balance ${formatPeso(available)}, ${formatPeso(required)} due — '
          'top up ${formatPeso(shortfall)} to continue.',
        ),
        // Cash In over this booking: it confirms the payment itself and comes
        // back here, with the booking as it was.
        action: SnackBarAction(
          label: 'Cash In',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CashInScreen(
              initialAmount: shortfall < 20 ? 20 : (shortfall * 100).ceil() / 100,
              returnToCaller: true,
            ),
          )),
        ),
      ));
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: _buildStepBody(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildActionBar(),
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
        // Tomorrow in Manila, not on the phone's clock: the website and the
        // database both count the clinic's days.
        final tomorrow = firstPatientBookableDay;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SchedulePicker(
              durationMinutes: _totalDuration,
              selectedDate: _selectedDate,
              selectedStartMinute: _selectedStartMinute,
              // Appointments need a full day's notice. Starting at tomorrow
              // also keeps today from looking selectable on the calendar.
              firstDay: tomorrow,
              lastDay: tomorrow.add(const Duration(days: 179)),
              // A free chair is not enough: the day must also be one a dentist
              // credentialed for every selected procedure holds clinic, or the
              // summary would name nobody for a visit already paid on.
              hasOpenSlot: (day) => _slotsWithDentist(day).any((slot) => slot.isAvailable),
              slotsFor: _slotsWithDentist,
              isLoadingSlots: _selectedDate != null && _serverSlots == null,
              slotsError: _serverSlotsError,
              onDateSelected: (day) {
                setState(() {
                  _selectedDate = day;
                  _selectedStartMinute = null;
                });
                _loadServerSlots(day);
              },
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
          selectedPaymentMethod: _paymentMethod,
          onPaymentMethodSelected: (method) => setState(() => _paymentMethod = method),
        );
    }
  }

  // --- Booking action bar ---

  /// Height of every action button in the wizard, footer and sheets alike.
  /// At the 44pt floor for a comfortable touch target — no lower.
  static const double _actionButtonHeight = 44;

  Widget _buildActionBar() {
    final isSummary = _step == BookingStep.summary;
    final label = isSummary ? 'PAY' : 'CONTINUE';
    // Nothing to go back to on the first stage, so Back only appears from the
    // Schedule stage onwards.
    final showBack = _step != BookingStep.services;

    final primary = SizedBox(
      height: _actionButtonHeight,
      child: ElevatedButton(
        // On the summary this opens the Terms and Conditions first; nothing
        // is charged until the patient has agreed to them.
        onPressed: _isSubmitting ? null : _next,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, _actionButtonHeight),
          elevation: 0,
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: showBack
              ? Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: _actionButtonHeight,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _back,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.textPrimary,
                            minimumSize: const Size(0, _actionButtonHeight),
                            elevation: 0,
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
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: primary),
                  ],
                )
              : SizedBox(width: double.infinity, child: primary),
        ),
      ),
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
          title: selected.isEmpty ? 'Select a service' : 'Add another service',
          subtitle: selected.isEmpty
              ? 'From our provided dental procedures'
              : 'Add one more procedure to this visit',
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


/// The full service menu, opened from the "Select a service" / "Add another
/// service" card. One tap adds one procedure and closes the sheet; anything
/// already in the visit is left off the list, so it cannot be added twice.
class _ServicePickerSheet extends StatefulWidget {
  final Set<DentalService> selected;
  final ValueChanged<DentalService> onPick;

  const _ServicePickerSheet({required this.selected, required this.onPick});

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
    if (widget.selected.contains(service)) return false;
    if (!_isSearching) return true;
    final needle = _query.trim().toLowerCase();
    return service.name.toLowerCase().contains(needle) ||
        service.description.toLowerCase().contains(needle);
  }

  /// Adds [service] to the visit and closes the sheet, so one tap finishes
  /// the pick. The next service is added with another trip to the sheet.
  void _pick(DentalService service) {
    widget.onPick(service);
    Navigator.pop(context);
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
              subtitle: widget.selected.isEmpty
                  ? 'Tap a procedure to add it'
                  : '${widget.selected.length} in this visit · tap one more to add it',
            ),
            if (catalog.hasLoaded) _buildSearchField(),
            if (!catalog.hasLoaded && catalog.isLoading)
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: PageSkeleton(cardCount: 6, showHeader: false),
                ),
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
    final fullMenu = servicesByCategory;

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _isSearching
                ? 'No procedure matches that search.'
                : 'Every procedure is already in this visit.',
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
          // "Other / Not sure", and any group holding a single procedure
          // (Dental cleaning). Tapping the heading selects it.
          if (entry.key.isDirectPick || (fullMenu[entry.key]?.length ?? 0) == 1)
            Builder(builder: (context) {
              final service = directPickService(entry.key, entry.value) ?? entry.value.first;
              return _DirectPickSection(
                group: entry.key,
                isSelected: widget.selected.contains(service),
                onTap: () => _pick(service),
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
              onToggleService: _pick,
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
                      child: Text(
                        group.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
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
/// Used by "Other / Not sure" (a dental checkup) and by any group holding a
/// single procedure, such as Dental cleaning. Only the heading shows; the
/// procedure, chair time and price appear once it is selected.
class _DirectPickSection extends StatelessWidget {
  final ServiceGroup group;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectPickSection({
    required this.group,
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
          child: Text(
            group.label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
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
            ],
          ),
        ),
      ),
    );
  }
}

// --- Step 3: Summary & payment ---

/// How the down payment is paid. Wallet debits the balance directly; GCash
/// and GrabPay go through PayMongo's checkout (see
/// [_BookAppointmentScreenState._payWithPayMongo]).
abstract final class _BookingPaymentMethod {
  static const wallet = 'Wallet';
  static const gcash = 'GCash';
  static const grabPay = 'GrabPay';

  static const all = [wallet, gcash, grabPay];

  /// The PayMongo rail behind [method], or null for the wallet.
  static CashInRail? railFor(String method) {
    final id = switch (method) {
      gcash => 'gcash',
      grabPay => 'grab_pay',
      _ => null,
    };
    if (id == null) return null;
    for (final rail in kCashInRails) {
      if (rail.id == id) return rail;
    }
    return null;
  }
}

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
  final String selectedPaymentMethod;
  final ValueChanged<String> onPaymentMethodSelected;

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
    required this.selectedPaymentMethod,
    required this.onPaymentMethodSelected,
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
        _PaymentOptionList(
          selectedMethod: selectedPaymentMethod,
          onSelected: onPaymentMethodSelected,
          walletBalance: walletBalance,
          downPayment: downPayment,
        ),
        if (selectedPaymentMethod == _BookingPaymentMethod.wallet && !canAffordDownPayment) ...[
          const SizedBox(height: 8),
          Text(
            AppMessages.insufficientBalance,
            style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.error),
          ),
        ],
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
              ? DoctorIcon(size: 19, color: AppColors.primary)
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
                Text(
                  // This is driven by the selected procedure, rather than the
                  // doctor's wider title. A cleaning therefore reads as
                  // "General Dentistry" directly below the doctor's name.
                  _serviceSpecializations,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
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

  String get _serviceSpecializations {
    final labels = <String>{
      for (final service in services) specializationLabelFor(service.specializationCode),
    };
    return labels.join(' • ');
  }
}

/// Wallet, GCash and GrabPay. GCash and GrabPay are paid through PayMongo's
/// own checkout and confirmed by the server before anything is booked.
class _PaymentOptionList extends StatelessWidget {
  final String selectedMethod;
  final ValueChanged<String> onSelected;
  final double walletBalance;
  final double downPayment;

  const _PaymentOptionList({
    required this.selectedMethod,
    required this.onSelected,
    required this.walletBalance,
    required this.downPayment,
  });

  @override
  Widget build(BuildContext context) {
    const methods = _BookingPaymentMethod.all;
    return Column(
      children: [
        for (var i = 0; i < methods.length; i++) ...[
          _PaymentOptionRow(
            method: methods[i],
            subtitle: methods[i] == _BookingPaymentMethod.wallet ? 'Balance ${formatPeso(walletBalance)}' : null,
            logo: _BookingPaymentMethod.railFor(methods[i])?.logo,
            isSelected: selectedMethod == methods[i],
            onTap: () => onSelected(methods[i]),
          ),
          if (i != methods.length - 1) Divider(height: 1, color: AppColors.border),
        ],
      ],
    );
  }
}

class _PaymentOptionRow extends StatelessWidget {
  final String method;

  /// A second line under the name — the wallet's balance. Null for GCash and
  /// GrabPay, which show their name alone.
  final String? subtitle;

  /// The rail's brand mark, or null for the wallet's card icon.
  final String? logo;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentOptionRow({
    required this.method,
    required this.subtitle,
    required this.logo,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      label: method,
      child: Material(
        color: isSelected ? AppColors.primary.withOpacity(0.06) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: logo == null
                      ? Icon(CupertinoIcons.creditcard, size: 20, color: AppColors.primary)
                      : SvgPicture.asset(logo!, height: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isSelected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                  size: 20,
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

/// The Terms and Conditions and the Privacy Policy, opened by PAY before any
/// money moves. Both are shown as one continuous text, Terms first. AGREE &
/// CONTINUE stays locked until the patient has scrolled to the very end, and
/// the screen pops `true` only when they press it.
class BookingTermsScreen extends StatefulWidget {
  const BookingTermsScreen({super.key});

  @override
  State<BookingTermsScreen> createState() => _BookingTermsScreenState();
}

class _BookingTermsScreenState extends State<BookingTermsScreen> {
  static const _documents = [
    'assets/files/TERMS AND CONDITIONS.txt',
    'assets/files/PRIVACY POLICY.txt',
  ];

  final ScrollController _scroll = ScrollController();
  late final Future<List<String>> _text = _load();

  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Both documents as one list of paragraphs, Terms first. Each line of the
  /// files is a paragraph (blank lines only space them), so the title, the
  /// "Last updated" line and every heading stand on their own. The files'
  /// byte-order mark and Windows line endings are dropped.
  static Future<List<String>> _load() async {
    final paragraphs = <String>[];
    for (final path in _documents) {
      final raw = await rootBundle.loadString(path);
      final text = raw.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (paragraphs.isNotEmpty) paragraphs.add(_divider);
      for (final line in text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) paragraphs.add(trimmed);
      }
    }
    return paragraphs;
  }

  static const _divider = '\u0000divider';

  /// Once reached, the end stays reached — scrolling back up to re-read a
  /// clause does not lock the box again.
  void _checkEnd() {
    if (_reachedEnd || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 24) {
      setState(() => _reachedEnd = true);
    }
  }

  /// A line the documents write in capitals ("AGREEMENT TO OUR LEGAL TERMS")
  /// is a heading.
  static bool _isHeading(String paragraph) {
    if (paragraph.length > 90 || paragraph.contains('\n')) return false;
    final letters = paragraph.replaceAll(RegExp(r'[^A-Za-z]'), '');
    return letters.length >= 3 && letters == letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Legal Terms & Privacy Policy'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<String>>(
              future: _text,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'The Terms and Conditions could not be opened. Please try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                final paragraphs = snapshot.data;
                if (paragraphs == null) {
                  return Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                // A text short enough to fit has no bottom to scroll to.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent <= 0) {
                    _checkEnd();
                  }
                });
                return Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: paragraphs.length,
                    itemBuilder: (context, i) => _paragraph(paragraphs[i], isFirst: i == 0),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      // Unlocks once the patient has scrolled to the end.
                      onPressed: _reachedEnd ? () => Navigator.pop(context, true) : null,
                      child: const Text(
                        'AGREE & CONTINUE',
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paragraph(String text, {required bool isFirst}) {
    if (text == _divider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Divider(color: AppColors.border, thickness: 1),
      );
    }
    if (_isHeading(text)) {
      return Padding(
        padding: EdgeInsets.only(top: isFirst ? 0 : 10, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: isFirst ? 17 : 13.5,
            fontWeight: FontWeight.bold,
            height: 1.35,
            color: AppColors.textPrimary,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.textPrimary)),
    );
  }
}

enum _PayMongoOutcome { paid, failed, stillPending }

/// Waits for PayMongo to authorize a GCash/GrabPay payment the patient is
/// completing in their browser or wallet app.
///
/// Reads `wallet_topup_requests` every 3 s — and at once whenever the app
/// comes back to the foreground — and asks `reconcile-topup` to check PayMongo
/// directly on tries 1, 4, 10, 20 and 40, in case the webhook is late. Gives
/// up after 3 minutes, or when the patient closes it; the payment is then
/// still confirmed in the background and lands in the wallet.
class _PayMongoWaitDialog extends StatefulWidget {
  final String requestId;
  final String railLabel;

  const _PayMongoWaitDialog({required this.requestId, required this.railLabel});

  @override
  State<_PayMongoWaitDialog> createState() => _PayMongoWaitDialogState();
}

class _PayMongoWaitDialogState extends State<_PayMongoWaitDialog> with WidgetsBindingObserver {
  static const _maxTries = 60;
  static const _reconcileOn = {1, 4, 10, 20, 40};

  Timer? _timer;
  int _attempt = 0;
  bool _checking = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(const Duration(seconds: 3), _check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || _done || !mounted) return;
    _checking = true;
    _timer?.cancel();
    _attempt++;
    if (_reconcileOn.contains(_attempt)) await WalletTopupApi.reconcile(widget.requestId);

    TopupState? state;
    try {
      state = await WalletTopupApi.fetchState(widget.requestId);
    } catch (_) {
      state = null;
    }
    _checking = false;
    if (!mounted || _done) return;

    switch (state?.status) {
      case 'paid':
        // Settled here, so the Wallet tab does not announce it again.
        await _forgetIfOurs();
        _finish(_PayMongoOutcome.paid);
        return;
      case 'failed':
      case 'expired':
        await _forgetIfOurs();
        _finish(_PayMongoOutcome.failed);
        return;
    }
    if (_attempt >= _maxTries) {
      _finish(_PayMongoOutcome.stillPending);
      return;
    }
    _timer = Timer(const Duration(seconds: 3), _check);
  }

  /// Clears the Wallet tab's remembered top-up only when it is this request,
  /// so a separate cash-in still waiting to be confirmed is left alone.
  Future<void> _forgetIfOurs() async {
    if (await WalletTopupApi.pendingRequestId() == widget.requestId) {
      await WalletTopupApi.savePending(null);
    }
  }

  void _finish(_PayMongoOutcome outcome) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 18),
            Text(
              'Waiting for ${widget.railLabel}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Finish the payment in the PayMongo page, then come back here. '
              'Your appointment is booked as soon as PayMongo confirms it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => _finish(_PayMongoOutcome.stillPending),
            child: const Text('Stop waiting'),
          ),
          TextButton(
            onPressed: _check,
            child: const Text('I have paid'),
          ),
        ],
      ),
    );
  }
}

// Retained as an internal component for any older booking surface that still
// renders the previous card treatment. This booking screen uses the flat list
// above.
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
