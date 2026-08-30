/// Which HTTP stack the client should use underneath.
///
/// The Dart VM's own `HttpClient` (used by `dart:io` and therefore by Dio's
/// default adapter) speaks **HTTP/1.1 only**. That means every parallel request
/// costs its own TCP + TLS handshake, and a lost packet stalls that whole
/// connection.
///
/// The platform stacks do better:
///  * iOS/macOS `NSURLSession` - HTTP/2 and HTTP/3 (QUIC)
///  * Android `Cronet` - HTTP/2 and QUIC
///
/// On a fast network the difference is small. On 2G/3G, high latency or lossy
/// Wi-Fi - which is where our users are - multiplexing many small files over
/// one connection is a large win.
enum HttpEngine {
  /// Dio's default `IOHttpClientAdapter` (dart:io, HTTP/1.1).
  ///
  /// This is the default so existing behaviour never changes by accident.
  dartIo,

  /// Native stack where one exists (Android/iOS/macOS), `dartIo` elsewhere.
  ///
  /// Falls back to `dartIo` at runtime if the native stack cannot start - for
  /// example an Android device where every Cronet provider is disabled
  /// (AOSP builds, devices without Play Services).
  native,

  /// `native` on mobile/macOS, `dartIo` on desktop and web.
  auto;

  static HttpEngine fromString(String? value, {HttpEngine fallback = HttpEngine.dartIo}) {
    switch (value?.trim().toLowerCase()) {
      case 'native':
        return HttpEngine.native;
      case 'auto':
        return HttpEngine.auto;
      case 'dartio':
      case 'dart_io':
      case 'io':
        return HttpEngine.dartIo;
      default:
        return fallback;
    }
  }
}

/// Transport level knobs.
///
/// [idleTimeout] and [maxConnectionsPerHost] only apply to [HttpEngine.dartIo];
/// the native stacks manage their own connection pools.
class HttpEngineOptions {
  const HttpEngineOptions({
    this.engine = HttpEngine.dartIo,
    this.idleTimeout = const Duration(seconds: 3),
    this.maxConnectionsPerHost,
    this.nativeCacheBytes = 0,
  });

  /// Reads the same option map that `HTTP`/`DioHttp` already take.
  ///
  /// `httpEngine`: `dartIo` (default), `native` or `auto`
  ///
  /// `idleTimeout`: seconds a pooled connection is kept alive, default 3.
  /// Raise it (20-30s) for clients that fetch many small files in a row,
  /// otherwise every file pays a fresh handshake.
  ///
  /// `maxConnectionsPerHost`: dart:io has **no limit** by default, so a queue
  /// is the only thing bounding concurrency. Set it as a safety net.
  ///
  /// `nativeCacheBytes`: in-memory HTTP cache for the native stacks, 0 = off.
  factory HttpEngineOptions.fromMap(Map<String, dynamic> options) {
    final idle = options['idleTimeout'];
    return HttpEngineOptions(
      engine: HttpEngine.fromString(options['httpEngine']?.toString()),
      idleTimeout: Duration(seconds: idle is int ? idle : 3),
      maxConnectionsPerHost: options['maxConnectionsPerHost'],
      nativeCacheBytes: options['nativeCacheBytes'] ?? 0,
    );
  }

  final HttpEngine engine;
  final Duration idleTimeout;
  final int? maxConnectionsPerHost;
  final int nativeCacheBytes;

  @override
  String toString() =>
      'HttpEngineOptions(engine: $engine, idleTimeout: $idleTimeout, '
      'maxConnectionsPerHost: $maxConnectionsPerHost)';
}
