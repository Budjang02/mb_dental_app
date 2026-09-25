import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/messages.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_api.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/app_toast.dart';
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

/// The reasons offered in the Cancel dialog — the website's list, and the
/// twin of the one `cancel_my_appointment()` knows. "Other" adds a short note,
/// sent as `Other: <note>`.
const List<String> kCancellationReasons = [
  'Schedule Conflict',
  'Personal / Family Emergency',
  'Health / Feeling Unwell',
  'Financial / Budgetary Reasons',
  'Other',
];

const String _otherReason = 'Other';
const int _otherNoteMax = 150;

/// The value sent to the database for [selected] and its [note]: the
/// category, or `Other: <note>`. Null when nothing valid is chosen.
String? cancellationReasonValue(String? selected, String note) {
  if (selected == null || !kCancellationReasons.contains(selected)) return null;
  if (selected != _otherReason) return selected;
  final cleaned = note.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return 'Other: ${cleaned.length > _otherNoteMax ? cleaned.substring(0, _otherNoteMax) : cleaned}';
}

/// Which bookings a patient may cancel or reschedule: Scheduled (Pending) or
/// Confirmed, not in the past — the website's `canAct`.
bool canPatientChange(Appointment appointment) {
  final today = DateTime.now();
  final day = DateTime(appointment.date.year, appointment.date.month, appointment.date.day);
  final isOpen = appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed;
  return isOpen && !day.isBefore(DateTime(today.year, today.month, today.day));
}

/// Asks for a cancellation reason — required — and, for a booking with a paid
/// deposit, for the patient to acknowledge that the deposit is forfeited.
/// Then cancels through `cancel_my_appointment()` on the server. The page
/// that called it stays open and follows the repository to the cancelled
/// state the database now holds.
void confirmCancelAppointment(BuildContext context, Appointment appointment) {
  final otherController = TextEditingController();
  String? selectedReason;
  var acknowledged = false;
  var showError = false;
  var busy = false;
  String? serverError;

  final paid = appointment.amountPaid > 0 && appointment.downpaymentPaidAt != null;
  final forfeit = paid
      ? (appointment.amountPaid - appointment.rescheduleFeeTotal).clamp(0, double.infinity).toDouble()
      : 0.0;

  showAppDialog(
    context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final needsDetail = selectedReason == _otherReason;
        final reason = cancellationReasonValue(selectedReason, otherController.text);
        final canSubmit = !busy && reason != null && (!paid || acknowledged);

        Future<void> submit() async {
          if (reason == null) {
            setDialogState(() => showError = true);
            return;
          }
          setDialogState(() {
            busy = true;
            serverError = null;
          });
          try {
            await PatientRepository().cancelAppointment(appointment.id, reason: reason);
          } catch (e) {
            debugPrint('Cancel failed: $e');
            setDialogState(() {
              busy = false;
              serverError = e is AppointmentChangeRefusedException
                  ? e.message
                  : 'Could not cancel the appointment. Please try again.';
            });
            return;
          }
          if (!dialogContext.mounted) return;
          final rootContext = Navigator.of(dialogContext, rootNavigator: true).context;
          Navigator.pop(dialogContext);
          if (rootContext.mounted) showAppToast(rootContext, 'Appointment cancelled. Your slot has been released.');
        }

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
                      'Cancel Appointment',
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
              const SizedBox(height: 14),

              // The clinic's policy, stated before anything is chosen.
              if (paid)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.35)),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textPrimary),
                      children: [
                        const TextSpan(text: 'Warning: ', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextSpan(
                          text: 'Cancelling will forfeit 100% of your paid 20% down payment deposit '
                              '(${formatPeso(forfeit)}). Down payments are non-refundable.',
                        ),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  'Your slot will be released. This cannot be undone.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              const SizedBox(height: 16),

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
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: showError && selectedReason == null ? AppColors.error : AppColors.border,
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < kCancellationReasons.length; i++)
                      _ReasonOption(
                        label: kCancellationReasons[i],
                        isSelected: selectedReason == kCancellationReasons[i],
                        isFirst: i == 0,
                        isLast: i == kCancellationReasons.length - 1,
                        onTap: busy
                            ? () {}
                            : () => setDialogState(() {
                                  selectedReason = kCancellationReasons[i];
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
                  maxLength: _otherNoteMax,
                  enabled: !busy,
                  onChanged: (_) => setDialogState(() => showError = false),
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Your reason',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    fillColor: AppColors.surface,
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
              if (paid) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: busy ? null : () => setDialogState(() => acknowledged = !acknowledged),
                  child: Row(
                    children: [
                      Checkbox(
                        value: acknowledged,
                        onChanged: busy ? null : (v) => setDialogState(() => acknowledged = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'I understand that my deposit will be forfeited.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (serverError != null) ...[
                const SizedBox(height: 8),
                Text(serverError!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
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
                        onPressed: busy ? null : () => Navigator.pop(dialogContext),
                        child: const Text('Keep Appointment', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                        onPressed: canSubmit ? submit : (busy ? null : () => setDialogState(() => showError = true)),
                        child: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Confirm Cancellation',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
