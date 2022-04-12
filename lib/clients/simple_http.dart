import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:robust_http/clients/base_http.dart';
import 'package:http/http.dart' as http;
import 'package:robust_http/http_log_adapter.dart';
import 'package:robust_http/http_response.dart';

import '../exceptions.dart';

@Deprecated(
    'This class has some trouble with dynamic type in header & parameter')
class SimpleHttp extends BaseHttp {
  late String baseUrl;
  late http.Client client;
  late Duration timeout;

  SimpleHttp(
      {required String baseUrl, Map<String, dynamic> options = const {}}) {
    this.baseUrl = baseUrl;
    client = http.Client();
    timeout = Duration(milliseconds: options["connectTimeout"] ?? 60000);
  }

  @override
  Future<dynamic> request(
      HttpMethod method, String url, Map<String, dynamic> headers,
      {Map<String, dynamic> parameters = const {},
      dynamic data,
      bool includeHttpResponse = false}) async {
    final response = await _mapRequest(method, url,
            parameters: parameters, data: data, headers: headers)
        .timeout(timeout,
            onTimeout: () =>
                throw TimeoutException('Request timeout', timeout));
    if (response.statusCode >= 400) {
      HttpLogAdapter.shared.logger
          ?.e('SimpleHttp Error: Reason: ${response.reasonPhrase}: ErrorCode: '
              '${response.statusCode}');
      throw UnexpectedResponseException(response.request?.url.toString() ?? '',
          response.statusCode, response.reasonPhrase ?? '');
    }
    HttpLogAdapter.shared.logger?.e('SimpleHttp Response: ${response.body}');
    return includeHttpResponse
        ? SimpleResponse.fromHttpResponse(response)
        : compute(parseJsonResponse, response.body);
  }

  Future<Response> _mapRequest(HttpMethod method, String url,
      {Map<String, dynamic> parameters = const {},
      dynamic data,
      Map<String, dynamic> headers = const {}}) {
    if (data is Map &&
        headers['content-type'] != 'application/x-www-form-urlencoded') {
      data = jsonEncode(data);
      HttpLogAdapter.shared.logger?.d('SimpleHttp data: $data');
    }

    final normalizedHeaders = headers.map((k, v) {
      return MapEntry<String, String>(k, v.toString());
    });

    switch (method) {
      case HttpMethod.GET:
        return client.get(_buildUri(url, parameters),
            headers: normalizedHeaders);
      case HttpMethod.HEAD:
        return client.head(_buildUri(url, parameters),
            headers: normalizedHeaders);
      case HttpMethod.POST:
        return client.post(_buildUri(url, parameters),
            headers: normalizedHeaders, body: data);
      case HttpMethod.PUT:
        return client.put(_buildUri(url, parameters),
            headers: normalizedHeaders, body: data);
      case HttpMethod.PATCH:
        return client.patch(_buildUri(url, parameters),
            headers: normalizedHeaders, body: data);
      case HttpMethod.DELETE:
        return client.delete(_buildUri(url, parameters),
            headers: normalizedHeaders, body: data);
      default:
        return client.get(_buildUri(url, parameters),
            headers: normalizedHeaders);
    }
  }

  Uri _buildUri(String endpoint, [Map<String, dynamic> query = const {}]) {
    HttpLogAdapter.shared.logger?.d('SimpleHttp endpoint: $endpoint');
    final queryParameters = query.map((k, v) => MapEntry('$k', '$v'));
    final fullUrl =
        endpoint.startsWith('http') ? endpoint : '$baseUrl$endpoint';
    final uri = Uri.parse(fullUrl);
    if (queryParameters.isEmpty) {
      return uri;
    }

    queryParameters.addAll(uri.queryParameters);
    if (fullUrl.startsWith('https'))
      return Uri.https(uri.authority, uri.path, queryParameters);

    return Uri.http(uri.authority, uri.path, queryParameters);
  }

  @override
  Future<void> handleException(error) async {
    HttpLogAdapter.shared.logger?.e('SimpleHttp exception: $error');
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
      {String? localPath, bool includeHttpResponse = false}) async {
    var req = await client.get(Uri.parse(url));
    var bytes = req.bodyBytes;
    File file = new File(localPath ?? '');
    await file.writeAsBytes(bytes);
    return file;
  }
}
