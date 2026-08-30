import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';
import 'package:robust_http/engine/http_engine.dart';
import 'package:robust_http/http_log_adapter.dart';

/// Resolves [HttpEngine.auto] into the stack we will actually use.
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

/// Builds the Dio adapter for the requested engine.
///
/// Never throws: if the native stack cannot be created we log it and fall back
/// to dart:io, because a device that cannot start Cronet must still be able to
/// make requests.
HttpClientAdapter createHttpClientAdapter(HttpEngineOptions options) {
  final engine = resolveEngine(options);
  if (engine == HttpEngine.native) {
    try {
      return NativeAdapter(
        // Cronet enables HTTP/2 and QUIC by default; we set them explicitly so
        // the intent is visible and can be flipped off if a device misbehaves.
        createCronetEngine: () => CronetEngine.build(
          enableHttp2: true,
          enableQuic: true,
          cacheMode:
              options.nativeCacheBytes > 0 ? CacheMode.memory : CacheMode.disabled,
          cacheMaxSize:
              options.nativeCacheBytes > 0 ? options.nativeCacheBytes : null,
        ),
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
          HttpLogAdapter.shared.logger?.w(
              'Cronet unavailable, falling back to dart:io HTTP/1.1: $error');
          return _ioAdapter(options);
        },
      );
    } catch (e, stackTrace) {
      HttpLogAdapter.shared.logger?.w(
          'Could not create the native HTTP adapter, using dart:io instead: $e',
          error: e,
          stackTrace: stackTrace);
      return _ioAdapter(options);
    }
  }

  return _ioAdapter(options);
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
