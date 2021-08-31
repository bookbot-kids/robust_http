import 'package:robust_http/clients/base_http.dart';
import 'package:robust_http/clients/simple_http.dart';

import 'exceptions.dart';

/// A [Dio] wrapper that can support retry when error happens
///
/// [Dio]:(https://pub.dev/packages/dio)
class HTTP {
  int _httpRetries = 3;
  BaseHttp _httpClient;

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
  HTTP(String baseUrl,
      [Map<String, dynamic> options = const {}, BaseHttp client]) {
    _httpRetries = options["httpRetries"] ?? _httpRetries;
    if (client == null) {
      _httpClient = SimpleHttp(
        baseUrl: baseUrl,
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
      {Map<String, dynamic> parameters,
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
      {Map<String, dynamic> parameters,
      bool includeHttpResponse = false}) async {
    return request(HttpMethod.GET, url,
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
    return request(HttpMethod.POST, url,
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
    return request(HttpMethod.PUT, url,
        parameters: parameters,
        data: data,
        includeHttpResponse: includeHttpResponse);
  }

  /// Download file, and manage the many network problems that can happen.
  /// Will only throw an exception when it's sure that there is no internet connection,
  /// exhausts its retries or gets an unexpected server response
  ///
  /// `localPath`: the save path. If it is null, then using stream download
  /// `includeHttpResponse`: true will return full http response (header, json data..), otherwise only return stream
  /// `url`: The file url
  Future<dynamic> download(String url,
      {String localPath, bool includeHttpResponse = false}) async {
    for (var i = 1; i <= (_httpRetries ?? this._httpRetries); i++) {
      try {
        _httpClient.download(url,
            localPath: localPath, includeHttpResponse: includeHttpResponse);
      } catch (error) {
        await _httpClient.handleException(error);
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
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    for (var i = 1; i <= (_httpRetries ?? this._httpRetries); i++) {
      try {
        return await _httpClient.request(method, url, headers,
            parameters: parameters, data: data);
      } catch (error) {
        await _httpClient.handleException(error);
      }
    }
    // Exhausted retries, so send back exception
    throw RetryFailureException();
  }
}
