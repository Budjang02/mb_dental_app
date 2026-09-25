import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/dental_service.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/repositories/load_state.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/reschedule_appointment_screen.dart';
import 'package:mb_dental_app/services/clinic_pdf.dart';
import 'package:mb_dental_app/services/supabase_service.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/check_in_qr.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/widgets/section_states.dart';
import 'package:mb_dental_app/widgets/skeleton.dart';

/// Opens the full details page for [appointment]. The cached copy is shown at
/// once while a fresh read from Supabase replaces it.
void openAppointmentDetails(BuildContext context, Appointment appointment) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AppointmentDetailsPage(appointmentId: appointment.id, initial: appointment),
    ),
  );
}

/// One appointment on a page of its own, laid out like the web portal's
/// details view: status, confirmation code and check-in QR, the visit itself,
/// what has been paid, and why it was cancelled when it was.
class AppointmentDetailsPage extends StatefulWidget {
  /// The appointment's id or its confirmation code.
  final String appointmentId;

  /// Already-loaded copy to draw while the fresh read is out, so opening the
  /// page from a list never flashes a skeleton.
  final Appointment? initial;

  const AppointmentDetailsPage({super.key, required this.appointmentId, this.initial});

  @override
  State<AppointmentDetailsPage> createState() => _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> {
  final PatientRepository _repository = PatientRepository();

  /// Wraps the QR card so "Save QR Image" captures exactly what is on screen.
  final GlobalKey _qrBoundaryKey = GlobalKey();

  Appointment? _appointment;
  SectionStatus _status = SectionStatus.loading;
  bool _notFound = false;
  bool _isSavingQr = false;

  /// Which document is being drawn — 'deposit', 'receipt' or 'invoice' — so
  /// its button shows a spinner and the others stay usable.
  String? _buildingDocument;

  /// The invoice and receipt on file for a completed visit, looked up from
  /// its billing records. Null until looked up.
  AppointmentDocuments? _documents;
  bool _documentsFailed = false;
  String? _documentsFor;

  /// The payment figures, read from the appointment and its bill the way the
  /// website reads them. Null until loaded; the row copy stands in meanwhile.
  AppointmentMoney? _money;

  Future<void> _loadMoney() async {
    final appointment = _appointment;
    if (appointment == null) return;
    try {
      final money = await ClinicDocumentsApi.moneyFor(appointment);
      if (!mounted || _appointment?.id != appointment.id) return;
      setState(() => _money = money);
    } catch (e) {
      debugPrint('Payment figures failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _appointment = widget.initial ?? _cached(widget.appointmentId);
    _repository.addListener(_onRepositoryChanged);
    _fetch();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  Appointment? _cached(String idOrCode) {
    for (final a in _repository.appointments) {
      if (a.id == idOrCode || a.confirmationCode == idOrCode) return a;
    }
    return null;
  }

  /// A cancel or reschedule made from this page updates the repository's copy;
  /// following it keeps the page in step without a second round trip.
  void _onRepositoryChanged() {
    final current = _appointment;
    if (current == null) return;
    final updated = _cached(current.id);
    if (updated != null && !identical(updated, current)) {
      setState(() => _appointment = updated);
      _loadDocumentsIfCompleted();
      _loadMoney();
    }
  }

  /// A completed visit's invoice and receipt are looked up once per
  /// appointment (and again on pull-to-refresh); nothing is created.
  Future<void> _loadDocumentsIfCompleted({bool force = false}) async {
    final appointment = _appointment;
    if (appointment == null || appointment.status != AppointmentStatus.completed) return;
    if (!force && _documentsFor == appointment.id) return;
    _documentsFor = appointment.id;
    setState(() {
      _documents = null;
      _documentsFailed = false;
    });
    try {
      final found = await ClinicDocumentsApi.findForAppointment(appointment.id);
      if (!mounted || _documentsFor != appointment.id) return;
      setState(() => _documents = found);
    } catch (e) {
      debugPrint('Looking up appointment documents failed: $e');
      if (!mounted || _documentsFor != appointment.id) return;
      setState(() {
        _documents = AppointmentDocuments.none;
        _documentsFailed = true;
      });
    }
  }

  Future<void> _fetch() async {
    setState(() => _status = SectionStatus.loading);
    try {
      final fresh = await _repository.fetchAppointment(widget.appointmentId);
      if (!mounted) return;
      setState(() {
        _notFound = fresh == null;
        if (fresh != null) _appointment = fresh;
        _status = SectionStatus.ready;
      });
      await Future.wait([_loadDocumentsIfCompleted(force: true), _loadMoney()]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = classifyFailure(e, context: 'appointment'));
    }
  }

  // ---------------------------------------------------------------------------
  // Actions

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showAppToast(context, 'Confirmation code copied');
  }

  Future<void> _saveQrImage(Appointment appointment) async {
    if (_isSavingQr) return;
    setState(() => _isSavingQr = true);
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('QR code is not on screen');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('QR code could not be encoded');

      final fileName = 'appointment-qr-${_fileSafe(appointment.checkInPayload)}.png';
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: fileName)],
          fileNameOverrides: [fileName],
          subject: 'Appointment check-in QR code',
        ),
      );
    } catch (e) {
      debugPrint('Saving QR image failed: $e');
      if (mounted) showAppToast(context, 'We could not save the QR image. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingQr = false);
    }
  }

  /// Draws one of the visit's documents — the Deposit Receipt, or a
  /// completed visit's Payment Receipt or Invoice — from its saved records
  /// and opens it in [ClinicDocumentPreview]. Read-only: the documents are
  /// redrawn from what the clinic issued, never issued again.
  Future<void> _openDocument(Appointment appointment, String kind) async {
    if (_buildingDocument != null) return;
    setState(() => _buildingDocument = kind);
    final label = switch (kind) {
      'invoice' => 'invoice',
      'receipt' => 'receipt',
      _ => 'deposit receipt',
    };
    ClinicPdfSpec? spec;
    Uint8List? bytes;
    try {
      spec = switch (kind) {
        'invoice' => _documents?.invoiceId == null ? null : await ClinicDocumentsApi.invoiceSpec(_documents!.invoiceId!),
        'receipt' =>
          _documents?.receiptId == null ? null : await ClinicDocumentsApi.paymentReceiptSpec(_documents!.receiptId!),
        _ => await ClinicDocumentsApi.depositReceiptSpec(appointment),
      };
      if (spec != null) bytes = await renderClinicPdf(spec);
    } catch (e) {
      debugPrint('Building $label failed: $e');
      if (mounted) {
        showAppToast(
          context,
          e is DocumentAccessException ? e.message : 'Could not download the $label. Please try again.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _buildingDocument = null);
    }
    if (!mounted) return;
    if (spec == null || bytes == null) {
      showAppToast(context, 'That $label could not be found.', isError: true);
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

  void _reschedule(Appointment appointment) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RescheduleAppointmentScreen(appointment: appointment)));
  }

  static String _fileSafe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Appointment Details'),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    final appointment = _appointment;

    if (appointment == null) {
      if (_status.isLoading) return const _DetailsSkeleton();
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (_notFound)
              const SectionEmptyState(
                icon: CupertinoIcons.calendar_badge_minus,
                title: 'Appointment not found',
                detail: 'This appointment does not exist or is no longer on your account.',
              )
            else
              SectionErrorNotice(status: _status, onRetry: _fetch, isRetrying: _status.isLoading),
          ],
        ),
      );
    }

    final isUpcoming =
        appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed;
    // The reason saved on the row by the patient, the clinic or the system —
    // or, when none was saved, the website's reading of who cancelled.
    final reason = appointment.cancellationReasonLabel(myUserId: SupabaseService.currentUserId);
    final notes = appointment.notes?.trim() ?? '';
    final canChange = canPatientChange(appointment);
    final canMove = canRescheduleOnline(appointment);
    final money = _money ?? AppointmentMoney.fromAppointment(appointment);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetch,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // A failed refresh keeps the copy already on screen and says so.
          if (_status.hasFailed) ...[SectionErrorLine(status: _status, onRetry: _fetch), const SizedBox(height: 12)],
          if (_notFound) ...[
            const _Banner(
              color: AppColors.warning,
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'No longer available',
              message: 'The clinic may have removed this appointment. Showing the last copy saved on this device.',
            ),
            const SizedBox(height: 12),
          ],

          _ConfirmationCard(
            appointment: appointment,
            isUpcoming: isUpcoming,
            qrBoundaryKey: _qrBoundaryKey,
            isSavingQr: _isSavingQr,
            onCopy: _copyCode,
            onSaveQr: () => _saveQrImage(appointment),
          ),
          const SizedBox(height: 20),

          _KeyValueRow(
            label: 'Status',
            value: statusLabel(appointment.status),
            trailing: _StatusBadge(status: appointment.status),
          ),
          const _RowDivider(),
          if (reason != null) ...[
            _KeyValueRow(label: 'Cancellation Reason', value: reason, valueColor: AppColors.error),
            const _RowDivider(),
          ],
          _KeyValueRow(label: 'Date', value: formatAppointmentDate(appointment.date)),
          const _RowDivider(),
          _KeyValueRow(
            label: 'Time',
            value: '${appointment.timeRangeLabel} (${formatDuration(appointment.durationMinutes)})',
          ),
          const _RowDivider(),
          _KeyValueRow(label: 'Dentist', value: doctorLabel(appointment.doctorName)),
          const _RowDivider(),
          _KeyValueRow(label: 'Service', value: appointment.serviceName),
          const SizedBox(height: 20),

          _PaymentSummaryCard(
            appointment: appointment,
            money: money,
            documents: _documents,
            documentsFailed: _documentsFailed,
            buildingDocument: _buildingDocument,
            onOpenDocument: (kind) => _openDocument(appointment, kind),
          ),

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Banner(color: AppColors.primary, icon: CupertinoIcons.doc_text, title: 'Note', message: notes),
          ],

          // Scheduled or Confirmed, and not in the past — the website's rule.
          // Rescheduling closes on the appointment's own day; Cancel stays.
          if (canChange) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Reschedule',
                    color: AppColors.primary,
                    onPressed: canMove ? () => _reschedule(appointment) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Cancel',
                    color: AppColors.error,
                    onPressed: () => confirmCancelAppointment(context, appointment),
                  ),
                ),
              ],
            ),
            if (!canMove) ...[
              const SizedBox(height: 8),
              Text(
                kSameDayRescheduleMessage,
                style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
              ),
            ],
            if (money.down > 0) ...[
              const SizedBox(height: 10),
              Text(
                'Rescheduling deducts a $kRescheduleFeePercent% administrative fee from your deposit. '
                'Cancelling forfeits the 20% down payment.',
                style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sections

class _StatusBadge extends StatelessWidget {
  final AppointmentStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

/// The check-in QR first, then the confirmation code under it, then the
/// arrival instruction while the visit is still ahead.
class _ConfirmationCard extends StatelessWidget {
  final Appointment appointment;

  /// Shows the "show this at the clinic" instruction. The QR itself is always
  /// drawn, so a past visit can still be looked up by the front desk.
  final bool isUpcoming;
  final GlobalKey qrBoundaryKey;
  final bool isSavingQr;
  final ValueChanged<String> onCopy;
  final VoidCallback onSaveQr;

  const _ConfirmationCard({
    required this.appointment,
    required this.isUpcoming,
    required this.qrBoundaryKey,
    required this.isSavingQr,
    required this.onCopy,
    required this.onSaveQr,
  });

  @override
  Widget build(BuildContext context) {
    final code = appointment.confirmationCode?.trim() ?? '';
    final qrPayload = appointment.checkInQrPayload;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (qrPayload != null) ...[
            // The website's verification link (/verify/?t=<qr_token>), at
            // level M with the standard quiet zone. Dark on white in either
            // theme, so it scans and saves the same everywhere. Keyed by the
            // token so a different appointment always redraws.
            RepaintBoundary(
              key: qrBoundaryKey,
              child: AppointmentQr(key: ValueKey(appointment.qrToken), qrToken: appointment.qrToken!),
            ),
            TextButton.icon(
              onPressed: isSavingQr ? null : onSaveQr,
              icon: isSavingQr
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.arrow_down_to_line, size: 15),
              label: const Text('Save QR Image', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                code.isEmpty
                    ? 'Your check-in QR code appears here once the clinic issues your confirmation code.'
                    : 'Your check-in QR code is not ready yet. Pull down to refresh, or give your '
                        'confirmation code at the front desk.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 6),
          const _RowDivider(),
          const SizedBox(height: 14),
          const _Eyebrow('Confirmation Code'),
          const SizedBox(height: 6),
          if (code.isEmpty)
            Text('Not issued yet', style: TextStyle(fontSize: 15, color: AppColors.textSecondary))
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: () => onCopy(code),
                    icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                    label: const Text('Copy', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          if (isUpcoming && qrPayload != null) ...[
            const SizedBox(height: 12),
            Text(
              'Show this QR code to clinic staff upon arrival for instant check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  final Appointment appointment;

  /// The payment figures, worked out as the website's details dialog does.
  final AppointmentMoney money;

  /// A completed visit's invoice and receipt on file; null while looking.
  final AppointmentDocuments? documents;
  final bool documentsFailed;
  final String? buildingDocument;
  final ValueChanged<String> onOpenDocument;

  const _PaymentSummaryCard({
    required this.appointment,
    required this.money,
    required this.documents,
    required this.documentsFailed,
    required this.buildingDocument,
    required this.onOpenDocument,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = appointment.status == AppointmentStatus.completed;
    // Only a down payment the server recorded as paid earns a deposit receipt.
    final hasVerifiedDeposit = money.paid;
    final downText = money.paid
        ? formatPeso(money.down)
        : money.down > 0
            ? '${formatPeso(money.down)} (not yet paid)'
            : formatPeso(0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('Payment Summary'),
          const SizedBox(height: 4),
          _KeyValueRow(label: 'Payment Method', value: paymentMethodLabel(money.method, paid: money.paid)),
          const _RowDivider(),
          _KeyValueRow(
            label: 'Service Price',
            value: money.priceMin > 0 ? pesoRange(money.priceMin, money.priceMax) : '—',
          ),
          const _RowDivider(),
          _KeyValueRow(
            label: 'Down Payment',
            value: downText,
            valueColor: money.paid ? AppColors.success : null,
          ),
          if (money.feeTotal > 0) ...[
            const _RowDivider(),
            _KeyValueRow(label: 'Reschedule Fees', value: '-${formatPeso(money.feeTotal)}', valueColor: AppColors.error),
            const _RowDivider(),
            _KeyValueRow(label: 'Deposit Credited to Final Bill', value: formatPeso(money.credited)),
          ],
          if (money.priceMin > 0) ...[
            const _RowDivider(),
            _KeyValueRow(
              label: money.billed ? 'Balance Due at Clinic' : 'Estimated Balance Due at Clinic',
              value: pesoRange(money.balanceMin, money.balanceMax),
              valueColor: AppColors.primary,
              emphasize: true,
            ),
          ],
          if (isCompleted) ...[
            const _RowDivider(),
            const SizedBox(height: 12),
            _completedDocuments(),
            const SizedBox(height: 8),
          ] else if (hasVerifiedDeposit) ...[
            const _RowDivider(),
            const SizedBox(height: 12),
            // Full width, outlined in teal: the same button as the completed
            // visit's receipt and invoice.
            SizedBox(
              width: double.infinity,
              child: _DocumentButton(
                label: 'Download Deposit Receipt',
                icon: CupertinoIcons.arrow_down_to_line,
                busy: buildingDocument == 'deposit',
                onPressed: buildingDocument == null ? () => onOpenDocument('deposit') : null,
              ),
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Download Receipt and Download Invoice, side by side. A button is live
  /// only once the clinic has issued that document.
  Widget _completedDocuments() {
    final looking = documents == null;
    final hasReceipt = documents?.receiptId != null;
    final hasInvoice = documents?.invoiceId != null;

    String? note;
    if (documentsFailed) {
      note = 'We could not check your receipt and invoice. Pull down to try again.';
    } else if (!looking && !hasReceipt && !hasInvoice) {
      note = 'Your receipt and invoice will be available here once the clinic issues them.';
    } else if (!looking && !hasReceipt) {
      note = 'Your receipt will be available here once the clinic records your payment.';
    } else if (!looking && !hasInvoice) {
      note = 'Your invoice will be available here once the clinic issues it.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _DocumentButton(
                label: 'Download Receipt',
                icon: CupertinoIcons.doc_text,
                busy: looking || buildingDocument == 'receipt',
                onPressed: hasReceipt && buildingDocument == null ? () => onOpenDocument('receipt') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DocumentButton(
                label: 'Download Invoice',
                icon: CupertinoIcons.doc_plaintext,
                busy: looking || buildingDocument == 'invoice',
                onPressed: hasInvoice && buildingDocument == null ? () => onOpenDocument('invoice') : null,
              ),
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.textSecondary)),
        ],
      ],
    );
  }
}

/// A full-width outlined download button, as on the website's details view.
class _DocumentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  const _DocumentButton({required this.label, required this.icon, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textSecondary,
          side: BorderSide(color: onPressed == null || busy ? AppColors.border : AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

/// Full-screen preview of a clinic document — Deposit Receipt, Payment
/// Receipt or Invoice — with its own save and close actions, so the patient
/// sees the document before keeping it.
class ClinicDocumentPreview extends StatelessWidget {
  final String title;
  final Uint8List bytes;
  final String fileName;

  const ClinicDocumentPreview({super.key, required this.title, required this.bytes, required this.fileName});

  Future<void> _save(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (e) {
      debugPrint('Saving $title failed: $e');
      if (context.mounted) {
        showAppToast(context, 'We could not save the ${title.toLowerCase()}. Please try again.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(title),
        actions: [
          TextButton.icon(
            onPressed: () => _save(context),
            icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 17),
            label: const Text('Save to Device', style: TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(CupertinoIcons.xmark),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: fileName,
      ),
    );
  }
}

/// How the website names a payment method (`PAD_METHOD_LABEL`): the wallet
/// is "E-Wallet", and cash not yet paid is "Cash (pay at clinic)".
String paymentMethodLabel(String method, {required bool paid}) {
  const labels = {'Wallet': 'E-Wallet', 'GCash': 'GCash', 'GrabPay': 'GrabPay', 'Maya': 'Maya', 'Cash': 'Cash', 'Card': 'Card'};
  final m = method.trim();
  if (m.isEmpty) return '—';
  final label = labels[m] ?? m;
  return m == 'Cash' && !paid ? '$label (pay at clinic)' : label;
}

/// `₱500.00`, or `₱500.00 – ₱800.00` when the rate card gives a range.
String pesoRange(double min, double max) =>
    max > min ? '${formatPeso(min)} – ${formatPeso(max)}' : formatPeso(min);

// -----------------------------------------------------------------------------
// Building blocks

/// Small uppercase section label, muted, like the web portal's.
class _Eyebrow extends StatelessWidget {
  final String text;

  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.textSecondary),
    );
  }
}

/// Label on the left, value on the right, no icons.
class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasize;

  /// Drawn in place of the plain [value] text, e.g. the status badge.
  final Widget? trailing;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasize = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: trailing != null
                ? Align(alignment: Alignment.centerRight, child: trailing)
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: emphasize ? 16 : 14,
                      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                      color: valueColor ?? AppColors.textPrimary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Divider(height: 1, thickness: 1, color: AppColors.border);
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String message;

  const _Banner({required this.color, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 3),
                Text(message, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  /// Null draws the button disabled.
  final VoidCallback? onPressed;

  const _ActionButton({required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: onPressed == null ? AppColors.border : color),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: const [
          SkeletonBox(height: 190, radius: 16),
          SizedBox(height: 24),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 24),
          SkeletonBox(height: 170, radius: 16),
        ],
      ),
    );
  }
}
