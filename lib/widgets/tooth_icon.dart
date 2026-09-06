import 'package:flutter/widgets.dart';

/// The tooth glyph used for the Records tab. Neither Material nor Cupertino
/// ships a tooth, so it is drawn here as a path in the same house style as the
/// rest of the navigation (see `app_icons.dart`): a clean linear outline with
/// rounded caps and joins.
///
/// The silhouette is an incisor seen face-on — a broad crown with a squared,
/// gently rounded biting edge that curves in at the shoulders, pulls into a
/// waist at the neck, and splits into two roots that taper to rounded points
/// with a clear notch between them. The squared-off top is what separates a
/// tooth from a generic blob at 22px; a domed crown reads as a balloon.
class ToothIcon extends StatelessWidget {
  final double size;
  final Color color;

  /// Draws the two cusp grooves inside the crown. Off for very small sizes,
  /// where the extra strokes only muddy the glyph.
  final bool showDetail;

  const ToothIcon({
    super.key,
    this.size = 22,
    required this.color,
    this.showDetail = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: CustomPaint(
        painter: _ToothIconPainter(color: color, showDetail: showDetail),
      ),
    );
  }
}

class _ToothIconPainter extends CustomPainter {
  final Color color;
  final bool showDetail;

  _ToothIconPainter({required this.color, required this.showDetail});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = w * 0.085;

    // Coordinates are unit fractions of the box, walked clockwise from the
    // middle of the biting edge: flat top, rounded shoulder, waist, left root
    // down to its tip, up into the notch, then the mirror of all of it.
    final path = Path()
      ..moveTo(0.50 * w, 0.10 * h)
      // Top edge out to the left shoulder — nearly straight, so the crown
      // reads as a biting surface rather than a dome.
      ..cubicTo(0.38 * w, 0.07 * h, 0.26 * w, 0.08 * h, 0.19 * w, 0.16 * h)
      // Shoulder curving down into the cervical waist.
      ..cubicTo(0.11 * w, 0.25 * h, 0.10 * w, 0.40 * h, 0.14 * w, 0.53 * h)
      // Left root: tapers as it falls.
      ..cubicTo(0.19 * w, 0.68 * h, 0.21 * w, 0.80 * h, 0.24 * w, 0.90 * h)
      ..cubicTo(0.26 * w, 0.96 * h, 0.34 * w, 0.96 * h, 0.36 * w, 0.90 * h)
      // Up the inside of the left root into the notch between the two.
      ..cubicTo(0.40 * w, 0.78 * h, 0.44 * w, 0.68 * h, 0.50 * w, 0.63 * h)
      // Mirror image, back up the right side.
      ..cubicTo(0.56 * w, 0.68 * h, 0.60 * w, 0.78 * h, 0.64 * w, 0.90 * h)
      ..cubicTo(0.66 * w, 0.96 * h, 0.74 * w, 0.96 * h, 0.76 * w, 0.90 * h)
      ..cubicTo(0.79 * w, 0.80 * h, 0.81 * w, 0.68 * h, 0.86 * w, 0.53 * h)
      ..cubicTo(0.90 * w, 0.40 * h, 0.89 * w, 0.25 * h, 0.81 * w, 0.16 * h)
      ..cubicTo(0.74 * w, 0.08 * h, 0.62 * w, 0.07 * h, 0.50 * w, 0.10 * h)
      ..close();

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);

    if (showDetail) {
      // Two short cusp grooves dropping from the biting edge, at two thirds
      // the main weight so they read as interior detail rather than as part
      // of the silhouette.
      final detail = Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.72
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0.35 * w, 0.24 * h), Offset(0.35 * w, 0.38 * h), detail);
      canvas.drawLine(Offset(0.65 * w, 0.24 * h), Offset(0.65 * w, 0.38 * h), detail);
    }
  }

  @override
  bool shouldRepaint(_ToothIconPainter old) =>
      old.color != color || old.showDetail != showDetail;
}
