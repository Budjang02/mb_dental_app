import 'package:mb_dental_app/models/patient.dart';
import 'package:mb_dental_app/models/appointment.dart';
import 'package:mb_dental_app/models/treatment.dart';
import 'package:mb_dental_app/models/payment.dart';

class PatientRepository {
  Patient getMockPatient() {
    return Patient(
      id: 'p-101',
      patientCode: 'PAT-2026-0089',
      firstName: 'John Wilson',
      lastName: 'Salvador',
      email: 'salvadorjohnwilson55@gmail.com',
      phone: '+63 992 299 0844',
      gender: 'Male',
      dateOfBirth: DateTime(2002, 5, 14),
    );
  }

  List<Appointment> getMockAppointments() {
    return [
      Appointment(
        id: 'app-01',
        serviceName: 'Oral Prophylaxis (Cleaning)',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: DateTime(2026, 8, 28),
        timeSlot: '10:00 AM',
        status: AppointmentStatus.confirmed,
        notes: 'Regular checkup and cleaning.',
      ),
      Appointment(
        id: 'app-02',
        serviceName: 'Tooth Filling (Composite)',
        doctorName: 'Dr. Jenneline Mariano',
        date: DateTime(2026, 9, 12),
        timeSlot: '01:30 PM',
        status: AppointmentStatus.pending,
      ),
      Appointment(
        id: 'app-03',
        serviceName: 'Dental Checkup',
        doctorName: 'Dr. John Paul Mariano',
        date: DateTime(2026, 5, 10),
        timeSlot: '11:00 AM',
        status: AppointmentStatus.completed,
      ),
    ];
  }

  List<Treatment> getMockTreatments() {
    return [
      Treatment(
        id: 'treat-01',
        procedure: 'Tooth #17 Composite Filling',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        date: DateTime(2026, 1, 15),
        notes: 'Restoration complete. Patient advised regarding oral hygiene.',
      ),
      Treatment(
        id: 'treat-02',
        procedure: 'Full Prophylaxis',
        doctorName: 'Dr. Jenneline Mariano',
        date: DateTime(2025, 12, 10),
        notes: 'Routine cleaning performed without complications.',
      ),
    ];
  }

  List<Payment> getMockBilling() {
    return [
      Payment(
        id: 'bill-01',
        referenceNo: 'REC-2026-8801',
        procedureName: 'Tooth Filling',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        amount: 2000.0,
        billedOn: DateTime(2026, 1, 15),
        status: 'Paid',
        paymentMethod: 'GCash',
      ),
      Payment(
        id: 'bill-02',
        referenceNo: 'REC-2026-9042',
        procedureName: 'Oral Prophylaxis',
        doctorName: 'Dr. Rey Vincent Bolasoc',
        amount: 1000.0,
        billedOn: DateTime(2026, 8, 28),
        status: 'Unpaid',
      ),
    ];
  }
}