import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Export Records', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            ListTile(
              leading: Icon(CupertinoIcons.doc_text, color: AppColors.primary),
              title: const Text('Save as PDF'),
              subtitle: const Text('Generates a summary you can save or share'),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportOdontogramPdf();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showToothTypesInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tooth Types', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.textPrimary)),
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
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(dialogContext).size.height * 0.82),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => Navigator.pop(dialogContext),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: AppColors.textSecondary),
                    ),
                  ),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Records'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          children: [
            // Segmented Tab Switcher
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
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
    );
  }

  Widget _buildTabButton(String label, int index) {
    final bool isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white,
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
    );
  }

  // --- TAB 1: INTERACTIVE ODONTOGRAM ---
  Widget _buildTeethDetailsTab() {
    final activeInfo = _toothConditions[_selectedToothNumber];

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
                        GestureDetector(
                          onTap: _showToothTypesInfoSheet,
                          child: const Icon(CupertinoIcons.info_circle, color: Colors.white70, size: 17),
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
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildArch(isUpper: true),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _pillLabel('Left', dark: true),
                          _pillLabel('Right', dark: true),
                        ],
                      ),
                    ),
                    _buildArch(isUpper: false),
                    const Divider(height: 28),

                    // Condition Legend
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildLegendDot('Healthy', Colors.white),
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

        // Selected Tooth Diagnostic Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tooth #$_selectedToothNumber',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          toothName(_selectedToothNumber),
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (activeInfo?['color'] ?? AppColors.success).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      activeInfo?['condition'] ?? 'Healthy',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: activeInfo?['color'] ?? AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                activeInfo?['notes'] ?? 'No specific clinical notes recorded for this tooth.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
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
            color: Colors.white,
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
                          color: Colors.grey.shade100,
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
        color: Colors.white,
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
                Icon(CupertinoIcons.tray, size: 36, color: Colors.grey.shade400),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Horseshoe-shaped dental arch: teeth are placed along a half-ellipse so
  /// the chart reads like a real jaw viewed from the front, front teeth at
  /// the peak of the curve and molars trailing off toward the sides.
  Widget _buildArch({required bool isUpper}) {
    final numbers = isUpper ? List.generate(16, (i) => i + 1) : List.generate(16, (i) => 32 - i);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width * 0.52;
        final radiusX = width / 2 - 22;
        final radiusY = height - 52;
        final centerY = isUpper ? height : 0.0;

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFF37474F),
                  borderRadius: isUpper
                      ? BorderRadius.vertical(top: Radius.elliptical(width / 2, height))
                      : BorderRadius.vertical(bottom: Radius.elliptical(width / 2, height)),
                ),
              ),
              Positioned(
                top: isUpper ? 12 : null,
                bottom: isUpper ? null : 12,
                left: 0,
                right: 0,
                child: Center(child: _pillLabel('Front')),
              ),
              Positioned(
                top: isUpper ? height * 0.44 : null,
                bottom: isUpper ? null : height * 0.44,
                left: 0,
                right: 0,
                child: Center(child: _pillLabel(isUpper ? 'Upper' : 'Lower')),
              ),
              for (int i = 0; i < numbers.length; i++)
                _buildToothAtAngle(
                  toothNum: numbers[i],
                  angleDeg: 180 - i * (180 / (numbers.length - 1)),
                  centerX: width / 2,
                  centerY: centerY,
                  radiusX: radiusX,
                  radiusY: radiusY,
                  isUpper: isUpper,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToothAtAngle({
    required int toothNum,
    required double angleDeg,
    required double centerX,
    required double centerY,
    required double radiusX,
    required double radiusY,
    required bool isUpper,
  }) {
    final rad = angleDeg * math.pi / 180;
    final dx = centerX + radiusX * math.cos(rad);
    final dy = isUpper ? centerY - radiusY * math.sin(rad) : centerY + radiusY * math.sin(rad);
    final rotation = isUpper ? (90 - angleDeg) * math.pi / 180 : (angleDeg - 90) * math.pi / 180;

    final isSelected = _selectedToothNumber == toothNum;
    final info = _toothConditions[toothNum];
    final fillColor = info?['color'] as Color? ?? Colors.white;
    final isMolar = toothTypeOf(toothNum) == ToothType.molar;
    final toothWidth = isMolar ? 23.0 : 16.0;
    const toothHeight = 26.0;

    return Positioned(
      left: dx - toothWidth / 2,
      top: dy - toothHeight / 2,
      child: Transform.rotate(
        angle: rotation,
        child: GestureDetector(
          onTap: () => setState(() => _selectedToothNumber = toothNum),
          child: Container(
            width: toothWidth,
            height: toothHeight,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.black.withOpacity(0.18),
                width: isSelected ? 2.5 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 6)]
                  : null,
            ),
          ),
        ),
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
            border: Border.all(color: Colors.grey.shade400),
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

enum ToothType { molar, premolar, canine, incisor }
