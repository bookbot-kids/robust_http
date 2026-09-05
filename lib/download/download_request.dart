import 'package:dio/dio.dart';

/// Progress of a single file.
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.bytesPerSecond,
    this.downloadedBytes = 0,
    this.attempt = 1,
    this.elapsed = Duration.zero,
    this.timeToFirstByte,
  });

  /// Bytes on disk, including anything resumed from a previous attempt.
  final int received;

  /// Total size, or -1 when the server did not say.
  final int total;
  final double bytesPerSecond;

  /// Bytes transferred by this network attempt. Unlike [received], this does
  /// not include bytes already present in a resumable partial file.
  final int downloadedBytes;
  final int attempt;
  final Duration elapsed;
  final Duration? timeToFirstByte;

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
    this.progressInterval = Duration.zero,
    this.resumeMetadataThresholdBytes = 0,
    this.allowUnvalidatedResume = false,
    this.attempt = 1,
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

  /// Minimum known file size for writing resumable sidecar metadata. Zero
  /// preserves the original behaviour. Smaller interrupted files restart.
  final int resumeMetadataThresholdBytes;

  /// Minimum time between callbacks. A final callback is always emitted.
  final Duration progressInterval;

  /// Permits a Range request without ETag or Last-Modified.
  final bool allowUnvalidatedResume;

  /// One-based attempt, set by the retry wrapper.
  final int attempt;

  String get partPath => '$savePath.part';
  String get metaPath => '$savePath.part.meta';

  DownloadRequest copyWith({
    DownloadProgressCallback? onProgress,
    int? attempt,
  }) => DownloadRequest(
        url: url,
        savePath: savePath,
        headers: headers,
        resume: resume,
        stallTimeout: stallTimeout,
        expectedMd5: expectedMd5,
        expectedSize: expectedSize,
        expectedContentType: expectedContentType,
        cancelToken: cancelToken,
        onProgress: onProgress ?? this.onProgress,
        progressInterval: progressInterval,
        resumeMetadataThresholdBytes: resumeMetadataThresholdBytes,
        allowUnvalidatedResume: allowUnvalidatedResume,
        attempt: attempt ?? this.attempt,
      );
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
    this.attempts = 1,
    this.timeToFirstByte,
    this.statusCode,
    this.responseHeaders = const {},
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
  final int attempts;
  final Duration? timeToFirstByte;
  final int? statusCode;
  final Map<String, List<String>> responseHeaders;

  String? header(String name) {
    final values = responseHeaders[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  double get bytesPerSecond => elapsed.inMilliseconds > 0
      ? downloadedBytes / (elapsed.inMilliseconds / 1000)
      : 0;

  DownloadResult copyWith({
    int? downloadedBytes,
    Duration? elapsed,
    int? attempts,
    Duration? timeToFirstByte,
  }) => DownloadResult(
        path: path,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        resumed: resumed,
        elapsed: elapsed ?? this.elapsed,
        fromCache: fromCache,
        attempts: attempts ?? this.attempts,
        timeToFirstByte: timeToFirstByte ?? this.timeToFirstByte,
        statusCode: statusCode,
        responseHeaders: responseHeaders,
      );

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
