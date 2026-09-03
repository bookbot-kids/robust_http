import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:robust_http/connection_helper.dart';
import 'package:robust_http/download/download_request.dart';
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

  /// Resumable, verifiable download of a single file.
  ///
  /// Unlike [download] this writes to a `.part` file, can continue an
  /// interrupted transfer with a Range request, reports progress and checks
  /// the finished bytes. Clients that cannot do this keep the default.
  Future<DownloadResult> downloadFile(DownloadRequest request) {
    throw UnimplementedError('$runtimeType does not support downloadFile');
  }

  Future<void> handleException(dynamic error, StackTrace stackTrace);

  /// Releases the underlying transport.
  ///
  /// Matters for the native stacks: a Cronet engine holds a connection pool
  /// and, when configured with a storage path, a lock on that directory - so a
  /// client that is replaced rather than closed leaves both behind, and the
  /// replacement cannot take the same path. Does nothing by default.
  void close() {}

  Future<bool> validateConnectionError({bool validateNetwork = true}) async {
    if (!await ConnectionHelper.shared.hasConnection()) {
      throw ConnectivityException('The connection is turn off',
          hasConnectionStatus: false);
    } else if (validateNetwork &&
        !await ConnectionHelper.shared.hasInternetConnection()) {
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
