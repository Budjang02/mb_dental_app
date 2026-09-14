import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

export 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// What a form field asks for. The icon is picked from this, the way the
/// website picks a field's icon from its input type or id, so every field of
/// the same kind carries the same icon on every screen.
enum FieldKind {
  email,
  password,
  newPassword,
  confirmPassword,
  fullName,
  firstName,
  lastName,
  username,
  phone,
  birthdate,
  gender,
  bloodType,
  maritalStatus,
  address,
  medicalHistory,
  code,
}

/// The Tabler outline icon for a field of [kind], the same line style the app's
/// navigation uses.
IconData fieldIconFor(FieldKind kind) {
  switch (kind) {
    case FieldKind.email:
      return TablerIcons.mail;
    case FieldKind.password:
      return TablerIcons.lock;
    case FieldKind.newPassword:
      return TablerIcons.key;
    case FieldKind.confirmPassword:
      return TablerIcons.lock_check;
    case FieldKind.fullName:
    case FieldKind.firstName:
    case FieldKind.lastName:
      return TablerIcons.user;
    case FieldKind.username:
      return TablerIcons.at;
    case FieldKind.phone:
      return TablerIcons.phone;
    case FieldKind.birthdate:
      return TablerIcons.calendar;
    case FieldKind.gender:
      return TablerIcons.gender_bigender;
    case FieldKind.bloodType:
      return TablerIcons.droplet;
    case FieldKind.maritalStatus:
      return TablerIcons.heart_handshake;
    case FieldKind.address:
      return TablerIcons.map_pin;
    case FieldKind.medicalHistory:
      return TablerIcons.notes;
    case FieldKind.code:
      return TablerIcons.shield_lock;
  }
}

/// A field's leading icon. Deliberately given no colour: the theme's
/// `prefixIconColor` paints it grey, and teal while the field has focus.
Icon fieldIcon(FieldKind kind, {double size = 20}) => Icon(fieldIconFor(kind), size: size);
