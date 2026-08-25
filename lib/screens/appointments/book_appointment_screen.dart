import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

class BookAppointmentScreen extends StatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  State<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends State<BookAppointmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _downPaymentController = TextEditingController(text: '500');
  final PatientRepository _repository = PatientRepository();

  String _selectedService = 'Oral Prophylaxis (Cleaning)';
  String _selectedDoctor = 'Dr. Rey Vincent Bolasoc';
  DateTime? _selectedDate;
  String? _selectedTimeSlot;
  bool _isSubmitting = false;
  bool _addDownPayment = false;
  String? _downPaymentError;

  final List<String> _services = [
    'Oral Prophylaxis (Cleaning)',
    'Tooth Filling (Composite)',
    'Tooth Extraction',
    'Root Canal Treatment',
    'Orthodonic Consultation (Braces)',
  ];

  final List<String> _doctors = [
    'Dr. Rey Vincent Bolasoc',
    'Dr. Jenneline Mariano',
    'Dr. John Paul Mariano',
  ];

  final List<String> _timeSlots = [
    '09:00 AM',
    '10:30 AM',
    '01:30 PM',
    '03:00 PM',
    '04:30 PM',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    _downPaymentController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
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

    double? downPaymentAmount;
    if (_addDownPayment) {
      downPaymentAmount = double.tryParse(_downPaymentController.text.trim());
      if (downPaymentAmount == null || downPaymentAmount <= 0) {
        setState(() => _downPaymentError = 'Enter a valid amount');
        return;
      }
      if (downPaymentAmount > _repository.walletBalance) {
        setState(() => _downPaymentError = 'Insufficient wallet balance');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _downPaymentError = null;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    if (downPaymentAmount != null) {
      _repository.deductForDownPayment(serviceName: _selectedService, amount: downPaymentAmount);
    }
    _repository.addAppointment(
      serviceName: _selectedService,
      doctorName: _selectedDoctor,
      date: _selectedDate!,
      timeSlot: _selectedTimeSlot!,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    setState(() => _isSubmitting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Appointment scheduled! Check the Upcoming tab.'),
        backgroundColor: AppColors.success,
      ),
    );

    Navigator.pop(context);
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
              // Dental Service Dropdown
              const Text('Select Dental Service', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedService,
                decoration: const InputDecoration(),
                items: _services
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedService = val!),
              ),
              const SizedBox(height: 20),

              // Preferred Doctor Dropdown
              const Text('Preferred Dentist', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedDoctor,
                decoration: const InputDecoration(),
                items: _doctors
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedDoctor = val!),
              ),
              const SizedBox(height: 20),

              // Date Selector - inline calendar
              const Text('Appointment Date', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary),
                  ),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                    onDateChanged: (date) => setState(() => _selectedDate = date),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Time Slot Chips
              const Text('Available Time Slots', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppColors.textPrimary,
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
              const Text('Additional Notes (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Describe any symptoms or specific requests...',
                ),
              ),
              const SizedBox(height: 20),

              // Optional Down Payment
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
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
                              const Text('Add a Down Payment',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(
                                'Wallet Balance: ₱${_repository.walletBalance.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: _addDownPayment,
                          activeTrackColor: AppColors.primary,
                          onChanged: (val) => setState(() {
                            _addDownPayment = val;
                            _downPaymentError = null;
                          }),
                        ),
                      ],
                    ),
                    if (_addDownPayment) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _downPaymentController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          prefixText: '₱ ',
                          labelText: 'Down Payment Amount',
                          errorText: _downPaymentError,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
                child: _isSubmitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text('Confirm Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
