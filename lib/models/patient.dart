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
  final String? avatarPath;

  Patient({
    required this.id,
    required this.patientCode,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    this.avatarPath,
  });

  String get fullName => '$firstName $lastName';

  Patient copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? gender,
    String? avatarPath,
  }) {
    return Patient(
      id: id,
      patientCode: patientCode,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }
}