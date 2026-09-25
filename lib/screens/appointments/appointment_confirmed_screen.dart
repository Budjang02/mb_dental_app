import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/services/clinic_pdf.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';

import 'appointment_details_screen.dart';
import 'appointments_screen.dart';

/// Shown straight after a booking the server confirmed — the website's
/// booking-confirmed dialog (`js/booking-confirmed.js`), laid out for a phone.
///
/// Everything on it is read back from Supabase for [appointmentId]: the
/// confirmation code the database stamped, the visit, and the payment figures
/// from the appointment and its billing. Opening it creates nothing.
class AppointmentConfirmedScreen extends StatefulWidget {
  final String appointmentId;

  /// Draws this booking and these figures without reading Supabase — for
  /// widget tests only.
  @visibleForTesting
  final Appointment? preview;
  @visibleForTesting
  final AppointmentMoney? previewMoney;

  const AppointmentConfirmedScreen({
    super.key,
    required this.appointmentId,
    this.preview,
    this.previewMoney,
  });

  @override
  State<AppointmentConfirmedScreen> createState() => _AppointmentConfirmedScreenState();
}

class _AppointmentConfirmedScreenState extends State<AppointmentConfirmedScreen> {
  final PatientRepository _repository = PatientRepository();

  Appointment? _appointment;
  AppointmentMoney? _money;
  bool _loading = true;
  bool _failed = false;
  bool _copied = false;
  bool _buildingReceipt = false;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _appointment = widget.preview;
      _money = widget.previewMoney;
      _loading = false;
      return;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final appointment = await _repository.fetchAppointment(widget.appointmentId);
      if (appointment == null) throw StateError('appointment not found');
      final money = await ClinicDocumentsApi.moneyFor(appointment);
      if (!mounted) return;
      setState(() {
        _appointment = appointment;
        _money = money;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Loading the confirmed booking failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    showAppToast(context, 'Confirmation code copied');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// The deposit receipt for this booking, drawn from its saved records by
  /// the same loader the details page uses.
  Future<void> _downloadReceipt(Appointment appointment) async {
    if (_buildingReceipt) return;
    setState(() => _buildingReceipt = true);
    ClinicPdfSpec? spec;
    Uint8List? bytes;
    try {
      spec = await ClinicDocumentsApi.depositReceiptSpec(appointment);
      if (spec != null) bytes = await renderClinicPdf(spec);
    } catch (e) {
      debugPrint('Deposit receipt failed: $e');
      if (mounted) {
        showAppToast(
          context,
          e is DocumentAccessException ? e.message : 'Could not download the deposit receipt. Please try again.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _buildingReceipt = false);
    }
    if (!mounted) return;
    if (spec == null || bytes == null) {
      showAppToast(context, 'The deposit receipt is not available yet. Please try again in a moment.', isError: true);
      return;
    }
    final document = spec;
    final pdf = bytes;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ClinicDocumentPreview(title: document.title, bytes: pdf, fileName: document.fileName),
      ),
    );
  }

  void _viewAppointments() {
    // In place of this screen, so Back from the list does not return here.
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppointmentsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Booking Complete'),
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    final appointment = _appointment;
    if (_loading && appointment == null) {
      return Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (appointment == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.checkmark_seal, size: 40, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                'Your appointment is booked.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _failed
                    ? 'We could not load its details just now. You can see it under My Appointments.'
                    : 'You can see it under My Appointments.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              if (_failed) TextButton(onPressed: _load, child: const Text('Try Again')),
              ElevatedButton(onPressed: _viewAppointments, child: const Text('View My Appointments')),
            ],
          ),
        ),
      );
    }

    final money = _money ?? AppointmentMoney.fromAppointment(appointment);
    final code = appointment.confirmationCode?.trim() ?? '';
    final confirmed = appointment.status == AppointmentStatus.confirmed;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.14), shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 38, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          confirmed ? 'Appointment Confirmed!' : 'Appointment Requested',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          confirmed
              ? 'Your slot has been reserved successfully.'
              : 'The clinic will confirm your appointment shortly.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 22),

        // Code box: small muted label over the code, Copy to its right.
        if (code.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.35)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONFIRMATION CODE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          code,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _copy(code),
                  icon: Icon(_copied ? CupertinoIcons.checkmark_alt : CupertinoIcons.doc_on_doc, size: 15),
                  label: Text(_copied ? 'Copied!' : 'Copy', style: const TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // The visit, then — under a divider in the same card — the money.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _Row('Service', appointment.serviceName),
              _Row('Dentist', doctorLabel(appointment.doctorName)),
              _Row('Date & Time', '${formatAppointmentDate(appointment.date)}, ${appointment.timeRangeLabel}'),
              Divider(color: AppColors.border, height: 18),
              _Row('Total Estimated Cost', money.priceMin > 0 ? pesoRange(money.priceMin, money.priceMax) : '—'),
              _Row(
                'Down Payment Paid',
                money.paid ? formatPeso(money.down) : '${formatPeso(money.down)} (not yet paid)',
                valueColor: money.paid ? AppColors.success : null,
              ),
              _Row('Payment Method', paymentMethodLabel(money.method, paid: money.paid)),
              _Row(
                'Estimated Balance Due at Clinic',
                pesoRange(money.balanceMin, money.balanceMax),
                valueColor: AppColors.primary,
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // The clinic's late-arrival policy, as the website states it.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(CupertinoIcons.clock, size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A strict 10-minute grace period applies. Arriving late results in automatic '
                  'cancellation and deposit forfeiture.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        if (money.paid) ...[
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _buildingReceipt ? null : () => _downloadReceipt(appointment),
              icon: _buildingReceipt
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.arrow_down_to_line, size: 17),
              label: const Text('Download Deposit Receipt', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: _viewAppointments,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('View My Appointments', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool strong;

  const _Row(this.label, this.value, {this.valueColor, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: strong ? 15 : 13.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
