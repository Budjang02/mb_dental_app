import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../models/appointment.dart';

/// Dark modules, as the website draws them.
const Color kCheckInQrForeground = Color(0xFF0F172A);
const Color kCheckInQrBackground = Color(0xFFFFFFFF);

/// Light border round the symbol, in modules — the QR standard's quiet zone
/// and the website encoder's default margin.
const int kCheckInQrQuietZone = 4;

/// Characters QR alphanumeric mode can carry.
final RegExp _alphanumeric = RegExp(r'^[0-9A-Z $%*+\-./:]+$');
final RegExp _numeric = RegExp(r'^[0-9]+$');

/// The check-in QR matrix for [payload], built the way the website's encoder
/// builds it, so both draw the same pattern for the same code:
///
/// * error correction level M (15%);
/// * the most compact mode the text fits — numeric, then alphanumeric, then
///   byte. A confirmation code such as `E3XZSR` is alphanumeric; encoding it
///   as bytes (what the app did before) gives a different, larger matrix;
/// * the smallest version that holds it, and the standard mask choice.
///
/// `[row][column]`, true for a dark module. The quiet zone is not included.
List<List<bool>> checkInQrMatrix(String payload) {
  const ecc = QrErrorCorrectLevel.M;
  for (var version = 1; version <= 40; version++) {
    final code = QrCode(version, ecc);
    if (_numeric.hasMatch(payload)) {
      code.addNumeric(payload);
    } else if (_alphanumeric.hasMatch(payload)) {
      code.addAlphaNumeric(payload);
    } else {
      code.addData(payload);
    }
    QrImage first;
    try {
      first = QrImage.withMaskPattern(code, 0); // Throws when this version is too small.
    } on InputTooLongException {
      continue;
    }

    // The mask is picked the way the website's encoder (the `qrcode` npm
    // package) picks it. The `qr` package scores masks by its own rules and
    // sometimes lands on a different one — a symbol that scans the same but
    // does not look the same.
    List<List<bool>>? best;
    var lowest = -1;
    for (var mask = 0; mask < 8; mask++) {
      final image = mask == 0 ? first : QrImage.withMaskPattern(code, mask);
      final matrix = [
        for (var y = 0; y < image.moduleCount; y++)
          [for (var x = 0; x < image.moduleCount; x++) image.isDark(y, x)],
      ];
      final penalty = qrMaskPenalty(matrix);
      if (lowest == -1 || penalty < lowest) {
        lowest = penalty;
        best = matrix;
      }
    }
    return best!;
  }
  throw ArgumentError.value(payload, 'payload', 'too long for a QR code');
}

/// The mask penalty of a finished symbol: rules N1-N4 of ISO/IEC 18004, as
/// the `qrcode` npm package (`lib/core/mask-pattern.js`) scores them. The
/// lowest-scoring mask wins; the first one wins a tie.
int qrMaskPenalty(List<List<bool>> m) {
  final size = m.length;
  int bit(int row, int col) => m[row][col] ? 1 : 0;
  var points = 0;

  // N1: runs of five or more same-coloured modules in a row or column.
  for (var row = 0; row < size; row++) {
    var countCol = 0, countRow = 0;
    int? lastCol, lastRow;
    for (var col = 0; col < size; col++) {
      var module = bit(row, col);
      if (module == lastCol) {
        countCol++;
      } else {
        if (countCol >= 5) points += 3 + (countCol - 5);
        lastCol = module;
        countCol = 1;
      }
      module = bit(col, row);
      if (module == lastRow) {
        countRow++;
      } else {
        if (countRow >= 5) points += 3 + (countRow - 5);
        lastRow = module;
        countRow = 1;
      }
    }
    if (countCol >= 5) points += 3 + (countCol - 5);
    if (countRow >= 5) points += 3 + (countRow - 5);
  }

  // N2: 2x2 blocks of one colour.
  var blocks = 0;
  for (var row = 0; row < size - 1; row++) {
    for (var col = 0; col < size - 1; col++) {
      final sum = bit(row, col) + bit(row, col + 1) + bit(row + 1, col) + bit(row + 1, col + 1);
      if (sum == 4 || sum == 0) blocks++;
    }
  }
  points += blocks * 3;

  // N3: finder-like 1:1:3:1:1 patterns with four light modules on one side.
  var finders = 0;
  for (var row = 0; row < size; row++) {
    var bitsCol = 0, bitsRow = 0;
    for (var col = 0; col < size; col++) {
      bitsCol = ((bitsCol << 1) & 0x7FF) | bit(row, col);
      if (col >= 10 && (bitsCol == 0x5D0 || bitsCol == 0x05D)) finders++;
      bitsRow = ((bitsRow << 1) & 0x7FF) | bit(col, row);
      if (col >= 10 && (bitsRow == 0x5D0 || bitsRow == 0x05D)) finders++;
    }
  }
  points += finders * 40;

  // N4: how far the share of dark modules strays from half.
  var dark = 0;
  for (final row in m) {
    for (final module in row) {
      if (module) dark++;
    }
  }
  final k = ((dark * 100 / (size * size)) / 5).ceil() - 10;
  points += k.abs() * 10;

  return points;
}

/// An appointment's QR: the public verification link for its [qrToken]
/// (`https://mbdentalcenter.web.app/verify/?t=<qr_token>`), the same URL the
/// website's QR carries. It holds only the random token — no name, date or
/// other patient detail.
class AppointmentQr extends StatelessWidget {
  final String qrToken;
  final double size;

  const AppointmentQr({super.key, required this.qrToken, this.size = 220});

  String get payload => Appointment.verifyUrlFor(qrToken);

  @override
  Widget build(BuildContext context) => CheckInQr(payload: payload, size: size);
}

/// The check-in QR on its white rounded card: [kCheckInQrForeground] modules,
/// a [kCheckInQrQuietZone]-module margin, drawn at [size] square.
class CheckInQr extends StatelessWidget {
  final String payload;
  final double size;

  const CheckInQr({super.key, required this.payload, this.size = 170});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _CheckInQrPainter(checkInQrMatrix(payload))),
      ),
    );
  }
}

class _CheckInQrPainter extends CustomPainter {
  final List<List<bool>> matrix;

  _CheckInQrPainter(this.matrix);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kCheckInQrBackground);

    final count = matrix.length + kCheckInQrQuietZone * 2;
    final module = size.width / count;
    final dark = Paint()
      ..color = kCheckInQrForeground
      ..isAntiAlias = false;
    for (var y = 0; y < matrix.length; y++) {
      for (var x = 0; x < matrix.length; x++) {
        if (!matrix[y][x]) continue;
        // A hair over one module wide so neighbours meet without seams.
        canvas.drawRect(
          Rect.fromLTWH(
            (x + kCheckInQrQuietZone) * module,
            (y + kCheckInQrQuietZone) * module,
            module + 0.5,
            module + 0.5,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckInQrPainter old) => old.matrix != matrix;
}
