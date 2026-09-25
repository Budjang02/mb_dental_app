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
import 'package:mb_dental_app/widgets/section_states.dart';
import 'appointment_details_screen.dart';
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
    // A fresh read every time the page opens, so a booking the clinic made or
    // changed on the website is here even if the realtime push was missed.
    // The copy already loaded stays on screen until the new one lands.
    _repository.refreshSection(SyncSection.appointments);
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
          // The tabs, the bar above them and the Book New button are drawn
          // whatever the appointments read did: only the list inside each tab
          // depends on it.
          final status = _repository.effectiveStatusOf(SyncSection.appointments);
          return TabBarView(
            controller: _tabController,
            children: [
              for (final view in AppointmentView.values)
                _buildAppointmentList(
                  all.where((a) => _matches(a, view)).toList(),
                  status,
                ),
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

  Widget _buildAppointmentList(List<Appointment> appointments, SectionStatus status) {
    // A failed read is said inside the list area, with its own retry. The tab
    // bar, the app bar and the Book New button stay exactly where they were.
    if (status.hasFailed) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
        children: [
          SectionErrorNotice(
            status: status,
            isRetrying: _repository.isRetrying(SyncSection.appointments),
            onRetry: () => _repository.retrySection(SyncSection.appointments),
          ),
        ],
      );
    }

    if (appointments.isEmpty) {
      // Still on its way: a skeleton, not "no appointments" — the patient must
      // not be told they have none before anyone has looked.
      if (status.isPending) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: const [SectionSkeleton(rows: 3)],
        );
      }
      // A list, not a bare Center, so the empty tab still takes the
      // pull-to-refresh gesture.
      return LayoutBuilder(
        builder: (context, constraints) => ListView(
          children: [
            SizedBox(
              height: constraints.maxHeight * 0.7,
              child: Center(
                child: Text('No appointments yet.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      );
    }

    // By visit date, latest first, on every tab — the website's order. It
    // used to be by booking time, which buried a visit booked long ago (a
    // Sep 30 appointment made in August sat below newer bookings for earlier
    // dates) and read as missing. Same-day visits run latest slot first, then
    // most recently booked.
    final ordered = [...appointments]..sort((a, b) {
        final byVisit = b.startsAt.compareTo(a.startsAt);
        if (byVisit != 0) return byVisit;
        return (b.createdAt ?? b.startsAt).compareTo(a.createdAt ?? a.startsAt);
      });

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
          onTap: () => openAppointmentDetails(context, item),
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
                  DoctorIcon(size: 16, color: AppColors.textSecondary),
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
