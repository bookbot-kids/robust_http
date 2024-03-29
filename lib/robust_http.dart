import 'package:robust_http/clients/base_http.dart';
import 'package:robust_http/clients/dio_http.dart';

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
      } catch (error) {
        try {
          await _httpClient?.handleException(error);
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
}
