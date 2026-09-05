# robust_http

A robust http Flutter package base on [dio](https://pub.dev/packages/dio).

## Fetures:

- Support to retry on error
- Localize general error
- Config dynamically
- Print http log messages

## Usage

```
var http = HTTP('https://httpstat.us/',
          {"connectTimeout": 3000, "receiveTimeout": 3000, "logLevel": Log.all});
var response = await http.get('200'); // success response
print(response); // print "200 OK"
```

## Resumable downloads

`downloadFile` streams into a `.part` file, validates the response and can
resume larger transfers. Callers with many small files can avoid sidecar-file
I/O and coalesce progress notifications without changing the safe defaults:

```dart
final result = await http.downloadFile(DownloadRequest(
  url: url,
  savePath: path,
  resumeMetadataThresholdBytes: 512 * 1024,
  progressInterval: const Duration(milliseconds: 100),
  onProgress: (progress) {
    print('${progress.downloadedBytes} bytes, attempt ${progress.attempt}');
  },
));
```

`DownloadResult` reports retry-wide elapsed time and downloaded bytes, the
number of attempts, time to first byte, HTTP status and response headers.
