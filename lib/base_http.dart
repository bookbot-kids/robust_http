enum ClientType { dio, resty }

abstract class BaseHttp {
  Future<dynamic> request(
      String method, String url, Map<String, String> headers,
      {Map<String, dynamic> parameters,
      dynamic data,
      bool includeHttpResponse = false});

  Future<dynamic> download(String url,
      {String localPath, bool includeHttpResponse = false});

  Future<void> handleException(dynamic error);
}
