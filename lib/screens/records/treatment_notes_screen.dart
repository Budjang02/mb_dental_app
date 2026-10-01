import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/app/theme_controller.dart';
import 'package:mb_dental_app/models/treatment_note.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

import 'dental_records_screen.dart';

/// A condition badge in the website's odontogram colours (css/odontogram.css),
/// the same in both themes. Aliases follow `_trnCondClass`: Cavity → Caries,
/// Filling → Filled, Other Marked → Marked.
class ConditionBadgeStyle {
  final Color fill;
  final Color border;
  final Color? text;
  final bool dashed;

  const ConditionBadgeStyle(this.fill, this.border, this.text, {this.dashed = false});

  static const _white = Colors.white;
  static const _ink = Color(0xFF0F172A);

  static const Map<String, ConditionBadgeStyle> _byKey = {
    'healthy': ConditionBadgeStyle(Color(0xFFF5F6F6), Color(0xFFCBD5E1), _ink),
    'root-canal': ConditionBadgeStyle(Color(0xFFA252EF), Color(0xFF7E22CE), _white),
    'caries': ConditionBadgeStyle(Color(0xFFFF7A00), Color(0xFFC2410C), _ink),
    'crown': ConditionBadgeStyle(Color(0xFFF59E0B), Color(0xFFB45309), _ink),
    'filled': ConditionBadgeStyle(Color(0xFF3B82F6), Color(0xFF1D4ED8), _white),
    'impacted': ConditionBadgeStyle(Color(0xFFF472B6), Color(0xFFBE185D), _ink),
    'marked': ConditionBadgeStyle(Color(0xFF14B8A6), Color(0xFF0F766E), _ink),
    'other': ConditionBadgeStyle(Color(0xFF14B8A6), Color(0xFF0F766E), _ink),
    // Theme text (null): drawn over the page.
    'missing': ConditionBadgeStyle(Color(0x4D64748B), Color(0xFF64748B), null, dashed: true),
  };

  /// Neutral, for a condition that is unknown or not recorded.
  static const neutral = ConditionBadgeStyle(Color(0x1F64748B), Color(0x6664748B), null);

  static ConditionBadgeStyle of(String condition) {
    var key = condition.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    key = const {'cavity': 'caries', 'filling': 'filled', 'other-marked': 'marked'}[key] ?? key;
    return _byKey[key] ?? neutral;
  }
}

class ConditionBadge extends StatelessWidget {
  final String condition;

  const ConditionBadge(this.condition, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = condition.trim().isEmpty ? 'Not recorded' : condition.trim();
    final style = condition.trim().isEmpty ? ConditionBadgeStyle.neutral : ConditionBadgeStyle.of(label);
    final text = style.text ?? (ThemeController().isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A));
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(999),
        border: style.dashed ? null : Border.all(color: style.border),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: text)),
    );
    if (!style.dashed) return badge;
    return CustomPaint(painter: _DashedPillPainter(style.border), child: badge);
  }
}

class _DashedPillPainter extends CustomPainter {
  final Color color;
  _DashedPillPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPillPainter old) => old.color != color;
}

/// The website's theme colours for the notes list and popup.
class _Tone {
  final bool dark = ThemeController().isDark;
  Color get dialog => dark ? const Color(0xFF0F172A) : Colors.white;
  Color get title => dark ? Colors.white : const Color(0xFF0F172A);
  Color get value => dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get muted => dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get divider => dark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
  Color get notesBg => dark ? const Color(0x661E293B) : const Color(0xFFF8FAFC);
  Color get notesText => dark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
  static const close = Color(0xFF94A3B8);
  static const chart = Color(0xFF14B8A6);
}

/// Every active treatment note, newest first, reached from the clock on the
/// Records screen. Read-only for the patient.
class TreatmentNotesScreen extends StatefulWidget {
  /// Takes the patient back to the chart they came from and points at a
  /// tooth. Null when opened from somewhere without the chart beneath it; the
  /// chart is then opened.
  final ValueChanged<String>? onViewOnChart;

  const TreatmentNotesScreen({super.key, this.onViewOnChart});

  @override
  State<TreatmentNotesScreen> createState() => _TreatmentNotesScreenState();
}

class _TreatmentNotesScreenState extends State<TreatmentNotesScreen> {
  final _repository = PatientRepository();

  @override
  void initState() {
    super.initState();
    // Opening the page reads the notes fresh: the clinic may have added,
    // edited or archived one since the record was loaded.
    unawaited(_repository.refreshTreatmentNotes(showLoading: _repository.treatmentNotes.isEmpty));
  }

  Future<void> _viewOnChart(String toothKey) async {
    final callback = widget.onViewOnChart;
    Navigator.of(context).pop(); // the notes page
    if (callback != null) {
      callback(toothKey);
    } else {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DentalRecordsScreen(focusToothKey: toothKey)));
    }
  }

  void _open(TreatmentNote note) {
    showDialog<void>(
      context: context,
      builder: (_) => _NoteDialog(noteId: note.id, initial: note, onViewOnChart: _viewOnChart),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ThemeController(), _repository]),
      builder: (context, _) {
        final tone = _Tone();
        final notes = _repository.treatmentNotes;
        final status = _repository.treatmentNotesStatus;
        final Widget body;
        if (status.hasFailed && notes.isEmpty) {
          body = _State(
            icon: FontAwesomeIcons.triangleExclamation,
            title: 'Unable to load treatment notes.',
            body: 'Please refresh the page or try again shortly.',
            action: TextButton(
              onPressed: () => _repository.refreshTreatmentNotes(showLoading: true),
              child: const Text('Retry'),
            ),
          );
        } else if (notes.isEmpty && (status.isPending || status == SectionStatus.idle)) {
          body = const _State(loading: true, title: 'Loading treatment notes…');
        } else if (notes.isEmpty) {
          body = const _State(
            icon: FontAwesomeIcons.fileLines,
            title: 'No treatment notes recorded yet.',
            body: 'Your clinical notes and procedure history will appear here after your visit.',
          );
        } else {
          body = ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _NoteRow(note: notes[i], tone: tone, onTap: () => _open(notes[i])),
          );
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Treatment Notes')),
          body: RefreshIndicator(
            onRefresh: _repository.refreshTreatmentNotes,
            child: body is ListView
                ? body
                : ListView(physics: const AlwaysScrollableScrollPhysics(), children: [body]),
          ),
        );
      },
    );
  }
}

class _State extends StatelessWidget {
  final FaIconData? icon;
  final String title;
  final String? body;
  final Widget? action;
  final bool loading;

  const _State({this.icon, required this.title, this.body, this.action, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final tone = _Tone();
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 32),
      child: Column(
        children: [
          if (loading)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else if (icon != null)
            FaIcon(icon!, size: 26, color: tone.muted),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(body!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: tone.muted)),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

/// One note in the list: date · time, the tooth and its condition once, a
/// two-line preview of the note, and who it is attributed to. The whole row
/// opens it; the chevron is only a cue.
class _NoteRow extends StatelessWidget {
  final TreatmentNote note;
  final _Tone tone;
  final VoidCallback onTap;

  const _NoteRow({required this.note, required this.tone, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = note.attribution;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: tone.divider)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [note.dateLabel, if (note.timeLabel.isNotEmpty) note.timeLabel].join(' · '),
                      style: TextStyle(fontSize: 12, color: tone.muted),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 15, color: tone.muted),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Tooth ${note.toothLabel}',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: tone.value)),
                    ConditionBadge(note.condition),
                  ],
                ),
              ),
              if (note.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(note.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, height: 1.4, color: tone.notesText)),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                a.staffOnly ? 'Recorded by ${a.primary}' : a.primary,
                style: TextStyle(fontSize: 12, color: tone.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The website's Treatment Notes viewer: a fixed title, Condition / Date /
/// Tooth number / Doctor rows, the full note in its own panel, and View on
/// Chart. Follows the note by id, so a clinic edit updates it and an archive
/// says so.
class _NoteDialog extends StatelessWidget {
  final String noteId;
  final TreatmentNote initial;
  final ValueChanged<String> onViewOnChart;

  const _NoteDialog({required this.noteId, required this.initial, required this.onViewOnChart});

  @override
  Widget build(BuildContext context) {
    final repository = PatientRepository();
    return ListenableBuilder(
      listenable: Listenable.merge([repository, ThemeController()]),
      builder: (context, _) {
        final tone = _Tone();
        TreatmentNote? live;
        for (final n in repository.treatmentNotes) {
          if (n.id == noteId) live = n;
        }
        final gone = live == null && repository.treatmentNotesStatus == SectionStatus.ready;
        final note = live ?? initial;
        final width = MediaQuery.sizeOf(context).width;
        final pad = width < 380 ? 20.0 : 24.0;
        final key = note.toothKey;

        Widget row(String label, Widget value) => Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tone.divider))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(label.toUpperCase(),
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: tone.muted)),
                  ),
                  Expanded(child: value),
                ],
              ),
            );
        TextStyle valueStyle() => TextStyle(fontSize: 14, color: tone.value);

        return Dialog(
          backgroundColor: tone.dialog,
          insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, pad - 8, pad - 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Treatment Notes',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: tone.title)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const FaIcon(FontAwesomeIcons.xmark, size: 16, color: _Tone.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (gone)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'The clinic has removed or archived this note. It is shown as it was when you opened it.',
                              style: TextStyle(fontSize: 12.5, color: tone.value),
                            ),
                          ),
                        row('Condition', Align(alignment: Alignment.centerLeft, child: ConditionBadge(note.condition))),
                        row(
                          'Date',
                          Text.rich(
                            TextSpan(text: note.dateLabel, children: [
                              if (note.timeLabel.isNotEmpty)
                                TextSpan(text: '  ${note.timeLabel}', style: TextStyle(color: tone.muted)),
                            ]),
                            style: valueStyle(),
                          ),
                        ),
                        row('Tooth number', Text(note.toothLabel, style: valueStyle())),
                        row(
                          note.attribution.staffOnly ? 'Recorded by' : 'Doctor',
                          Text(note.attribution.primary, style: valueStyle()),
                        ),
                        const SizedBox(height: 14),
                        Text('NOTES',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: tone.muted)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tone.notesBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tone.divider),
                          ),
                          child: SelectableText(
                            note.notes.trim().isEmpty ? '—' : note.notes,
                            style: TextStyle(fontSize: 14, height: 1.625, color: tone.notesText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 16, pad, pad),
                  child: Tooltip(
                    message: key.isEmpty ? 'This note is not linked to a tooth' : '',
                    child: ElevatedButton(
                      onPressed: key.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              onViewOnChart(key);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Tone.chart,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _Tone.chart.withValues(alpha: 0.4),
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('View on Chart', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
