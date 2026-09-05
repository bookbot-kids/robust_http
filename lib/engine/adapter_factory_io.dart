import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
// Re-exports the cronet_http and cupertino_http types used below,
// including QuicException.
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:robust_http/engine/http_engine.dart';
import 'package:robust_http/http_log_adapter.dart';

/// Resolves [HttpEngine.auto] into the stack we will actually use.
///
/// Reads nothing but the platform, so it can be called to *ask* which stack a
/// client would get without building one - which matters now that building one
/// can allocate a Cronet engine holding a storage path.
HttpEngine resolveEngine(HttpEngineOptions options) {
  switch (options.engine) {
    case HttpEngine.dartIo:
      return HttpEngine.dartIo;
    case HttpEngine.native:
      return HttpEngine.native;
    case HttpEngine.auto:
      return (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
          ? HttpEngine.native
          : HttpEngine.dartIo;
  }
}

/// Whether [error] is QUIC failing, as opposed to the network failing.
///
/// Cronet races QUIC against TCP and remembers a broken alternative service
/// per network, so most blocked-UDP cases never surface here at all. The ones
/// that do must not be counted as congestion: schools and offices routinely
/// block UDP/443, and halving a concurrency limit because HTTP/3 is
/// unavailable makes us slower on exactly the networks that can least afford
/// it.
bool isQuicError(Object? error) {
  if (error is QuicException) {
    return true;
  }

  if (error is DioException) {
    return error.error is QuicException;
  }

  return false;
}

/// Builds the Dio adapter for the requested engine.
///
/// Never throws: if the native stack cannot be created we log it and fall back
/// to dart:io, because a device that cannot start Cronet must still be able to
/// make requests.
HttpClientAdapter createHttpClientAdapter(HttpEngineOptions options,
    {HttpEngineChanged? onEngineChanged}) {
  final engine = resolveEngine(options);
  if (engine == HttpEngine.native) {
    try {
      final cache = _resolveCache(options);
      onEngineChanged?.call(HttpEngine.native);
      return NativeAdapter(
        // Cronet enables HTTP/2 and QUIC by default; we set them explicitly so
        // the intent is visible and can be flipped off if a device misbehaves.
        createCronetEngine: () => _buildCronetEngine(options, cache),
        createCupertinoConfiguration: () {
          final config = URLSessionConfiguration.defaultSessionConfiguration();
          if (options.nativeCacheBytes > 0) {
            config.cache = URLCache.withCapacity(
                memoryCapacity: options.nativeCacheBytes);
          }
          return config;
        },
        // Android devices where every Cronet provider is disabled (AOSP
        // images, no Play Services) - common on cheap hardware. Without this
        // the adapter would throw on the first request.
        createFallbackAdapter: (error, stackTrace) {
          onEngineChanged?.call(HttpEngine.dartIo);
          HttpLogAdapter.shared.logger?.w(
              'Cronet unavailable, falling back to dart:io HTTP/1.1: $error');
          return _ioAdapter(options);
        },
      );
    } catch (e, stackTrace) {
      onEngineChanged?.call(HttpEngine.dartIo);
      HttpLogAdapter.shared.logger?.w(
          'Could not create the native HTTP adapter, using dart:io instead: $e',
          error: e,
          stackTrace: stackTrace);
      return _ioAdapter(options);
    }
  }

  onEngineChanged?.call(HttpEngine.dartIo);
  return _ioAdapter(options);
}

/// Builds the engine, and builds it again without the disk cache if that is
/// what it takes.
///
/// This runs **lazily, inside the adapter's first request** - and
/// `CronetWithFallbackAdapter` only falls back to dart:io when the error is
/// specifically "every Cronet provider is disabled". Any other throw from
/// here is rethrown and fails that request and every one after it. A storage
/// path is exactly such a throw waiting to happen: Cronet rejects a path that
/// is not a writable directory, and refuses one already held by another live
/// engine. Neither can be ruled out from Dart before the call.
///
/// So the disk cache is treated as an optimisation that may be declined. If
/// it costs us the engine, we build the engine again without it: HTTP/3 has
/// to be rediscovered each launch, which is what happens today anyway, and
/// every download still works.
CronetEngine _buildCronetEngine(HttpEngineOptions options, _CronetCache cache) {
  final quicHints = [
    // Without a hint, QUIC cannot be used until an `alt-svc` header has
    // arrived over a connection already made on TCP - so the first request to
    // a host is never HTTP/3, and no request is unless the answer is written
    // down somewhere (see [_resolveCache]).
    for (final host in options.quicHints) (host, 443, 443),
  ];

  // Rung 1: everything.
  final withCache = _tryBuild(
    'HTTP/3 hints and a ${cache.mode.name} cache',
    () => CronetEngine.build(
      enableHttp2: true,
      enableQuic: true,
      quicHints: quicHints,
      cacheMode: cache.mode,
      cacheMaxSize: cache.maxSize,
      storagePath: cache.storagePath,
    ),
  );
  if (withCache != null) {
    return withCache;
  }

  // Rung 2: keep the hints, drop the cache. HTTP/3 is then rediscovered on
  // every launch rather than remembered - which is what happens today.
  final withHints = _tryBuild(
    'HTTP/3 hints',
    () => CronetEngine.build(
      enableHttp2: true,
      enableQuic: true,
      quicHints: quicHints,
      cacheMode: CacheMode.disabled,
    ),
  );
  if (withHints != null) {
    return withHints;
  }

  // Rung 3: exactly what shipped before any of this existed. Deliberately not
  // guarded - a throw here is Cronet itself being unavailable, and it has to
  // reach `CronetWithFallbackAdapter`, which is the only thing that can drop
  // the whole app to dart:io.
  return CronetEngine.build(
    enableHttp2: true,
    enableQuic: true,
    cacheMode: CacheMode.disabled,
  );
}

/// One rung of that ladder. Null means "this one did not work, try less".
///
/// Every optional thing is built behind this because the engine is created
/// **lazily, inside the adapter's first request**, and
/// `CronetWithFallbackAdapter` only falls back to dart:io when the error is
/// specifically "every Cronet provider is disabled". Any other throw is
/// rethrown and fails that request and every one after it. A storage path is
/// exactly such a throw waiting to happen - Cronet rejects a path that is not
/// a writable directory, and refuses one already held by another live engine -
/// and neither can be ruled out from Dart before the call. So HTTP/3 is
/// treated as an optimisation that may be declined, never as a requirement.
CronetEngine? _tryBuild(String what, CronetEngine Function() build) {
  try {
    return build();
  } catch (e) {
    HttpLogAdapter.shared.logger
        ?.w('Cronet would not start with $what, trying with less: $e');
    return null;
  }
}

/// What Cronet will actually be told, after the requested mode has been
/// checked against what the device can provide.
class _CronetCache {
  const _CronetCache(this.mode, this.maxSize, this.storagePath);

  final CacheMode mode;
  final int? maxSize;
  final String? storagePath;
}

/// Cronet's own constraints, enforced here so a misconfiguration costs HTTP/3
/// rather than every request:
///
///  * a disk mode without a usable `storagePath` throws, so we step down to
///    memory instead;
///  * any mode but `disabled` requires a `cacheMaxSize`, so one is supplied
///    even for `diskNoHttp`, which stores no bodies and needs very little.
_CronetCache _resolveCache(HttpEngineOptions options) {
  final requested = options.effectiveCacheMode;
  if (requested == NativeCacheMode.disabled) {
    return const _CronetCache(CacheMode.disabled, null, null);
  }

  final size = options.nativeCacheBytes > 0
      ? options.nativeCacheBytes
      : _defaultCacheBytes;

  if (!requested.needsStoragePath) {
    return _CronetCache(CacheMode.memory, size, null);
  }

  final path = _usableStoragePath(options.nativeStoragePath);
  if (path == null) {
    HttpLogAdapter.shared.logger?.w(
        'No usable storage path for $requested, keeping the cache in memory - '
        'HTTP/3 will have to be rediscovered each launch');
    return _CronetCache(CacheMode.memory, size, null);
  }

  return _CronetCache(
    requested == NativeCacheMode.disk ? CacheMode.disk : CacheMode.diskNoHttp,
    size,
    path,
  );
}

/// 1 MB. `diskNoHttp` keeps server properties and session tickets, not
/// response bodies, so this is far more than it needs.
const _defaultCacheBytes = 1024 * 1024;

/// The directory, created if it does not exist yet. Null when it cannot be
/// used at all - a caller that passes a path inside a directory the app may
/// not write to should lose the disk cache, not every request.
String? _usableStoragePath(String? path) {
  if (path == null || path.trim().isEmpty) {
    return null;
  }

  try {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory.path;
  } catch (e) {
    HttpLogAdapter.shared.logger
        ?.w('Cannot use "$path" for the native HTTP cache: $e');
    return null;
  }
}

IOHttpClientAdapter _ioAdapter(HttpEngineOptions options) {
  return IOHttpClientAdapter()
    ..createHttpClient = () {
      final client = HttpClient()..idleTimeout = options.idleTimeout;
      if (options.maxConnectionsPerHost != null) {
        client.maxConnectionsPerHost = options.maxConnectionsPerHost;
      }
      return client;
    };
}
