import 'package:flutter/widgets.dart';

/// The app's navigation glyph set, drawn by hand instead of pulled from
/// Material or Cupertino.
///
/// House style, applied to every glyph here: a single-weight linear outline —
/// no fills, no two-tone shapes — with round stroke caps and round joins, so
/// the icons read as the outline/rounded variants the clinic dashboard is
/// meant to use. Material's `_outlined` set has square caps and its `_rounded`
/// set is solid, so neither family gives both at once; drawing them keeps the
/// five navigation icons consistent with each other and with [ToothIcon].
///
/// Every path is written in a unit box (0..1 on both axes) and scaled to the
/// requested [AppIcon.size], so a glyph stays identical at any size and the
/// stroke weight tracks it.
enum AppIconGlyph { home, calendar, wallet, records, person }

class AppIcon extends StatelessWidget {
  final AppIconGlyph glyph;
  final double size;
  final Color color;

  /// Stroke weight as a fraction of [size]. The default matches [ToothIcon]
  /// so a tooth sitting in the same row does not look lighter or heavier than
  /// its neighbours.
  final double weight;

  const AppIcon({
    super.key,
    required this.glyph,
    required this.color,
    this.size = 22,
    this.weight = 0.085,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AppIconPainter(glyph: glyph, color: color, weight: weight),
      ),
    );
  }
}

class _AppIconPainter extends CustomPainter {
  final AppIconGlyph glyph;
  final Color color;
  final double weight;

  const _AppIconPainter({required this.glyph, required this.color, required this.weight});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case AppIconGlyph.home:
        _home(canvas, s, paint);
      case AppIconGlyph.calendar:
        _calendar(canvas, s, paint);
      case AppIconGlyph.wallet:
        _wallet(canvas, s, paint);
      case AppIconGlyph.records:
        _records(canvas, s, paint);
      case AppIconGlyph.person:
        _person(canvas, s, paint);
    }
  }

  /// Pitched roof over a body whose bottom corners are rounded, with the
  /// doorway drawn as an open three-sided shape so the glyph stays linear.
  void _home(Canvas canvas, double s, Paint paint) {
    final body = Path()
      ..moveTo(0.11 * s, 0.46 * s)
      ..lineTo(0.50 * s, 0.13 * s)
      ..lineTo(0.89 * s, 0.46 * s)
      ..lineTo(0.89 * s, 0.79 * s)
      ..cubicTo(0.89 * s, 0.87 * s, 0.85 * s, 0.90 * s, 0.78 * s, 0.90 * s)
      ..lineTo(0.22 * s, 0.90 * s)
      ..cubicTo(0.15 * s, 0.90 * s, 0.11 * s, 0.87 * s, 0.11 * s, 0.79 * s)
      ..close();

    final door = Path()
      ..moveTo(0.38 * s, 0.90 * s)
      ..lineTo(0.38 * s, 0.64 * s)
      ..cubicTo(0.38 * s, 0.60 * s, 0.41 * s, 0.58 * s, 0.45 * s, 0.58 * s)
      ..lineTo(0.55 * s, 0.58 * s)
      ..cubicTo(0.59 * s, 0.58 * s, 0.62 * s, 0.60 * s, 0.62 * s, 0.64 * s)
      ..lineTo(0.62 * s, 0.90 * s);

    canvas.drawPath(body, paint);
    canvas.drawPath(door, paint);
  }

  /// Rounded page with two binder rings above it and a rule under the header,
  /// plus two date marks so it reads as a calendar rather than a plain card.
  void _calendar(Canvas canvas, double s, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.10 * s, 0.20 * s, 0.90 * s, 0.90 * s),
        Radius.circular(0.16 * s),
      ),
      paint,
    );
    canvas.drawLine(Offset(0.32 * s, 0.09 * s), Offset(0.32 * s, 0.28 * s), paint);
    canvas.drawLine(Offset(0.68 * s, 0.09 * s), Offset(0.68 * s, 0.28 * s), paint);
    canvas.drawLine(Offset(0.10 * s, 0.41 * s), Offset(0.90 * s, 0.41 * s), paint);

    // Date marks: short round-capped ticks, deliberately lighter than the
    // frame so they sit behind it in the eye.
    final marks = Paint()
      ..color = paint.color
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = paint.strokeWidth * 0.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0.32 * s, 0.62 * s), Offset(0.335 * s, 0.62 * s), marks);
    canvas.drawLine(Offset(0.66 * s, 0.62 * s), Offset(0.675 * s, 0.62 * s), marks);
    canvas.drawLine(Offset(0.32 * s, 0.75 * s), Offset(0.335 * s, 0.75 * s), marks);
  }

  /// Billfold with a rounded card pocket on the right and the clasp inside it.
  void _wallet(Canvas canvas, double s, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.09 * s, 0.22 * s, 0.91 * s, 0.88 * s),
        Radius.circular(0.18 * s),
      ),
      paint,
    );
    // Pocket: only its left edge and rounded corners are drawn, because its
    // right edge is the wallet's own edge.
    final pocket = Path()
      ..moveTo(0.91 * s, 0.42 * s)
      ..lineTo(0.66 * s, 0.42 * s)
      ..cubicTo(0.58 * s, 0.42 * s, 0.56 * s, 0.48 * s, 0.56 * s, 0.55 * s)
      ..cubicTo(0.56 * s, 0.62 * s, 0.58 * s, 0.68 * s, 0.66 * s, 0.68 * s)
      ..lineTo(0.91 * s, 0.68 * s);
    canvas.drawPath(pocket, paint);
    canvas.drawCircle(
      Offset(0.72 * s, 0.55 * s),
      0.055 * s,
      Paint()
        ..color = paint.color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
  }

  /// A folder, matching the one the "My Records" quick action uses, with a
  /// single rule inside so it does not read as an empty box at 22px.
  void _records(Canvas canvas, double s, Paint paint) {
    final folder = Path()
      ..moveTo(0.10 * s, 0.78 * s)
      ..lineTo(0.10 * s, 0.27 * s)
      ..cubicTo(0.10 * s, 0.22 * s, 0.13 * s, 0.19 * s, 0.18 * s, 0.19 * s)
      ..lineTo(0.38 * s, 0.19 * s)
      ..cubicTo(0.42 * s, 0.19 * s, 0.45 * s, 0.21 * s, 0.47 * s, 0.25 * s)
      ..lineTo(0.52 * s, 0.34 * s)
      ..lineTo(0.82 * s, 0.34 * s)
      ..cubicTo(0.87 * s, 0.34 * s, 0.90 * s, 0.37 * s, 0.90 * s, 0.42 * s)
      ..lineTo(0.90 * s, 0.78 * s)
      ..cubicTo(0.90 * s, 0.83 * s, 0.87 * s, 0.86 * s, 0.82 * s, 0.86 * s)
      ..lineTo(0.18 * s, 0.86 * s)
      ..cubicTo(0.13 * s, 0.86 * s, 0.10 * s, 0.83 * s, 0.10 * s, 0.78 * s)
      ..close();
    canvas.drawPath(folder, paint);
    canvas.drawLine(Offset(0.32 * s, 0.60 * s), Offset(0.68 * s, 0.60 * s), paint);
  }

  /// Head over shoulders, the shoulders drawn as an open arc so the glyph
  /// keeps the same stroke language as the rest of the set.
  void _person(Canvas canvas, double s, Paint paint) {
    canvas.drawCircle(Offset(0.50 * s, 0.32 * s), 0.19 * s, paint);
    final shoulders = Path()
      ..moveTo(0.15 * s, 0.90 * s)
      ..cubicTo(0.15 * s, 0.68 * s, 0.30 * s, 0.60 * s, 0.50 * s, 0.60 * s)
      ..cubicTo(0.70 * s, 0.60 * s, 0.85 * s, 0.68 * s, 0.85 * s, 0.90 * s);
    canvas.drawPath(shoulders, paint);
  }

  @override
  bool shouldRepaint(_AppIconPainter old) =>
      old.glyph != glyph || old.color != color || old.weight != weight;
}
