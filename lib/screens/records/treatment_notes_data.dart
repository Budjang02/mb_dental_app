import '../../repositories/patient_repository.dart';

/// Treatment notes shown on the dental chart and on the Treatment Notes page.
///
/// Read straight from the clinic's `tooth_records` table through
/// [PatientRepository]: the chart is the clinic's record of the patient's
/// mouth, so there is nothing for the app to hold of its own.
List<Map<String, String>> get kTreatmentNotes => PatientRepository().toothRecords;
