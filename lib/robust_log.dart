import 'package:dio_http/dio_http.dart';
import 'package:robust_http/http_log_adapter.dart';

/// A log interceptor to print http request, response. Must be set [LogAdapter.shared.logger] first
class LoggerInterceptor extends Interceptor {
  /// Should print debug log
  final bool canPrintDebugLog;

  /// The log messages
  List<String> logMessages = [];

  LoggerInterceptor([this.canPrintDebugLog = false]);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // reset the messages when starting a new request
    logMessages = [];

    logMessages.add('*** Request ***');
    logMessages.add(_formatKeyValue('uri', options.uri));

    logMessages.add(_formatKeyValue('method', options.method));
    logMessages
        .add(_formatKeyValue('responseType', options.responseType?.toString()));
    logMessages
        .add(_formatKeyValue('followRedirects', options.followRedirects));
    logMessages.add(_formatKeyValue('connectTimeout', options.connectTimeout));
    logMessages.add(_formatKeyValue('receiveTimeout', options.receiveTimeout));
    logMessages.add(_formatKeyValue('extra', options.extra));

    logMessages.add('headers:');
    options.headers
        .forEach((key, v) => logMessages.add(_formatKeyValue(' $key', v)));
    logMessages.add('data:');
    logMessages.addAll(_formatMessage(options.data));
    handler.next(options);
  }

  @override
  void onError(
    DioError err,
    ErrorInterceptorHandler handler,
  ) async {
    logMessages.add('*** DioError ***:');
    logMessages.add('uri: ${err.requestOptions.uri}');
    logMessages.add('$err');
    if (err.response != null) {
      logMessages.addAll(_formatResponse(err.response));
    }
    _printErrorLog(logMessages);
    handler.next(err);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    logMessages.add('*** Response ***');
    logMessages.addAll(_formatResponse(response));
    _printDebugLog(logMessages);
    handler.next(response);
  }

  /// Format the http response into list of strings
  List<String> _formatResponse(Response response) {
    List<String> logMessages = [];
    logMessages.add(_formatKeyValue('uri', response.requestOptions?.uri));
    logMessages.add(_formatKeyValue('statusCode', response.statusCode));
    if (response.isRedirect == true) {
      logMessages.add(_formatKeyValue('redirect', response.realUri));
    }
    if (response.headers != null) {
      logMessages.add('headers:');
      response.headers.forEach(
          (key, v) => logMessages.add(_formatKeyValue(' $key', v.join(','))));
    }
    logMessages.add('Response Text:');
    logMessages.addAll(_formatMessage(response.toString()));
    return logMessages;
  }

  /// Format key and value into string
  String _formatKeyValue(String key, Object v) {
    return '$key: $v';
  }

  /// Format the message into list of string
  List<String> _formatMessage(msg) {
    return msg.toString().split('\n') ?? <String>[];
  }

  /// Print log at debug level
  void _printDebugLog(List<String> messages) {
    if (messages.isNotEmpty && canPrintDebugLog)
      HttpLogAdapter.shared.logger?.d(messages.join('\n'));
  }

  /// Print log at error level
  void _printErrorLog(List<String> messages) {
    if (messages.isNotEmpty)
      HttpLogAdapter.shared.logger?.e(messages.join('\n'));
  }
}
