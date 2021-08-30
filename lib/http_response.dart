


import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:robust_http/simple_http.dart';

class SimpleResponse {

  /// Response body. may have been transformed
  dynamic data;

  /// Response headers.
  Headers headers;

  /// Http status code.
  int statusCode;

  SimpleResponse.fromHttpResponse(Response httpResponse) {
    data = compute(parseJsonResponse, httpResponse.body);
    statusCode = httpResponse.statusCode;
    headers = Headers.fromMap(httpResponse.headers);
  }

}


class Headers {
  // Header field name
  static const acceptHeader = 'accept';
  static const contentEncodingHeader = 'content-encoding';
  static const contentLengthHeader = 'content-length';
  static const contentTypeHeader = 'content-type';
  static const wwwAuthenticateHeader = 'www-authenticate';

  // Header field value
  static const jsonContentType = 'application/json; charset=utf-8';
  static const formUrlEncodedContentType = 'application/x-www-form-urlencoded';
  static const textPlainContentType = 'text/plain';

  final Map<String, String> _map;

  Map<String, String> get map => _map;

  Headers() : _map = {};

  Headers.fromMap(Map<String, String> map)
      : _map = map.map((k, v) => MapEntry(k.trim().toLowerCase(), v));

  /// Convenience method for the value for a single valued header. If
  /// there is no header with the provided name, [:null:] will be
  /// returned. If the header has more than one value an exception is
  /// thrown.
  String value(String name) => _map[name.trim().toLowerCase()];

  void clear() {
    _map.clear();
  }

  bool get isEmpty => _map.isEmpty;
}
