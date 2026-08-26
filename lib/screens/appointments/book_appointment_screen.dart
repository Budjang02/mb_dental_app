import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:mb_dental_app/widgets/app_calendar.dart';
import 'payment_method_screen.dart';

const List<String> dentalServices = [
  'Braces / Orthodontics',
  'Crown / Bridge',
  'Dental Checkup',
  'Dental Filling',
  'General Cleaning',
  'Root Canal',
  'Teeth Whitening',
  'Tooth Extraction',
];

/// Placeholder doctor value: the clinic assigns the actual dentist after
/// booking, so the patient no longer picks one up front.
const String unassignedDoctor = 'To be assigned';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  String _selectedService = dentalServices.first;
  DateTime? _selectedDate;
  DateTime _focusedDay = DateTime.now();
  String? _selectedTimeSlot;
  bool _isSubmitting = false;

  static const List<String> _timeSlots = [
    '10:00 AM',
    '11:00 AM',
    '12:00 PM',
    '01:00 PM',
    '02:00 PM',
    '03:00 PM',
    '04:00 PM',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an appointment date.')),
      );
      return;
    }
    if (_selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a time slot.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentMethodScreen(
          serviceName: _selectedService,
          doctorName: unassignedDoctor,
          date: _selectedDate!,
          timeSlot: _selectedTimeSlot!,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Appointment'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dental Service Selector
              Text('Select Dental Service', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedService,
                    isExpanded: true,
                    icon: Icon(CupertinoIcons.chevron_down, color: AppColors.primary, size: 18),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      prefixIcon: Icon(CupertinoIcons.bandage, color: AppColors.primary, size: 20),
                    ),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    dropdownColor: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    items: dentalServices
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedService = val!),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Date Selector - styled calendar
              Text('Appointment Date', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              AppCalendar(
                focusedDay: _focusedDay,
                selectedDay: _selectedDate,
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 90)),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDate = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) => _focusedDay = focused,
              ),
              const SizedBox(height: 20),

              // Time Slot Chips
              Text('Available Time Slots', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _timeSlots.map((slot) {
                  final isSelected = _selectedTimeSlot == slot;
                  return ChoiceChip(
                    label: Text(slot),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
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

              // Notes Input
              Text('Additional Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Describe any symptoms or specific requests...',
                ),
              ),
              const SizedBox(height: 32),

              // Continue Button
              ElevatedButton(
                onPressed: _isSubmitting ? null : _handleContinue,
                child: _isSubmitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text('Continue to Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
