import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robust_http/download/download_request.dart';
import 'package:robust_http/download/resumable_downloader.dart';

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.beforeResponse);
  final void Function() beforeResponse;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    beforeResponse();
    return ResponseBody.fromString('hello', 200, headers: {
      Headers.contentLengthHeader: ['5']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late Dio dio;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('narration_file_test');
    dio = Dio();
  });
  tearDown(() {
    dio.close(force: true);
    directory.deleteSync(recursive: true);
  });

  test('cache directory removed during request is recreated before writing',
      () async {
    final parent = Directory('${directory.path}/narration/gb');
    final target = File('${parent.path}/book.json');
    dio.httpClientAdapter = _ResponseAdapter(() {
      expect(parent.existsSync(), isTrue);
      parent.deleteSync(recursive: true);
    });
    final result = await ResumableDownloader(dio).download(DownloadRequest(
        url: 'https://example.test/cue', savePath: target.path));
    expect(result.totalBytes, 5);
    expect(target.readAsStringSync(), 'hello');
    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('file-open failure reaches the download future without a zone error',
      () async {
    final target = File('${directory.path}/book.json');
    dio.httpClientAdapter = _ResponseAdapter(() {
      Directory('${target.path}.part').createSync();
    });
    await expectLater(
        ResumableDownloader(dio).download(DownloadRequest(
            url: 'https://example.test/cue', savePath: target.path)),
        throwsA(isA<FileSystemException>()));
    expect(target.existsSync(), isFalse);
  });
}
