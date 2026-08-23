/// Represents patient demographic and account details.
class Patient {
  final String id;
  final String patientCode;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String gender;
  final DateTime dateOfBirth;

  Patient({
    required this.id,
    required this.patientCode,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
  });

  String get fullName => '$firstName $lastName';
}