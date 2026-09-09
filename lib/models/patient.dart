/// Represents patient demographic and account details.
class Patient {
  final String id;
  final String patientCode;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final String phone;
  final String? avatarPath;

  // Profile-completion fields. Registration only collects name, email and
  // password, so everything below starts empty and is filled in later under
  // Profile → Manage Profile or at clinic check-in.
  final String? gender;
  final DateTime? dateOfBirth;
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
    this.gender,
    this.dateOfBirth,
    this.avatarPath,
    this.bloodType,
    this.address,
    this.maritalStatus,
    this.medicalHistory,
  });

  String get fullName => '$firstName $lastName'.trim();

  /// Which of the optional details are still blank, so Profile can nudge the
  /// patient to finish setting up their record.
  List<String> get missingProfileFields => [
        // Sign-up stopped asking for a number, so it is one of these now.
        if (phone.isEmpty) 'Phone Number',
        if (gender == null || gender!.isEmpty) 'Gender',
        if (dateOfBirth == null) 'Date of Birth',
        if (address == null || address!.isEmpty) 'Address',
      ];

  bool get isProfileComplete => missingProfileFields.isEmpty;

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
