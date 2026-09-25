import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The clinic's one A4 layout for the documents a patient takes away —
/// Deposit Receipt, Invoice and Payment Receipt. A port of the website's
/// `js/pdf-docs.js`, so a document downloaded from the app and one downloaded
/// from the website read the same: logo and clinic at the top left, the
/// title, number and date at the top right, a teal rule, an info grid, the
/// item table, a totals block and the footer.
///
/// The standard PDF fonts have no peso sign, so amounts print as
/// `PHP 1,234.00`, exactly as the website's do.

const _clinicName = 'MARIANO AND BOLASOC DENTAL CENTER';
const _clinicAddress = 'La Rosa Street, Corner Gil Carlos San Jose, Baliuag, Bulacan 3006';
const _clinicPhone = '09458550225';
const _clinicEmail = 'raphaelgiron32@gmail.com';

const _teal = PdfColor.fromInt(0xFF0D9488);
const _ink = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _headFill = PdfColor.fromInt(0xFFF0FDFA);
const _headInk = PdfColor.fromInt(0xFF115E59);
const _minus = PdfColor.fromInt(0xFFB91C1C);

/// One column of the item table. [width] is relative, as on the website.
class PdfColumn {
  final String header;
  final double width;
  final bool alignRight;

  const PdfColumn(this.header, this.width, {this.alignRight = false});
}

/// One line of the totals block. [minus] prints it red; [strong] puts it on
/// the teal band.
class PdfTotal {
  final String label;
  final String value;
  final bool minus;
  final bool strong;

  const PdfTotal(this.label, this.value, {this.minus = false, this.strong = false});
}

/// Everything a document says, drawn by [renderClinicPdf].
class ClinicPdfSpec {
  final String title;
  final String numberLabel;
  final String number;
  final String dateLabel;
  final String date;
  final List<(String, String)> left;
  final List<(String, String)> right;
  final List<PdfColumn> columns;
  final List<List<String>> rows;
  final List<PdfTotal> totals;
  final String stamp;
  final String note;
  final String fileName;

  const ClinicPdfSpec({
    required this.title,
    required this.numberLabel,
    required this.number,
    required this.dateLabel,
    required this.date,
    required this.left,
    required this.right,
    required this.columns,
    required this.rows,
    required this.totals,
    this.stamp = '',
    this.note = '',
    required this.fileName,
  });
}

// --- Formatting shared with the loaders (the website's pdf* helpers) --------

/// `PHP 1,234.00`, with a leading minus for a negative amount.
String pdfMoney(num value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}PHP $buffer.${parts[1]}';
}

/// `PHP 500.00 - PHP 800.00`, or one amount when there is no spread.
String pdfRange(num min, num max) {
  final lo = min < 0 ? 0 : min;
  final hi = max < lo ? lo : max;
  return hi > lo ? '${pdfMoney(lo)} - ${pdfMoney(hi)}' : pdfMoney(lo);
}

const _methodLabels = {
  'Wallet': 'E-Wallet',
  'GCash': 'GCash',
  'GrabPay': 'GrabPay',
  'Maya': 'Maya',
  'Cash': 'Cash',
  'Card': 'Card',
  'Account': "Patient's account",
};

String pdfMethod(String? method) =>
    _methodLabels[method] ?? ((method == null || method.isEmpty) ? '-' : method);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _shortMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _shortDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// A plain `YYYY-MM-DD` read as a calendar day (never shifted a day by the
/// time zone); a timestamp read in local time.
DateTime? _parseDay(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    final p = text.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }
  return DateTime.tryParse(text)?.toLocal();
}

/// "October 2, 2026", or "-".
String pdfDate(Object? value) {
  final d = value is DateTime ? value : _parseDay(value);
  return d == null ? '-' : '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String _clock(int minuteOfDay) {
  final h = (minuteOfDay ~/ 60) % 24;
  final m = minuteOfDay % 60;
  return '${h % 12 == 0 ? 12 : h % 12}:${m.toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
}

/// "Fri, Oct 2, 2026, 10:00 AM - 11:00 AM".
String pdfSchedule(Object? date, Object? time, int minutes) {
  final d = _parseDay(date?.toString().split('T').first);
  if (d == null) return '-';
  final day = '${_shortDays[d.weekday - 1]}, ${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time?.toString() ?? '');
  if (match == null) return day;
  final start = int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  final end = minutes > 0 ? ' - ${_clock(start + minutes)}' : '';
  return '$day, ${_clock(start)}$end';
}

/// `#00042`, or "-".
String pdfPatientNo(Object? number) {
  final text = number?.toString().replaceFirst('#', '').trim() ?? '';
  return text.isEmpty ? '-' : '#${text.padLeft(5, '0')}';
}

/// File-name safe: `Invoice-26639Z.pdf`.
String pdfFileName(String kind, String? ref) {
  final safe = (ref ?? '').replaceAll(RegExp(r'[^0-9A-Za-z-]'), '');
  return '$kind-${safe.isEmpty ? 'document' : safe}.pdf';
}

/// The built-in PDF font is Latin-1 only: dashes and curly quotes are folded
/// to plain ones and anything else outside it dropped, rather than drawn as
/// empty boxes.
String _latin(String text) => text
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('₱', 'PHP ')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

// --- Rendering ---------------------------------------------------------------

Future<pw.MemoryImage?> _logo() async {
  try {
    final data = await rootBundle.load('assets/images/light_mode_icon.png');
    return pw.MemoryImage(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  } catch (_) {
    return null; // No logo beats no document.
  }
}

/// Draws [spec] as an A4 PDF.
Future<Uint8List> renderClinicPdf(ClinicPdfSpec spec) async {
  final logo = await _logo();
  final doc = pw.Document(title: '${spec.title} ${spec.number}', creator: _clinicName);

  pw.TextStyle style(double size, {bool bold = false, PdfColor color = _ink}) =>
      pw.TextStyle(fontSize: size * 1.0, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color);

  pw.Widget header() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null) ...[
                pw.SizedBox(height: 16 * PdfPageFormat.mm, child: pw.Image(logo)),
                pw.SizedBox(width: 4 * PdfPageFormat.mm),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_clinicName, style: style(11.5, bold: true)),
                    pw.SizedBox(height: 3),
                    pw.Text(_clinicAddress, style: style(7.8, color: _muted)),
                    pw.SizedBox(height: 2),
                    pw.Text('Tel. $_clinicPhone  |  $_clinicEmail', style: style(7.8, color: _muted)),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(_latin(spec.title.toUpperCase()), style: style(16, bold: true, color: _teal)),
                  pw.SizedBox(height: 4),
                  pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(text: '${spec.numberLabel}  ', style: style(8.5, color: _muted)),
                      pw.TextSpan(text: _latin(spec.number.isEmpty ? '-' : spec.number), style: style(8.5, bold: true)),
                    ]),
                  ),
                  pw.SizedBox(height: 3),
                  pw.RichText(
                    text: pw.TextSpan(children: [
                      pw.TextSpan(text: '${spec.dateLabel}  ', style: style(8.5, color: _muted)),
                      pw.TextSpan(text: _latin(spec.date), style: style(8.5, bold: true)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4 * PdfPageFormat.mm),
          pw.Container(height: 0.7 * PdfPageFormat.mm, color: _teal),
          pw.SizedBox(height: 7 * PdfPageFormat.mm),
        ],
      );

  pw.Widget info(List<(String, String)> pairs) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final (label, value) in pairs) ...[
            pw.Text(_latin(label.toUpperCase()), style: style(7, color: _muted)),
            pw.SizedBox(height: 2),
            pw.Text(_latin(value.isEmpty ? '-' : value), style: style(9.5, bold: true)),
            pw.SizedBox(height: 3 * PdfPageFormat.mm),
          ],
        ],
      );

  final totalWidth = spec.columns.fold<double>(0, (sum, c) => sum + c.width);
  pw.Widget cell(String text, PdfColumn column, pw.TextStyle textStyle) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2.5 * PdfPageFormat.mm, vertical: 2 * PdfPageFormat.mm),
        child: pw.Text(
          _latin(text),
          style: textStyle,
          textAlign: column.alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  final rows = spec.rows.isEmpty ? [List.filled(spec.columns.length, '')..[0] = 'No items'] : spec.rows;
  final table = pw.Table(
    columnWidths: {
      for (var i = 0; i < spec.columns.length; i++) i: pw.FlexColumnWidth(spec.columns[i].width / totalWidth),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(
          color: _headFill,
          border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 0.4 * PdfPageFormat.mm)),
        ),
        repeat: true,
        children: [for (final c in spec.columns) cell(c.header, c, style(8, bold: true, color: _headInk))],
      ),
      for (final row in rows)
        pw.TableRow(
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6))),
          children: [
            for (var i = 0; i < spec.columns.length; i++)
              cell(i < row.length ? row[i] : '', spec.columns[i], style(8.8)),
          ],
        ),
    ],
  );

  pw.Widget totals() => pw.SizedBox(
        width: 96 * PdfPageFormat.mm,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            for (final t in spec.totals)
              t.strong
                  ? pw.Container(
                      margin: const pw.EdgeInsets.only(top: 1.5 * PdfPageFormat.mm),
                      padding: const pw.EdgeInsets.symmetric(horizontal: 3 * PdfPageFormat.mm, vertical: 2.4 * PdfPageFormat.mm),
                      color: _teal,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(_latin(t.label), style: style(10, bold: true, color: PdfColors.white)),
                          pw.Text(_latin(t.value), style: style(10, bold: true, color: PdfColors.white)),
                        ],
                      ),
                    )
                  : pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 3 * PdfPageFormat.mm, vertical: 1.6 * PdfPageFormat.mm),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6)),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Text(_latin(t.label), style: style(8.8, color: t.minus ? _minus : _ink)),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(_latin(t.value), style: style(8.8, color: t.minus ? _minus : _ink)),
                        ],
                      ),
                    ),
          ],
        ),
      );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 16 * PdfPageFormat.mm,
        marginRight: 16 * PdfPageFormat.mm,
        marginTop: 12 * PdfPageFormat.mm,
        marginBottom: 10 * PdfPageFormat.mm,
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 3 * PdfPageFormat.mm),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('This is a computer-generated document. No signature required.', style: style(7.5, color: _muted)),
            pw.Text(_clinicName, style: style(7.5, color: _muted)),
          ],
        ),
      ),
      build: (context) => [
        header(),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: info(spec.left)),
            pw.SizedBox(width: 10 * PdfPageFormat.mm),
            pw.Expanded(child: info(spec.right)),
          ],
        ),
        pw.SizedBox(height: 2 * PdfPageFormat.mm),
        table,
        pw.SizedBox(height: 5 * PdfPageFormat.mm),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            // Status stamp in the space left of the totals block.
            spec.stamp.isEmpty
                ? pw.SizedBox()
                : pw.Container(
                    margin: const pw.EdgeInsets.only(top: 1 * PdfPageFormat.mm),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4 * PdfPageFormat.mm, vertical: 2 * PdfPageFormat.mm),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _teal, width: 0.6 * PdfPageFormat.mm),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5 * PdfPageFormat.mm)),
                    ),
                    child: pw.Text(spec.stamp, style: style(11, bold: true, color: _teal)),
                  ),
            totals(),
          ],
        ),
        if (spec.note.isNotEmpty) ...[
          pw.SizedBox(height: 4 * PdfPageFormat.mm),
          pw.Text(_latin(spec.note), style: style(8, color: _muted)),
        ],
      ],
    ),
  );
  return doc.save();
}
