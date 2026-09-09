import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/schedule_picker.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';

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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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
                  _requiredLabel('New Date & Time'),
                  const SizedBox(height: 8),
                  SchedulePicker(
                    durationMinutes: _duration,
                    selectedDate: _selectedDate,
                    selectedStartMinute: _selectedStartMinute,
                    firstDay: today,
                    lastDay: today.add(const Duration(days: 730)),
                    // The appointment being moved must not block itself.
                    hasOpenSlot: (day) => _repository.hasOpenSlotOn(
                      day: day,
                      durationMinutes: _duration,
                      excludeAppointmentId: widget.appointment.id,
                    ),
                    slotsFor: (day) => _repository.slotOptionsFor(
                      day: day,
                      durationMinutes: _duration,
                      excludeAppointmentId: widget.appointment.id,
                    ),
                    onDateSelected: (day) => setState(() {
                      _selectedDate = day;
                      _selectedStartMinute = null;
                    }),
                    onSlotSelected: (minute) => setState(() => _selectedStartMinute = minute),
                  ),
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
                      : const Text('Confirm New Schedule'),
                ),
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
        const TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
      ],
    ),
  );
}
