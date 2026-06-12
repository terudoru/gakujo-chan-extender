class DownloadDestinationSettings {
  const DownloadDestinationSettings({
    required this.isConfigured,
    this.displayName,
  });

  final bool isConfigured;
  final String? displayName;

  factory DownloadDestinationSettings.fromMap(Map<dynamic, dynamic>? raw) {
    return DownloadDestinationSettings(
      isConfigured: raw?['isConfigured'] == true,
      displayName: raw?['displayName']?.toString(),
    );
  }
}
