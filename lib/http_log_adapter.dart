import 'package:logger/logger.dart';
import 'package:singleton/singleton.dart';

/// An adapter to set [Logger] for this package
///
/// [Logger]:(https://pub.dev/packages/logger)
class HttpLogAdapter {
  factory HttpLogAdapter() =>
      Singleton.lazy(() => HttpLogAdapter._privateConstructor());
  HttpLogAdapter._privateConstructor();
  static HttpLogAdapter shared = HttpLogAdapter();

  /// Logger instance to write log, must be set before using
  Logger? logger;
}
