import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../app/theme.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

/// Opens the device camera to capture a payment QR code.
///
/// TODO: once a real payments API exists, replace the ImagePicker capture +
/// simulated recognition below with a live QR decoder (e.g. mobile_scanner)
/// wired to the clinic's payment endpoint.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  bool _isProcessing = false;

  Future<void> _openCameraAndScan() async {
    setState(() => _isProcessing = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 60);
      if (!mounted) return;
      setState(() => _isProcessing = false);
      if (photo == null) return;
      _showRecognizedPaymentSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera unavailable: $e')),
      );
    }
  }

  void _showRecognizedPaymentSheet() {
    const merchant = 'Mariano & Bolasoc Dental Center';
    const amount = 350.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.checkmark_seal_fill, color: AppColors.success, size: 40),
            const SizedBox(height: 12),
            const Text('Code Recognized', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Pay to', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const Text(merchant,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            const Text('₱350.00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: AppColors.primary)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: () {
                      final repository = PatientRepository();
                      if (repository.walletBalance < amount) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Insufficient wallet balance.')),
                        );
                        return;
                      }
                      repository.addWalletTransaction(
                        title: merchant,
                        subtitle: 'QR Payment',
                        amount: amount,
                        type: TransactionType.debit,
                        icon: CupertinoIcons.qrcode_viewfinder,
                        method: 'Wallet',
                      );
                      Navigator.pop(context);
                      Navigator.pop(this.context);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Payment sent.'), backgroundColor: AppColors.success),
                      );
                    },
                    child: const Text('Confirm Payment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan to Pay'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(CupertinoIcons.qrcode_viewfinder, color: Colors.white54, size: 90),
            ),
            const SizedBox(height: 24),
            const Text(
              'Line up the QR code within the frame',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 220,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isProcessing ? null : _openCameraAndScan,
                icon: _isProcessing
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(CupertinoIcons.camera_fill, size: 18),
                label: const Text('Open Camera'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
