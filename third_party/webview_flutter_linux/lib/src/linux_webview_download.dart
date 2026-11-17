/// Progress of a download WebKit saves without the application's delegate.
class LinuxDownloadProgress {
  const LinuxDownloadProgress({
    required this.id,
    required this.fileName,
    required this.bytesReceived,
    required this.totalBytes,
    required this.status,
  });

  final String id;
  final String fileName;
  final int bytesReceived;
  final int? totalBytes;
  final String status;

  bool get isActive => status == 'downloading';

  double? get fraction {
    final total = totalBytes;
    return total == null || total <= 0
        ? null
        : (bytesReceived / total).clamp(0.0, 1.0);
  }
}
