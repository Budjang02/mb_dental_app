import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/widgets/check_in_qr.dart';

/// Reference matrices from the `qrcode` npm package (level M), the encoder
/// family the website uses. `qrcode-generator` agrees on every one. Rebuild
/// with: `QR.create(code, {errorCorrectionLevel: 'M'}).modules`.
const Map<String, List<String>> _reference = {
  '123456': [
    '111111100001001111111',
    '100000100111101000001',
    '101110101010001011101',
    '101110101000101011101',
    '101110101110101011101',
    '100000101101001000001',
    '111111101010101111111',
    '000000001000000000000',
    '101111100101001111100',
    '001110001111111001111',
    '011001101010101101001',
    '001101011101111000111',
    '110001100010100100010',
    '000000001010100100100',
    '111111100011010010101',
    '100000101000000110110',
    '101110101111010010100',
    '101110101101111001000',
    '101110101110101100000',
    '100000100101111001010',
    '111111101100100100100',
  ],
  'E3XZSR': [
    '111111100111101111111',
    '100000100000101000001',
    '101110101001001011101',
    '101110101101101011101',
    '101110101010101011101',
    '100000101101001000001',
    '111111101010101111111',
    '000000001110000000000',
    '101111100101001111100',
    '101011000101111000010',
    '001001100100101101001',
    '110100010111111001011',
    '001010110110100100010',
    '000000001000100100101',
    '111111100101010011100',
    '100000101100000111111',
    '101110101111010010100',
    '101110101101111100100',
    '101110101010101101100',
    '100000100101111101001',
    '111111101010100100100',
  ],
  'MB-7Q2K9': [
    '111111100110001111111',
    '100000100010101000001',
    '101110101001001011101',
    '101110101110001011101',
    '101110101011101011101',
    '100000101010101000001',
    '111111101010101111111',
    '000000001001100000000',
    '101111100010101111100',
    '010110000010100101010',
    '011101110111010010001',
    '100010001110000111101',
    '000010111111010011011',
    '000000001101111100011',
    '111111100010101101100',
    '100000101011111100100',
    '101110101000100110010',
    '101110101100100111100',
    '101110101001010001100',
    '100000100110000100101',
    '111111101101010011100',
  ],
  'abc-12': [
    '111111100101101111111',
    '100000100110001000001',
    '101110101001001011101',
    '101110101110001011101',
    '101110101101101011101',
    '100000101100101000001',
    '111111101010101111111',
    '000000001011100000000',
    '101111100100101111100',
    '011101001100100100101',
    '011110101111010010010',
    '110100001000000111110',
    '010010101001010010000',
    '000000001011111100101',
    '111111100000101101010',
    '100000101011111110101',
    '101110101100100100010',
    '101110101010100011000',
    '101110101111010101100',
    '100000100110000000100',
    '111111101011010101010',
  ],
};

String _row(List<bool> row) => row.map((dark) => dark ? '1' : '0').join();

void main() {
  _reference.forEach((code, expected) {
    test('"$code" gives the same matrix as the website encoder', () {
      final matrix = checkInQrMatrix(code);
      expect(matrix.map(_row).toList(), expected);
    });
  });

  testWidgets('AppointmentQr encodes the verification link for its token', (tester) async {
    const qr = AppointmentQr(qrToken: '0123456789abcdef0123456789abcdef');
    expect(qr.payload, 'https://mbdentalcenter.web.app/verify/?t=0123456789abcdef0123456789abcdef');
    await tester.pumpWidget(const MaterialApp(home: Center(child: qr)));
    expect(tester.takeException(), isNull);
    // A 72-character link needs a larger symbol than a bare code.
    expect(checkInQrMatrix(qr.payload).length, greaterThan(21));
  });

  testWidgets('draws dark #0F172A modules on white with a 4-module quiet zone', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: CheckInQr(payload: 'E3XZSR', size: 203))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CheckInQr)), const Size(203, 203));
    expect(kCheckInQrForeground, const Color(0xFF0F172A));
    expect(kCheckInQrBackground, const Color(0xFFFFFFFF));
    expect(kCheckInQrQuietZone, 4);
  });
}
