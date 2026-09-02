import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/payment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'tooth_shapes.dart';
import 'treatment_notes_data.dart';
import 'treatment_notes_screen.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Universal Numbering System (#1-32), starting at the upper-right wisdom
/// tooth and ending at the lower-right wisdom tooth.
const List<String> _toothNames = [
  'Upper Right Third Molar (Wisdom Tooth)',
  'Upper Right Second Molar',
  'Upper Right First Molar',
  'Upper Right Second Premolar',
  'Upper Right First Premolar',
  'Upper Right Canine',
  'Upper Right Lateral Incisor',
  'Upper Right Central Incisor',
  'Upper Left Central Incisor',
  'Upper Left Lateral Incisor',
  'Upper Left Canine',
  'Upper Left First Premolar',
  'Upper Left Second Premolar',
  'Upper Left First Molar',
  'Upper Left Second Molar',
  'Upper Left Third Molar (Wisdom Tooth)',
  'Lower Left Third Molar (Wisdom Tooth)',
  'Lower Left Second Molar',
  'Lower Left First Molar',
  'Lower Left Second Premolar',
  'Lower Left First Premolar',
  'Lower Left Canine',
  'Lower Left Lateral Incisor',
  'Lower Left Central Incisor',
  'Lower Right Central Incisor',
  'Lower Right Lateral Incisor',
  'Lower Right Canine',
  'Lower Right First Premolar',
  'Lower Right Second Premolar',
  'Lower Right First Molar',
  'Lower Right Second Molar',
  'Lower Right Third Molar (Wisdom Tooth)',
];

String toothName(int toothNumber) => _toothNames[toothNumber - 1];

/// Chart legend, in the order the reference lists them. Also the source of
/// truth for the colour each recorded condition paints its tooth with.
const Map<String, Color> kToothConditionColors = {
  'Not Recorded': Color(0xFFFFFFFF),
  'Healthy': Color(0xFF2DD4BF),
  'Caries/Cavity': Color(0xFFFFB74D),
  'Filled': Color(0xFF64B5F6),
  'Crown': Color(0xFFE040FB),
  'Missing': Color(0xFFE57373),
  'Root Canal': Color(0xFFFB923C),
  'Impacted': Color(0xFFF472B6),
  'Other': Color(0xFFA78BFA),
};

const List<String> _billMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatBillDate(DateTime date) => '${_billMonths[date.month - 1]} ${date.day}, ${date.year}';

/// Reads the leading "#12" out of a treatment note's tooth field. Returns null
/// for whole-mouth entries such as "Full Mouth".
int? toothNumberOf(String toothField) {
  final match = RegExp(r'^#(\d+)').firstMatch(toothField.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}

class DentalRecordsScreen extends StatefulWidget {
  const DentalRecordsScreen({super.key});

  @override
  State<DentalRecordsScreen> createState() => _DentalRecordsScreenState();
}

class _DentalRecordsScreenState extends State<DentalRecordsScreen> {
  int _selectedTabIndex = 0; // 0 = Dental Chart, 1 = Billing, 2 = X-Rays & Files
  int _selectedToothNumber = 6;

  final Map<int, Map<String, dynamic>> _toothConditions = {
    6: {'condition': 'Filled', 'color': const Color(0xFF64B5F6), 'notes': 'Composite filling applied on Upper Right Canine.'},
    14: {'condition': 'Caries/Cavity', 'color': const Color(0xFFFFB74D), 'notes': 'Slight cavity detected on Upper Left Molar.'},
    19: {'condition': 'Crown', 'color': const Color(0xFFE040FB), 'notes': 'Porcelain crown fitted.'},
    30: {'condition': 'Missing', 'color': const Color(0xFFE57373), 'notes': 'Tooth extracted.'},
  };

  Future<void> _exportOdontogramPdf() async {
    final patient = PatientRepository().patient;
    final doc = pw.Document();
    final rows = _toothConditions.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    doc.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Dental Record Summary', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Mariano & Bolasoc Dental Center'),
            pw.SizedBox(height: 16),
            pw.Text('Patient: ${patient.fullName}'),
            pw.Text('Patient Code: ${patient.patientCode}'),
            pw.Text('Generated: ${DateTime.now().toString().split('.').first}'),
            pw.SizedBox(height: 20),
            pw.Text('Tooth Conditions', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            if (rows.isEmpty)
              pw.Text('No conditions recorded. All teeth healthy.')
            else
              pw.TableHelper.fromTextArray(
                headers: ['Tooth #', 'Name', 'Condition', 'Notes'],
                data: rows
                    .map((e) => [
                          '#${e.key}',
                          toothName(e.key),
                          e.value['condition'].toString(),
                          e.value['notes'].toString(),
                        ])
                    .toList(),
              ),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'dental-record-${patient.patientCode}.pdf',
    );
  }

  void _showToothTypesInfoSheet() {
    showAppDialog(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tooth Types', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary)),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Each of the 32 adult teeth is numbered #1 to #32 (Universal Numbering System) and falls into one of four types.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const _ToothTypeInfoRow(
              title: 'Incisors',
              subtitle: 'The 8 front teeth, top and bottom. Flat, chisel-shaped edges for cutting and biting.',
            ),
            const SizedBox(height: 12),
            const _ToothTypeInfoRow(
              title: 'Canines',
              subtitle: 'The 4 pointed teeth at the corners of the arch. Used for tearing food.',
            ),
            const SizedBox(height: 12),
            const _ToothTypeInfoRow(
              title: 'Premolars',
              subtitle: 'The 8 teeth behind the canines, with ridged surfaces for crushing food.',
            ),
            const SizedBox(height: 12),
            const _ToothTypeInfoRow(
              title: 'Molars',
              subtitle: 'The 12 broad teeth at the back, including wisdom teeth, used for grinding.',
            ),
          ],
        ),
      ),
    );
  }

  void _showTreatmentNoteDetail(Map<String, String> note) {
    showAppDialog(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: AppDialogCloseButton(),
            ),
            Text(
              note['procedure'] ?? '',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(note['date'] ?? '', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            _kv('Tooth', note['tooth'] ?? ''),
            _kv('Condition', note['condition'] ?? ''),
            _kv('Performed by', note['doctor'] ?? ''),
            const SizedBox(height: 8),
            Text('Notes', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(note['notes'] ?? '', style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([PatientRepository(), ThemeController()]),
      builder: (context, _) => Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Records'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
        child: Column(
          children: [
            // Segmented Tab Switcher
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  _buildTabButton('Dental Chart', 0),
                  _buildTabButton('Billing', 1),
                  _buildTabButton('X-Rays & Files', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_selectedTabIndex == 0) _buildDentalChartTab(),
            if (_selectedTabIndex == 1) _buildBillingTab(),
            if (_selectedTabIndex == 2) _buildXRaysAndFilesTab(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final bool isSelected = _selectedTabIndex == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selectedTabIndex = index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 1: INTERACTIVE ODONTOGRAM ---
  Widget _buildDentalChartTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Outer card holds the title and actions; the chart itself sits in a
        // second, inset box, as in the reference layout.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interactive Odontogram',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Universal Numbering',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _showToothTypesInfoSheet,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(CupertinoIcons.info_circle, color: AppColors.textSecondary, size: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _exportOdontogramPdf,
              icon: const Icon(CupertinoIcons.doc_text, size: 14),
              label: const Text('Export as PDF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _permanentTeethPill(),
              const SizedBox(height: 16),
              _archLabel('Upper Permanent Teeth (Maxillary)'),
              const SizedBox(height: 10),
              // Both arches share one stack so a single dashed midline runs
              // straight down the chart, as in the reference.
              Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DashedRulePainter(color: AppColors.border, vertical: true),
                    ),
                  ),
                  Column(
                    children: [
                      _toothRow(List.generate(16, (i) => i + 1)),
                      const SizedBox(height: 8),
                      _sideMarkersRow(),
                      const SizedBox(height: 12),
                      _toothRow(List.generate(16, (i) => 32 - i)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _archLabel('Lower Permanent Teeth (Mandibular)'),
              const SizedBox(height: 12),
              _orientationFooter(),
              Divider(height: 26, color: AppColors.border),
              _conditionLegend(),
            ],
          ),
        ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildMergedToothCard(),
      ],
    );
  }

  /// "RIGHT ------------- LEFT" rule sitting between the two arches.
  Widget _sideMarkersRow() {
    Widget marker(String text) => Text(
          text,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        );

    return Row(
      children: [
        marker('RIGHT'),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 1,
            child: CustomPaint(
              painter: _DashedRulePainter(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(width: 8),
        marker('LEFT'),
      ],
    );
  }

  /// Bottom orientation strip: which side of the mouth each half of the
  /// chart belongs to, with the midline called out in the centre.
  Widget _orientationFooter() {
    final style = TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
      letterSpacing: 1,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Transform.rotate(
                angle: math.pi,
                child: Icon(CupertinoIcons.play_arrow_solid, size: 9, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 5),
              Text('RIGHT', style: style),
            ],
          ),
          Text('— MIDLINE —', style: style),
          Row(
            children: [
              Text('LEFT', style: style),
              const SizedBox(width: 5),
              Icon(CupertinoIcons.play_arrow_solid, size: 9, color: AppColors.textSecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _conditionLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final entry in kToothConditionColors.entries) _buildLegendSwatch(entry.key, entry.value),
      ],
    );
  }

  Widget _permanentTeethPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'PERMANENT TEETH',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: 0.6),
      ),
    );
  }

  Widget _archLabel(String text) {
    return Text(
      text.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.8),
    );
  }

  /// One straight row of 16 teeth, numbered underneath.
  Widget _toothRow(List<int> numbers) {
    return Row(
      children: [
        for (final n in numbers) Expanded(child: _buildToothSlot(n)),
      ],
    );
  }

  Widget _buildToothSlot(int toothNum) {
    final isSelected = _selectedToothNumber == toothNum;
    final info = _toothConditions[toothNum];
    final conditionColor = info?['color'] as Color?;

    // Unrecorded teeth are drawn as white silhouettes with a teal outline;
    // recorded ones take their condition color, matching the reference chart.
    final fillColor = conditionColor?.withOpacity(0.85) ?? Colors.white;
    final strokeColor = isSelected
        ? AppColors.primary
        : (conditionColor ?? AppColors.primary.withOpacity(0.55));

    final tooth = CustomPaint(
      size: const Size(20, 42),
      painter: _ToothPainter(
        toothNumber: toothNum,
        fillColor: fillColor,
        strokeColor: strokeColor,
        strokeWidth: isSelected ? 1.7 : 1.15,
      ),
    );

    final label = Text(
      '$toothNum',
      style: TextStyle(
        fontSize: 9,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedToothNumber = toothNum),
        borderRadius: BorderRadius.circular(10),
        splashColor: AppColors.primary.withOpacity(0.25),
        highlightColor: AppColors.primary.withOpacity(0.12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tooth,
              const SizedBox(height: 4),
              label,
            ],
          ),
        ),
      ),
    );
  }

  /// Treatment notes for whichever tooth is selected in the odontogram above.
  Widget _buildMergedToothCard() {
    final matching = kTreatmentNotes
        .where((n) => toothNumberOf(n['tooth'] ?? '') == _selectedToothNumber)
        .toList();

    return Container(
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
          Row(
            children: [
              Icon(CupertinoIcons.doc_text, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Treatment Notes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              // Opens the full history on its own page; this card stays scoped
              // to whichever tooth is selected on the chart.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TreatmentNotesScreen()),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(CupertinoIcons.clock, size: 18, color: AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
          Divider(height: 18, thickness: 0.6, color: AppColors.border),
          if (matching.isEmpty)
            Text(
              'No treatment notes recorded for Tooth #$_selectedToothNumber yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            for (int i = 0; i < matching.length; i++) ...[
              if (i > 0) Divider(height: 22, color: AppColors.border),
              _ToothTreatmentNoteTile(
                note: matching[i],
                onTap: () => _showTreatmentNoteDetail(matching[i]),
              ),
            ],
        ],
      ),
    );
  }

  // --- TAB 3: X-RAYS & FILES ---
  Widget _buildXRaysAndFilesTab() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'X-Rays & Files',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 48),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(CupertinoIcons.tray, size: 36, color: AppColors.textSecondary),
                const SizedBox(height: 12),
                Text(
                  'No X-rays or files yet',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Files your dentist uploads will appear here automatically once your records are connected.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 4: BILLING ---
  /// Rows stay compact on purpose: only the date, procedure, amount and
  /// status are listed, and tapping a row opens the full statement (doctor,
  /// invoice and receipt numbers included).
  Widget _buildBillingTab() {
    final bills = List<Payment>.from(PatientRepository().billing)
      ..sort((a, b) => b.billedOn.compareTo(a.billedOn));

    if (bills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('No billing statements yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('DATE / PROCEDURE',
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
              Expanded(
                flex: 2,
                child: Text('AMOUNT / STATUS',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
        for (int i = 0; i < bills.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildBillingRow(bills[i]),
        ],
      ],
    );
  }

  Widget _buildBillingRow(Payment bill) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showBillingDetail(bill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatBillDate(bill.billedOn),
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(
                      bill.procedureName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${bill.amount.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    _buildBillStatusChip(bill.status, bill.isPaid),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillStatusChip(String status, bool paid) {
    final color = paid ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  void _showBillingDetail(Payment bill) {
    showAppDialog(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Align(
              alignment: Alignment.centerRight,
              child: AppDialogCloseButton(),
            ),
            Text(
              bill.procedureName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            _buildBillStatusChip(bill.status, bill.isPaid),
            const SizedBox(height: 16),
            _kv('Date', _formatBillDate(bill.billedOn)),
            _kv('Procedure', bill.procedureName),
            _kv('Doctor', bill.doctorName),
            _kv('Amount', '₱${bill.amount.toStringAsFixed(2)}'),
            _kv('Status', bill.status),
            _kv('Invoice', bill.invoiceNo),
            _kv('Receipt', bill.receiptNo ?? 'Issued once paid'),
            if (bill.paymentMethod != null) _kv('Paid via', bill.paymentMethod!),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendSwatch(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ToothTypeInfoRow extends StatelessWidget {
  final String title;
  final String subtitle;

  const _ToothTypeInfoRow({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

/// One treatment note for the currently selected tooth: the date, the tooth it
/// belongs to, the condition, the notes and the dentist who performed it. The
/// whole tile is tappable and opens the note's full detail.
class _ToothTreatmentNoteTile extends StatelessWidget {
  final Map<String, String> note;
  final VoidCallback onTap;

  const _ToothTreatmentNoteTile({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // No box of its own: the note sits directly on the tooth card, keeping
    // every line of text but dropping the nested frame around it.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.calendar, size: 13, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(
                    note['date'] ?? '',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const Spacer(),
                  Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                note['procedure'] ?? '',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _tag(note['tooth'] ?? '', AppColors.primary),
                  _tag('Condition: ${note['condition'] ?? '—'}', AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                note['notes'] ?? '',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(CupertinoIcons.person, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Performed by ${note['doctor'] ?? 'the clinic'}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Draws an anatomical tooth silhouette — a rounded crown with a cervical
/// waist plus one to three tapering roots — modelled on a printed odontogram
/// chart. [rootsUp] flips the drawing for the maxillary arch, whose roots
/// point up towards the gum line.
/// Draws one tooth from the outline traced off the reference chart
/// (see tooth_shapes.dart), filled and stroked in whatever colours its
/// current condition and selection state call for.
class _ToothPainter extends CustomPainter {
  final int toothNumber;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const _ToothPainter({
    required this.toothNumber,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final outline = kToothOutlines[toothNumber];
    if (outline == null || outline.length < 6) return;

    // The traced points sit in a unit box that stands for the reference
    // chart's 45x87 tooth cell. Fit that box into the slot without distorting
    // it, so the teeth keep the proportions they have on the reference.
    const sourceAspect = 45 / 87;
    final inset = strokeWidth / 2 + 0.5;
    final availableW = size.width - inset * 2;
    final availableH = size.height - inset * 2;
    final boxW = availableH * sourceAspect <= availableW ? availableH * sourceAspect : availableW;
    final boxH = boxW / sourceAspect;
    final dx = inset + (availableW - boxW) / 2;
    final dy = inset + (availableH - boxH);
    Offset at(int i) => Offset(dx + outline[i * 2] * boxW, dy + outline[i * 2 + 1] * boxH);

    final count = outline.length ~/ 2;
    final path = Path();
    // Quadratics through the midpoints of the traced polygon: keeps the
    // silhouette exact while smoothing away the pixel steps.
    var previous = at(count - 1);
    var current = at(0);
    path.moveTo((previous.dx + current.dx) / 2, (previous.dy + current.dy) / 2);
    for (var i = 1; i <= count; i++) {
      final next = at(i % count);
      path.quadraticBezierTo(
        current.dx,
        current.dy,
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      current = next;
    }
    path.close();

    canvas.drawPath(path, Paint()..color = fillColor..style = PaintingStyle.fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // Crown grooves, traced from the same drawing.
    final grooves = kToothGrooves[toothNumber];
    if (grooves != null && grooves.isNotEmpty) {
      final groovePaint = Paint()
        ..color = strokeColor.withOpacity(0.55)
        ..strokeWidth = strokeWidth * 0.65
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i + 3 < grooves.length; i += 4) {
        canvas.drawLine(
          Offset(dx + grooves[i] * boxW, dy + grooves[i + 1] * boxH),
          Offset(dx + grooves[i + 2] * boxW, dy + grooves[i + 3] * boxH),
          groovePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ToothPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.toothNumber != toothNumber;
  }
}

class _DashedRulePainter extends CustomPainter {
  final Color color;
  final bool vertical;

  const _DashedRulePainter({required this.color, this.vertical = false});

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 4.0;
    const gap = 4.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    if (vertical) {
      final x = size.width / 2;
      for (double y = 0; y < size.height; y += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, size.height)), paint);
      }
    } else {
      final y = size.height / 2;
      for (double x = 0; x < size.width; x += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.vertical != vertical;
}
