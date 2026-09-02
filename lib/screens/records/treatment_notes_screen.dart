import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';
import 'treatment_notes_data.dart';

/// Full treatment history, reached from the clock control on the dental
/// chart's Treatment Notes card.
class TreatmentNotesScreen extends StatelessWidget {
  const TreatmentNotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController(),
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Treatment Notes')),
        body: kTreatmentNotes.isEmpty
            ? Center(
                child: Text(
                  'No treatment notes recorded yet.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Every procedure on record, newest first.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  for (final note in kTreatmentNotes) ...[
                    _TreatmentNoteCard(
                      note: note,
                      onTap: () => _showNoteDetail(context, note),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
    );
  }

  void _showNoteDetail(BuildContext context, Map<String, String> note) {
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
            child: Text(value,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _TreatmentNoteCard extends StatelessWidget {
  final Map<String, String> note;
  final VoidCallback onTap;

  const _TreatmentNoteCard({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                const SizedBox(height: 10),
                Text(
                  note['notes'] ?? '',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                ),
                const SizedBox(height: 10),
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
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
