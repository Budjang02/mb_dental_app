import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'book_appointment_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final PatientRepository _repository = PatientRepository();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Appointment> _filter(List<Appointment> all, AppointmentStatus statusFilter) {
    if (statusFilter == AppointmentStatus.pending) {
      return all
          .where((a) => a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed)
          .toList();
    }
    return all.where((a) => a.status == statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: _repository,
        builder: (context, _) {
          final all = _repository.appointments;
          return TabBarView(
            controller: _tabController,
            children: [
              _buildAppointmentList(_filter(all, AppointmentStatus.pending)),
              _buildAppointmentList(_filter(all, AppointmentStatus.completed)),
              _buildAppointmentList(_filter(all, AppointmentStatus.cancelled)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BookAppointmentScreen()));
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(CupertinoIcons.add, color: Colors.white),
        label: const Text('Book New', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildAppointmentList(List<Appointment> appointments) {
    if (appointments.isEmpty) {
      return const Center(
        child: Text('No appointments found.', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: appointments.length,
      itemBuilder: (context, index) => _buildAppointmentCard(appointments[index]),
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                  const Icon(CupertinoIcons.person, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(item.doctorName, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(CupertinoIcons.calendar, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${formatAppointmentDate(item.date)} at ${item.timeSlot}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
