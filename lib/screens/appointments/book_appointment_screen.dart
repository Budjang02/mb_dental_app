import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import 'package:mb_dental_app/widgets/app_calendar.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
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

/// Icon + one-line description shown beside each service in the picker, so the
/// list reads as a menu of treatments instead of a wall of checkboxes.
const Map<String, (IconData, String)> _serviceDetails = {
  'Braces / Orthodontics': (CupertinoIcons.wand_rays, 'Alignment and bite correction'),
  'Crown / Bridge': (CupertinoIcons.rosette, 'Restore or replace a damaged tooth'),
  'Dental Checkup': (CupertinoIcons.search, 'Routine exam and diagnosis'),
  'Dental Filling': (CupertinoIcons.bandage, 'Repair cavities and small chips'),
  'General Cleaning': (CupertinoIcons.sparkles, 'Scaling, polishing, plaque removal'),
  'Root Canal': (CupertinoIcons.bolt, 'Treat infected tooth pulp'),
  'Teeth Whitening': (CupertinoIcons.sun_max, 'Brighten stained or dull teeth'),
  'Tooth Extraction': (CupertinoIcons.scissors, 'Remove a damaged or impacted tooth'),
};

IconData serviceIcon(String service) => _serviceDetails[service]?.$1 ?? CupertinoIcons.bandage;

String serviceDescription(String service) => _serviceDetails[service]?.$2 ?? '';

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

  final Set<String> _selectedServices = {dentalServices.first};
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

  Future<void> _showServicePicker() async {
    final tempSelection = Set<String>.from(_selectedServices);
    var query = '';

    final confirmed = await showAppDialog<bool>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final visible = dentalServices
              .where((s) => s.toLowerCase().contains(query.trim().toLowerCase()))
              .toList();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dental Services',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pick every treatment you need in this visit.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const AppDialogCloseButton(),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  onChanged: (value) => setDialogState(() => query = value),
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search services',
                    hintStyle: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    fillColor: AppColors.background,
                    prefixIcon: Icon(CupertinoIcons.search, size: 18, color: AppColors.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: visible.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: Text(
                          'No service matches "${query.trim()}".',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final service = visible[index];
                          final isChecked = tempSelection.contains(service);
                          return _ServiceOptionTile(
                            service: service,
                            isSelected: isChecked,
                            onTap: () => setDialogState(() {
                              if (isChecked) {
                                tempSelection.remove(service);
                              } else {
                                tempSelection.add(service);
                              }
                            }),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tempSelection.isEmpty
                            ? 'None selected'
                            : '${tempSelection.length} selected',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ),
                    if (tempSelection.isNotEmpty)
                      TextButton(
                        onPressed: () => setDialogState(tempSelection.clear),
                        child: Text('Clear', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(96, 42),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      onPressed: tempSelection.isEmpty ? null : () => Navigator.pop(dialogContext, true),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedServices
          ..clear()
          ..addAll(tempSelection);
      });
    }
  }

  void _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedServices.isEmpty) {
      showAppToast(context, 'Please select at least one dental service.', isError: true);
      return;
    }
    if (_selectedDate == null) {
      showAppToast(context, 'Please select an appointment date.', isError: true);
      return;
    }
    if (_selectedTimeSlot == null) {
      showAppToast(context, 'Please select a time slot.', isError: true);
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
          serviceName: _selectedServices.join(', '),
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
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
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
              // Dental Service Selector — opens a searchable multi-select sheet
              // and previews the picks as chips instead of one truncated line.
              _RequiredLabel('Select Dental Services'),
              const SizedBox(height: 4),
              Text(
                'You can select more than one service.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              _ServiceSelectorField(
                selected: _selectedServices,
                onTap: _showServicePicker,
                onRemove: (service) => setState(() => _selectedServices.remove(service)),
              ),
              const SizedBox(height: 20),

              // Date Selector - styled calendar
              _RequiredLabel('Appointment Date'),
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

              // Time Slot Chips
              _RequiredLabel('Available Time Slots'),
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
      ),
    );
  }
}

/// The form's service field: a tappable card that lists the chosen services as
/// removable chips, so several selections stay readable at a glance.
class _ServiceSelectorField extends StatelessWidget {
  final Set<String> selected;
  final VoidCallback onTap;
  final ValueChanged<String> onRemove;

  const _ServiceSelectorField({
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = selected.isEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isEmpty ? AppColors.border : AppColors.primary.withOpacity(0.4)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.square_list, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isEmpty
                          ? 'Tap to choose services'
                          : '${selected.length} service${selected.length == 1 ? '' : 's'} selected',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_down, color: AppColors.primary, size: 18),
                ],
              ),
              if (!isEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selected
                      .map(
                        (service) => Container(
                          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(serviceIcon(service), size: 13, color: AppColors.primary),
                              const SizedBox(width: 5),
                              Text(
                                service,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => onRemove(service),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Icon(CupertinoIcons.xmark, size: 11, color: AppColors.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row in the service picker: icon, name, description and a check
/// indicator, with the whole row acting as the tap target.
class _ServiceOptionTile extends StatelessWidget {
  final String service;
  final bool isSelected;
  final VoidCallback onTap;

  const _ServiceOptionTile({
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(isSelected ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(serviceIcon(service), size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serviceDescription(service),
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
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

/// A form section label with a red required-field asterisk appended.
class _RequiredLabel extends StatelessWidget {
  final String label;

  const _RequiredLabel(this.label);

  @override
  Widget build(BuildContext context) {
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
}
