import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_calendar.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';

const List<String> _timeSlots = [
  '10:00 AM',
  '11:00 AM',
  '12:00 PM',
  '01:00 PM',
  '02:00 PM',
  '03:00 PM',
  '04:00 PM',
];

/// Moves an existing appointment to a new date/time via
/// [PatientRepository.rescheduleAppointment] instead of booking a new one.
class RescheduleAppointmentScreen extends StatefulWidget {
  final Appointment appointment;

  const RescheduleAppointmentScreen({super.key, required this.appointment});

  @override
  State<RescheduleAppointmentScreen> createState() => _RescheduleAppointmentScreenState();
}

class _RescheduleAppointmentScreenState extends State<RescheduleAppointmentScreen> {
  DateTime? _selectedDate;
  DateTime _focusedDay = DateTime.now();
  String? _selectedTimeSlot;
  bool _isSubmitting = false;
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
    if (_selectedTimeSlot == null) {
      showAppToast(context, 'Please select a new time slot.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    PatientRepository().rescheduleAppointment(
      widget.appointment.id,
      date: _selectedDate!,
      timeSlot: _selectedTimeSlot!,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    setState(() => _isSubmitting = false);
    showAppToast(context, 'Appointment rescheduled.');
    Navigator.pop(context);
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
                          'Currently: ${formatAppointmentDate(widget.appointment.date)} at ${widget.appointment.timeSlot}',
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
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDate = selected;
                        _focusedDay = focused;
                      });
                    },
                    onPageChanged: (focused) => _focusedDay = focused,
                  ),
                  const SizedBox(height: 20),
                  _requiredLabel('New Time Slot'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _timeSlots.map((slot) {
                      final isSelected = _selectedTimeSlot == slot;
                      return ChoiceChip(
                        label: Text(slot),
                        selected: isSelected,
                        showCheckmark: false,
                        selectedColor: const Color(0xFF14B8A6),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: isSelected ? const Color(0xFF14B8A6) : AppColors.border),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        onSelected: (selected) {
                          setState(() {
                            _selectedTimeSlot = selected ? slot : null;
                          });
                        },
                      );
                    }).toList(),
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
