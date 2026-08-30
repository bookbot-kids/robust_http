import 'dart:math';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:robust_http/exceptions.dart';

/// What to do with a failed attempt.
enum RetryVerdict {
  /// Wait and try again.
  retry,

  /// The server told us this will never work (404, 403, 400...). Stop.
  permanent,

  /// There is no network at all. The caller should wait for connectivity
  /// instead of burning attempts and battery.
  offline,
}

/// Retry rules shared by requests and downloads.
///
/// Two things this fixes compared to a plain retry loop:
///  * **Classification.** A 404 is retried zero times, a 503 is retried with
///    backoff. Retrying a 404 only wastes battery, and giving up on a 503
///    loses a download that would have worked a second later.
///  * **Jitter.** Fixed backoff makes every device on the same Wi-Fi retry at
///    the same moment. Full jitter spreads them out.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
    this.useJitter = true,
  });

  /// A shorter policy for anything a user is actively waiting on.
  static const interactive = RetryPolicy(maxAttempts: 3, maxDelay: Duration(seconds: 8));

  /// A patient policy for background work (packs, prefetching).
  static const background = RetryPolicy(maxAttempts: 6, maxDelay: Duration(seconds: 60));

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool useJitter;

  static final _random = Random();

  /// Status codes that will never succeed by trying again.
  static bool isPermanentStatus(int statusCode) {
    if (statusCode == 408 || statusCode == 429) {
      // Timeout / rate limit: transient by definition.
      return false;
    }
    return statusCode >= 400 && statusCode < 500;
  }

  RetryVerdict verdict(Object error) {
    if (error is ConnectivityException) {
      return RetryVerdict.offline;
    }

    if (error is UnexpectedResponseException) {
      return isPermanentStatus(error.statusCode)
          ? RetryVerdict.permanent
          : RetryVerdict.retry;
    }

    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null && isPermanentStatus(status)) {
        return RetryVerdict.permanent;
      }
      switch (error.type) {
        case DioExceptionType.cancel:
          return RetryVerdict.permanent;
        case DioExceptionType.badCertificate:
          // Usually a captive portal intercepting TLS rather than a real
          // attack on our public CDN - worth one more try on a new network.
          return RetryVerdict.retry;
        default:
          return RetryVerdict.retry;
      }
    }

    // Timeouts, socket errors, corrupted payloads: all worth another attempt.
    return RetryVerdict.retry;
  }

  /// How long to wait before attempt [attempt] (1-based).
  ///
  /// Honours `Retry-After` when the server sent one - a 429 from Cloudflare
  /// means back off exactly that long, not what we guessed.
  Duration delayFor(int attempt, {Duration? retryAfter}) {
    if (retryAfter != null) {
      return retryAfter > maxDelay ? maxDelay : retryAfter;
    }

    final exponential = baseDelay * pow(2, (attempt - 1).clamp(0, 10)).toDouble();
    final capped = exponential > maxDelay ? maxDelay : exponential;
    if (!useJitter) {
      return capped;
    }

    // Full jitter: anywhere in [0, capped]. Keeps a room full of tablets from
    // retrying in lockstep.
    return Duration(milliseconds: _random.nextInt(capped.inMilliseconds + 1));
  }

  /// Reads `Retry-After` (seconds, or an HTTP date) from a response.
  static Duration? retryAfterOf(Response? response) {
    final raw = response?.headers.value('retry-after');
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final seconds = int.tryParse(raw.trim());
    if (seconds != null) {
      return Duration(seconds: seconds);
    }

    try {
      final diff = parseHttpDate(raw).difference(DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      return null;
    }
  }
}
