import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';

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
                    const Text(
                      'Interactive Odontogram',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(100, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Generating PDF report...'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                      label: const Text(
                        'Save as PDF',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
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
                    const Text('Upper Arch (Teeth 1 - 16)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(16, (i) => _buildAnatomicalTooth(i + 1)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Lower Arch (Teeth 17 - 32)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(16, (i) => _buildAnatomicalTooth(32 - i)),
                      ),
                    ),
                    const Divider(height: 24),

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
                  Text(
                    'Selected: Tooth #$_selectedToothNumber',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
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
              const SizedBox(height: 8),
              Text(
                activeInfo?['notes'] ?? 'No specific clinical notes recorded for this tooth.',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
                  Text(
                    note['procedure'] ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    note['date'] ?? '',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
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
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                note['notes'] ?? '',
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
              const Divider(height: 20),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Attending: ${note['doctor']}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
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
          const Text(
            'X - Rays & Files',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'Uploaded File',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Anatomical Tooth Renderer
  Widget _buildAnatomicalTooth(int toothNum) {
    final isSelected = _selectedToothNumber == toothNum;
    final info = _toothConditions[toothNum];
    final fillColor = info?['color'] ?? Colors.white;

    ToothType toothType;
    if ([1, 2, 3, 14, 15, 16, 17, 18, 19, 30, 31, 32].contains(toothNum)) {
      toothType = ToothType.molar;
    } else if ([4, 5, 12, 13, 20, 21, 28, 29].contains(toothNum)) {
      toothType = ToothType.premolar;
    } else if ([6, 11, 22, 27].contains(toothNum)) {
      toothType = ToothType.canine;
    } else {
      toothType = ToothType.incisor;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedToothNumber = toothNum),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            CustomPaint(
              size: Size(toothType == ToothType.molar ? 22 : 16, 28),
              painter: AnatomicalToothPainter(
                fillColor: fillColor,
                borderColor: isSelected ? AppColors.primary : Colors.grey.shade400,
                borderWidth: isSelected ? 2.5 : 1.0,
                type: toothType,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$toothNum',
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
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
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

enum ToothType { molar, premolar, canine, incisor }

class AnatomicalToothPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final ToothType type;

  AnatomicalToothPainter({
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    required this.type,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintFill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final paintBorder = Paint()
      ..color = borderColor
      ..strokeWidth = borderWidth
      ..style = PaintingStyle.stroke;

    final path = Path();

    switch (type) {
      case ToothType.molar:
        path.moveTo(size.width * 0.1, size.height * 0.2);
        path.quadraticBezierTo(size.width * 0.3, 0, size.width * 0.5, size.height * 0.1);
        path.quadraticBezierTo(size.width * 0.7, 0, size.width * 0.9, size.height * 0.2);
        path.lineTo(size.width, size.height * 0.5);
        path.lineTo(size.width * 0.8, size.height);
        path.lineTo(size.width * 0.5, size.height * 0.7);
        path.lineTo(size.width * 0.2, size.height);
        path.lineTo(0, size.height * 0.5);
        path.close();
        break;

      case ToothType.premolar:
        path.moveTo(size.width * 0.2, size.height * 0.15);
        path.quadraticBezierTo(size.width * 0.5, 0, size.width * 0.8, size.height * 0.15);
        path.lineTo(size.width * 0.9, size.height * 0.5);
        path.lineTo(size.width * 0.6, size.height);
        path.lineTo(size.width * 0.4, size.height);
        path.lineTo(size.width * 0.1, size.height * 0.5);
        path.close();
        break;

      case ToothType.canine:
        path.moveTo(size.width * 0.5, 0);
        path.lineTo(size.width, size.height * 0.35);
        path.lineTo(size.width * 0.7, size.height);
        path.lineTo(size.width * 0.3, size.height);
        path.lineTo(0, size.height * 0.35);
        path.close();
        break;

      case ToothType.incisor:
        path.moveTo(size.width * 0.1, size.height * 0.05);
        path.lineTo(size.width * 0.9, size.height * 0.05);
        path.lineTo(size.width * 0.8, size.height * 0.45);
        path.lineTo(size.width * 0.55, size.height);
        path.lineTo(size.width * 0.45, size.height);
        path.lineTo(size.width * 0.2, size.height * 0.45);
        path.close();
        break;
    }

    canvas.drawPath(path, paintFill);
    canvas.drawPath(path, paintBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}