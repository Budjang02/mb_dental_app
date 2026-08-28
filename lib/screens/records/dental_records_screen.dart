import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
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

ToothType toothTypeOf(int toothNum) {
  if ([1, 2, 3, 14, 15, 16, 17, 18, 19, 30, 31, 32].contains(toothNum)) return ToothType.molar;
  if ([4, 5, 12, 13, 20, 21, 28, 29].contains(toothNum)) return ToothType.premolar;
  if ([6, 11, 22, 27].contains(toothNum)) return ToothType.canine;
  return ToothType.incisor;
}

/// Upper molars carry three roots and lower molars two; every other tooth has
/// a single root. Drives how many prongs the odontogram silhouette draws.
int toothRootCount(int toothNum) {
  if (toothTypeOf(toothNum) != ToothType.molar) return 1;
  return toothNum <= 16 ? 3 : 2;
}

/// Teeth #1-16 are the upper arch, so their roots point up on the chart.
bool isUpperTooth(int toothNum) => toothNum <= 16;

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
  int _selectedTabIndex = 0; // 0 = Teeth Details, 1 = Treatment Notes, 2 = X-Rays & Files
  int _selectedToothNumber = 6;

  final Map<int, Map<String, dynamic>> _toothConditions = {
    6: {'condition': 'Filled', 'color': const Color(0xFF64B5F6), 'notes': 'Composite filling applied on Upper Right Canine.'},
    14: {'condition': 'Caries/Cavity', 'color': const Color(0xFFFFB74D), 'notes': 'Slight cavity detected on Upper Left Molar.'},
    19: {'condition': 'Crown', 'color': const Color(0xFFE040FB), 'notes': 'Porcelain crown fitted.'},
    30: {'condition': 'Missing', 'color': const Color(0xFFE57373), 'notes': 'Tooth extracted.'},
  };

  final List<Map<String, String>> _allTreatmentNotes = [
    {
      'date': 'Jan 15, 2026',
      'tooth': '#6 Upper Right Canine',
      'condition': 'Filled',
      'procedure': 'Composite Tooth Filling',
      'notes': 'Restoration complete. Patient advised regarding oral hygiene.',
      'doctor': 'Dr. Rey Vincent Bolasoc',
    },
    {
      'date': 'Dec 10, 2025',
      'tooth': 'Full Mouth',
      'condition': 'Cleaned',
      'procedure': 'Full Oral Prophylaxis',
      'notes': 'Routine scaling and polishing completed without complications.',
      'doctor': 'Dr. Jenneline Mariano',
    },
    {
      'date': 'Nov 05, 2025',
      'tooth': '#14 Upper Left Molar',
      'condition': 'Caries/Cavity',
      'notes': 'Slight cavity detected. Scheduled restoration procedure.',
      'procedure': 'Diagnostic Examination',
      'doctor': 'Dr. Rey Vincent Bolasoc',
    },
  ];

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

    await Printing.layoutPdf(onLayout: (format) async => doc.save());
  }

  void _showExportSheet() {
    showAppDialog(
      context,
      maxHeightFactor: 0.4,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Export Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(CupertinoIcons.doc_text, color: AppColors.primary),
              title: Text('Save as PDF', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text('Generates a summary you can save or share', style: TextStyle(color: AppColors.textSecondary)),
              onTap: () {
                Navigator.pop(dialogContext);
                _exportOdontogramPdf();
              },
            ),
          ],
        ),
      ),
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
      listenable: ThemeController(),
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
                  _buildTabButton('Teeth Details', 0),
                  _buildTabButton('Treatment Notes', 1),
                  _buildTabButton('X-Rays & Files', 2),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_selectedTabIndex == 0) _buildTeethDetailsTab(),
            if (_selectedTabIndex == 1) _buildTreatmentNotesTab(),
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
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- TAB 1: INTERACTIVE ODONTOGRAM ---
  Widget _buildTeethDetailsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Interactive Odontogram',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _showToothTypesInfoSheet,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(CupertinoIcons.info_circle, color: Colors.white70, size: 17),
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(90, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _showExportSheet,
                      icon: const Icon(CupertinoIcons.square_arrow_up, size: 14),
                      label: const Text('Export', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              // Canvas Container
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _permanentTeethPill(),
                    const SizedBox(height: 14),
                    _archLabel('Upper Permanent Teeth (Maxillary)'),
                    const SizedBox(height: 6),
                    _rightLeftRow(),
                    const SizedBox(height: 2),
                    _toothRow(List.generate(16, (i) => i + 1)),
                    const SizedBox(height: 14),
                    _midlineDivider(),
                    const SizedBox(height: 14),
                    _toothRow(List.generate(16, (i) => 32 - i)),
                    const SizedBox(height: 2),
                    _rightLeftRow(),
                    const SizedBox(height: 6),
                    _archLabel('Lower Permanent Teeth (Mandibular)'),
                    const Divider(height: 28),

                    // Condition Legend
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildLegendDot('Healthy', AppColors.surface),
                        _buildLegendDot('Caries/Cavity', const Color(0xFFFFB74D)),
                        _buildLegendDot('Filled', const Color(0xFF64B5F6)),
                        _buildLegendDot('Crown', const Color(0xFFE040FB)),
                        _buildLegendDot('Missing', const Color(0xFFE57373)),
                      ],
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

  Widget _rightLeftRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _pillLabel('RIGHT', dark: true),
          _pillLabel('LEFT', dark: true),
        ],
      ),
    );
  }

  Widget _midlineDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'MIDLINE',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 1),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }

  /// One straight row of 16 teeth, numbered underneath, matching the
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

    // Unrecorded teeth stay "empty" with a teal outline; recorded ones take
    // their condition color, matching the reference odontogram chart.
    final fillColor = conditionColor?.withOpacity(0.85) ?? AppColors.surface;
    final strokeColor = isSelected
        ? AppColors.primary
        : (conditionColor ?? AppColors.primary.withOpacity(0.55));

    final tooth = CustomPaint(
      size: const Size(16, 34),
      painter: _ToothPainter(
        type: toothTypeOf(toothNum),
        rootCount: toothRootCount(toothNum),
        // Upper teeth hang down from the gum line, so their roots point up.
        rootsUp: isUpperTooth(toothNum),
        fillColor: fillColor,
        strokeColor: strokeColor,
        strokeWidth: isSelected ? 1.6 : 1.0,
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
    final matching = _allTreatmentNotes
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
              Text(
                'Treatment Notes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Tooth #$_selectedToothNumber',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (matching.isEmpty)
            Text(
              'No treatment notes recorded for Tooth #$_selectedToothNumber yet.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          else
            for (int i = 0; i < matching.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _ToothTreatmentNoteTile(
                note: matching[i],
                onTap: () => _showTreatmentNoteDetail(matching[i]),
              ),
            ],
        ],
      ),
    );
  }

  // --- TAB 2: CARDS-BASED TREATMENT NOTES ---
  Widget _buildTreatmentNotesTab() {
    return Column(
      children: _allTreatmentNotes.map((note) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showTreatmentNoteDetail(note),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          note['procedure'] ?? '',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ),
                      Text(note['date'] ?? '', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          note['tooth'] ?? '',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Condition: ${note['condition']}',
                          style: TextStyle(fontSize: 11, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(note['notes'] ?? '', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Icon(CupertinoIcons.person, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('Performed by ${note['doctor']}',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const Spacer(),
                      Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
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

  Widget _pillLabel(String text, {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: dark ? AppColors.border : Colors.white54),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: dark ? AppColors.textSecondary : Colors.white70,
          fontSize: 10,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
        ),
        const SizedBox(width: 4),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
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

enum ToothType { molar, premolar, canine, incisor }

/// Draws an anatomical tooth silhouette — a rounded crown with a cervical
/// waist plus one to three tapering roots — modelled on a printed odontogram
/// chart. [rootsUp] flips the drawing for the maxillary arch, whose roots
/// point up towards the gum line.
class _ToothPainter extends CustomPainter {
  final ToothType type;
  final int rootCount;
  final bool rootsUp;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const _ToothPainter({
    required this.type,
    required this.rootCount,
    required this.rootsUp,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (rootsUp) {
      // Mirror vertically so the crown sits at the bottom and roots reach up.
      canvas.translate(0, size.height);
      canvas.scale(1, -1);
    }

    final path = _buildPath(size);
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

    // Faint cervical line where the crown meets the roots, the detail that
    // makes the silhouette read as a tooth rather than a blob.
    final neckY = size.height * _crownHeight;
    canvas.drawLine(
      Offset(size.width * 0.24, neckY),
      Offset(size.width * 0.76, neckY),
      Paint()
        ..color = strokeColor.withOpacity(0.35)
        ..strokeWidth = strokeWidth * 0.7
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  /// Fraction of the height taken by the crown; molars have stubbier crowns
  /// and longer roots than the narrow front teeth.
  double get _crownHeight {
    switch (type) {
      case ToothType.molar:
        return 0.44;
      case ToothType.premolar:
        return 0.40;
      case ToothType.canine:
        return 0.36;
      case ToothType.incisor:
        return 0.40;
    }
  }

  /// Half-width of the crown as a fraction of the box, measured from center.
  double get _crownHalfWidth {
    switch (type) {
      case ToothType.molar:
        return 0.48;
      case ToothType.premolar:
        return 0.38;
      case ToothType.canine:
        return 0.34;
      case ToothType.incisor:
        return 0.36;
    }
  }

  Path _buildPath(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final hw = w * _crownHalfWidth;
    final neck = h * _crownHeight;
    final roots = _roots(hw, h);
    final tipHalf = w * 0.055;

    final path = Path()..moveTo(cx - hw * 0.74, h * 0.03);

    // --- Crown: the biting edge across the top. ---
    switch (type) {
      case ToothType.molar:
        // Two shallow cusps with a groove between them.
        path.quadraticBezierTo(cx - hw * 0.34, h * 0.10, cx, h * 0.05);
        path.quadraticBezierTo(cx + hw * 0.34, h * 0.10, cx + hw * 0.74, h * 0.03);
        break;
      case ToothType.premolar:
        // A single dip between two small cusps.
        path.quadraticBezierTo(cx, h * 0.11, cx + hw * 0.74, h * 0.03);
        break;
      case ToothType.canine:
        // Pointed cusp tip.
        path.quadraticBezierTo(cx - hw * 0.30, h * 0.01, cx, 0);
        path.quadraticBezierTo(cx + hw * 0.30, h * 0.01, cx + hw * 0.74, h * 0.03);
        break;
      case ToothType.incisor:
        // Flat chisel edge.
        path.lineTo(cx + hw * 0.74, h * 0.03);
        break;
    }

    // --- Right shoulder down to the neck. ---
    path.quadraticBezierTo(cx + hw, h * 0.09, cx + hw, neck * 0.60);
    path.quadraticBezierTo(cx + hw, neck * 0.93, cx + roots.last.neckRight, neck);

    // --- Roots, right to left, with a furcation notch between each pair. ---
    for (var i = roots.length - 1; i >= 0; i--) {
      final root = roots[i];
      final tipX = cx + root.tipX;
      path.quadraticBezierTo(
        cx + root.neckRight,
        (neck + root.tipY) * 0.55,
        tipX + tipHalf,
        root.tipY - h * 0.015,
      );
      path.quadraticBezierTo(tipX, root.tipY + h * 0.015, tipX - tipHalf, root.tipY - h * 0.015);
      path.quadraticBezierTo(
        cx + root.neckLeft,
        (neck + root.tipY) * 0.55,
        cx + root.neckLeft,
        neck,
      );
      if (i > 0) {
        // Notch rises into the crown so the roots read as separate prongs.
        final previous = roots[i - 1];
        path.quadraticBezierTo(
          cx + (root.neckLeft + previous.neckRight) * 0.5,
          neck - h * 0.06,
          cx + previous.neckRight,
          neck,
        );
      }
    }

    // --- Left shoulder back up to the biting edge. ---
    path.quadraticBezierTo(cx - hw, neck * 0.93, cx - hw, neck * 0.60);
    path.quadraticBezierTo(cx - hw, h * 0.09, cx - hw * 0.74, h * 0.03);
    path.close();
    return path;
  }

  /// Root geometry (offsets from the tooth's center) laid out left to right.
  List<_Root> _roots(double hw, double h) {
    switch (rootCount) {
      case 3:
        return [
          _Root(neckLeft: -hw * 0.88, neckRight: -hw * 0.34, tipX: -hw * 0.66, tipY: h * 0.93),
          _Root(neckLeft: -hw * 0.22, neckRight: hw * 0.22, tipX: 0, tipY: h),
          _Root(neckLeft: hw * 0.34, neckRight: hw * 0.88, tipX: hw * 0.66, tipY: h * 0.93),
        ];
      case 2:
        return [
          _Root(neckLeft: -hw * 0.88, neckRight: -hw * 0.12, tipX: -hw * 0.48, tipY: h * 0.98),
          _Root(neckLeft: hw * 0.12, neckRight: hw * 0.88, tipX: hw * 0.48, tipY: h * 0.98),
        ];
      default:
        return [_Root(neckLeft: -hw * 0.84, neckRight: hw * 0.84, tipX: 0, tipY: h)];
    }
  }

  @override
  bool shouldRepaint(covariant _ToothPainter oldDelegate) {
    return oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.rootCount != rootCount ||
        oldDelegate.rootsUp != rootsUp ||
        oldDelegate.type != type;
  }
}

/// One root prong of a tooth silhouette, in offsets from the tooth's center.
class _Root {
  final double neckLeft;
  final double neckRight;
  final double tipX;
  final double tipY;

  const _Root({
    required this.neckLeft,
    required this.neckRight,
    required this.tipX,
    required this.tipY,
  });
}
