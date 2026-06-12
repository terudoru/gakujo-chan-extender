class GakujoDownloadUrlPolicy {
  const GakujoDownloadUrlPolicy._();

  static bool shouldDownload(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return false;
    }

    final path = uri.path.toLowerCase();
    if (RegExp(r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|csv|txt)$')
        .hasMatch(path)) {
      return true;
    }

    final normalized = rawUrl.toLowerCase();
    if (normalized.contains('download')) {
      return true;
    }

    final eventId = uri.queryParameters['_eventId']?.toLowerCase();
    return eventId != null && eventId.contains('download');
  }
}
