import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/data/clinic_catalog.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/patient_document.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
import 'dental_arch_chart.dart';
import 'document_viewer_screen.dart';
import 'tooth_glyphs.dart';
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

/// Tooth fill per condition, the exact values in the website's
/// css/odontogram.css. An unmarked tooth is Healthy, as it is on the website.
const Map<String, Color> kToothConditionColors = {
  'Healthy': Color(0xFFD1FAE5),
  'Caries/Cavity': Color(0xFFFEF3C7),
  'Filled': Color(0xFFDBEAFE),
  'Crown': Color(0xFFF3E8FF),
  'Missing': Color(0xFFFEE2E2),
  'Root Canal': Color(0xFFFFF7ED),
  'Impacted': Color(0xFFFCE7F3),
  'Other': Color(0xFFE0E7FF),
};

/// Outline and label colour per condition, the exact values in the website's
/// css/odontogram.css.
const Map<String, Color> kToothConditionStrokes = {
  'Healthy': Color(0xFF10B981),
  'Caries/Cavity': Color(0xFFF59E0B),
  'Filled': Color(0xFF3B82F6),
  'Crown': Color(0xFFA855F7),
  'Missing': Color(0xFFEF4444),
  'Root Canal': Color(0xFFEA580C),
  'Impacted': Color(0xFFEC4899),
  'Other': Color(0xFF6366F1),
};

/// Conditions whose outline is dashed (`stroke-dasharray: 3 2`). Missing is
/// the only one on the website; every other outline is solid.
const Set<String> kToothDashedConditions = {'Missing'};

/// The condition name [kToothConditionColors] is keyed by, for however the
/// row spells it.
///
/// Case-insensitive on purpose: the lookup used to be exact, so a row saying
/// "crown", "Caries" or "Root canal" matched nothing and every such tooth was
/// painted with the catch-all swatch. An empty condition is Healthy.
String canonicalToothCondition(String raw) {
  switch (raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_]+'), ' ')) {
    case '':
    case 'healthy':
      return 'Healthy';
    case 'caries':
    case 'cavity':
    case 'caries/cavity':
      return 'Caries/Cavity';
    case 'filled':
      return 'Filled';
    case 'crown':
      return 'Crown';
    case 'missing':
      return 'Missing';
    case 'root canal':
      return 'Root Canal';
    case 'impacted':
      return 'Impacted';
    default:
      return 'Other';
  }
}

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

  /// The file currently being opened, so only its row shows a spinner.
  String? _openingDocumentId;

  /// What the clinic has currently recorded against each tooth, read from the
  /// patient's own chart.
  ///
  /// One entry per tooth: `tooth_records` comes back newest first, so the first
  /// row for a tooth is its present state and any earlier row for the same
  /// tooth is history the chart does not paint.
  Map<int, Map<String, dynamic>> get _toothConditions {
    final current = <int, Map<String, dynamic>>{};
    for (final record in PatientRepository().toothRecords) {
      final tooth = toothNumberOf(record['tooth'] ?? '');
      if (tooth == null) continue;
      if (current.containsKey(tooth)) continue;

      final condition = canonicalToothCondition(record['condition'] ?? '');
      current[tooth] = {
        'condition': condition,
        'color': kToothConditionColors[condition]!,
        'stroke': kToothConditionStrokes[condition]!,
        'notes': record['notes'] ?? '',
        'date': record['date'] ?? '',
        'doctor': record['doctor'] ?? '',
      };
    }
    return current;
  }

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
            pw.Text(kClinicName),
            if (kClinicAddress.isNotEmpty) pw.Text(kClinicAddress),
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
                headers: ['Tooth #', 'Name', 'Condition', 'Doctor', 'Recorded', 'Notes'],
                data: rows
                    .map((e) => [
                          '#${e.key}',
                          toothName(e.key),
                          e.value['condition'].toString(),
                          doctorLabel(e.value['doctor'] as String?),
                          e.value['date'].toString(),
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
        actions: [
          IconButton(
            tooltip: 'Treatment history',
            icon: Icon(CupertinoIcons.clock, color: AppColors.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TreatmentNotesScreen()),
            ),
          ),
        ],
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
                            // The Print Chart button beside this column takes
                            // its width first, so the subtitle has to be able
                            // to give — a large text scale overflowed it.
                            Flexible(
                              child: Text(
                                'Universal Numbering',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                              ),
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
                      // A tooth with no row is Healthy, as on the website.
                      idleFill: kToothConditionColors['Healthy']!,
                      idleStroke: kToothConditionStrokes['Healthy']!,
                      conditionStrokes: {
                        for (final entry in _toothConditions.entries)
                          entry.key: entry.value['stroke'] as Color,
                      },
                      dashedTeeth: {
                        for (final entry in _toothConditions.entries)
                          if (kToothDashedConditions.contains(entry.value['condition'])) entry.key,
                      },
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

  // --- TAB 3: X-RAYS & FILES ---
  /// The X-rays, prescriptions and other files the clinic holds for this
  /// patient, newest first.
  ///
  /// The files themselves are private in storage, so nothing here is a direct
  /// link — tapping a row asks for a short-lived signed URL and opens that.
  Widget _buildXRaysAndFilesTab() {
    final documents = PatientRepository().documents;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'X-Rays & Files',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ),
              if (documents.isNotEmpty)
                Text(
                  '${documents.length} file${documents.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (documents.isEmpty)
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
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Files your dentist uploads will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            )
          else
            for (int i = 0; i < documents.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _PatientFileRow(
                document: documents[i],
                previewUrl: PatientRepository().previewUrlFor(documents[i]),
                isOpening: _openingDocumentId == documents[i].id,
                onTap: () => _openDocument(documents[i]),
              ),
            ],
        ],
      ),
    );
  }

  /// Opens a file. Anything the app can draw — an X-ray image or a PDF — is
  /// shown in [DocumentViewerScreen]; anything else is handed to the device.
  Future<void> _openDocument(PatientDocument document) async {
    if (document.isPreviewable) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentViewerScreen(document: document)),
      );
      return;
    }

    if (_openingDocumentId != null) return;
    setState(() => _openingDocumentId = document.id);

    try {
      final url = await PatientRepository().documentUrl(document);
      if (!mounted) return;
      if (url == null) {
        showAppToast(context, 'That file is not available to open.', isError: true);
        return;
      }
      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        showAppToast(context, 'No app on this device can open that file.', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'We could not open that file. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _openingDocumentId = null);
    }
  }

  /// What the tooth is and what the clinic currently has recorded against it,
  /// opened by tapping its crown. This is where the chart's colours get named,
  /// now that no legend sits under the arch.
  ///
  /// Shows the present state only. The full history per tooth lives under
  /// Treatment Notes, so repeating it here just buried the one line a patient
  /// opens this dialog to read.
  void _showToothDetail(int tooth) {
    final info = _toothConditions[tooth];
    final condition = (info?['condition'] as String?) ?? 'Healthy';
    final swatch = (info?['color'] as Color?) ?? kToothConditionColors[condition]!;
    final stroke = (info?['stroke'] as Color?) ?? kToothConditionStrokes[condition]!;
    final clinicalNote = (info?['notes'] as String?)?.trim() ?? '';
    final recordedOn = (info?['date'] as String?)?.trim() ?? '';
    final recordedBy = (info?['doctor'] as String?)?.trim() ?? '';

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
                    border: Border.all(color: stroke),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: stroke),
                  ),
                  child: Text(
                    condition,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: stroke),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _kv('Tooth', '#$tooth'),
            _kv('Name', toothName(tooth)),
            _kv('Type', _toothTypeLabel(tooth)),
            _kv('Condition', condition),
            if (recordedOn.isNotEmpty) _kv('Last updated', recordedOn),
            if (recordedBy.isNotEmpty) _kv('Doctor', recordedBy),
            if (clinicalNote.isNotEmpty) _kv('Clinical note', clinicalNote),
            if (info == null) ...[
              const SizedBox(height: 4),
              Text(
                'Your dentist has not recorded anything for this tooth yet.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
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
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(kDoctorIcon, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            doctorLabel(item.doctorName),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
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
            _kv('Doctor', doctorLabel(item.doctorName)),
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

/// One file in the X-Rays & Files list.
class _PatientFileRow extends StatelessWidget {
  final PatientDocument document;

  /// Signed link for the thumbnail, when one has been fetched. Null falls back
  /// to the kind icon rather than leaving a hole in the row.
  final String? previewUrl;

  final bool isOpening;
  final VoidCallback onTap;

  const _PatientFileRow({
    required this.document,
    required this.previewUrl,
    required this.isOpening,
    required this.onTap,
  });

  /// A thumbnail of the file itself where the app can draw one, otherwise the
  /// icon for its kind. An X-ray is far easier to pick out of a list by sight
  /// than by filename.
  Widget _thumbnail() {
    final url = previewUrl;
    if (document.isImage && url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          // A broken or expired link must not blank the row.
          errorBuilder: (context, _, __) => _iconTile(),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : SizedBox(
                  width: 52,
                  height: 52,
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                ),
        ),
      );
    }
    return _iconTile();
  }

  Widget _iconTile() {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(document.kind.icon, size: 20, color: AppColors.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isOpening ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _thumbnail(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        document.kind.label,
                        _formatPlanDate(document.uploadedOn),
                        if (document.sizeLabel.isNotEmpty) document.sizeLabel,
                      ].join(' • '),
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                    // Who put the file on the record. Blank for files the
                    // patient uploaded themselves, which need no attribution.
                    if (document.uploadedBy.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(kDoctorIcon, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              document.uploadedBy,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isOpening)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              else
                Icon(
                  document.isPreviewable
                      ? CupertinoIcons.eye
                      : CupertinoIcons.arrow_up_right_square,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
