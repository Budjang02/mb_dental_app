import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import 'package:mb_dental_app/models/wallet_transaction.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';

/// Wallet "Pay / Scan" flow, simulated entirely inside the app.
///
/// The device camera is deliberately never opened: the viewfinder below is a
/// drawn mock with an animated scan line, and tapping Scan resolves a demo
/// clinic payment after a short delay.
///
/// TODO: once a real payments API exists, swap the mock viewfinder for a live
/// QR decoder (e.g. mobile_scanner) wired to the clinic's payment endpoint.
class ScanPayScreen extends StatefulWidget {
  const ScanPayScreen({super.key});

  @override
  State<ScanPayScreen> createState() => _ScanPayScreenState();
}

class _ScanPayScreenState extends State<ScanPayScreen> with SingleTickerProviderStateMixin {
  static const String _merchant = 'Mariano & Bolasoc Dental Center';
  static const double _amount = 350.0;

  late final AnimationController _scanLineController;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    super.dispose();
  }

  /// Simulated recognition — no camera, no permissions, no plugin.
  Future<void> _scan() async {
    setState(() => _isScanning = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _isScanning = false);
    _showRecognizedPaymentSheet();
  }

  void _showRecognizedPaymentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.checkmark_seal_fill, color: AppColors.success, size: 40),
            const SizedBox(height: 12),
            Text('Code Recognized',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Pay to', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Text(_merchant,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Text('₱${_amount.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: AppColors.primary)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    onPressed: () {
                      final repository = PatientRepository();
                      if (repository.walletBalance < _amount) {
                        Navigator.pop(sheetContext);
                        showAppToast(context, 'Insufficient wallet balance.', isError: true);
                        return;
                      }
                      repository.addWalletTransaction(
                        title: _merchant,
                        subtitle: 'QR Payment',
                        amount: _amount,
                        type: TransactionType.debit,
                        icon: CupertinoIcons.qrcode_viewfinder,
                        method: 'Wallet',
                      );
                      Navigator.pop(sheetContext);
                      Navigator.pop(context);
                      showAppToast(context, 'Payment sent.');
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
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
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
              _buildViewfinder(),
              const SizedBox(height: 24),
              Text(
                _isScanning ? 'Reading code…' : 'Line up the QR code within the frame',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Demo mode — this scanner runs inside the app and never opens your camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.35),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 220,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isScanning ? null : _scan,
                  icon: _isScanning
                      ? const SizedBox(
                          height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(CupertinoIcons.qrcode_viewfinder, size: 18),
                  label: Text(_isScanning ? 'Scanning…' : 'Scan Code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mock viewfinder: a framed QR placeholder with a teal line sweeping
  /// across it, so the screen reads as a scanner without any camera feed.
  Widget _buildViewfinder() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: AppColors.primary, width: 2),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: Icon(CupertinoIcons.qrcode, color: Colors.white24, size: 120),
            ),
          ),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AnimatedBuilder(
                animation: _scanLineController,
                builder: (context, child) => Align(
                  alignment: Alignment(0, _scanLineController.value * 2 - 1),
                  child: child,
                ),
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0),
                        AppColors.primary,
                        AppColors.primary.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
