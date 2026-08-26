import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/appointment.dart';
import 'package:mb_dental_app/repositories/patient_repository.dart';
import 'package:mb_dental_app/widgets/appointment_detail_sheet.dart';
import 'package:mb_dental_app/widgets/app_calendar.dart';
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

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

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
    Iterable<Appointment> result;
    if (statusFilter == AppointmentStatus.pending) {
      result = all.where((a) => a.status == AppointmentStatus.pending || a.status == AppointmentStatus.confirmed);
    } else {
      result = all.where((a) => a.status == statusFilter);
    }
    if (_selectedDay != null) {
      result = result.where((a) => isSameDay(a.date, _selectedDay));
    }
    return result.toList();
  }

  List<Object> _appointmentsOnDay(DateTime day) {
    return _repository.appointments.where((a) => isSameDay(a.date, day)).toList();
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AppCalendar(
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  eventLoader: _appointmentsOnDay,
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = isSameDay(_selectedDay, selected) ? null : selected;
                      _focusedDay = focused;
                    });
                  },
                  onPageChanged: (focused) => _focusedDay = focused,
                ),
              ),
              if (_selectedDay != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text('Showing ${_selectedDay!.month}/${_selectedDay!.day}/${_selectedDay!.year}'),
                      labelStyle: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      deleteIcon: const Icon(CupertinoIcons.xmark_circle_fill, size: 16),
                      deleteIconColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
                      onDeleted: () => setState(() => _selectedDay = null),
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAppointmentList(_filter(all, AppointmentStatus.pending)),
                    _buildAppointmentList(_filter(all, AppointmentStatus.completed)),
                    _buildAppointmentList(_filter(all, AppointmentStatus.cancelled)),
                  ],
                ),
              ),
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
      return Center(
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
                  Icon(CupertinoIcons.person, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(item.doctorName, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(CupertinoIcons.calendar, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '${formatAppointmentDate(item.date)} at ${item.timeSlot}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
