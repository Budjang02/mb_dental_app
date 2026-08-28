/// Represents patient demographic and account details.
class Patient {
  final String id;
  final String patientCode;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String phone;
  final String gender;
  final DateTime dateOfBirth;
  final String? avatarPath;

  // Optional profile-completion fields — not required at registration.
  final String? bloodType;
  final String? address;
  final String? maritalStatus;
  final String? medicalHistory;

  Patient({
    required this.id,
    required this.patientCode,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    this.avatarPath,
    this.bloodType,
    this.address,
    this.maritalStatus,
    this.medicalHistory,
  });

  String get fullName => '$firstName $lastName';

  Patient copyWith({
    String? firstName,
    String? lastName,
    String? username,
    String? phone,
    String? gender,
    DateTime? dateOfBirth,
    String? avatarPath,
    String? bloodType,
    String? address,
    String? maritalStatus,
    String? medicalHistory,
  }) {
    return Patient(
      id: id,
      patientCode: patientCode,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      email: email,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      avatarPath: avatarPath ?? this.avatarPath,
      bloodType: bloodType ?? this.bloodType,
      address: address ?? this.address,
      maritalStatus: maritalStatus ?? this.maritalStatus,
      medicalHistory: medicalHistory ?? this.medicalHistory,
    );
  }
}