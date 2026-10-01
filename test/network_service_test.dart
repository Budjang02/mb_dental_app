import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mb_dental_app/services/network_service.dart';

void main() {
  test('sends requests without a DNS pre-flight gate', () async {
    var requestWasSent = false;
    final client = ConnectivityAwareClient(
      MockClient((request) async {
        requestWasSent = true;
        return http.Response('ok', 200);
      }),
    );

    final response = await client.get(Uri.parse('https://example.invalid/auth/v1/token'));

    expect(requestWasSent, isTrue);
    expect(response.statusCode, 200);
  });
}
