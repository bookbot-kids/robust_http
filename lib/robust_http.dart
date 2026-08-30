import 'package:robust_http/clients/base_http.dart';
import 'package:robust_http/clients/dio_http.dart';
import 'package:robust_http/connection_helper.dart';
import 'package:robust_http/download/download_request.dart';
import 'package:robust_http/engine/http_engine.dart';
import 'package:robust_http/http_log_adapter.dart';
import 'package:robust_http/retry/retry_policy.dart';

import 'exceptions.dart';

/// A [Dio] wrapper that can support retry when error happens
///
/// [Dio]:(https://pub.dev/packages/dio)
class HTTP {
  int _httpRetries = 2;
  BaseHttp? _httpClient;

  /// Http request headers. The keys of initial headers will be converted to lowercase,
  /// for example 'Content-Type' will be converted to 'content-type'.
  ///
  /// You should use lowercase as the key name when you need to set the request header.
  Map<String, dynamic> headers = {};

  /// The HTTP stack this client actually uses. `native` means HTTP/2 (and
  /// HTTP/3 where the server offers it); `dartIo` means HTTP/1.1, where every
  /// concurrent request needs its own connection.
  HttpEngine get engine {
    final client = _httpClient;
    return client is DioHttp ? client.engine : HttpEngine.dartIo;
  }

  /// Configure HTTP with defaults from a Map
  ///
  /// `httpRetries` the retry number on failure, default is 3
  ///
  /// `connectTimeout` connection timeout, default is 60 seconds
  ///
  /// `receiveTimeout` receive timeout, default is 60 seconds
  ///
  /// `headers` http headers
  ///
  /// `logLevel` logLevel to print http log. Only accept `none`, `debug` or `error`. Default is `error`
  ///
  /// `httpEngine` which HTTP stack to use: `dartIo` (default, HTTP/1.1),
  /// `native` (NSURLSession/Cronet - HTTP/2 and HTTP/3) or `auto`
  ///
  /// `idleTimeout` seconds to keep a pooled connection alive, default 3.
  /// Raise it for clients that fetch many small files in a row
  ///
  /// `maxConnectionsPerHost` dart:io has no limit by default
  HTTP(String? baseUrl,
      [Map<String, dynamic> options = const {}, BaseHttp? client]) {
    _httpRetries = options["httpRetries"] ?? _httpRetries;
    if (client == null) {
      _httpClient = DioHttp(
        baseUrl: baseUrl ?? '',
        options: options,
      );
    } else {
      _httpClient = client;
    }
  }

  /// Does a http HEAD (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> head(String url,
      {Map<String, dynamic> parameters = const {},
      dynamic data,
      bool includeHttpResponse = false}) async {
    return request(HttpMethod.HEAD, url,
        parameters: parameters,
        data: data,
        includeHttpResponse: includeHttpResponse);
  }

  /// Does a http GET (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> get(String url,
      {Map<String, dynamic> parameters = const {},
      bool includeHttpResponse = false}) async {
    return request(HttpMethod.GET, url,
        parameters: parameters, includeHttpResponse: includeHttpResponse);
  }

  /// Does a http POST (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> post(
    String url, {
    Map<String, dynamic> parameters = const {},
    dynamic data,
    bool includeHttpResponse = false,
    bool isMultipart = false,
  }) async {
    return request(
      HttpMethod.POST,
      url,
      parameters: parameters,
      data: data,
      includeHttpResponse: includeHttpResponse,
      isMultipart: isMultipart,
    );
  }

  /// Does a http PUT (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> put(
    String url, {
    Map<String, dynamic> parameters = const {},
    dynamic data,
    bool includeHttpResponse = false,
    bool isMultipart = false,
  }) async {
    return request(
      HttpMethod.PUT,
      url,
      parameters: parameters,
      data: data,
      includeHttpResponse: includeHttpResponse,
      isMultipart: isMultipart,
    );
  }

  /// Does a http PATCH (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> patch(
    String url, {
    Map<String, dynamic> parameters = const {},
    dynamic data,
    bool includeHttpResponse = false,
    bool isMultipart = false,
  }) async {
    return request(
      HttpMethod.PATCH,
      url,
      parameters: parameters,
      data: data,
      includeHttpResponse: includeHttpResponse,
      isMultipart: isMultipart,
    );
  }

  /// Download file, and manage the many network problems that can happen.
  /// Will only throw an exception when it's sure that there is no internet connection,
  /// exhausts its retries or gets an unexpected server response
  ///
  /// `localPath`: the save path. If it is null, then using stream download
  /// `includeHttpResponse`: true will return full http response (header, json data..), otherwise only return stream
  /// `url`: The file url
  Future<dynamic> download(String url,
      {String? localPath, bool includeHttpResponse = false}) async {
    for (var i = 1; i <= _httpRetries; i++) {
      try {
        return await _httpClient?.download(url,
            localPath: localPath, includeHttpResponse: includeHttpResponse);
      } catch (e) {
        // don't retry in this case
        if ((e is UnexpectedResponseException && e.statusCode >= 500) ||
            e is ConnectivityException) {
          rethrow;
        } else {
          if (i == _httpRetries) {
            rethrow;
          } else {
            // slow down on next retry
            await Future.delayed(Duration(seconds: 2 * i));
          }
        }
      }
    }
    // Exhausted retries, so send back exception
    throw RetryFailureException();
  }

  /// Make call, and manage the many network problems that can happen.
  /// Will only throw an exception when it's sure that there is no internet connection,
  /// exhausts its retries or gets an unexpected server response
  ///
  /// `includeHttpResponse`: true will return full http response (header, json data..), otherwise only return json
  /// `parameters`: query parameters
  /// `method`: http method like GET, PUT, POST, HEAD..
  /// `url`: The url path
  Future<dynamic> request(HttpMethod method, String url,
      {Map<String, dynamic> parameters = const {},
      dynamic data,
      bool includeHttpResponse = false,
      bool isMultipart = false}) async {
    for (var i = 1; i <= _httpRetries; i++) {
      try {
        return await _httpClient?.request(
          method,
          url,
          headers,
          parameters: parameters,
          data: data,
          includeHttpResponse: includeHttpResponse,
          isMultipart: isMultipart,
        );
      } catch (error, stackTrace) {
        try {
          await _httpClient?.handleException(error, stackTrace);
        } catch (e) {
          // don't retry in this case
          if ((e is UnexpectedResponseException && e.statusCode >= 500) ||
              e is ConnectivityException) {
            rethrow;
          } else {
            if (i == _httpRetries) {
              rethrow;
            } else {
              // slow down on next retry
              await Future.delayed(Duration(seconds: 2 * i));
            }
          }
        }
      }
    }
    // Exhausted retries, so send back exception
    throw RetryFailureException();
  }

  /// Downloads a file with resume, verification and network-aware retries.
  ///
  /// Prefer this over [download] for anything large or anything a user is
  /// waiting on:
  ///  * writes `<savePath>.part` and renames on success, so a killed app never
  ///    leaves a truncated file that looks complete
  ///  * continues an interrupted transfer with `Range`/`If-Range` instead of
  ///    starting over - the difference between finishing and never finishing
  ///    on a 3G connection
  ///  * classifies failures: a 404 stops immediately, a 503 or timeout backs
  ///    off with jitter, and `Retry-After` is honoured
  ///  * stops early when the device is offline so the caller can wait for
  ///    connectivity instead of burning attempts
  ///
  /// Throws [ConnectivityException] when offline, [UnexpectedResponseException]
  /// for a permanent server answer, or the last error after [policy] is spent.
  Future<DownloadResult> downloadFile(
    DownloadRequest request, {
    RetryPolicy policy = const RetryPolicy(),
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= policy.maxAttempts; attempt++) {
      try {
        final client = _httpClient;
        if (client == null) {
          throw UnknownException('HTTP client is not initialised');
        }
        return await client.downloadFile(request);
      } catch (error) {
        lastError = error;
        final verdict = policy.verdict(error);

        if (verdict == RetryVerdict.permanent) {
          rethrow;
        }

        if (verdict == RetryVerdict.offline) {
          rethrow;
        }

        // A transient failure. Check we still have a network before spending
        // another attempt on it. If the connectivity check itself fails we
        // assume we are online - a broken probe must not block downloads.
        var connected = true;
        try {
          connected = await ConnectionHelper.shared.hasConnection();
        } catch (_) {}
        if (!connected) {
          throw ConnectivityException('The connection is turn off',
              hasConnectionStatus: false);
        }

        if (attempt == policy.maxAttempts) {
          rethrow;
        }

        final delay = policy.delayFor(
          attempt,
          retryAfter:
              error is UnexpectedResponseException ? error.retryAfter : null,
        );
        HttpLogAdapter.shared.logger?.i(
            'Download attempt $attempt/${policy.maxAttempts} failed for '
            '${request.url} ($error), retrying in ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
      }
    }

    throw lastError ?? RetryFailureException();
  }
}
