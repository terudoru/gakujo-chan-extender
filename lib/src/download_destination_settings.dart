class DownloadDestinationSettings {
  const DownloadDestinationSettings({
    required this.isConfigured,
    this.displayName,
    this.path,
    this.isSessionOnly = false,
  });

  final bool isConfigured;
  final String? displayName;
  final String? path;
  final bool isSessionOnly;

  factory DownloadDestinationSettings.fromMap(Map<dynamic, dynamic>? raw) {
    return DownloadDestinationSettings(
      isConfigured: raw?['isConfigured'] == true,
      displayName: raw?['displayName']?.toString(),
      path: raw?['path']?.toString(),
    );
  }
}
