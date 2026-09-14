import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/messages.dart';
import '../../app/theme.dart';
import '../../app/theme_controller.dart';
import '../../data/clinic_catalog.dart';
import '../../models/dental_service.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'book_appointment_screen.dart';

/// The four views of the list, in the order their tabs run across the top.
/// [all] leads, so the page still opens on every booking at once.
enum AppointmentView { all, upcoming, completed, cancelled }

String _viewLabel(AppointmentView view) {
  switch (view) {
    case AppointmentView.all:
      return 'All';
    case AppointmentView.upcoming:
      return 'Upcoming';
    case AppointmentView.completed:
      return 'Completed';
    case AppointmentView.cancelled:
      return 'Cancelled';
  }
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  final PatientRepository _repository = PatientRepository();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: AppointmentView.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Pending and confirmed bookings both count as upcoming.
  bool _matches(Appointment a, AppointmentView view) {
    switch (view) {
      case AppointmentView.all:
        return true;
      case AppointmentView.upcoming:
        return a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed;
      case AppointmentView.completed:
        return a.status == AppointmentStatus.completed;
      case AppointmentView.cancelled:
        return a.status == AppointmentStatus.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: [
            for (final view in AppointmentView.values) Tab(text: _viewLabel(view)),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_repository, ThemeController()]),
        builder: (context, _) {
          final all = _repository.appointments;
          return TabBarView(
            controller: _tabController,
            children: [
              for (final view in AppointmentView.values)
                _buildAppointmentList(all.where((a) => _matches(a, view)).toList()),
            ],
          );
        },
      ),
      // Lifted clear of the dashboard's floating navigation bar, which now
      // overlays the bottom of this screen.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen()));
          },
          backgroundColor: AppColors.primary,
          icon: const Icon(CupertinoIcons.add, color: Colors.white),
          label: const Text('Book New', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _buildAppointmentList(List<Appointment> appointments) {
    if (appointments.isEmpty) {
      return Center(
        child: Text('No appointments found.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    // Oldest first, newest at the bottom — the same reading order as the chat.
    final ordered = [...appointments]..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
      itemCount: ordered.length,
      itemBuilder: (context, index) => _buildAppointmentCard(ordered[index]),
    );
  }

  Widget _buildAppointmentCard(Appointment item) {
    final color = statusColor(item.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showAppointmentDetailSheet(context, item),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.serviceName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor(item.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel(item.status),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor(item.status)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(kDoctorIcon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      doctorLabel(item.doctorName),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(CupertinoIcons.calendar, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  // The whole booked block, not just its start: the patient
                  // needs to know how long they are giving up.
                  Expanded(
                    child: Text(
                      '${formatAppointmentDate(item.date)} at ${item.timeRangeLabel}'
                          '  (${formatDuration(item.durationMinutes)})',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
}
