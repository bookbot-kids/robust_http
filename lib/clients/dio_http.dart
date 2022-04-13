import 'dart:io';

import 'package:dio/dio.dart';
import 'package:enum_to_string/enum_to_string.dart';
import 'package:robust_http/clients/base_http.dart';
import 'package:robust_http/exceptions.dart';
import 'package:robust_http/file_info.dart';
import 'package:robust_http/http_log_adapter.dart';
import 'package:robust_http/robust_log.dart';
import 'package:http_parser/http_parser.dart';

class DioHttp extends BaseHttp {
  late Dio _dio;
  var _validateNetworkOnError = true;

  DioHttp({required String baseUrl, Map<String, dynamic> options = const {}}) {
    final baseOptions = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: options["connectTimeout"] ?? 60000,
      receiveTimeout: options["receiveTimeout"] ?? 60000,
      headers: options["headers"] ?? {},
    );

    if (options["responseType"] != null) {
      if (options["responseType"] is ResponseType) {
        baseOptions.responseType = options["responseType"];
      } else {
        baseOptions.responseType = EnumToString.fromString(
                ResponseType.values, options["responseType"]) ??
            ResponseType.json;
      }
    } else {
      baseOptions.responseType = ResponseType.json;
    }

    if (options["validateStatus"] != null) {
      baseOptions.validateStatus = options["validateStatus"];
    }

    if (options["validateNetworkOnError"] != null) {
      _validateNetworkOnError = options["validateNetworkOnError"];
    }

    _dio = new Dio(baseOptions);
    var logLevel = options['logLevel'];
    if (logLevel != 'none') {
      _dio.interceptors.add(LoggerInterceptor(logLevel == 'debug'));
    }
  }

  @override
  Future<void> handleException(error) async {
    if (await validateConnectionError(
        validateNetwork: _validateNetworkOnError)) {
      if (error is DioError) {
        if (error.type == DioErrorType.connectTimeout ||
            error.type == DioErrorType.receiveTimeout) {
          throw error;
        } else if (error.response != null) {
          throw UnexpectedResponseException(error.requestOptions.path,
              error.response?.statusCode ?? 0, error.message);
        } else {
          HttpLogAdapter.shared.logger?.i(
              'DioError error on ${error.requestOptions.path} ${error.message}');
          throw UnknownException(
              ' Request error on ${error.requestOptions.path} ${error.message}');
        }
      } else {
        HttpLogAdapter.shared.logger?.i('Unknown error: $error');
        throw UnknownException(error.message);
      }
    }
  }

  @override
  Future<dynamic> request(
    HttpMethod method,
    String url,
    Map<String, dynamic> headers, {
    Map<String, dynamic> parameters = const {},
    dynamic data,
    bool includeHttpResponse = false,
    bool isMultipart = false,
  }) async {
    _dio.options.headers = headers;
    _dio.options.method = method.name;
    // multipart upload
    if (isMultipart &&
        data is Map<String, dynamic> &&
        data.containsKey('files')) {
      final files = data.remove('files') as List<FileInfo>;
      final multipartFiles = <MultipartFile>[];
      for (final info in files) {
        final item = MultipartFile.fromBytes(
          File(info.localPath).readAsBytesSync(),
          filename: info.fileName,
          contentType: info.mimeType != null
              ? MediaType.parse(info.mimeType!)
              : MediaType('application', 'octet-stream'),
          headers: info.headers,
        );
        multipartFiles.add(item);
      }

      if (multipartFiles.length == 1) {
        data['file'] = multipartFiles.first;
      } else {
        data['files'] = multipartFiles;
      }

      final formData = FormData.fromMap(data);
      final response =
          await _dio.request(url, queryParameters: parameters, data: formData);
      return includeHttpResponse ? response : response.data;
    } else {
      final response =
          await _dio.request(url, queryParameters: parameters, data: data);
      return includeHttpResponse ? response : response.data;
    }
  }

  @override
  Future download(String url,
      {String? localPath, bool includeHttpResponse = false}) async {
    if (localPath != null) {
      return await _dio.download(url, localPath);
    }

    final response = await _dio.get<ResponseBody>(url,
        options: Options(responseType: ResponseType.stream));
    return includeHttpResponse == true ? response : response.data;
  }
}
