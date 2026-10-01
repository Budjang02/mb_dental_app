import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/repositories/clinic_documents_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/appointment_details_screen.dart';
import 'package:mb_dental_app/services/clinic_pdf.dart';
import 'package:mb_dental_app/services/supabase_service.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'package:mb_dental_app/widgets/section_states.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

// Billing & Receipts — js/patient-billing.js and the Billing Overview in
// js/invoice.js.

String _day(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final m = manilaTime(d);
  return '${months[m.month - 1]} ${m.day}, ${m.year}';
}

/// The three summary figures, by the website's rules: a voided charge is in
/// neither total; receipts are counted once each by receipt id, since one
/// receipt can settle several charges.
class BillingSummary {
  final double outstanding;
  final double paid;
  final int receipts;

  const BillingSummary(this.outstanding, this.paid, this.receipts);

  factory BillingSummary.of(List<Payment> charges) {
    var due = 0.0, paid = 0.0;
    final receiptIds = <String>{};
    for (final b in charges) {
      if (b.isVoided) continue;
      if (b.isPaid) {
        paid += b.amount;
      } else {
        due += b.amount;
      }
      if (b.receiptId != null) receiptIds.add(b.receiptId!);
    }
    return BillingSummary(due, paid, receiptIds.length);
  }
}

/// (icon, colour, tile) for a charge's status.
(FaIconData, Color, Color) billingStatusStyle(Payment b) {
  if (b.isVoided) {
    return (
      FontAwesomeIcons.ban,
      const Color(0xFF64748B),
      const Color(0xFF64748B).withValues(alpha: 0.12),
    );
  }
  if (b.isPaid) {
    return (
      FontAwesomeIcons.circleCheck,
      const Color(0xFF16A34A),
      const Color(0xFF22C55E).withValues(alpha: 0.12),
    );
  }
  return (
    FontAwesomeIcons.hourglassHalf,
    const Color(0xFFD97706),
    const Color(0xFFF59E0B).withValues(alpha: 0.12),
  );
}

class BillingReceiptsView extends StatelessWidget {
  const BillingReceiptsView({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    final status = repository.effectiveStatusOf(SyncSection.billing);
    final charges = repository.billing;
    final loading = status.isPending && charges.isEmpty;

    return RefreshIndicator(
      onRefresh: () => repository.load(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (status.hasFailed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SectionErrorNotice(
                status: status,
                compact: true,
                isRetrying: repository.isRetrying(SyncSection.billing),
                onRetry: () => repository.retrySection(SyncSection.billing),
              ),
            )
          else if (loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SectionSkeleton(rows: 3),
            )
          else if (charges.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No transactions yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final charge in charges) ...[
              _ChargeRow(charge: charge),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _ChargeRow extends StatelessWidget {
  final Payment charge;

  const _ChargeRow({required this.charge});

  @override
  Widget build(BuildContext context) {
    final b = charge;
    final bits = [
      _day(b.billedOn),
      if (b.isPaid)
        (b.paymentMethod ?? '').trim().isEmpty
            ? 'Unspecified'
            : b.paymentMethod!.trim(),
      if (b.isVoided) 'Voided' else if (!b.isPaid) 'Unpaid',
    ];
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BillingOverviewScreen(charge: b)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.procedureName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bits.join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (b.invoiceNo.isNotEmpty ||
                        (b.receiptNo ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (b.invoiceNo.isNotEmpty)
                            _RefChip(FontAwesomeIcons.fileInvoice, b.invoiceNo),
                          if ((b.receiptNo ?? '').isNotEmpty)
                            _RefChip(FontAwesomeIcons.receipt, b.receiptNo!),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatPeso(b.amount),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: b.isVoided
                      ? AppColors.textSecondary.withValues(alpha: 0.6)
                      : AppColors.textPrimary,
                  decoration: b.isVoided ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefChip extends StatelessWidget {
  final FaIconData icon;
  final String text;

  const _RefChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, size: 10, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Billing Overview ---

/// What the overview needs beyond the charge itself, read fresh.
class _OverviewData {
  final double depositApplied;
  final double remaining;
  final bool coversVisit;

  const _OverviewData(this.depositApplied, this.remaining, this.coversVisit);
}

/// Billing Overview for one charge (`_openBillingOverview`): the charge, how it
/// was settled, and its two documents as separate actions — each opens by its
/// own id, and one not issued yet says so.
class BillingOverviewScreen extends StatefulWidget {
  final Payment charge;

  const BillingOverviewScreen({super.key, required this.charge});

  @override
  State<BillingOverviewScreen> createState() => _BillingOverviewScreenState();
}

class _BillingOverviewScreenState extends State<BillingOverviewScreen> {
  _OverviewData? _data;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double _n(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  /// The website's rule: the deposit is what the receipt actually applied once
  /// paid; before that, the verified deposit still standing (paid, not
  /// forfeited, less reschedule fees). The remaining balance covers the whole
  /// visit's unpaid, unvoided charges less that deposit.
  Future<void> _load() async {
    final b = widget.charge;
    var deposit = 0.0;
    double? receiptDeposit;
    var visitUnpaid = b.isOwed ? b.amount : 0.0;
    var coversVisit = false;
    final db = SupabaseService.client;
    try {
      final item = await db
          .from('receipt_items')
          .select('payment_receipts(deposit_applied)')
          .eq('billing_record_id', b.id)
          .maybeSingle();
      final r = item?['payment_receipts'];
      final receipt = r is List ? (r.isEmpty ? null : r.first) : r;
      if (receipt is Map && receipt['deposit_applied'] != null)
        receiptDeposit = _n(receipt['deposit_applied']);
    } catch (e) {
      debugPrint('Billing overview receipt unavailable: $e');
    }
    if (b.appointmentId != null) {
      try {
        final a = await db
            .from('appointments')
            .select(
              'downpayment_amount, downpayment_paid_at, reschedule_fee_total, deposit_forfeited_at, '
              'billing_records(amount, status, voided_at)',
            )
            .eq('id', b.appointmentId!)
            .maybeSingle();
        if (a != null) {
          coversVisit = true;
          final down = _n(a['downpayment_amount']);
          if (a['downpayment_paid_at'] != null &&
              a['deposit_forfeited_at'] == null &&
              down > 0) {
            final fees = _n(a['reschedule_fee_total']);
            deposit = down - (fees < down ? fees : down);
          }
          visitUnpaid = ((a['billing_records'] as List?) ?? const [])
              .whereType<Map>()
              .where(
                (x) =>
                    x['voided_at'] == null &&
                    '${x['status']}'.toLowerCase() != 'paid',
              )
              .fold(0.0, (s, x) => s + _n(x['amount']));
        }
      } catch (e) {
        debugPrint('Billing overview visit unavailable: $e');
      }
    }
    final applied = receiptDeposit ?? deposit;
    final remaining = b.isOwed
        ? (visitUnpaid - applied).clamp(0, double.infinity).toDouble()
        : 0.0;
    if (mounted)
      setState(() => _data = _OverviewData(applied, remaining, coversVisit));
  }

  Future<void> _open(String kind) async {
    final b = widget.charge;
    if (_opening != null) return;
    setState(() => _opening = kind);
    ClinicPdfSpec? spec;
    Uint8List? bytes;
    try {
      spec = kind == 'invoice'
          ? await ClinicDocumentsApi.invoiceSpec(b.invoiceId!)
          : await ClinicDocumentsApi.paymentReceiptSpec(b.receiptId!);
      if (spec != null) bytes = await renderClinicPdf(spec);
    } catch (e) {
      if (mounted) {
        showAppToast(
          context,
          e is DocumentAccessException
              ? e.message
              : 'Could not open that document. Please try again.',
          isError: true,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _opening = null);
    }
    if (!mounted) return;
    if (spec == null || bytes == null) {
      showAppToast(context, 'That document could not be found.', isError: true);
      return;
    }
    final doc = spec;
    final pdf = bytes;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ClinicDocumentPreview(
          title: doc.title,
          bytes: pdf,
          fileName: doc.fileName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeController();
    final b = widget.charge;
    final (_, fg, bg) = billingStatusStyle(b);
    final data = _data;
    final method = (b.paymentMethod ?? '').trim().isNotEmpty
        ? b.paymentMethod!.trim()
        : (b.isOwed ? 'Not paid yet' : 'Unspecified');

    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: value),
          ),
        ],
      ),
    );
    Widget text(String v, {bool strong = false}) => Text(
      v,
      style: TextStyle(
        fontSize: 13,
        fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
    Widget section(String title, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Billing Overview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          section('Billing Information', [
            row('Transaction Date', text(_day(b.billedOn))),
            row('Procedure', text(b.procedureName)),
            row(
              'Attending Doctor',
              text(b.doctorName.trim().isEmpty ? 'Not assigned' : b.doctorName),
            ),
            row(
              'Total Amount',
              Text(
                formatPeso(b.amount),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  decoration: b.isVoided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            row(
              'Payment Status',
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    b.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: fg,
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: 20, color: AppColors.border),
            Text(
              'Payment Breakdown',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            row('Payment Method', text(method)),
            row(
              'Down Payment Applied',
              data == null
                  ? const _Dash()
                  : text(
                      data.depositApplied > 0
                          ? '−${formatPeso(data.depositApplied)}'
                          : formatPeso(0),
                    ),
            ),
            row(
              data?.coversVisit ?? false
                  ? 'Remaining Balance (visit)'
                  : 'Remaining Balance',
              data == null
                  ? const _Dash()
                  : text(formatPeso(data.remaining), strong: true),
            ),
            if (b.isPaid) row('Amount Paid', text(formatPeso(b.amount))),
          ]),
          section('Billed Documents', [
            const SizedBox(height: 6),
            b.invoiceId != null
                ? _DocAction(
                    icon: FontAwesomeIcons.fileInvoice,
                    label: 'View Official Invoice',
                    code: b.invoiceNo.isEmpty ? 'Invoice' : b.invoiceNo,
                    busy: _opening == 'invoice',
                    onTap: () => _open('invoice'),
                  )
                : const _DocPending(
                    icon: FontAwesomeIcons.fileInvoice,
                    title: 'Official Invoice Pending',
                    body:
                        'An official invoice will be available once this transaction is issued.',
                  ),
            const SizedBox(height: 8),
            b.receiptId != null
                ? _DocAction(
                    icon: FontAwesomeIcons.receipt,
                    label: 'View Payment Receipt',
                    code: b.receiptNo ?? 'Receipt',
                    busy: _opening == 'receipt',
                    onTap: () => _open('receipt'),
                  )
                : const _DocPending(
                    icon: FontAwesomeIcons.clock,
                    title: 'Receipt Pending',
                    body:
                        'A payment receipt will be available once this transaction is settled.',
                  ),
            const SizedBox(height: 8),
          ]),
        ],
      ),
    );
  }
}

class _Dash extends StatelessWidget {
  const _Dash();

  @override
  Widget build(BuildContext context) =>
      Text('…', style: TextStyle(color: AppColors.textSecondary));
}

class _DocAction extends StatelessWidget {
  final FaIconData icon;
  final String label;
  final String code;
  final bool busy;
  final VoidCallback onTap;

  const _DocAction({
    required this.icon,
    required this.label,
    required this.code,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          color: AppColors.primary.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            FaIcon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    code,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FaIcon(
                    FontAwesomeIcons.arrowRight,
                    size: 13,
                    color: AppColors.primary,
                  ),
          ],
        ),
      ),
    );
  }
}

class _DocPending extends StatelessWidget {
  final FaIconData icon;
  final String title;
  final String body;

  const _DocPending({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FaIcon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
