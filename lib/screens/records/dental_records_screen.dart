import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'dental_arch_chart.dart';
import 'tooth_glyphs.dart';
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

/// The coral the reference chart marks a picked tooth with. Deliberately not
/// part of [kToothConditionColors]: a condition describes the tooth, while
/// selection only says which one the panel underneath is talking about, so a
/// tooth that already has a condition keeps its own colour and takes the ring.
const Color kToothSelectedFill = Color(0xFFEE8172);
const Color kToothSelectedOutline = Color(0xFFC2503F);

const List<String> _planMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatPlanDate(DateTime date) => '${_planMonths[date.month - 1]} ${date.day}, ${date.year}';

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
  int _selectedTabIndex = 0; // 0 = Dental Chart, 1 = Treatment Plan, 2 = X-Rays & Files
  /// Null until a crown is tapped: the chart opens with nothing singled out.
  int? _selectedToothNumber;

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
                  _buildTabButton('Treatment Plan', 1),
                  _buildTabButton('X-Rays & Files', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_selectedTabIndex == 0) _buildDentalChartTab(),
            if (_selectedTabIndex == 1) _buildTreatmentPlanTab(),
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
        // Outer card carries the title and the actions; the arch itself sits
        // in a second, inset well, framed the way the reference drawing is.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Interactive Odontogram',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              'Universal Numbering',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _showToothTypesInfoSheet,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Icon(CupertinoIcons.info_circle,
                                    color: AppColors.textSecondary, size: 14),
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
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _exportOdontogramPdf,
                    icon: const Icon(CupertinoIcons.doc_text, size: 14),
                    label: const Text('Export as PDF',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _selectTeethHeading(),
                    const SizedBox(height: 18),
                    DentalArchChart(
                      selectedTooth: _selectedToothNumber,
                      onSelect: (tooth) {
                        setState(() => _selectedToothNumber = tooth);
                        _showToothDetail(tooth);
                      },
                      conditionColors: {
                        for (final entry in _toothConditions.entries)
                          entry.key: entry.value['color'] as Color,
                      },
                      // Straight from the shared colour map, so every tooth is
                      // painted with the app's own condition keys.
                      idleFill: kToothConditionColors['Not Recorded']!,
                      outlineColor: AppColors.toothOutline,
                      selectedFill: kToothSelectedFill,
                      selectedOutline: kToothSelectedOutline,
                      labelColor: AppColors.textSecondary,
                    ),
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

  /// The reference's own heading, in its two weights.
  Widget _selectTeethHeading() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(fontSize: 13, letterSpacing: 1.6, color: AppColors.textPrimary),
        children: [
          const TextSpan(text: 'SELECT ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
            text: 'TEETH',
            style: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMergedToothCard() {
    final selected = _selectedToothNumber;
    final matching = selected == null
        ? const <Map<String, String>>[]
        : kTreatmentNotes.where((n) => toothNumberOf(n['tooth'] ?? '') == selected).toList();

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
          if (selected == null)
            Text(
              'Tap a tooth on the chart above to see its treatment notes.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else if (matching.isEmpty)
            Text(
              'No treatment notes recorded for Tooth #$selected yet.',
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

  /// Everything on file for one tooth, opened by tapping its crown: what it
  /// is, what has been recorded against it, and every treatment note filed
  /// under it. This is where the chart's colours get named, now that no legend
  /// sits under the arch.
  void _showToothDetail(int tooth) {
    final info = _toothConditions[tooth];
    final condition = (info?['condition'] as String?) ?? 'Not Recorded';
    final swatch = (info?['color'] as Color?) ?? kToothConditionColors[condition]!;
    // The unrecorded swatch is white, which cannot carry a chip on its own.
    final accent = info == null ? AppColors.textSecondary : swatch;
    final notes = kTreatmentNotes.where((n) => toothNumberOf(n['tooth'] ?? '') == tooth).toList();

    showAppDialog(
      context,
      builder: (dialogContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#$tooth',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    toothName(tooth),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withOpacity(0.45)),
                  ),
                  child: Text(
                    condition,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv('Tooth', '#$tooth'),
            _kv('Name', toothName(tooth)),
            _kv('Type', _toothTypeLabel(tooth)),
            _kv('Condition', condition),
            if (info?['notes'] != null) _kv('Clinical note', info!['notes'] as String),
            const SizedBox(height: 8),
            Divider(height: 20, color: AppColors.border),
            Text(
              'Treatment History',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            if (notes.isEmpty)
              Text(
                'No treatment recorded for this tooth yet.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              )
            else
              for (int i = 0; i < notes.length; i++) ...[
                if (i > 0) Divider(height: 18, color: AppColors.border),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notes[i]['procedure'] ?? '',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${notes[i]['date'] ?? ''} \u2022 ${notes[i]['doctor'] ?? ''}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    if ((notes[i]['notes'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notes[i]['notes']!,
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }

  /// "Molar", "Premolar", "Canine" or "Incisor" for the dialog's summary.
  String _toothTypeLabel(int tooth) {
    switch (toothTypeOf(tooth)) {
      case ToothType.molar:
        return 'Molar';
      case ToothType.premolar:
        return 'Premolar';
      case ToothType.canine:
        return 'Canine';
      case ToothType.incisor:
        return 'Incisor';
    }
  }

  // --- TAB 2: TREATMENT PLAN ---
  /// What the clinic has planned but not yet carried out. Empty for most
  /// patients, so the empty state is the common case and is written to match
  /// the one on X-Rays & Files rather than being a bare line of text.
  Widget _buildTreatmentPlanTab() {
    final plan = List<TreatmentPlanItem>.from(PatientRepository().treatmentPlan)
      ..sort((a, b) {
        // Scheduled items first, soonest at the top; anything still unscheduled
        // trails behind them.
        if (a.plannedFor == null && b.plannedFor == null) return 0;
        if (a.plannedFor == null) return 1;
        if (b.plannedFor == null) return -1;
        return a.plannedFor!.compareTo(b.plannedFor!);
      });

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
            'Treatment Plan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          if (plan.isEmpty)
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
                  Icon(CupertinoIcons.doc_text, size: 36, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    'No treatment plan yet.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Procedures your dentist plans for you will appear here after your next visit.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < plan.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _buildTreatmentPlanRow(plan[i]),
            ],
        ],
      ),
    );
  }

  Widget _buildTreatmentPlanRow(TreatmentPlanItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTreatmentPlanDetail(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
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
                    Text(
                      item.procedure,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.plannedFor == null
                          ? '${item.toothLabel} \u2022 Not scheduled'
                          : '${item.toothLabel} \u2022 ${_formatPlanDate(item.plannedFor!)}',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(
                '\u20b1${item.estimatedCost.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 4),
              Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _showTreatmentPlanDetail(TreatmentPlanItem item) {
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
              item.procedure,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            _kv('Tooth', item.toothLabel),
            _kv('Dentist', item.doctorName),
            _kv('Planned for', item.plannedFor == null ? 'Not scheduled' : _formatPlanDate(item.plannedFor!)),
            _kv('Estimated cost', '\u20b1${item.estimatedCost.toStringAsFixed(2)}'),
            if (item.notes.isNotEmpty) _kv('Notes', item.notes),
          ],
        ),
      ),
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
