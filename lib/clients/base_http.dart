import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:robust_http/connection_helper.dart';
import 'package:robust_http/exceptions.dart';

enum HttpMethod { GET, POST, PUT, PATCH, DELETE, HEAD }

extension $HttpMethod on HttpMethod {
  String get name => EnumToString.convertToString(this);
}

abstract class BaseHttp {
  Future<dynamic> request(
    HttpMethod method,
    String url,
    Map<String, dynamic> headers, {
    Map<String, dynamic> parameters,
    dynamic data,
    bool includeHttpResponse = false,
    bool isMultipart = false,
  });

  Future<dynamic> download(String url,
      {String? localPath, bool includeHttpResponse = false});

  Future<void> handleException(dynamic error);

  Future<bool> validateConnectionError({bool validateNetwork = true}) async {
    if (!await ConnectionHelper.hasConnection()) {
      throw ConnectivityException('The connection is turn off',
          hasConnectionStatus: false);
    } else if (validateNetwork &&
        !await ConnectionHelper.hasInternetConnection()) {
      throw ConnectivityException(
          'The connection is turn on but there is no internet connection',
          hasConnectionStatus: true);
    }

    return true;
  }
}

dynamic parseJsonResponse(String? responseBody) {
  return responseBody != null && responseBody.isNotEmpty
      ? jsonDecode(responseBody)
      : responseBody;
}
