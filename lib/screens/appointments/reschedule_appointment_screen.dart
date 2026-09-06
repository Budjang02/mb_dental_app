import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_calendar.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/models/dental_service.dart';

/// Moves an existing appointment to a new date/time via
/// [PatientRepository.rescheduleAppointment] instead of booking a new one.
class RescheduleAppointmentScreen extends StatefulWidget {
  final Appointment appointment;

  const RescheduleAppointmentScreen({super.key, required this.appointment});

  @override
  State<RescheduleAppointmentScreen> createState() => _RescheduleAppointmentScreenState();
}

class _RescheduleAppointmentScreenState extends State<RescheduleAppointmentScreen> {
  final PatientRepository _repository = PatientRepository();

  DateTime? _selectedDate;
  DateTime _focusedDay = DateTime.now();

  /// Start of the new block, as minutes from midnight.
  int? _selectedStartMinute;
  bool _isSubmitting = false;

  /// The moved appointment keeps its original chair time, so the grid only
  /// offers starts that still fit the same block.
  int get _duration => widget.appointment.durationMinutes;
  late final TextEditingController _notesController =
      TextEditingController(text: widget.appointment.notes ?? '');

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _confirm() async {
    if (_selectedDate == null) {
      showAppToast(context, 'Please select a new date.', isError: true);
      return;
    }
    if (_selectedStartMinute == null) {
      showAppToast(context, 'Please select a new time slot.', isError: true);
      return;
    }

    // The slot may have been taken while this screen was open.
    if (!_repository.isSlotAvailable(
      day: _selectedDate!,
      startMinute: _selectedStartMinute!,
      durationMinutes: _duration,
      excludeAppointmentId: widget.appointment.id,
    )) {
      showAppToast(context, AppMessages.slotUnavailable, isError: true);
      setState(() => _selectedStartMinute = null);
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    _repository.rescheduleAppointment(
      widget.appointment.id,
      date: _selectedDate!,
      timeSlot: formatMinuteOfDay(_selectedStartMinute!),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    setState(() => _isSubmitting = false);
    showAppToast(context, 'Appointment rescheduled.');
    Navigator.pop(context);
  }

  Widget _buildSlotGrid() {
    final slots = _repository.slotOptionsFor(
      day: _selectedDate!,
      durationMinutes: _duration,
      excludeAppointmentId: widget.appointment.id,
    );

    if (slots.every((slot) => !slot.isAvailable)) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'No ${formatDuration(_duration)} block is free on this day. Please choose another date.',
          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textSecondary),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        const gap = 10.0;
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final slot in slots)
              SizedBox(
                width: itemWidth,
                child: Opacity(
                  opacity: slot.isAvailable ? 1 : 0.45,
                  child: Material(
                    color: _selectedStartMinute == slot.startMinute
                        ? AppColors.primary
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: slot.isAvailable
                          ? () => setState(() => _selectedStartMinute =
                              _selectedStartMinute == slot.startMinute ? null : slot.startMinute)
                          : null,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selectedStartMinute == slot.startMinute
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          slot.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            decoration: slot.isAvailable ? null : TextDecoration.lineThrough,
                            color: _selectedStartMinute == slot.startMinute
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                        Text(widget.appointment.serviceName,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('with ${widget.appointment.doctorName}',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text(
                          'Currently: ${formatAppointmentDate(widget.appointment.date)} at ${widget.appointment.timeRangeLabel}',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _requiredLabel('New Date'),
                  const SizedBox(height: 8),
                  AppCalendar(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDate,
                    firstDay: DateTime.now(),
                    lastDay: DateTime.now().add(const Duration(days: 730)),
                    enabledDayPredicate: isClinicOpenOn,
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDate = selected;
                        _focusedDay = focused;
                        _selectedStartMinute = null;
                      });
                    },
                    onPageChanged: (focused) => _focusedDay = focused,
                  ),
                  const SizedBox(height: 20),
                  _requiredLabel('New Time Slot'),
                  const SizedBox(height: 4),
                  Text(
                    _selectedDate == null
                        ? 'Select an open day first. The clinic is open $clinicOperatingDaysLabel, $clinicHoursLabel.'
                        : 'Start times are 15 minutes apart and reserve a ${formatDuration(_duration)} block.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedDate != null) _buildSlotGrid(),
                  const SizedBox(height: 20),
                  Text('Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Add any notes about this reschedule...',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _confirm,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm New Schedule'),
              ),
            ),
          ),
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
        TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
      ],
    ),
  );
}
