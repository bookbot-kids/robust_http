import 'package:flutter_test/flutter_test.dart';

import 'package:robust_http/robust_http.dart';

void main() {
  group('HTTP: ', () {
    late HTTP http;
    setUp(() {
      http = HTTP(
        'https://httpstat.us/',
        {"connectTimeout": 3000, "receiveTimeout": 3000},
        // DioHttp(
        //     baseUrl: 'https://httpstat.us/',
        //     options: {"connectTimeout": 3000, "receiveTimeout": 3000}),
      );
    });

    test('Test full url', () async {
      expect((await http.get('https://httpstat.us/200')), equals("200 OK"));
    });

    test('Test path', () async {
      expect((await http.get('200')), equals("200 OK"));
    });

    test('Test json header', () async {
      http.headers = {
        'accept': 'application/json',
      };
      final response = await http.get('200');
      expect(response['code'], equals(200));
    });

    test('Test bad response gets exception', () async {
      expect(http.get('500'), throwsException);
    });

    test('Test timeout', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(http.get('https://httpstat.us/200?sleep=5000'), throwsException);
    });
  });
}
