import 'package:connectivity/connectivity.dart';
import 'package:dio/dio.dart';
import 'package:robust_http/robust_log.dart';

import 'exceptions.dart';

/// A [Dio] wrapper that can support retry when error happens
///
/// [Dio]:(https://pub.dev/packages/dio)
class HTTP {
  int _httpRetries = 3;
  Dio _dio;

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
  /// `logLevel` logLevel to print http log. Only accept `debug` or `error`. Default only print error
  HTTP(String baseUrl, [Map<String, dynamic> options = const {}]) {
    _httpRetries = options["httpRetries"] ?? _httpRetries;

    final baseOptions = BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: options["connectTimeout"] ?? 60000,
        receiveTimeout: options["receiveTimeout"] ?? 60000,
        headers: options["headers"] ?? {});

    _dio = new Dio(baseOptions);
    var logLevel = options['logLevel'];
    _dio.interceptors.add(LoggerInterceptor(logLevel == 'debug'));
  }

  /// Does a http GET (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> get(String url,
      {Map<String, dynamic> parameters,
      bool includeHttpResponse = false}) async {
    return request("GET", url,
        parameters: parameters, includeHttpResponse: includeHttpResponse);
  }

  /// Does a http POST (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> post(String url,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    return request("POST", url,
        parameters: parameters,
        data: data,
        includeHttpResponse: includeHttpResponse);
  }

  /// Does a http PUT (with optional overrides).
  /// You can pass the full url, or the path after the baseUrl.
  /// Will timeout, check connectivity and retry until there is a response.
  /// Will handle most success or failure cases and will respond with either data or exception.
  Future<dynamic> put(String url,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    return request("PUT", url,
        parameters: parameters,
        data: data,
        includeHttpResponse: includeHttpResponse);
  }

  /// Make call, and manage the many network problems that can happen.
  /// Will only throw an exception when it's sure that there is no internet connection,
  /// exhausts its retries or gets an unexpected server response
  ///
  /// `includeHttpResponse`: true will return full http response (header, json data..), otherwise only return json
  /// `parameters`: query parameters
  /// `method`: http method like GET, PUT, POST..
  /// `url`: The url path
  Future<dynamic> request(String method, String url,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    _dio.options.method = method;

    for (var i = 1; i <= (_httpRetries ?? this._httpRetries); i++) {
      try {
        var response =
            (await _dio.request(url, queryParameters: parameters, data: data));
        return includeHttpResponse == true ? response : response.data;
      } catch (error) {
        await _handleException(error);
      }
    }
    // Exhausted retries, so send back exception
    throw RetryFailureException();
  }

  /// Get dio instance
  Dio get dio {
    return _dio;
  }

  /// Http request headers. The keys of initial headers will be converted to lowercase,
  /// for example 'Content-Type' will be converted to 'content-type'.
  ///
  /// You should use lowercase as the key name when you need to set the request header.
  set headers(Map<String, dynamic> map) {
    _dio.options.headers = map;
  }

  /// Handle exceptions that come from various failures
  Future<void> _handleException(dynamic error) async {
    print(error.toString());
    if (error is DioError) {
      if (error.type == DioErrorType.CONNECT_TIMEOUT ||
          error.type == DioErrorType.RECEIVE_TIMEOUT) {
        if (await Connectivity().checkConnectivity() ==
            ConnectivityResult.none) {
          throw ConnectivityException();
        }
      } else if (error.type == DioErrorType.RESPONSE) {
        throw UnexpectedResponseException(error.response);
      } else {
        print(error.toString());
        throw UnknownException(error.message);
      }
    } else {
      print(error.toString());
      throw UnknownException(error.message);
    }
  }
}
