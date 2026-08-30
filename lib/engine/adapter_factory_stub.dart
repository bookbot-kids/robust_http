import 'package:dio/dio.dart';
import 'package:robust_http/engine/http_engine.dart';

/// Web build: the browser picks the protocol itself, so there is nothing to
/// select. Returns Dio's platform default adapter.
HttpClientAdapter createHttpClientAdapter(HttpEngineOptions options) =>
    HttpClientAdapter();

/// Web has no selectable stack.
HttpEngine resolveEngine(HttpEngineOptions options) => HttpEngine.dartIo;
