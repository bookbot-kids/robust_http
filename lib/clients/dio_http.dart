import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:robust_http/clients/base_http.dart';
import 'package:robust_http/exceptions.dart';
import 'package:robust_http/robust_log.dart';

class DioHttp extends BaseHttp {
  Dio _dio;

  DioHttp({@required String baseUrl, Map<String, dynamic> options = const {}}) {
    final baseOptions = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: options["connectTimeout"] ?? 60000,
      receiveTimeout: options["receiveTimeout"] ?? 60000,
      headers: options["headers"] ?? {},
      responseType: options["responseType"] ?? ResponseType.json,
    );

    if (options["validateStatus"] != null) {
      baseOptions.validateStatus = options["validateStatus"];
    }

    _dio = new Dio(baseOptions);
    var logLevel = options['logLevel'];
    if (logLevel != 'none') {
      _dio.interceptors.add(LoggerInterceptor(logLevel == 'debug'));
    }
  }

  @override
  Future<void> handleException(error) async {
    if (error is DioError) {
      if (error.type == DioErrorType.connectTimeout ||
          error.type == DioErrorType.receiveTimeout) {
        if (await Connectivity().checkConnectivity() ==
            ConnectivityResult.none) {
          throw ConnectivityException();
        }
      } else if (error.response != null) {
        throw UnexpectedResponseException(error.requestOptions.path,
            error.response.statusCode, error.message);
      } else {
        throw UnknownException(
            ' Request error on ${error.requestOptions.path} ${error.message}');
      }
    } else {
      throw UnknownException(error.message);
    }
  }

  @override
  Future<dynamic> request(
      HttpMethod method, String url, Map<String, dynamic> headers,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false}) async {
    _dio.options.headers = headers;
    _dio.options.method = method.name;
    final response =
        await _dio.request(url, queryParameters: parameters, data: data);
    return includeHttpResponse ? response : response.data;
  }

  @override
  Future download(String url,
      {String localPath, bool includeHttpResponse = false}) async {
    if (localPath != null) {
      return await _dio.download(url, localPath);
    }

    final response = await _dio.get<ResponseBody>(url,
        options: Options(responseType: ResponseType.stream));
    return includeHttpResponse == true ? response : response.data;
  }
}
