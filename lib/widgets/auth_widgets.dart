import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

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
      fontSize: 13,
      height: 1.6,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
    );
    // Links read as darker text, not bold, so the notice stays quiet.
    final link = muted.copyWith(color: AppColors.textPrimary);

    // Recognisers are owned by the spans, which live only as long as this
    // build; a StatelessWidget cannot dispose them, so they are created fresh
    // each build rather than cached in a field that would leak.
    TextSpan document(String label) => TextSpan(
          text: label,
          style: link,
          recognizer: TapGestureRecognizer()
            ..onTap = () => showLegalDocument(context),
        );

    return Text.rich(
      TextSpan(
        style: muted,
        children: [
          TextSpan(text: '$leadIn '),
          document('Terms'),
          // Breaks after "Terms" so the notice sits as two centred lines.
          const TextSpan(text: '\nand '),
          document('Conditions of Use'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// The clinic's Terms and Conditions, bundled with the app. The same file
/// the booking screen shows before payment, so both always carry the same
/// wording.
const String _termsAsset = 'assets/files/TERMS AND CONDITIONS.txt';

/// Opens the Terms and Conditions in a tall sheet the patient can scroll
/// through. The text is the bundled file as written; only its byte-order
/// mark, line endings and blank spacer lines are dropped for display.
void showLegalDocument(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: AppColors.border),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: _loadParagraphs(_termsAsset),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'The Terms and Conditions could not be opened. Please try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    final paragraphs = snapshot.data;
                    if (paragraphs == null) {
                      return Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                    }
                    return Scrollbar(
                      controller: scrollController,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                        itemCount: paragraphs.length,
                        itemBuilder: (context, i) =>
                            _legalParagraph(paragraphs[i], isFirst: i == 0),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
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
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Each non-blank line of the file is a paragraph, so the title, the "Last
/// updated" line and every heading stand on their own.
Future<List<String>> _loadParagraphs(String asset) async {
  final raw = await rootBundle.loadString(asset);
  return raw
      .replaceAll('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

/// A line the document writes in capitals ("AGREEMENT TO OUR LEGAL TERMS") is
/// a heading; the first line is the document title.
Widget _legalParagraph(String text, {required bool isFirst}) {
  final letters = text.replaceAll(RegExp(r'[^A-Za-z]'), '');
  final isHeading =
      text.length <= 90 && letters.length >= 3 && letters == letters.toUpperCase();

  if (isHeading) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 12, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isFirst ? 18 : 13.5,
          fontWeight: FontWeight.bold,
          height: 1.35,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        height: 1.55,
        color: AppColors.textSecondary,
      ),
    ),
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
    // No fixed colour: grey, and teal while the field has focus (theme).
    prefixIcon: Icon(icon, size: 20),
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
