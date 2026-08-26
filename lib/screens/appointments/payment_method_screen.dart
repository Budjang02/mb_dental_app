import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';

enum _PaymentOption { cash, wallet }

class PaymentMethodScreen extends StatefulWidget {
  final String serviceName;
  final String doctorName;
  final DateTime date;
  final String timeSlot;
  final String? notes;

  const PaymentMethodScreen({
    super.key,
    required this.serviceName,
    required this.doctorName,
    required this.date,
    required this.timeSlot,
    this.notes,
  });

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  final PatientRepository _repository = PatientRepository();
  _PaymentOption _selected = _PaymentOption.cash;
  bool _isConfirming = false;

  void _confirm() async {
    setState(() => _isConfirming = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    _repository.addAppointment(
      serviceName: widget.serviceName,
      doctorName: widget.doctorName,
      date: widget.date,
      timeSlot: widget.timeSlot,
      notes: widget.notes,
      paymentMethod: _selected == _PaymentOption.cash ? 'Cash' : 'Wallet',
    );

    setState(() => _isConfirming = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Appointment scheduled! Check the Upcoming tab.'),
        backgroundColor: AppColors.success,
      ),
    );

    // Pop this payment screen and the booking form beneath it, back to
    // whichever screen (Dashboard or Appointments) started the booking flow.
    Navigator.pop(context);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Booking Summary',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
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
                        _summaryRow(CupertinoIcons.bandage, 'Service', widget.serviceName),
                        const SizedBox(height: 12),
                        _summaryRow(CupertinoIcons.calendar, 'Date', formatAppointmentDate(widget.date)),
                        const SizedBox(height: 12),
                        _summaryRow(CupertinoIcons.clock, 'Time', widget.timeSlot),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Payment Option',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _PaymentOptionTile(
                    icon: CupertinoIcons.money_dollar_circle,
                    title: 'Cash',
                    subtitle: 'Pay in person at the clinic',
                    isSelected: _selected == _PaymentOption.cash,
                    onTap: () => setState(() => _selected = _PaymentOption.cash),
                  ),
                  const SizedBox(height: 12),
                  _PaymentOptionTile(
                    icon: CupertinoIcons.creditcard,
                    title: 'Wallet',
                    subtitle: 'Available balance: ₱${_repository.walletBalance.toStringAsFixed(2)}',
                    isSelected: _selected == _PaymentOption.wallet,
                    onTap: () => setState(() => _selected = _PaymentOption.wallet),
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
                onPressed: _isConfirming ? null : _confirm,
                child: _isConfirming
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Confirm Booking'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border, width: isSelected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(
              isSelected ? CupertinoIcons.check_mark_circled_solid : CupertinoIcons.circle,
              color: isSelected ? AppColors.primary : AppColors.border,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
