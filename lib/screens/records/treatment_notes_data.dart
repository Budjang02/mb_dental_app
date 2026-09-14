import '../../repositories/patient_repository.dart';

/// Treatment notes shown on the dental chart and on the Treatment Notes page.
///
/// Read from the clinic's `treatment_notes` history through
/// [PatientRepository], falling back to the chart's `tooth_records` for a
/// patient whose history has not been written yet.
List<Map<String, String>> get kTreatmentNotes => PatientRepository().treatmentNotes;
