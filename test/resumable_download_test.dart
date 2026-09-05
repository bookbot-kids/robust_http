import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robust_http/clients/dio_http.dart';
import 'package:robust_http/download/download_request.dart';
import 'package:robust_http/exceptions.dart';
import 'package:robust_http/retry/retry_policy.dart';
import 'package:robust_http/robust_http.dart';

void main() {
  late HttpServer server;
  late Directory tempDir;
  late String baseUrl;

  // Each test installs its own handler.
  late Future<void> Function(HttpRequest) handler;

  // What the server saw, so we can assert on resume behaviour.
  final rangeHeaders = <String?>[];
  final ifRangeHeaders = <String?>[];
  var requestCount = 0;

  final payload =
      List<int>.generate(64 * 1024, (i) => (i * 31 + 7) % 256, growable: false);
  final payloadMd5 = md5.convert(payload).toString();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('robust_http_test');
    rangeHeaders.clear();
    ifRangeHeaders.clear();
    requestCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.host}:${server.port}';
    server.listen((request) async {
      requestCount++;
      rangeHeaders.add(request.headers.value('range'));
      ifRangeHeaders.add(request.headers.value('if-range'));
      await handler(request);
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDir.delete(recursive: true);
  });

  /// Serves [payload], honouring Range, optionally cutting the connection
  /// after [cutAfter] bytes to simulate a dropped mobile connection.
  Future<void> Function(HttpRequest) fileHandler({int? cutAfter}) {
    return (request) async {
      final range = request.headers.value('range');
      var start = 0;
      if (range != null && range.startsWith('bytes=')) {
        start = int.parse(range.substring(6).split('-').first);
      }
      final body = payload.sublist(start);

      if (cutAfter == null) {
        if (start > 0) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set('content-range',
              'bytes $start-${payload.length - 1}/${payload.length}');
        }
        request.response.headers.set('content-type', 'application/octet-stream');
        request.response.headers.set('etag', '"v1"');
        request.response.headers.contentLength = body.length;
        request.response.add(body);
        await request.response.close();
        return;
      }

      // Promise the full length, send a prefix, then kill the socket - what a
      // mobile connection dropping mid-file looks like to the client.
      final socket = await request.response.detachSocket(writeHeaders: false);
      final head = StringBuffer()
        ..write(start > 0
            ? 'HTTP/1.1 206 Partial Content\r\n'
            : 'HTTP/1.1 200 OK\r\n')
        ..write('content-type: application/octet-stream\r\n')
        ..write('etag: "v1"\r\n')
        ..write('content-length: ${body.length}\r\n');
      if (start > 0) {
        head.write(
            'content-range: bytes $start-${payload.length - 1}/${payload.length}\r\n');
      }
      head.write('\r\n');
      socket.add(utf8.encode(head.toString()));
      socket.add(body.sublist(0, min(cutAfter, body.length)));
      await socket.flush();
      await socket.close();
      socket.destroy();
    };
  }

  DioHttp clientFor() => DioHttp(baseUrl: baseUrl, options: {
        'logLevel': 'none',
        'connectTimeout': 5000,
        'receiveTimeout': 5000,
      });

  test('downloads a file and verifies its md5', () async {
    handler = fileHandler();
    final savePath = '${tempDir.path}/book.json';

    final result = await clientFor().downloadFile(DownloadRequest(
      url: '$baseUrl/book.json',
      savePath: savePath,
      expectedMd5: payloadMd5,
    ));

    expect(result.fromCache, isFalse);
    expect(result.totalBytes, payload.length);
    expect(await File(savePath).readAsBytes(), payload);
    // No leftovers.
    expect(File('$savePath.part').existsSync(), isFalse);
    expect(File('$savePath.part.meta').existsSync(), isFalse);
  });

  test('resumes with a Range request after the connection drops', () async {
    const cut = 20000;
    handler = fileHandler(cutAfter: cut);
    final savePath = '${tempDir.path}/big.webp';
    final client = clientFor();
    final request = DownloadRequest(
      url: '$baseUrl/big.webp',
      savePath: savePath,
      expectedMd5: payloadMd5,
      stallTimeout: const Duration(seconds: 2),
    );

    // First attempt dies mid-stream but leaves a .part behind.
    await expectLater(client.downloadFile(request), throwsA(isNotNull));
    final partial = await File('$savePath.part').length();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(payload.length));

    // Second attempt completes it.
    handler = fileHandler();
    final result = await client.downloadFile(request);

    expect(result.resumed, isTrue);
    expect(rangeHeaders.last, 'bytes=$partial-');
    // Only the missing bytes went over the wire.
    expect(result.downloadedBytes, payload.length - partial);
    expect(await File(savePath).readAsBytes(), payload);
  });

  test('Last-Modified validates a resume when ETag is unavailable', () async {
    final savePath = '${tempDir.path}/last-modified.webp';
    const partial = 12000;
    await File('$savePath.part').writeAsBytes(payload.take(partial).toList());
    await File('$savePath.part.meta').writeAsString(json.encode({
      'url': '$baseUrl/last-modified.webp',
      'etag': null,
      'lastModified': 'Wed, 21 Oct 2015 07:28:00 GMT',
    }));
    handler = fileHandler();

    final result = await clientFor().downloadFile(DownloadRequest(
      url: '$baseUrl/last-modified.webp',
      savePath: savePath,
      expectedMd5: payloadMd5,
    ));

    expect(result.resumed, isTrue);
    expect(rangeHeaders.single, 'bytes=$partial-');
    expect(ifRangeHeaders.single, 'Wed, 21 Oct 2015 07:28:00 GMT');
  });

  test('a partial without a validator restarts safely', () async {
    final savePath = '${tempDir.path}/unvalidated.webp';
    await File('$savePath.part').writeAsBytes(payload.take(12000).toList());
    await File('$savePath.part.meta').writeAsString(json.encode({
      'url': '$baseUrl/unvalidated.webp',
      'etag': null,
      'lastModified': null,
    }));
    handler = fileHandler();

    final result = await clientFor().downloadFile(DownloadRequest(
      url: '$baseUrl/unvalidated.webp',
      savePath: savePath,
      expectedMd5: payloadMd5,
    ));

    expect(result.resumed, isFalse);
    expect(rangeHeaders.single, isNull);
    expect(await File(savePath).readAsBytes(), payload);
  });

  test('small-file fast path skips resume metadata', () async {
    handler = fileHandler(cutAfter: 12000);
    final savePath = '${tempDir.path}/small.webp';
    final request = DownloadRequest(
      url: '$baseUrl/small.webp',
      savePath: savePath,
      resumeMetadataThresholdBytes: payload.length + 1,
    );

    await expectLater(clientFor().downloadFile(request), throwsA(isNotNull));
    expect(File('$savePath.part').existsSync(), isTrue);
    expect(File('$savePath.part.meta').existsSync(), isFalse);

    handler = fileHandler();
    await clientFor().downloadFile(request);
    expect(rangeHeaders.last, isNull,
        reason: 'a small interrupted file restarts instead of using Range');
  });

  test('coalesced progress always reports the final byte count', () async {
    handler = fileHandler();
    final progress = <DownloadProgress>[];

    final result = await clientFor().downloadFile(DownloadRequest(
      url: '$baseUrl/progress.webp',
      savePath: '${tempDir.path}/progress.webp',
      progressInterval: const Duration(days: 1),
      onProgress: progress.add,
    ));

    expect(progress.length, lessThanOrEqualTo(2));
    expect(progress.last.received, payload.length);
    expect(progress.last.downloadedBytes, payload.length);
    expect(progress.last.attempt, 1);
    expect(progress.last.timeToFirstByte, isNotNull);
    expect(result.timeToFirstByte, isNotNull);
  });

  test('an existing file is a cache hit and costs no request', () async {
    handler = fileHandler();
    final savePath = '${tempDir.path}/cached.webp';
    await File(savePath).writeAsBytes(payload);

    final result = await clientFor().downloadFile(
        DownloadRequest(url: '$baseUrl/cached.webp', savePath: savePath));

    expect(result.fromCache, isTrue);
    expect(requestCount, 0);
  });

  test('rejects a captive portal login page', () async {
    handler = (request) async {
      request.response.headers.set('content-type', 'text/html');
      request.response.write('<html>Please sign in to the Wi-Fi</html>');
      await request.response.close();
    };

    await expectLater(
      clientFor().downloadFile(DownloadRequest(
        url: '$baseUrl/cover.webp',
        savePath: '${tempDir.path}/cover.webp',
        expectedContentType: 'image/',
      )),
      throwsA(isA<InvalidContentException>()),
    );
  });

  test('rejects a file whose md5 does not match', () async {
    handler = fileHandler();
    await expectLater(
      clientFor().downloadFile(DownloadRequest(
        url: '$baseUrl/book.json',
        savePath: '${tempDir.path}/book.json',
        expectedMd5: 'deadbeef',
      )),
      throwsA(isA<InvalidContentException>()),
    );
    // The bad bytes are gone, so the next attempt starts clean.
    expect(File('${tempDir.path}/book.json.part').existsSync(), isFalse);
  });

  test('a 404 fails immediately without retrying', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };

    final http = HTTP(baseUrl, {'logLevel': 'none'});
    await expectLater(
      http.downloadFile(
        DownloadRequest(
            url: '$baseUrl/missing.webp',
            savePath: '${tempDir.path}/missing.webp'),
        policy: const RetryPolicy(maxAttempts: 4, baseDelay: Duration(milliseconds: 1)),
      ),
      throwsA(isA<UnexpectedResponseException>()
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
    expect(requestCount, 1, reason: 'a 404 must not be retried');
  });

  test('a 503 is retried and then succeeds', () async {
    handler = (request) async {
      if (requestCount < 3) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.headers.set('retry-after', '0');
        await request.response.close();
        return;
      }
      await fileHandler()(request);
    };

    final http = HTTP(baseUrl, {'logLevel': 'none'});
    final result = await http.downloadFile(
      DownloadRequest(
          url: '$baseUrl/book.json', savePath: '${tempDir.path}/book.json'),
      policy: const RetryPolicy(maxAttempts: 5, baseDelay: Duration(milliseconds: 1)),
    );

    expect(result.totalBytes, payload.length);
    expect(requestCount, 3);
    expect(result.attempts, 3);
  });

  test('a 503 exposes Retry-After before retry policy handles it', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.set('retry-after', '7');
      request.response.write('temporarily unavailable');
      await request.response.close();
    };

    await expectLater(
      clientFor().downloadFile(DownloadRequest(
        url: '$baseUrl/busy.webp',
        savePath: '${tempDir.path}/busy.webp',
      )),
      throwsA(isA<UnexpectedResponseException>().having(
          (error) => error.retryAfter, 'retryAfter', const Duration(seconds: 7))),
    );
  });

  test('retry result includes bytes and time from failed attempts', () async {
    handler = (request) => requestCount == 1
        ? fileHandler(cutAfter: 12000)(request)
        : fileHandler()(request);
    final progress = <DownloadProgress>[];
    final result = await HTTP(baseUrl, {'logLevel': 'none'}).downloadFile(
      DownloadRequest(
        url: '$baseUrl/retry.webp',
        savePath: '${tempDir.path}/retry.webp',
        onProgress: progress.add,
      ),
      policy: const RetryPolicy(
        maxAttempts: 2,
        baseDelay: Duration.zero,
        useJitter: false,
      ),
    );

    expect(result.attempts, 2);
    expect(result.downloadedBytes, payload.length);
    expect(progress.map((item) => item.attempt).toSet(), {1, 2});
  });

  test('cancellation interrupts Retry-After backoff', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.set('retry-after', '30');
      await request.response.close();
    };
    final token = CancelToken();
    final watch = Stopwatch()..start();
    final future = HTTP(baseUrl, {'logLevel': 'none'}).downloadFile(
      DownloadRequest(
        url: '$baseUrl/cancel.webp',
        savePath: '${tempDir.path}/cancel.webp',
        cancelToken: token,
      ),
      policy: const RetryPolicy(maxAttempts: 2),
    );
    final expectation = expectLater(future, throwsA(isA<DioException>()));
    while (requestCount == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    token.cancel('test cancellation');

    await expectation;
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(requestCount, 1);
  });

  test('result exposes response status and cache headers', () async {
    handler = (request) async {
      request.response.headers.set('content-type', 'application/octet-stream');
      request.response.headers.set('cf-cache-status', 'HIT');
      request.response.add(payload);
      await request.response.close();
    };

    final result = await clientFor().downloadFile(DownloadRequest(
      url: '$baseUrl/headers.webp',
      savePath: '${tempDir.path}/headers.webp',
    ));

    expect(result.statusCode, HttpStatus.ok);
    expect(result.header('CF-Cache-Status'), 'HIT');
  });
}
