import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

enum _PaymentOption { cash, wallet }

/// Reservation fee charged to the wallet at booking time. Paying it is what
/// lets the clinic confirm the slot straight away instead of holding the
/// request as pending.
const double kDownPayment = 500.0;

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
    final payingFromWallet = _selected == _PaymentOption.wallet;

    // The wallet route charges the down payment up front, so it cannot go
    // ahead on an underfunded wallet.
    if (payingFromWallet && _repository.walletBalance < kDownPayment) {
      showAppToast(
        context,
        'You need at least ₱${kDownPayment.toStringAsFixed(2)} in your wallet for the down payment.',
        isError: true,
      );
      return;
    }

    setState(() => _isConfirming = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    if (payingFromWallet) {
      _repository.addWalletTransaction(
        title: 'Appointment Down Payment',
        subtitle: widget.serviceName,
        amount: kDownPayment,
        type: TransactionType.debit,
        icon: CupertinoIcons.calendar_badge_plus,
        method: 'Wallet',
      );
    }

    // A paid down payment secures the slot, so the booking comes in already
    // confirmed; cash bookings stay pending until the clinic confirms them.
    _repository.addAppointment(
      serviceName: widget.serviceName,
      doctorName: widget.doctorName,
      date: widget.date,
      timeSlot: widget.timeSlot,
      notes: widget.notes,
      paymentMethod: payingFromWallet ? 'Wallet' : 'Cash',
      status: payingFromWallet ? AppointmentStatus.confirmed : AppointmentStatus.pending,
    );

    setState(() => _isConfirming = false);

    showAppToast(
      context,
      payingFromWallet
          ? 'Down payment received — your appointment is confirmed!'
          : 'Appointment requested! The clinic will confirm it shortly.',
    );

    // Pop this payment screen and the booking form beneath it, back to
    // whichever screen (Dashboard or Appointments) started the booking flow.
    Navigator.pop(context);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
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
                    icon: Icons.payments_rounded,
                    title: 'Cash',
                    subtitle: 'Pay in person at the clinic',
                    note: 'No down payment needed. The clinic confirms your booking after review.',
                    noteColor: AppColors.textSecondary,
                    isSelected: _selected == _PaymentOption.cash,
                    onTap: () => setState(() => _selected = _PaymentOption.cash),
                  ),
                  const SizedBox(height: 12),
                  _PaymentOptionTile(
                    icon: CupertinoIcons.creditcard,
                    title: 'Wallet — Down Payment',
                    subtitle: 'Available balance: ₱${_repository.walletBalance.toStringAsFixed(2)}',
                    note: 'A ₱${kDownPayment.toStringAsFixed(2)} down payment is required to confirm. '
                        'Pay it now and your appointment is confirmed automatically.',
                    noteColor: AppColors.primary,
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
                    : Text(
                        _selected == _PaymentOption.wallet
                            ? 'Pay ₱${kDownPayment.toStringAsFixed(2)} & Confirm'
                            : 'Confirm Booking',
                      ),
              ),
            ),
          ),
        ],
      ),
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

  /// Extra line under the option spelling out what it means for confirmation
  /// - e.g. that the wallet route charges a down payment right away.
  final String note;
  final Color noteColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.noteColor,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                      Text(title,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
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
            const SizedBox(height: 10),
            Text(note, style: TextStyle(fontSize: 11.5, height: 1.35, color: noteColor)),
          ],
        ),
      ),
    );
  }
}
