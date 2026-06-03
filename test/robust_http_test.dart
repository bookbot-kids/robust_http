import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:robust_http/robust_http.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // TestWidgetsFlutterBinding installs an HttpOverrides that makes every real
  // HttpClient request return status 400. These are integration tests that hit
  // a live endpoint, so remove the override to allow real network access.
  HttpOverrides.global = null;

  // connectivity_plus has no platform implementation under `flutter test`, so
  // its method channel throws MissingPluginException. Mock it to report a live
  // connection (the error/retry paths call Connectivity().checkConnectivity()).
  const connectivityChannel =
      MethodChannel('dev.fluttercommunity.plus/connectivity');
  const testUrl = 'https://tools-httpstatus.pickup-services.com';

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      connectivityChannel,
      (call) async => call.method == 'check' ? <String>['wifi'] : null,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  group('HTTP: ', () {
    late HTTP http;
    setUp(() {
      http = HTTP(
        testUrl,
        {"connectTimeout": 3000, "receiveTimeout": 3000},
        // DioHttp(
        //     baseUrl: 'https://httpstat.us/',
        //     options: {"connectTimeout": 3000, "receiveTimeout": 3000}),
      );
    });

    test('Test full url', () async {
      expect((await http.get('${testUrl}/200')), equals("200 OK"));
    });

    test('Test path', () async {
      expect((await http.get('${testUrl}/200')), equals("200 OK"));
    });

    test('Test json header', () async {
      http.headers = {
        'accept': 'application/json',
      };
      final response = await http.get('${testUrl}/200');
      expect(response['code'], equals(200));
    });

    test('Test bad response gets exception', () async {
      expect(http.get('${testUrl}/500'), throwsException);
    });

    test('Test timeout', () async {
      expect(http.get('${testUrl}/200?sleep=5000'), throwsException);
    });
  });
}
