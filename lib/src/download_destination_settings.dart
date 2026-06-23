class DownloadDestinationSettings {
  const DownloadDestinationSettings({
    required this.isConfigured,
    this.displayName,
    this.path,
  });

  final bool isConfigured;
  final String? displayName;
  final String? path;

  factory DownloadDestinationSettings.fromMap(Map<dynamic, dynamic>? raw) {
    return DownloadDestinationSettings(
      isConfigured: raw?['isConfigured'] == true,
      displayName: raw?['displayName']?.toString(),
      path: raw?['path']?.toString(),
    );
  }
}
