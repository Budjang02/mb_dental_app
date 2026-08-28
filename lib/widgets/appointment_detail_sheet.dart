import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/screens/appointments/reschedule_appointment_screen.dart';
import 'package:mb_dental_app/widgets/app_dialog.dart';

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatAppointmentDate(DateTime date) => '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

/// "Scheduled" is the patient-facing term for a freshly booked appointment
/// that hasn't been confirmed by the clinic yet.
String statusLabel(AppointmentStatus status) {
  switch (status) {
    case AppointmentStatus.pending:
      return 'Scheduled';
    case AppointmentStatus.confirmed:
      return 'Confirmed';
    case AppointmentStatus.completed:
      return 'Completed';
    case AppointmentStatus.cancelled:
      return 'Cancelled';
  }
}

Color statusColor(AppointmentStatus status) {
  switch (status) {
    case AppointmentStatus.pending:
      return AppColors.warning;
    case AppointmentStatus.confirmed:
      return AppColors.success;
    case AppointmentStatus.completed:
      return AppColors.primary;
    case AppointmentStatus.cancelled:
      return AppColors.error;
  }
}

void showAppointmentDetailSheet(BuildContext context, Appointment appointment) {
  final bool isCancellable =
      appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed;

  showAppDialog(
    context,
    builder: (dialogContext) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    appointment.serviceName,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
                const AppDialogCloseButton(),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor(appointment.status).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel(appointment.status),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor(appointment.status)),
              ),
            ),
            const SizedBox(height: 20),
            _detailRow(CupertinoIcons.person, 'Dentist', appointment.doctorName),
            const SizedBox(height: 14),
            _detailRow(CupertinoIcons.calendar, 'Date', formatAppointmentDate(appointment.date)),
            const SizedBox(height: 14),
            _detailRow(CupertinoIcons.clock, 'Time', appointment.timeSlot),
            if (appointment.notes != null && appointment.notes!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _detailRow(CupertinoIcons.doc_text, 'Notes', appointment.notes!),
            ],
            if (appointment.status == AppointmentStatus.cancelled &&
                appointment.cancellationReason != null &&
                appointment.cancellationReason!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _detailRow(CupertinoIcons.exclamationmark_circle, 'Cancellation Reason', appointment.cancellationReason!),
            ],
            if (isCancellable) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          // Route through the dialog's own Navigator, not the
                          // caller's context — a caller like the Dashboard's
                          // Next Appointment card switches tabs (and disposes
                          // itself) the moment the dialog opens, which would
                          // leave `context` stale by the time this button is
                          // actually tapped.
                          final navigator = Navigator.of(dialogContext);
                          navigator.pop();
                          navigator.push(
                            MaterialPageRoute(
                              builder: (_) => RescheduleAppointmentScreen(appointment: appointment),
                            ),
                          );
                        },
                        child: const Text('Reschedule', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _confirmCancel(dialogContext, appointment),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}

Widget _detailRow(IconData icon, String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    ],
  );
}

/// Preset cancellation reasons the patient picks from, so the clinic gets
/// consistent answers instead of free text. "Other" is the one entry that
/// opens a text field.
const List<String> _cancellationReasons = [
  'Schedule conflict',
  'Feeling unwell',
  'Financial reasons',
  'Travelling / out of town',
  'Booked by mistake',
  'Other',
];

const String _otherReason = 'Other';

void _confirmCancel(BuildContext sheetContext, Appointment appointment) {
  final otherController = TextEditingController();
  String? selectedReason;
  var showError = false;

  showAppDialog(
    sheetContext,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final needsDetail = selectedReason == _otherReason;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(CupertinoIcons.exclamationmark_triangle, color: AppColors.error, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cancel Appointment?',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                  const AppDialogCloseButton(),
                ],
              ),
              const SizedBox(height: 14),

              // What is being cancelled, so the patient can double-check.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.serviceName,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(CupertinoIcons.calendar, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${formatAppointmentDate(appointment.date)} at ${appointment.timeSlot}',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  children: const [
                    TextSpan(text: 'Reason for cancelling'),
                    TextSpan(text: ' *', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // The reason list box: tap one, no typing needed.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: showError && selectedReason == null ? AppColors.error : AppColors.border,
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _cancellationReasons.length; i++)
                      _ReasonOption(
                        label: _cancellationReasons[i],
                        isSelected: selectedReason == _cancellationReasons[i],
                        isFirst: i == 0,
                        isLast: i == _cancellationReasons.length - 1,
                        onTap: () => setDialogState(() {
                          selectedReason = _cancellationReasons[i];
                          showError = false;
                        }),
                      ),
                  ],
                ),
              ),

              if (needsDetail) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: otherController,
                  maxLines: 2,
                  onChanged: (_) {
                    if (showError) setDialogState(() => showError = false);
                  },
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Tell us briefly why',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    fillColor: AppColors.background,
                  ),
                ),
              ],

              if (showError) ...[
                const SizedBox(height: 8),
                Text(
                  needsDetail ? 'Please describe your reason.' : 'Please choose a reason.',
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Keep It', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final detail = otherController.text.trim();
                          if (selectedReason == null || (needsDetail && detail.isEmpty)) {
                            setDialogState(() => showError = true);
                            return;
                          }
                          PatientRepository().cancelAppointment(
                            appointment.id,
                            reason: needsDetail ? detail : selectedReason!,
                          );
                          Navigator.pop(dialogContext);
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Cancel It', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// One row of the cancellation-reason list box, with a radio indicator.
class _ReasonOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  const _ReasonOption({
    required this.label,
    required this.isSelected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 13 : 0),
      bottom: Radius.circular(isLast ? 13 : 0),
    );

    return Material(
      color: isSelected ? AppColors.primary.withOpacity(0.08) : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? CupertinoIcons.largecircle_fill_circle : CupertinoIcons.circle,
                size: 19,
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
