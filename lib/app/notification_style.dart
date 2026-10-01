import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The colour family a notice is drawn in. Mirrors the website's
/// `.ndi-icon.tone-*` classes (css/app-shell.css, css/dark-mode.css).
enum NotificationTone { blue, green, red, orange, purple, teal, gray }

/// Icon and colours for one notice, chosen from its stable `event` key — never
/// from the title, which is prose and may be reworded. The rules are the
/// website's `NOTIF_TONE_RULES` and `_ndbIcon` (js/notif-feed.js) plus the
/// events the patient feed derives, so a notice looks the same on both.
class NotificationStyle {
  NotificationStyle._();

  /// First match wins, so specific keys sit above the family they belong to.
  static const List<(String, NotificationTone)> _toneRules = [
    ('appointment.cancelled', NotificationTone.red),
    ('appointment.confirmed', NotificationTone.green),
    ('appointment.paid', NotificationTone.green),
    ('appointment.rescheduled', NotificationTone.purple),
    ('appointment.earlier_slot', NotificationTone.purple),
    ('appointment.reminder', NotificationTone.orange),
    ('appointment.pending', NotificationTone.orange),
    ('appointment.payment_requested', NotificationTone.orange),
    ('appointment', NotificationTone.blue),
    ('visit_payment_paid', NotificationTone.green),
    ('visit_payment_requested', NotificationTone.orange),
    ('billing.paid', NotificationTone.green),
    ('billing.charged', NotificationTone.orange),
    ('billing.voided', NotificationTone.red),
    ('billing', NotificationTone.blue),
    ('treatment_plan', NotificationTone.purple),
    ('clinical', NotificationTone.purple),
    ('patient.registered', NotificationTone.teal),
    ('patient.approved', NotificationTone.teal),
  ];

  static NotificationTone toneOf(String event) {
    if (event.isEmpty) return NotificationTone.gray;
    for (final (prefix, tone) in _toneRules) {
      if (event.startsWith(prefix)) return tone;
    }
    return NotificationTone.gray;
  }

  /// Font Awesome Solid, the set the website draws with.
  static FaIconData iconOf(String event) {
    final e = event;
    if (e.startsWith('appointment.cancelled'))
      return FontAwesomeIcons.calendarXmark;
    if (e.startsWith('appointment.confirmed'))
      return FontAwesomeIcons.calendarCheck;
    if (e.startsWith('appointment.rescheduled'))
      return FontAwesomeIcons.calendarDay;
    if (e.startsWith('appointment.reminder')) return FontAwesomeIcons.clock;
    if (e.startsWith('appointment.pending'))
      return FontAwesomeIcons.hourglassHalf;
    if (e.startsWith('appointment.assigned') ||
        e.startsWith('appointment.unassigned')) {
      return FontAwesomeIcons.userDoctor;
    }
    if (e.startsWith('appointment.paid')) return FontAwesomeIcons.pesoSign;
    if (e.startsWith('appointment.earlier_slot'))
      return FontAwesomeIcons.forward;
    if (e.startsWith('visit_payment_requested'))
      return FontAwesomeIcons.fileInvoiceDollar;
    if (e.startsWith('visit_payment_paid')) return FontAwesomeIcons.pesoSign;
    if (e.startsWith('appointment')) return FontAwesomeIcons.calendarPlus;
    if (e.startsWith('patient.registered')) return FontAwesomeIcons.userPlus;
    if (e.startsWith('patient.approved')) return FontAwesomeIcons.userCheck;
    if (e.startsWith('patient')) return FontAwesomeIcons.idCard;
    if (e.startsWith('billing')) return FontAwesomeIcons.receipt;
    if (e.startsWith('treatment_plan') ||
        e.startsWith('clinical.treatment_plan')) {
      return FontAwesomeIcons.listCheck;
    }
    if (e.startsWith('clinical')) return FontAwesomeIcons.tooth;
    if (e.startsWith('member') || e.startsWith('profile'))
      return FontAwesomeIcons.userGear;
    if (e.startsWith('clinic')) return FontAwesomeIcons.clock;
    return FontAwesomeIcons.bell;
  }

  /// Icon colour. The light values are the website's 700 shades; dark mode
  /// lifts them off the slate the way css/dark-mode.css does.
  static Color iconColor(NotificationTone tone, {required bool dark}) {
    switch (tone) {
      case NotificationTone.blue:
        return dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
      case NotificationTone.green:
        return dark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
      case NotificationTone.red:
        return dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
      case NotificationTone.orange:
        return dark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C);
      case NotificationTone.purple:
        return dark ? const Color(0xFFD8B4FE) : const Color(0xFF7E22CE);
      case NotificationTone.teal:
        return dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
      case NotificationTone.gray:
        return dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    }
  }

  /// Icon tile background: the tone's 500 shade at the website's opacity.
  static Color tileColor(NotificationTone tone, {required bool dark}) {
    switch (tone) {
      case NotificationTone.blue:
        return const Color(0xFF3B82F6).withValues(alpha: dark ? 0.18 : 0.12);
      case NotificationTone.green:
        return const Color(0xFF22C55E).withValues(alpha: dark ? 0.16 : 0.14);
      case NotificationTone.red:
        return const Color(0xFFEF4444).withValues(alpha: dark ? 0.16 : 0.12);
      case NotificationTone.orange:
        return const Color(0xFFF97316).withValues(alpha: dark ? 0.16 : 0.13);
      case NotificationTone.purple:
        return const Color(0xFFA855F7).withValues(alpha: dark ? 0.18 : 0.12);
      case NotificationTone.teal:
        return const Color(0xFF14B8A6).withValues(alpha: dark ? 0.16 : 0.13);
      case NotificationTone.gray:
        return dark
            ? const Color(0xFF94A3B8).withValues(alpha: 0.16)
            : const Color(0xFF64748B).withValues(alpha: 0.12);
    }
  }

  /// The unread indicator on the row's left edge (the website's `--teal`).
  static const Color unreadIndicator = Color(0xFF0D9488);
}
