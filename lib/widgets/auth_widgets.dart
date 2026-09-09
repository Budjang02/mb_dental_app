import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../data/clinic_catalog.dart';

/// The pieces Sign In and Create Account both draw below their form: a
/// labelled rule, the two social providers, and the terms line under them.
///
/// These lived inline in the login screen. They are shared now because the two
/// screens must not drift — a Google button that looks different depending on
/// which screen you reached it from reads as two different products.

/// `———— OR CONTINUE WITH ————`, with the label supplied by the caller since
/// signing in and signing up word it differently.
class AuthDivider extends StatelessWidget {
  final String label;

  const AuthDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}

/// Google and Facebook side by side, each filling half the width.
class SocialAuthRow extends StatelessWidget {
  final VoidCallback onGoogle;
  final VoidCallback onFacebook;

  const SocialAuthRow({super.key, required this.onGoogle, required this.onFacebook});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _button(
            onTap: onGoogle,
            label: 'Google',
            icon: const SizedBox(
              height: 20,
              width: 20,
              child: CustomPaint(painter: GoogleLogoPainter()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _button(
            onTap: onFacebook,
            label: 'Facebook',
            icon: const Icon(Icons.facebook_rounded, size: 22, color: Color(0xFF1877F2)),
          ),
        ),
      ],
    );
  }

  Widget _button({
    required VoidCallback onTap,
    required String label,
    required Widget icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The consent line that closes both auth screens.
///
/// The sentence stays muted — it is a disclosure, not a call to action — but
/// the two document names inside it are emphasised and tappable, because a
/// patient agreeing to something has to be able to read it first.
class TermsNotice extends StatelessWidget {
  /// The part before the document names, e.g. "By signing up, you agree to our".
  final String leadIn;

  const TermsNotice({super.key, required this.leadIn});

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontSize: 11.5,
      height: 1.45,
      color: AppColors.textSecondary,
    );
    final link = muted.copyWith(
      fontWeight: FontWeight.bold,
      color: AppColors.textPrimary,
    );

    // Recognisers are owned by the spans, which live only as long as this
    // build; a StatelessWidget cannot dispose them, so they are created fresh
    // each build rather than cached in a field that would leak.
    TextSpan document(String label) => TextSpan(
          text: label,
          style: link,
          recognizer: TapGestureRecognizer()
            ..onTap = () => showLegalDocument(context, label),
        );

    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          TextSpan(text: '$leadIn '),
          document('Terms'),
          const TextSpan(text: ' and '),
          document('Conditions of Use'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Opens the named legal document.
///
/// The clinic has not supplied the final wording yet, so this shows where it
/// will live and how to ask for a copy in the meantime rather than inventing
/// terms nobody at the practice has agreed to.
// TODO: render the real document (bundled asset or fetched from the clinic
// site) once legal provides it.
void showLegalDocument(BuildContext context, String title) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'The full $title for $kClinicName is not published in the app yet. '
              'Ask the front desk for a copy, or contact us and we will send it '
              'to you.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _contactLine(Icons.mail_outline, kClinicEmail),
            const SizedBox(height: 8),
            _contactLine(Icons.phone_outlined, kClinicPhone),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text(
                  'Close',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _contactLine(IconData icon, String value) {
  return Row(
    children: [
      Icon(icon, size: 16, color: AppColors.primary),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    ],
  );
}

/// The outlined field shape every auth screen uses. Kept in one place so a
/// password box on Create New Password matches one on Sign In exactly.
InputDecoration authInputDecoration({
  required String label,
  required IconData icon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.primary, size: 22),
    suffixIcon: suffixIcon,
    border: border(AppColors.border),
    enabledBorder: border(AppColors.border),
    focusedBorder: border(AppColors.primary, 2),
  );
}

/// Draws the actual Google "G" brand mark (the four-color G used on every
/// "Sign in with Google" button), traced from Google's official 48x48 vector
/// artwork so no external logo asset/network fetch is needed.
class GoogleLogoPainter extends CustomPainter {
  const GoogleLogoPainter();

  static const double _viewBoxSize = 48;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewBoxSize;
    canvas.save();
    canvas.scale(scale, scale);

    final paint = Paint()..style = PaintingStyle.fill;

    // Yellow arc
    paint.color = const Color(0xFFFFC107);
    canvas.drawPath(_yellowPath(), paint);

    // Red arc
    paint.color = const Color(0xFFFF3D00);
    canvas.drawPath(_redPath(), paint);

    // Green arc
    paint.color = const Color(0xFF4CAF50);
    canvas.drawPath(_greenPath(), paint);

    // Blue arc
    paint.color = const Color(0xFF1976D2);
    canvas.drawPath(_bluePath(), paint);

    canvas.restore();
  }

  Path _yellowPath() {
    return Path()
      ..moveTo(43.611, 20.083)
      ..lineTo(42, 20.083)
      ..lineTo(42, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(33.654, 32.657, 29.223, 36, 24, 36)
      ..cubicTo(17.373, 36, 12, 30.627, 12, 24)
      ..cubicTo(12, 17.373, 17.373, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(12.955, 4, 4, 12.955, 4, 24)
      ..cubicTo(4, 35.045, 12.955, 44, 24, 44)
      ..cubicTo(35.045, 44, 44, 35.045, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20.083)
      ..close();
  }

  Path _redPath() {
    return Path()
      ..moveTo(6.306, 14.691)
      ..lineTo(12.877, 19.51)
      ..cubicTo(14.655, 15.108, 18.961, 12, 24, 12)
      ..cubicTo(27.059, 12, 29.842, 13.154, 31.961, 15.039)
      ..lineTo(37.618, 9.382)
      ..cubicTo(34.046, 6.053, 29.268, 4, 24, 4)
      ..cubicTo(16.318, 4, 9.656, 8.337, 6.306, 14.691)
      ..close();
  }

  Path _greenPath() {
    return Path()
      ..moveTo(24, 44)
      ..cubicTo(29.166, 44, 33.86, 42.023, 37.409, 38.808)
      ..lineTo(31.219, 33.57)
      ..cubicTo(29.211, 35.091, 26.715, 36, 24, 36)
      ..cubicTo(18.798, 36, 14.381, 32.683, 12.717, 28.054)
      ..lineTo(6.195, 33.079)
      ..cubicTo(9.505, 39.556, 16.227, 44, 24, 44)
      ..close();
  }

  Path _bluePath() {
    return Path()
      ..moveTo(43.611, 20.083)
      ..lineTo(42, 20.083)
      ..lineTo(42, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 28)
      ..lineTo(35.303, 28)
      ..cubicTo(34.511, 30.237, 33.072, 32.166, 31.216, 33.571)
      ..cubicTo(31.217, 33.57, 31.218, 33.57, 31.219, 33.569)
      ..lineTo(37.409, 38.807)
      ..cubicTo(36.971, 39.205, 44, 34, 44, 24)
      ..cubicTo(44, 22.659, 43.862, 21.35, 43.611, 20.083)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
