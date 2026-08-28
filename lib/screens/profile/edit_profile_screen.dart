import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final PatientRepository _repository = PatientRepository();

  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _medicalHistoryController;
  late String _gender;
  late DateTime _dateOfBirth;
  String? _bloodType;
  String? _maritalStatus;
  bool _isSaving = false;

  static const List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const List<String> _maritalStatuses = ['Single', 'Married', 'Widowed', 'Divorced'];

  @override
  void initState() {
    super.initState();
    final patient = _repository.patient;
    _firstNameController = TextEditingController(text: patient.firstName);
    _lastNameController = TextEditingController(text: patient.lastName);
    _phoneController = TextEditingController(text: patient.phone);
    _addressController = TextEditingController(text: patient.address ?? '');
    _medicalHistoryController = TextEditingController(text: patient.medicalHistory ?? '');
    _gender = patient.gender;
    _dateOfBirth = patient.dateOfBirth;
    _bloodType = patient.bloodType;
    _maritalStatus = patient.maritalStatus;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _medicalHistoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    _repository.updatePatient(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phone: _phoneController.text.trim(),
      gender: _gender,
      dateOfBirth: _dateOfBirth,
      bloodType: _bloodType,
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      maritalStatus: _maritalStatus,
      medicalHistory: _medicalHistoryController.text.trim().isEmpty ? null : _medicalHistoryController.text.trim(),
    );

    setState(() => _isSaving = false);
    showAppToast(context, 'Profile updated.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'First Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Last Name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                isExpanded: true,
                icon: Icon(CupertinoIcons.chevron_down, color: AppColors.primary, size: 18),
                decoration: InputDecoration(
                  labelText: 'Gender',
                  prefixIcon: Icon(CupertinoIcons.person_2, color: AppColors.primary, size: 20),
                ),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _gender = v!),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDateOfBirth,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Birthdate'),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_dateOfBirth.month}/${_dateOfBirth.day}/${_dateOfBirth.year}',
                        style: TextStyle(color: AppColors.textPrimary),
                      ),
                      Icon(CupertinoIcons.calendar, color: AppColors.primary, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Additional Info (Optional)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _bloodType,
                isExpanded: true,
                icon: Icon(CupertinoIcons.chevron_down, color: AppColors.primary, size: 18),
                decoration: InputDecoration(
                  labelText: 'Blood Type',
                  prefixIcon: Icon(CupertinoIcons.drop, color: AppColors.primary, size: 20),
                ),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                items: _bloodTypes.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) => setState(() => _bloodType = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _maritalStatus,
                isExpanded: true,
                icon: Icon(CupertinoIcons.chevron_down, color: AppColors.primary, size: 18),
                decoration: InputDecoration(
                  labelText: 'Marital Status',
                  prefixIcon: Icon(Icons.diversity_1, color: AppColors.primary, size: 20),
                ),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                items: _maritalStatuses.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _maritalStatus = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Address',
                  prefixIcon: Icon(CupertinoIcons.map_pin_ellipse, color: AppColors.primary, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _medicalHistoryController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Medical History',
                  hintText: 'Allergies, conditions, medications, etc.',
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
