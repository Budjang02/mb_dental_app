import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mb_dental_app/app/theme.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';

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

/// A stable, ticket-style reference number derived from the appointment id.
String appointmentReference(String id) => '#${100000 + (id.hashCode.abs() % 900000)}';

void showAppointmentDetailSheet(BuildContext context, Appointment appointment) {
  final bool isCancellable =
      appointment.status == AppointmentStatus.pending || appointment.status == AppointmentStatus.confirmed;

  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) {
      return Dialog(
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appointmentReference(appointment.id),
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(dialogContext),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(CupertinoIcons.xmark_circle_fill, size: 22, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        appointment.serviceName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ),
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
                  ],
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
                if (isCancellable) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _confirmCancel(dialogContext, appointment),
                      child: const Text('Cancel Appointment', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ],
            ),
          ),
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

void _confirmCancel(BuildContext sheetContext, Appointment appointment) {
  showDialog(
    context: sheetContext,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Cancel Appointment?'),
      content: Text(
          'This will cancel your ${appointment.serviceName} appointment on ${formatAppointmentDate(appointment.date)}.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Keep Appointment'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () {
            PatientRepository().cancelAppointment(appointment.id);
            Navigator.pop(dialogContext);
            Navigator.pop(sheetContext);
          },
          child: const Text('Cancel It'),
        ),
      ],
    ),
  );
}
