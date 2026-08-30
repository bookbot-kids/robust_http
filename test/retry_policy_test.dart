import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robust_http/exceptions.dart';
import 'package:robust_http/retry/retry_policy.dart';

void main() {
  group('RetryPolicy.verdict', () {
    const policy = RetryPolicy();

    test('4xx is permanent, so a missing file is never retried', () {
      for (final status in [400, 401, 403, 404, 410, 422]) {
        expect(policy.verdict(UnexpectedResponseException('u', status, '')),
            RetryVerdict.permanent,
            reason: '$status should not be retried');
      }
    });

    test('408 and 429 are transient even though they are 4xx', () {
      for (final status in [408, 429]) {
        expect(policy.verdict(UnexpectedResponseException('u', status, '')),
            RetryVerdict.retry);
      }
    });

    test('5xx is retried', () {
      for (final status in [500, 502, 503, 504]) {
        expect(policy.verdict(UnexpectedResponseException('u', status, '')),
            RetryVerdict.retry);
      }
    });

    test('offline is reported separately so the caller can wait', () {
      expect(policy.verdict(ConnectivityException('off')), RetryVerdict.offline);
    });

    test('timeouts are retried, cancellation is not', () {
      final options = RequestOptions(path: '/x');
      expect(
          policy.verdict(DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout)),
          RetryVerdict.retry);
      expect(
          policy.verdict(DioException(
              requestOptions: options, type: DioExceptionType.cancel)),
          RetryVerdict.permanent);
    });
  });

  group('RetryPolicy.delayFor', () {
    test('grows exponentially and stays under the cap', () {
      const policy = RetryPolicy(
          baseDelay: Duration(seconds: 1),
          maxDelay: Duration(seconds: 10),
          useJitter: false);
      expect(policy.delayFor(1), const Duration(seconds: 1));
      expect(policy.delayFor(2), const Duration(seconds: 2));
      expect(policy.delayFor(3), const Duration(seconds: 4));
      expect(policy.delayFor(9), const Duration(seconds: 10));
    });

    test('jitter keeps every delay inside the exponential bound', () {
      const policy = RetryPolicy(baseDelay: Duration(seconds: 1));
      for (var i = 0; i < 200; i++) {
        final delay = policy.delayFor(3);
        expect(delay, greaterThanOrEqualTo(Duration.zero));
        expect(delay, lessThanOrEqualTo(const Duration(seconds: 4)));
      }
    });

    test('a Retry-After from the server wins over our own backoff', () {
      const policy = RetryPolicy(maxDelay: Duration(seconds: 60));
      expect(policy.delayFor(1, retryAfter: const Duration(seconds: 30)),
          const Duration(seconds: 30));
    });

    test('Retry-After is still capped', () {
      const policy = RetryPolicy(maxDelay: Duration(seconds: 60));
      expect(policy.delayFor(1, retryAfter: const Duration(hours: 1)),
          const Duration(seconds: 60));
    });
  });

  group('RetryPolicy.retryAfterOf', () {
    Response<void> responseWith(String value) => Response<void>(
          requestOptions: RequestOptions(path: '/x'),
          headers: Headers.fromMap({
            'retry-after': [value]
          }),
        );

    test('reads a delay in seconds', () {
      expect(RetryPolicy.retryAfterOf(responseWith('12')),
          const Duration(seconds: 12));
    });

    test('ignores a value it cannot parse', () {
      expect(RetryPolicy.retryAfterOf(responseWith('soon')), isNull);
    });

    test('null response has no delay', () {
      expect(RetryPolicy.retryAfterOf(null), isNull);
    });
  });
}
