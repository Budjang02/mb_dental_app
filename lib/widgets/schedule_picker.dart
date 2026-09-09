import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/clinic_catalog.dart';
import '../repositories/patient_repository.dart';

/// The "when" decision, in two cards: pick the day, then pick the time.
///
/// The time card only exists once a day is chosen. Showing an empty band
/// stepper over an empty chip grid asked the patient to answer the second
/// question before the first, and the answer changed as soon as they did.
///
/// Both headers are the same control — a label between two arrows — so the
/// calendar and the time band are navigated the same way, and neither needs a
/// caption to explain itself.
///
/// Shared by the patient booking wizard and the reschedule screen, and it is
/// the same widget the web build renders, so the two stay in step by
/// construction rather than by discipline.
class SchedulePicker extends StatefulWidget {
  /// Chair time the visit needs. Only starts with this much continuous room
  /// before closing are ever offered.
  final int durationMinutes;

  final DateTime? selectedDate;
  final int? selectedStartMinute;

  /// Earliest and latest selectable day, inclusive.
  final DateTime firstDay;
  final DateTime lastDay;

  /// Reads availability. Kept as a callback rather than a repository handle so
  /// reschedule can exclude the appointment being moved from its own conflict
  /// check.
  final bool Function(DateTime day) hasOpenSlot;
  final List<SlotOption> Function(DateTime day) slotsFor;

  final ValueChanged<DateTime> onDateSelected;

  /// Null when the patient taps the selected chip again to clear it.
  final ValueChanged<int?> onSlotSelected;

  const SchedulePicker({
    super.key,
    required this.durationMinutes,
    required this.selectedDate,
    required this.selectedStartMinute,
    required this.firstDay,
    required this.lastDay,
    required this.hasOpenSlot,
    required this.slotsFor,
    required this.onDateSelected,
    required this.onSlotSelected,
  });

  @override
  State<SchedulePicker> createState() => _SchedulePickerState();
}

class _SchedulePickerState extends State<SchedulePicker> {
  /// First of the month on screen.
  late DateTime _month;

  TimeOfDayBand _band = TimeOfDayBand.morning;

  @override
  void initState() {
    super.initState();
    final anchor = widget.selectedDate ?? widget.firstDay;
    _month = DateTime(anchor.year, anchor.month);
    _band = _bandForSelection() ?? TimeOfDayBand.morning;
  }

  @override
  void didUpdateWidget(SchedulePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow a selection made elsewhere (a restored draft, or the slot-taken
    // bounce on submit) so the calendar is never showing a different month
    // from the date that is actually selected.
    final date = widget.selectedDate;
    if (date != null && date != oldWidget.selectedDate && !_isVisible(date)) {
      _month = DateTime(date.year, date.month);
    }
  }

  TimeOfDayBand? _bandForSelection() {
    final minute = widget.selectedStartMinute;
    return minute == null ? null : bandFor(minute);
  }

  bool _isVisible(DateTime day) => _month.year == day.year && _month.month == day.month;

  /// The arrows stop at the edges of the bookable range rather than stepping
  /// into months where nothing can be picked.
  bool get _canGoBack =>
      _month.isAfter(DateTime(widget.firstDay.year, widget.firstDay.month));

  bool get _canGoForward =>
      _month.isBefore(DateTime(widget.lastDay.year, widget.lastDay.month));

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _shiftBand(int delta) {
    final next = _band.index + delta;
    if (next < 0 || next >= TimeOfDayBand.values.length) return;
    setState(() => _band = TimeOfDayBand.values[next]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: _stepperBar(
                label: '${_monthNames[_month.month - 1]} ${_month.year}',
                backEnabled: _canGoBack,
                forwardEnabled: _canGoForward,
                backLabel: 'Previous month',
                forwardLabel: 'Next month',
                onBack: () => _shiftMonth(-1),
                onForward: () => _shiftMonth(1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _monthGrid(_month),
            ),
          ],
        ),
        if (widget.selectedDate != null) ...[
          const SizedBox(height: 14),
          _card(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: _stepperBar(
                  label: _band.label,
                  backEnabled: _band.index > 0,
                  forwardEnabled: _band.index < TimeOfDayBand.values.length - 1,
                  backLabel: 'Earlier in the day',
                  forwardLabel: 'Later in the day',
                  onBack: () => _shiftBand(-1),
                  onForward: () => _shiftBand(1),
                ),
              ),
              Divider(color: AppColors.border, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: _slotSection(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  // --- Headers ---

  /// `<  September 2026  >` and `<  Morning: 10:00 AM - 11:45 AM  >`: the same
  /// control twice, so a patient learns one gesture for both axes.
  Widget _stepperBar({
    required String label,
    required bool backEnabled,
    required bool forwardEnabled,
    required String backLabel,
    required String forwardLabel,
    required VoidCallback onBack,
    required VoidCallback onForward,
  }) {
    return Row(
      children: [
        _arrow(
          icon: CupertinoIcons.chevron_left,
          enabled: backEnabled,
          semanticLabel: backLabel,
          onTap: onBack,
        ),
        Expanded(
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        _arrow(
          icon: CupertinoIcons.chevron_right,
          enabled: forwardEnabled,
          semanticLabel: forwardLabel,
          onTap: onForward,
        ),
      ],
    );
  }

  Widget _arrow({
    required IconData icon,
    required bool enabled,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            // Still a 32pt target even though nothing is drawn around it.
            height: 32,
            width: 32,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? AppColors.primary : AppColors.textSecondary.withOpacity(0.4),
            ),
          ),
        ),
      ),
    );
  }

  // --- Calendar ---

  Widget _monthGrid(DateTime month) {
    final firstOfMonth = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Sunday-first, matching the calendar on the Appointments tab.
    final leadingBlanks = firstOfMonth.weekday % 7;
    final cells = <Widget>[
      for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++)
        _dayCell(DateTime(month.year, month.month, day)),
    ];
    // Only the rows this month actually occupies. Padding to a fixed six kept
    // every month the same height, but left a blank row under the five-row
    // ones — more dead space than the shift it was avoiding.
    final rows = (cells.length / 7).ceil();
    while (cells.length < rows * 7) {
      cells.add(const SizedBox.shrink());
    }

    return Column(
      children: [
        Row(
          children: [
            for (final letter in _weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: AspectRatio(aspectRatio: 1, child: cells[row * 7 + col]),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime day) {
    final isSelected = widget.selectedDate != null && _isSameDay(day, widget.selectedDate!);
    final isToday = _isSameDay(day, DateTime.now());

    final inRange = !day.isBefore(_dateOnly(widget.firstDay)) &&
        !day.isAfter(_dateOnly(widget.lastDay));
    // Closed days and days with nothing left to book are both dead ends, so
    // they look and behave the same.
    final selectable = inRange && isClinicOpenOn(day) && widget.hasOpenSlot(day);

    final Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (!selectable) {
      textColor = AppColors.textSecondary.withOpacity(0.35);
    } else if (isToday) {
      textColor = AppColors.primary;
    } else {
      textColor = AppColors.textPrimary;
    }

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: selectable ? () => widget.onDateSelected(day) : null,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppColors.primary
                  : (isToday && selectable ? AppColors.primary.withOpacity(0.14) : null),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Slots ---

  /// Bookable starts inside [band] for the selected day. Anything taken, too
  /// close to closing, or outside the band never reaches the UI.
  List<int> _availableStarts(TimeOfDayBand band) {
    final date = widget.selectedDate;
    if (date == null) return const [];
    return widget
        .slotsFor(date)
        .where((slot) => slot.isAvailable && band.contains(slot.startMinute))
        .map((slot) => slot.startMinute)
        .toList();
  }

  Widget _slotSection() {
    final starts = _availableStarts(_band);
    if (starts.isEmpty) {
      return _notice('Nothing free this ${_bandLower(_band)}.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 10.0;
            // Chips stay ~100px wide, so the grid widens on the web build
            // instead of stretching three chips across a desktop card.
            final columns = (constraints.maxWidth / 110).floor().clamp(3, 6);
            final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final start in starts)
                  SizedBox(width: itemWidth, child: _slotChip(start)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _slotChip(int startMinute) {
    final isSelected = widget.selectedStartMinute == startMinute;

    return Material(
      color: isSelected ? AppColors.primary : AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onSlotSelected(isSelected ? null : startMinute),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Text(
            formatMinuteOfDay(startMinute),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notice(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary),
      ),
    );
  }

  static String _bandLower(TimeOfDayBand band) => band.label.toLowerCase();

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dateOnly(DateTime day) => DateTime(day.year, day.month, day.day);

  static const List<String> _weekdayLetters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}
