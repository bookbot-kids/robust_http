import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity/connectivity.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:robust_http/base_http.dart';
import 'package:http/http.dart' as http;
import 'package:robust_http/http_response.dart';

import 'exceptions.dart';

class SimpleHttp extends BaseHttp {
  String baseUrl;
  http.Client client;
  Duration timeout;

  SimpleHttp(
      {@required String baseUrl, Map<String, dynamic> options = const {}}) {
    this.baseUrl = baseUrl;
    client = http.Client();
    timeout = Duration(milliseconds: options["connectTimeout"] ?? 60000);
  }

  @override
  Future<dynamic> request(
      String method, String url, Map<String, dynamic> headers,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    final response = await _mapRequest(method, url,
            parameters: parameters, data: data, headers: headers)
        .timeout(timeout,
            onTimeout: () =>
                throw TimeoutException('Request timeout', timeout));
    if (response.statusCode >= 400) {
      throw UnexpectedResponseException(response.request.url.toString(),
          response.statusCode, response.reasonPhrase);
    }
    return includeHttpResponse
        ? SimpleResponse.fromHttpResponse(response)
        : compute(parseJsonResponse, response.body);
  }

  Future<Response> _mapRequest(String method, String url,
      {Map<String, dynamic> parameters,
      data,
      Map<String, String> headers = const {}}) {
    switch (method) {
      case 'GET':
        return client.get(_buildUri(url, parameters), headers: headers);
      case 'HEAD':
        return client.head(_buildUri(url, parameters), headers: headers);
      case 'POST':
        return client.post(_buildUri(url, parameters),
            headers: headers, body: data);
      case 'PUT':
        return client.put(_buildUri(url, parameters),
            headers: headers, body: data);
      case 'PATCH':
        return client.patch(_buildUri(url, parameters),
            headers: headers, body: data);
      case 'DELETE':
        return client.delete(_buildUri(url, parameters),
            headers: headers, body: data);
      default:
        return client.get(_buildUri(url, parameters), headers: headers);
    }
  }

  Uri _buildUri(String endpoint, [Map<String, dynamic> query]) {
    final queryParameters = query?.map((k, v) => MapEntry('$k', '$v')) ?? {};
    final fullUrl = endpoint.contains('http') ? endpoint : '$baseUrl/$endpoint';
    final uri = Uri.parse(fullUrl);
    queryParameters.addAll(uri.queryParameters);
    return Uri.https(uri.authority, uri.path, queryParameters);
  }

  @override
  Future<void> handleException(error) async {
    if (error is UnexpectedResponseException) {
      throw error;
    } else if (error is TimeoutException) {
      if (await Connectivity().checkConnectivity() == ConnectivityResult.none) {
        throw ConnectivityException();
      }
    } else {
      throw UnknownException(error.message);
    }
  }

  @override
  Future<dynamic> download(String url,
      {String localPath, bool includeHttpResponse = false}) async {
    var req = await client.get(Uri.parse(url));
    var bytes = req.bodyBytes;
    File file = new File(localPath);
    await file.writeAsBytes(bytes);
    return file;
  }
}

dynamic parseJsonResponse(String responseBody) {
  return responseBody != null && responseBody.isNotEmpty
      ? jsonDecode(responseBody)
      : responseBody;
}
