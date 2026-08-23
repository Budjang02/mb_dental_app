import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
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
  late List<Appointment> _allAppointments;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _allAppointments = _repository.getMockAppointments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Appointment> _getFilteredAppointments(AppointmentStatus statusFilter) {
    if (statusFilter == AppointmentStatus.pending) {
      return _allAppointments
          .where((a) =>
      a.status == AppointmentStatus.pending ||
          a.status == AppointmentStatus.confirmed)
          .toList();
    }
    return _allAppointments.where((a) => a.status == statusFilter).toList();
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAppointmentList(_getFilteredAppointments(AppointmentStatus.pending)),
          _buildAppointmentList(_getFilteredAppointments(AppointmentStatus.completed)),
          _buildAppointmentList(_getFilteredAppointments(AppointmentStatus.cancelled)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BookAppointmentScreen(),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Book New', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildAppointmentList(List<Appointment> appointments) {
    if (appointments.isEmpty) {
      return const Center(
        child: Text(
          'No appointments found.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: appointments.length,
      itemBuilder: (context, index) {
        final item = appointments[index];
        return _buildAppointmentCard(item);
      },
    );
  }

  Widget _buildAppointmentCard(Appointment item) {
    Color badgeColor;
    String statusText;

    switch (item.status) {
      case AppointmentStatus.confirmed:
        badgeColor = AppColors.success;
        statusText = 'Confirmed';
        break;
      case AppointmentStatus.pending:
        badgeColor = AppColors.warning;
        statusText = 'Pending';
        break;
      case AppointmentStatus.completed:
        badgeColor = AppColors.primary;
        statusText = 'Completed';
        break;
      case AppointmentStatus.cancelled:
        badgeColor = AppColors.error;
        statusText = 'Cancelled';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.serviceName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  item.doctorName,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')} at ${item.timeSlot}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}