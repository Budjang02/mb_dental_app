import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/appointment.dart';
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

/// The website's peso format (`_padPeso`): no `.00` on a whole amount,
/// two decimals when there are centavos — `₱500`, `₱1,250.50`.
String padPeso(double v) {
  final whole = v == v.roundToDouble();
  final fixed = v.abs().toStringAsFixed(whole ? 0 : 2);
  final parts = fixed.split('.');
  final digits = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return '${v < 0 ? '-' : ''}₱$b${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// `₱500`, or `₱500 – ₱800` when the rate card gives a range (`_padRange`).
String pesoRange(double min, double max) {
  final lo = min < 0 ? 0.0 : min;
  final hi = max > lo ? max : lo;
  return hi > lo ? '${padPeso(lo)} – ${padPeso(hi)}' : padPeso(lo);
}

/// The website's appointment-detail colours, light and dark.
class _Tone {
  final bool dark = ThemeController().isDark;
  Color get background => dark ? const Color(0xFF0F172A) : Colors.white;
  Color get text => dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get label => dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get divider => dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  Color get qrSurface => dark ? const Color(0x991E293B) : const Color(0xFFF8FAFC);
  Color get buttonBorder => dark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get docText => dark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
  Color get downPayment => dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
  Color get balance => dark ? Colors.white : const Color(0xFF0F172A);
  static const red = Color(0xFFDC2626);
}

/// One appointment on a page of its own, laid out like the website's
/// details view: QR and confirmation code, Appointment Information, Payment
/// Summary, its documents, then Reschedule and Cancel when allowed.
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

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> with WidgetsBindingObserver {
  final PatientRepository _repository = PatientRepository();

  /// Wraps the QR so "Save QR Image" captures it with its white margin.
  final GlobalKey _qrBoundaryKey = GlobalKey();

  Appointment? _appointment;
  SectionStatus _status = SectionStatus.loading;
  bool _notFound = false;
  bool _isSavingQr = false;
  bool _copied = false;
  Timer? _copiedTimer;

  /// Which document is being drawn — 'deposit', 'receipt' or 'invoice'.
  String? _buildingDocument;

  /// The issued invoice and receipt for the visit. Null while checking.
  AppointmentDocuments? _documents;
  bool _documentsFailed = false;
  String? _documentsFor;

  /// The payment figures, read the way the website reads them.
  AppointmentMoney? _money;

  /// Bumped per fetch, so a slow answer for an earlier request (or another
  /// appointment) never replaces what is on screen.
  int _fetchSeq = 0;

  @override
  void initState() {
    super.initState();
    _appointment = widget.initial ?? _cached(widget.appointmentId);
    _repository.addListener(_onRepositoryChanged);
    WidgetsBinding.instance.addObserver(this);
    _fetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _repository.removeListener(_onRepositoryChanged);
    _copiedTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _fetch(quiet: true);
  }

  Appointment? _cached(String idOrCode) {
    for (final a in _repository.appointments) {
      if (a.id == idOrCode || a.confirmationCode == idOrCode) return a;
    }
    return null;
  }

  /// A realtime change, a payment, a cancel or a reschedule updates the
  /// repository's copy; following it keeps the page in step.
  void _onRepositoryChanged() {
    final current = _appointment;
    if (current == null) return;
    final updated = _cached(current.id);
    if (updated != null && !identical(updated, current)) {
      setState(() => _appointment = updated);
      _loadDocuments(force: true);
      _loadMoney();
    }
  }

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

  /// Confirmed and completed visits look up their issued invoice (and
  /// receipt); nothing is created.
  Future<void> _loadDocuments({bool force = false}) async {
    final appointment = _appointment;
    if (appointment == null) return;
    final wanted = appointment.status == AppointmentStatus.completed || appointment.status == AppointmentStatus.confirmed;
    if (!wanted) return;
    if (!force && _documentsFor == appointment.id && _documents != null && !_documentsFailed) return;
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

  Future<void> _fetch({bool quiet = false}) async {
    final seq = ++_fetchSeq;
    if (!quiet) setState(() => _status = SectionStatus.loading);
    try {
      final fresh = await _repository.fetchAppointment(widget.appointmentId);
      if (!mounted || seq != _fetchSeq) return;
      setState(() {
        _notFound = fresh == null;
        if (fresh != null) _appointment = fresh;
        _status = SectionStatus.ready;
      });
      await Future.wait([_loadDocuments(force: true), _loadMoney()]);
    } catch (e) {
      if (!mounted || seq != _fetchSeq) return;
      setState(() => _status = classifyFailure(e, context: 'appointment'));
    }
  }

  // ---------------------------------------------------------------------------
  // Actions

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _saveQrImage(Appointment appointment) async {
    if (_isSavingQr) return;
    setState(() => _isSavingQr = true);
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('QR code is not on screen');
      final image = await boundary.toImage(pixelRatio: 4);
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

  void _enlargeQr(String payload) {
    showDialog<void>(
      context: context,
      builder: (dialog) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialog),
                  icon: const Icon(TablerIcons.x, size: 20, color: Color(0xFF0F172A)),
                ),
              ),
              LayoutBuilder(
                builder: (context, box) => CheckInQr(payload: payload, size: box.maxWidth.clamp(0, 360) - 8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Draws one of the visit's documents from its saved records and opens it
  /// in [ClinicDocumentPreview]. Read-only: redrawn, never issued again.
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

  Future<void> _reschedule(Appointment appointment) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RescheduleAppointmentScreen(appointment: appointment)));
    if (mounted) _fetch(quiet: true);
  }

  static String _fileSafe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  // ---------------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) {
        final tone = _Tone();
        return Scaffold(
          backgroundColor: tone.background,
          appBar: AppBar(
            backgroundColor: tone.background,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Appointment Details'),
          ),
          body: SafeArea(top: false, child: _buildBody(tone)),
        );
      },
    );
  }

  Widget _buildBody(_Tone tone) {
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

    final money = _money ?? AppointmentMoney.fromAppointment(appointment);
    final qr = _QrCard(
      appointment: appointment,
      tone: tone,
      boundaryKey: _qrBoundaryKey,
      saving: _isSavingQr,
      copied: _copied,
      onCopy: _copyCode,
      onSave: () => _saveQrImage(appointment),
      onEnlarge: _enlargeQr,
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoSection(appointment: appointment, tone: tone),
        const SizedBox(height: 24),
        _PaymentSection(money: money, tone: tone, onRetry: _loadMoney),
        const SizedBox(height: 20),
        _DocumentsSection(
          appointment: appointment,
          money: money,
          tone: tone,
          documents: _documents,
          failed: _documentsFailed,
          building: _buildingDocument,
          onOpen: (kind) => _openDocument(appointment, kind),
          onRetry: () => _loadDocuments(force: true),
        ),
        _Footer(
          appointment: appointment,
          money: money,
          tone: tone,
          onReschedule: () => _reschedule(appointment),
        ),
      ],
    );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _fetch,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 720;
          return ListView(
            // A fresh scroll position per appointment: it always opens at the top.
            key: PageStorageKey('appointment-${appointment.id}'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              if (_status.hasFailed) ...[SectionErrorLine(status: _status, onRetry: _fetch), const SizedBox(height: 12)],
              if (_notFound) ...[
                Text(
                  'The clinic may have removed this appointment. Showing the last copy saved on this device.',
                  style: TextStyle(fontSize: 13, color: tone.label),
                ),
                const SizedBox(height: 12),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 300, child: qr),
                    const SizedBox(width: 28),
                    Expanded(child: details),
                  ],
                )
              else ...[
                qr,
                const SizedBox(height: 24),
                details,
              ],
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sections

/// The QR (tap to enlarge), Save QR Image, a rule, then the confirmation code
/// with Copy — the website's QR card.
class _QrCard extends StatelessWidget {
  final Appointment appointment;
  final _Tone tone;
  final GlobalKey boundaryKey;
  final bool saving;
  final bool copied;
  final ValueChanged<String> onCopy;
  final VoidCallback onSave;
  final ValueChanged<String> onEnlarge;

  const _QrCard({
    required this.appointment,
    required this.tone,
    required this.boundaryKey,
    required this.saving,
    required this.copied,
    required this.onCopy,
    required this.onSave,
    required this.onEnlarge,
  });

  @override
  Widget build(BuildContext context) {
    final code = appointment.confirmationCode?.trim() ?? '';
    final payload = appointment.checkInQrPayload;
    final secondary = OutlinedButton.styleFrom(
      foregroundColor: tone.text,
      side: BorderSide(color: tone.buttonBorder),
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(color: tone.qrSurface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          if (payload != null) ...[
            Semantics(
              button: true,
              label: 'Enlarge QR code',
              child: GestureDetector(
                onTap: () => onEnlarge(payload),
                // White margin round the code, so the saved image keeps its
                // quiet space on any background.
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: CheckInQr(key: ValueKey(payload), payload: payload, size: 200),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: secondary,
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(TablerIcons.download, size: 16),
              label: const Text('Save QR Image', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Your check-in QR code appears here once the clinic issues your confirmation code.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.35, color: tone.label),
              ),
            ),
          const SizedBox(height: 14),
          Divider(height: 1, color: tone.divider),
          const SizedBox(height: 14),
          Text('CONFIRMATION CODE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: tone.label)),
          const SizedBox(height: 8),
          if (code.isEmpty)
            Text('Not issued yet', style: TextStyle(fontSize: 15, color: tone.label))
          else
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                SelectableText(
                  code,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['Courier', 'RobotoMono'],
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: tone.text,
                  ),
                ),
                OutlinedButton.icon(
                  style: secondary,
                  onPressed: () => onCopy(code),
                  icon: Icon(copied ? TablerIcons.check : TablerIcons.copy, size: 16),
                  label: Text(copied ? 'Copied!' : 'Copy',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Section heading, as the website writes them.
class _Heading extends StatelessWidget {
  final String text;
  final _Tone tone;

  const _Heading(this.text, this.tone);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: tone.text)),
      );
}

/// A ruled label / value row on the page background.
class _Row extends StatelessWidget {
  final String label;
  final Widget value;
  final _Tone tone;

  const _Row(this.label, this.value, this.tone);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tone.divider))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: TextStyle(fontSize: 13.5, color: tone.label))),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: value)),
        ],
      ),
    );
  }
}

Text _value(String text, _Tone tone, {Color? color, double size = 14, FontWeight weight = FontWeight.w600}) =>
    Text(text, textAlign: TextAlign.right, style: TextStyle(fontSize: size, fontWeight: weight, color: color ?? tone.text));

/// Status pill colours (light text, dark text, background).
(Color, Color, Color) _statusColors(String raw, bool dark) {
  final s = raw.toLowerCase();
  if (s == 'confirmed') {
    return (const Color(0xFF059669), const Color(0xFF34D399), const Color(0xFF10B981).withValues(alpha: 0.10));
  }
  if (s.startsWith('pending') || s == 'scheduled') {
    return (const Color(0xFFD97706), const Color(0xFFFBBF24), const Color(0xFFF59E0B).withValues(alpha: 0.10));
  }
  if (s == 'ongoing') {
    return (const Color(0xFF0D9488), const Color(0xFF2DD4BF), const Color(0xFF14B8A6).withValues(alpha: 0.10));
  }
  if (s == 'cancelled' || s == 'no-show' || s == 'no show') {
    return (const Color(0xFFDC2626), const Color(0xFFF87171), const Color(0xFFEF4444).withValues(alpha: 0.10));
  }
  return (const Color(0xFF475569), const Color(0xFFCBD5E1), dark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
}

class _StatusPill extends StatelessWidget {
  final Appointment appointment;
  final _Tone tone;

  const _StatusPill(this.appointment, this.tone);

  @override
  Widget build(BuildContext context) {
    final raw = appointment.rawStatus.trim().isNotEmpty ? appointment.rawStatus.trim() : statusLabel(appointment.status);
    final (light, dark, bg) = _statusColors(raw, tone.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(raw, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tone.dark ? dark : light)),
    );
  }
}

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class _InfoSection extends StatelessWidget {
  final Appointment appointment;
  final _Tone tone;

  const _InfoSection({required this.appointment, required this.tone});

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final reason = a.cancellationReasonLabel(myUserId: SupabaseService.currentUserId);
    final notes = a.notes?.trim() ?? '';
    // `appointment_date` is a calendar date: read as written, never shifted
    // through UTC.
    final day = DateTime.tryParse(a.rawDate);
    final date = day == null ? formatAppointmentDate(a.date) : '${_monthsLong[day.month - 1]} ${day.day}, ${day.year}';
    final time = a.rawTime.trim().isEmpty ? 'To be confirmed' : a.timeRangeLabel;
    final doctor = a.doctorName.trim();
    final dentist = doctor.isEmpty || doctor == kUnassignedDoctor ? 'To be assigned' : doctor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading('Appointment Information', tone),
        _Row('Status', _StatusPill(a, tone), tone),
        if (reason != null) _Row('Cancellation Reason', _value(reason, tone), tone),
        _Row('Date', _value(date, tone), tone),
        _Row('Time', _value(time, tone), tone),
        _Row('Dentist', _value(dentist, tone), tone),
        _Row('Service', _value(a.serviceName, tone), tone),
        if (notes.isNotEmpty) _Row('Notes', _value(notes, tone, weight: FontWeight.w400), tone),
      ],
    );
  }
}

class _PaymentSection extends StatelessWidget {
  final AppointmentMoney money;
  final _Tone tone;
  final VoidCallback onRetry;

  const _PaymentSection({required this.money, required this.tone, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final m = money;
    // A positive amount alone is not a payment: only a down payment the server
    // stamped paid (and not forfeited) is shown as received and deducted.
    final String downText;
    if (m.down <= 0) {
      downText = padPeso(0);
    } else if (m.forfeited) {
      downText = '${padPeso(m.down)} (forfeited)';
    } else if (m.paid) {
      downText = padPeso(m.down);
    } else {
      downText = '${padPeso(m.down)} (not yet verified)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading('Payment Summary', tone),
        _Row('Payment Method', _value(paymentMethodLabel(m.method, paid: m.paid), tone), tone),
        _Row('Service Price', _value(m.priceMin > 0 ? pesoRange(m.priceMin, m.priceMax) : '—', tone), tone),
        _Row('Down Payment', _value(downText, tone, color: tone.downPayment), tone),
        if (m.feeTotal > 0) _Row('Reschedule Fees', _value('-${padPeso(m.feeTotal)}', tone), tone),
        if (m.paid && m.feeTotal > 0)
          _Row('Deposit Credited to Final Bill', _value(padPeso(m.credited), tone), tone),
        if (m.priceMin > 0)
          _Row(
            m.billed ? 'Balance Due at Clinic' : 'Estimated Balance Due at Clinic',
            _value(pesoRange(m.balanceMin, m.balanceMax), tone, color: tone.balance, size: 17.5, weight: FontWeight.w800),
            tone,
          ),
        if (m.billingFailed) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  "We could not check the clinic's bill for this visit, so these figures are estimates.",
                  style: TextStyle(fontSize: 12, height: 1.35, color: tone.label),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
      ],
    );
  }
}

/// The visit's documents. Confirmed: the issued invoice only — no deposit
/// receipt, no pro-forma. Completed: invoice and payment receipt. Otherwise a
/// verified deposit keeps its Deposit Receipt.
class _DocumentsSection extends StatelessWidget {
  final Appointment appointment;
  final AppointmentMoney money;
  final _Tone tone;
  final AppointmentDocuments? documents;
  final bool failed;
  final String? building;
  final ValueChanged<String> onOpen;
  final VoidCallback onRetry;

  const _DocumentsSection({
    required this.appointment,
    required this.money,
    required this.tone,
    required this.documents,
    required this.failed,
    required this.building,
    required this.onOpen,
    required this.onRetry,
  });

  Widget _button(String label, String kind) => _DocAction(
        label: label,
        tone: tone,
        busy: building == kind,
        onPressed: building == null ? () => onOpen(kind) : null,
      );

  /// Download Receipt and Download Invoice side by side, outlined in teal; a
  /// button is live only once the clinic has issued that document.
  Widget _completedDocuments() {
    final looking = documents == null && !failed;
    final hasReceipt = documents?.receiptId != null;
    final hasInvoice = documents?.invoiceId != null;

    String? note;
    if (failed) {
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
                busy: looking || building == 'receipt',
                onPressed: hasReceipt && building == null ? () => onOpen('receipt') : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DocumentButton(
                label: 'Download Invoice',
                icon: CupertinoIcons.doc_plaintext,
                busy: looking || building == 'invoice',
                onPressed: hasInvoice && building == null ? () => onOpen('invoice') : null,
              ),
            ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note, style: TextStyle(fontSize: 11.5, height: 1.35, color: tone.label)),
        ],
      ],
    );
  }

  Widget _note(String text) =>
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(text, style: TextStyle(fontSize: 12.5, color: tone.label)));

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final checking = documents == null && !failed;
    final retry = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(TablerIcons.refresh, size: 16),
        label: Text(appointment.status == AppointmentStatus.confirmed ? 'Retry loading invoice' : 'Retry loading documents'),
      ),
    );

    switch (appointment.status) {
      case AppointmentStatus.confirmed:
        // A deposit the server recorded as received keeps its receipt.
        if (money.down > 0 && money.paid) {
          children.add(_button('Download Deposit Receipt', 'deposit'));
          children.add(const SizedBox(height: 8));
        }
        if (checking) {
          children.add(_note('Checking invoice…'));
        } else if (failed) {
          children.add(retry);
        } else if (documents?.invoiceId != null) {
          children.add(_button('Download Invoice', 'invoice'));
        }
      case AppointmentStatus.completed:
        children.add(_completedDocuments());
      case AppointmentStatus.pending:
      case AppointmentStatus.cancelled:
        // Only money the server recorded as received earns a receipt.
        if (money.down > 0 && (money.paid || money.forfeited)) {
          children.add(_button('Download Deposit Receipt', 'deposit'));
        }
        if (money.forfeited) children.add(_note('This deposit was forfeited when the appointment was cancelled.'));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// The completed visit's outlined teal download button.
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

class _DocAction extends StatelessWidget {
  final String label;
  final _Tone tone;
  final bool busy;
  final VoidCallback? onPressed;

  const _DocAction({required this.label, required this.tone, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: tone.docText,
        side: BorderSide(color: tone.buttonBorder),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(TablerIcons.download, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
    );
  }
}

/// Reschedule (neutral) and Cancel Appointment (red), when the status and
/// schedule allow them, with any limit said in words.
class _Footer extends StatelessWidget {
  final Appointment appointment;
  final AppointmentMoney money;
  final _Tone tone;
  final VoidCallback onReschedule;

  const _Footer({required this.appointment, required this.money, required this.tone, required this.onReschedule});

  @override
  Widget build(BuildContext context) {
    if (!canPatientChange(appointment)) return const SizedBox.shrink();
    final canMove = canRescheduleOnline(appointment);
    ButtonStyle outlined(Color fg, Color border) => OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: border),
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: tone.divider),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: outlined(tone.text, tone.buttonBorder),
                onPressed: canMove ? onReschedule : null,
                child: const Text('Reschedule', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: outlined(_Tone.red, _Tone.red),
                onPressed: () => confirmCancelAppointment(context, appointment),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Cancel Appointment', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-screen preview of a clinic document — Deposit Receipt, Payment
/// Receipt or Invoice — with its own save and close actions.
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
            icon: const Icon(TablerIcons.download, size: 17),
            label: const Text('Save to Device', style: TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(TablerIcons.x),
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

class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: const [
          SkeletonBox(height: 280, radius: 12),
          SizedBox(height: 24),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 18),
          SizedBox(height: 24),
          SkeletonBox(height: 170, radius: 12),
        ],
      ),
    );
  }
}
