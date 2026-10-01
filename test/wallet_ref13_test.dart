import 'package:flutter_test/flutter_test.dart';
import 'package:mb_dental_app/widgets/wallet_txn_widgets.dart';

void main() {
  group('walletRef13', () {
    test('matches the website for a known reference', () {
      expect(walletRef13('APPT-9e519947'), '4041254521580');
      // Computed by the website's own _walletRef13 (js/patient-wallet.js).
      expect(walletRef13('pay_4f9XyZ12abcD'), '1071604980921');
      expect(walletRef13('WTX-2026-000123'), '8066659806698');
      expect(walletRef13('ñ₱'), '6574366024343');
    });

    test('is always 13 digits and stable', () {
      final ref = walletRef13('REF-1726480000000');
      expect(ref, matches(RegExp(r'^\d{13}$')));
      expect(walletRef13('REF-1726480000000'), ref);
    });

    test('shows a dash when there is no reference', () {
      expect(walletRef13(''), '—');
      expect(walletRef13(null), '—');
    });
  });

  test('date labels are Manila time whatever the device zone', () {
    // 03:40 UTC is 11:40 in Manila.
    final d = DateTime.utc(2026, 9, 16, 3, 40);
    expect(formatTxnMonth(d), 'September 2026');
    expect(formatTxnDay(d), '16 September 2026');
    expect(formatTxnDateTime(d), 'Sep 16, 2026, 11:40 AM');
  });
}
