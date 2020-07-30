import 'package:logger/logger.dart';

/// An adapter to set [Logger] for this package
///
/// [Logger]:(https://pub.dev/packages/logger)
class HttpLogAdapter {
  HttpLogAdapter._privateConstructor();
  static HttpLogAdapter shared = HttpLogAdapter._privateConstructor();

  /// Logger instance to write log, must be set before using
  Logger logger;
}
