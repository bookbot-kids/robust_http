import 'package:dio/dio.dart';

/// A Log interceptor.
/// It supports to log on console or other cloud like instabug, firebase...
class Log extends LogInterceptor {
  static const none = 0;
  static const basic = 1;
  static const all = 2;
  int level;
  Log({this.level = none})
      : super(
          request: level >= basic,
          requestHeader: level >= basic,
          requestBody: level >= all,
          responseHeader: level >= all,
          responseBody: level >= all,
        );
}
