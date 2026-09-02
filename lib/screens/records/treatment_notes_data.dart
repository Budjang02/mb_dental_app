/// Treatment notes shown on the dental chart and on the Treatment Notes page.
///
/// Mock data for now, newest first — this is the seam a real records API
/// would fill in later.
const List<Map<String, String>> kTreatmentNotes = [
  {
    'date': 'Jan 15, 2026',
    'tooth': '#6 Upper Right Canine',
    'condition': 'Filled',
    'procedure': 'Composite Tooth Filling',
    'notes': 'Restoration complete. Patient advised regarding oral hygiene.',
    'doctor': 'Dr. Rey Vincent Bolasoc',
  },
  {
    'date': 'Dec 10, 2025',
    'tooth': 'Full Mouth',
    'condition': 'Cleaned',
    'procedure': 'Full Oral Prophylaxis',
    'notes': 'Routine scaling and polishing completed without complications.',
    'doctor': 'Dr. Jenneline Mariano',
  },
  {
    'date': 'Nov 05, 2025',
    'tooth': '#14 Upper Left Molar',
    'condition': 'Caries/Cavity',
    'notes': 'Slight cavity detected. Scheduled restoration procedure.',
    'procedure': 'Diagnostic Examination',
    'doctor': 'Dr. Rey Vincent Bolasoc',
  },
];
