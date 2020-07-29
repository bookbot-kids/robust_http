import 'package:logger/logger.dart';

/// An adapter to set [Logger] for this package
///
/// [Logger]:(https://pub.dev/packages/logger)
class LogAdapter {
  LogAdapter._privateConstructor();
  static LogAdapter shared = LogAdapter._privateConstructor();

  /// Logger instance to write log, must be set before using
  Logger logger;
}
