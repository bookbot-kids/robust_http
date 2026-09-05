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

typedef HttpEngineChanged = void Function(HttpEngine engine);

/// What the native stacks are allowed to keep on the device.
///
/// This is not our file cache - downloaded files are stored by the app under
/// their own names. What it holds is the stack's own bookkeeping, and the
/// entry that matters is **which hosts answered over QUIC**: without somewhere
/// to write that down, every launch has to rediscover HTTP/3 through an
/// `alt-svc` header on a connection that has already been made over TCP.
enum NativeCacheMode {
  /// No cache at all. Nothing is remembered between launches.
  disabled,

  /// In memory only, cleared when the process ends.
  memory,

  /// On disk, **server properties only** - no response bodies. This is the one
  /// to use for HTTP/3: it persists the QUIC knowledge and 0-RTT tickets
  /// without duplicating files the app already stores itself.
  diskNoHttp,

  /// On disk, including response bodies.
  disk;

  bool get needsStoragePath =>
      this == NativeCacheMode.diskNoHttp || this == NativeCacheMode.disk;

  static NativeCacheMode? fromString(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'disabled':
      case 'none':
        return NativeCacheMode.disabled;
      case 'memory':
        return NativeCacheMode.memory;
      case 'disknohttp':
      case 'disk_no_http':
        return NativeCacheMode.diskNoHttp;
      case 'disk':
        return NativeCacheMode.disk;
      default:
        return null;
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
    this.quicHints = const [],
    this.nativeStoragePath,
    this.nativeCacheMode,
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
  /// `nativeCacheBytes`: HTTP cache size for the native stacks, 0 = off.
  ///
  /// `quicHints`: hosts already known to speak QUIC, so the first request can
  /// try HTTP/3 instead of learning it from an `alt-svc` header on a
  /// connection that has already been made over TCP. Android only - Apple's
  /// stack has no equivalent that is reachable from Dart.
  ///
  /// `nativeStoragePath`: an app-private directory the native stack may write
  /// its bookkeeping to. Required by [NativeCacheMode.diskNoHttp] and
  /// [NativeCacheMode.disk], ignored otherwise.
  ///
  /// `nativeCacheMode`: `disabled`, `memory`, `diskNoHttp` or `disk`. When
  /// omitted it is derived from `nativeCacheBytes`, which is what every
  /// existing caller gets.
  factory HttpEngineOptions.fromMap(Map<String, dynamic> options) {
    final idle = options['idleTimeout'];
    final hints = options['quicHints'];
    return HttpEngineOptions(
      engine: HttpEngine.fromString(options['httpEngine']?.toString()),
      idleTimeout: Duration(seconds: idle is int ? idle : 3),
      maxConnectionsPerHost: options['maxConnectionsPerHost'],
      nativeCacheBytes: options['nativeCacheBytes'] ?? 0,
      quicHints: hints is List
          ? [
              for (final host in hints)
                if (host.toString().trim().isNotEmpty) host.toString().trim()
            ]
          : const [],
      nativeStoragePath: options['nativeStoragePath']?.toString(),
      nativeCacheMode:
          NativeCacheMode.fromString(options['nativeCacheMode']?.toString()),
    );
  }

  final HttpEngine engine;
  final Duration idleTimeout;
  final int? maxConnectionsPerHost;
  final int nativeCacheBytes;

  /// Hosts to attempt QUIC against immediately. Port 443 is assumed.
  final List<String> quicHints;

  /// Where the native stack may keep its own bookkeeping.
  final String? nativeStoragePath;

  /// Null means "derive it from [nativeCacheBytes]", which is the behaviour
  /// callers had before this option existed.
  final NativeCacheMode? nativeCacheMode;

  /// The cache mode actually in force, with the legacy derivation applied.
  NativeCacheMode get effectiveCacheMode =>
      nativeCacheMode ??
      (nativeCacheBytes > 0 ? NativeCacheMode.memory : NativeCacheMode.disabled);

  @override
  String toString() =>
      'HttpEngineOptions(engine: $engine, idleTimeout: $idleTimeout, '
      'maxConnectionsPerHost: $maxConnectionsPerHost, '
      'cacheMode: $effectiveCacheMode, quicHints: $quicHints)';
}
