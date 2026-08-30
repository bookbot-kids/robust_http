import 'package:dio/dio.dart';

/// Progress of a single file.
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
  });

  /// Bytes on disk, including anything resumed from a previous attempt.
  final int received;

  /// Total size, or -1 when the server did not say.
  final int total;
  final double bytesPerSecond;

  bool get hasTotal => total > 0;
  double get percent => hasTotal ? (received / total).clamp(0.0, 1.0) : 0.0;

  @override
  String toString() => 'DownloadProgress($received/$total, '
      '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s)';
}

typedef DownloadProgressCallback = void Function(DownloadProgress progress);

/// One file to fetch.
class DownloadRequest {
  DownloadRequest({
    required this.url,
    required this.savePath,
    this.headers = const {},
    this.resume = true,
    this.stallTimeout = const Duration(seconds: 20),
    this.expectedMd5,
    this.expectedSize,
    this.expectedContentType,
    this.cancelToken,
    this.onProgress,
  });

  final String url;

  /// Final path. While downloading we write `savePath.part` and rename on
  /// success, so a killed app never leaves a half file that looks complete.
  final String savePath;
  final Map<String, dynamic> headers;

  /// Continue a previous `.part` with a Range request when possible.
  final bool resume;

  /// Abort if no byte arrives for this long. A stalled socket on a bad
  /// network can otherwise hang far longer than any connect timeout.
  final Duration stallTimeout;

  /// Verify the finished file. Content-addressed files (our CDN names files
  /// by hash) get this for free.
  final String? expectedMd5;
  final int? expectedSize;

  /// Guards against captive portals answering with an HTML login page.
  final String? expectedContentType;

  final CancelToken? cancelToken;
  final DownloadProgressCallback? onProgress;

  String get partPath => '$savePath.part';
  String get metaPath => '$savePath.part.meta';
}

/// Result of a finished download.
class DownloadResult {
  const DownloadResult({
    required this.path,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.resumed,
    required this.elapsed,
    required this.fromCache,
  });

  final String path;

  /// Size of the finished file.
  final int totalBytes;

  /// Bytes actually pulled over the network this time.
  final int downloadedBytes;

  /// True when we continued a partial file instead of starting over.
  final bool resumed;
  final Duration elapsed;

  /// True when the file already existed and nothing was fetched.
  final bool fromCache;

  double get bytesPerSecond => elapsed.inMilliseconds > 0
      ? downloadedBytes / (elapsed.inMilliseconds / 1000)
      : 0;

  @override
  String toString() => 'DownloadResult($path, $totalBytes bytes, '
      'resumed: $resumed, fromCache: $fromCache)';
}

/// The downloaded bytes did not match what we asked for - a truncated file, a
/// captive portal login page, or a corrupted proxy response.
class InvalidContentException implements Exception {
  InvalidContentException(this.url, this.reason);
  final String url;
  final String reason;

  @override
  String toString() => 'Invalid content from $url: $reason';
}
