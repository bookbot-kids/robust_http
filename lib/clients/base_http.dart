import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';

enum HttpMethod { GET, POST, PUT, PATCH, DELETE, HEAD }

extension $HttpMethod on HttpMethod {
  String get name => EnumToString.convertToString(this);
}

abstract class BaseHttp {
  Future<dynamic> request(
      HttpMethod method, String url, Map<String, dynamic> headers,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false});

  Future<dynamic> download(String url,
      {String localPath, bool includeHttpResponse = false});

  Future<void> handleException(dynamic error);
}

dynamic parseJsonResponse(String responseBody) {
  return responseBody != null && responseBody.isNotEmpty
      ? jsonDecode(responseBody)
      : responseBody;
}
