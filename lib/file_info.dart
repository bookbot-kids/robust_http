class FileInfo {
  final String localPath;
  final String? mimeType;
  final String? fileName;
  final Map<String, List<String>> headers;

  FileInfo(
    this.localPath, {
    this.headers = const {},
    this.mimeType,
    this.fileName,
  });
}
