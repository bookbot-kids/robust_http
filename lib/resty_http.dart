import 'package:flutter/cupertino.dart';
import 'package:resty/resty.dart';
import 'package:robust_http/base_http.dart';

import 'exceptions.dart';

class RestyHttp extends BaseHttp {
  Resty _resty;

  RestyHttp(
      {@required String baseUrl, Map<String, dynamic> options = const {}}) {
    _resty = Resty(
        host: baseUrl,
        secure: true,
        timeout: Duration(milliseconds: options["connectTimeout"] ?? 60000),
        headers: options["headers"] ?? {},
        json: options["json"] ?? true,
        logger: options["logger"] ?? false);
  }

  @override
  Future<dynamic> request(
      String method, String url, Map<String, dynamic> headers,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    final response = await _mapRequest(method, url,
        parameters: parameters, data: data, headers: headers);
    if (response.isClientError || response.isServerError) {
      throw UnexpectedResponseException('', response.statusCode, '');
    }
    return includeHttpResponse ? response : response.json;
  }

  Future<Response> _mapRequest(String method, String url,
      {Map<String, dynamic> parameters,
      data,
      Map<String, dynamic> headers = const {}}) {
    switch (method) {
      case 'GET':
        return _resty.get(url, query: parameters, headers: headers);
      case 'POST':
        return _resty.post(url, body: data, headers: headers);
      case 'PUT':
        return _resty.put(url, body: parameters, headers: headers);
      case 'PATCH':
        return _resty.patch(url, body: parameters, headers: headers);
      case 'DELETE':
        return _resty.delete(url, query: parameters, headers: headers);
      default:
        return _resty.get(url, query: parameters, headers: headers);
    }
  }

  @override
  Future<void> handleException(error) {
    if (error is UnexpectedResponseException) {
      throw error;
    } else {
      throw UnknownException(error.message);
    }
  }

  @override
  Future download(String url,
      {String localPath, bool includeHttpResponse = false}) {
  }
}
