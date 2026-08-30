import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:robust_http/download/download_request.dart';
import 'package:robust_http/exceptions.dart';
import 'package:robust_http/http_log_adapter.dart';
import 'package:robust_http/retry/retry_policy.dart';

/// Downloads one file, once, and can continue where a previous attempt stopped.
///
/// Retries live one level up (see `HTTP.downloadFile`) - because every attempt
/// resumes, a retry on a flaky network costs only the bytes that are missing,
/// not the whole file again.
class ResumableDownloader {
  ResumableDownloader(this._dio);

  final Dio _dio;

  Future<DownloadResult> download(DownloadRequest request) async {
    final started = DateTime.now();
    final target = File(request.savePath);

    // Content-addressed files never change under the same name, so an
    // existing file is a finished download.
    if (await target.exists()) {
      final size = await target.length();
      if (request.expectedSize == null || request.expectedSize == size) {
        return DownloadResult(
          path: request.savePath,
          totalBytes: size,
          downloadedBytes: 0,
          resumed: false,
          elapsed: Duration.zero,
          fromCache: true,
        );
      }
      // Wrong size on disk: treat it as garbage and fetch again.
      await target.delete();
    }

    await target.parent.create(recursive: true);

    final part = File(request.partPath);
    var offset = 0;
    String? etag;
    if (request.resume && await part.exists()) {
      final meta = await _readMeta(request);
      if (meta != null && meta['url'] == request.url) {
        offset = await part.length();
        etag = meta['etag'] as String?;
      } else {
        // Meta lost or belongs to another url - cannot trust the bytes.
        await part.delete();
      }
    }

    final headers = <String, dynamic>{...request.headers};
    if (offset > 0) {
      headers['range'] = 'bytes=$offset-';
      if (etag != null) {
        // If the file changed on the CDN, the server answers 200 (full body)
        // instead of 206 and we restart cleanly.
        headers['if-range'] = etag;
      }
    }

    final cancelToken = CancelToken();
    request.cancelToken?.whenCancel.then((error) {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel(error);
      }
    });

    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        request.url,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          // We inspect the status ourselves so 206/416 are not exceptions.
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioException(request, e);
    }

    final status = response.statusCode ?? 0;

    if (status == HttpStatus.requestedRangeNotSatisfiable) {
      // Our partial file is longer than the resource (it changed, or the disk
      // holds junk). Start over on the next attempt.
      await _discardPart(request);
      throw UnexpectedResponseException(request.url, status,
          'Range not satisfiable, partial file discarded');
    }

    if (status == HttpStatus.tooManyRequests ||
        status == HttpStatus.serviceUnavailable) {
      throw UnexpectedResponseException(
          request.url, status, 'Server asked us to slow down',
          retryAfter: RetryPolicy.retryAfterOf(response));
    }

    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      throw UnexpectedResponseException(
          request.url, status, 'Unexpected status while downloading');
    }

    final resumed = status == HttpStatus.partialContent && offset > 0;
    if (!resumed) {
      // Server ignored the Range (or we had nothing) - write from scratch.
      offset = 0;
    }

    _checkContentType(request, response);

    final total = _totalBytesOf(response, offset);
    await _writeMeta(request, response);

    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = offset;
    var downloaded = 0;
    var lastChunkAt = DateTime.now();
    Timer? stallWatchdog;

    try {
      // dio's receiveTimeout does not cover every stall case on the native
      // stacks, so we watch the byte flow ourselves.
      stallWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        if (DateTime.now().difference(lastChunkAt) > request.stallTimeout) {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('stalled for ${request.stallTimeout.inSeconds}s');
          }
        }
      });

      await for (final chunk in response.data!.stream) {
        lastChunkAt = DateTime.now();
        sink.add(chunk);
        received += chunk.length;
        downloaded += chunk.length;
        request.onProgress?.call(DownloadProgress(
          received: received,
          total: total,
          bytesPerSecond: _speed(downloaded, started),
        ));
      }
    } on DioException catch (e) {
      await sink.close();
      if (CancelToken.isCancel(e) && request.cancelToken?.isCancelled != true) {
        // Our stall watchdog fired: a timeout, not a user cancel.
        throw NetworkTimeoutException(
            'Download stalled after ${request.stallTimeout.inSeconds}s: ${request.url}');
      }
      throw _mapDioException(request, e);
    } catch (_) {
      await sink.close();
      rethrow;
    } finally {
      stallWatchdog?.cancel();
    }

    await sink.flush();
    await sink.close();

    await _verify(request, part, total);

    await part.rename(request.savePath);
    await _deleteQuietly(File(request.metaPath));

    return DownloadResult(
      path: request.savePath,
      totalBytes: await File(request.savePath).length(),
      downloadedBytes: downloaded,
      resumed: resumed,
      elapsed: DateTime.now().difference(started),
      fromCache: false,
    );
  }

  /// Total size of the finished file, from Content-Range or Content-Length.
  int _totalBytesOf(Response<ResponseBody> response, int offset) {
    final contentRange = response.headers.value('content-range');
    if (contentRange != null) {
      final slash = contentRange.lastIndexOf('/');
      if (slash != -1) {
        final size = int.tryParse(contentRange.substring(slash + 1));
        if (size != null) {
          return size;
        }
      }
    }

    final length = int.tryParse(response.headers.value('content-length') ?? '');
    return length == null ? -1 : length + offset;
  }

  void _checkContentType(DownloadRequest request, Response<ResponseBody> response) {
    final expected = request.expectedContentType;
    if (expected == null) {
      return;
    }

    final actual = response.headers.value('content-type') ?? '';
    if (!actual.toLowerCase().contains(expected.toLowerCase())) {
      // Classic captive portal: 200 OK with an HTML login page where an image
      // was expected.
      throw InvalidContentException(
          request.url, 'expected $expected but got "$actual"');
    }
  }

  Future<void> _verify(DownloadRequest request, File part, int total) async {
    final size = await part.length();

    if (total > 0 && size != total) {
      await _discardPart(request);
      throw InvalidContentException(
          request.url, 'truncated: got $size of $total bytes');
    }

    if (request.expectedSize != null && size != request.expectedSize) {
      await _discardPart(request);
      throw InvalidContentException(
          request.url, 'expected ${request.expectedSize} bytes, got $size');
    }

    final expectedMd5 = request.expectedMd5;
    if (expectedMd5 != null) {
      final digest = await md5.bind(part.openRead()).first;
      if (digest.toString() != expectedMd5.toLowerCase()) {
        await _discardPart(request);
        throw InvalidContentException(
            request.url, 'md5 mismatch (expected $expectedMd5, got $digest)');
      }
    }
  }

  Future<Map<String, dynamic>?> _readMeta(DownloadRequest request) async {
    try {
      final file = File(request.metaPath);
      if (!await file.exists()) {
        return null;
      }
      return json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      HttpLogAdapter.shared.logger?.w('Could not read download meta: $e');
      return null;
    }
  }

  Future<void> _writeMeta(
      DownloadRequest request, Response<ResponseBody> response) async {
    try {
      await File(request.metaPath).writeAsString(json.encode({
        'url': request.url,
        'etag': response.headers.value('etag'),
        'lastModified': response.headers.value('last-modified'),
      }));
    } catch (e) {
      // Losing the meta only costs us the ability to resume.
      HttpLogAdapter.shared.logger?.w('Could not write download meta: $e');
    }
  }

  Future<void> _discardPart(DownloadRequest request) async {
    await _deleteQuietly(File(request.partPath));
    await _deleteQuietly(File(request.metaPath));
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Nothing useful to do if the file cannot be removed.
    }
  }

  double _speed(int downloaded, DateTime started) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    return ms > 0 ? downloaded / (ms / 1000) : 0;
  }

  Object _mapDioException(DownloadRequest request, DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkTimeoutException(
            'Timeout downloading ${request.url}: ${e.message}');
      case DioExceptionType.badResponse:
        return UnexpectedResponseException(
          request.url,
          e.response?.statusCode ?? 0,
          e.message ?? '',
          data: e.response?.data,
          stackTrace: e.stackTrace,
        );
      default:
        return e;
    }
  }
}
