import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/services/clinic_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatting matches the website template', () {
    test('money prints as PHP with thousands separators', () {
      expect(pdfMoney(1234.5), 'PHP 1,234.50');
      expect(pdfMoney(-300), '-PHP 300.00');
      expect(pdfRange(500, 800), 'PHP 500.00 - PHP 800.00');
      expect(pdfRange(500, 500), 'PHP 500.00');
    });

    test('dates read as calendar days', () {
      expect(pdfDate('2026-10-02'), 'October 2, 2026');
      expect(pdfDate(null), '-');
    });

    test('schedule names the day and the time span', () {
      expect(pdfSchedule('2026-10-02', '10:00:00', 60), 'Fri, Oct 2, 2026, 10:00 AM - 11:00 AM');
      expect(pdfSchedule('2026-10-02', null, 60), 'Fri, Oct 2, 2026');
    });

    test('patient number, method and file name', () {
      expect(pdfPatientNo(42), '#00042');
      expect(pdfPatientNo(null), '-');
      expect(pdfMethod('Wallet'), 'E-Wallet');
      expect(pdfMethod(null), '-');
      expect(pdfFileName('Invoice', '2663-9Z/'), 'Invoice-2663-9Z.pdf');
    });
  });

  test('an invoice renders to a PDF', () async {
    final bytes = await renderClinicPdf(const ClinicPdfSpec(
      title: 'Invoice',
      numberLabel: 'Invoice No.',
      number: 'INV-0001',
      dateLabel: 'Date Issued',
      date: 'October 2, 2026',
      left: [('Patient Name', 'Test Patient'), ('Appointment Reference', 'E3XZSR')],
      right: [('Attending Dentist', 'Dr. Jenneline Mariano'), ('Invoice Status', 'Paid in full')],
      columns: [
        PdfColumn('Description', 70),
        PdfColumn('Status', 22),
        PdfColumn('Rate', 32, alignRight: true),
        PdfColumn('Adjustment', 30, alignRight: true),
        PdfColumn('Amount', 32, alignRight: true),
      ],
      rows: [
        ['Dental Checkup – follow-up', 'Paid', 'PHP 500.00', '-', 'PHP 500.00'],
      ],
      totals: [
        PdfTotal('Total Service Cost', 'PHP 500.00'),
        PdfTotal('Less: Booking Deposit Credited', '-PHP 100.00', minus: true),
        PdfTotal('Final Balance Due', 'PHP 0.00', strong: true),
      ],
      stamp: 'PAID IN FULL',
      note: 'This invoice is an official statement of charges for the visit above.',
      fileName: 'Invoice-E3XZSR.pdf',
    ));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
