enum StarSyncStatus {
  disabled,
  ok,
  error,
  needsLegacyReset,
  needsGoogleSignIn,
  accountMismatch,
  accountReturned,
}

/// Google addresses are not case-sensitive, and stored and returned spellings can differ.
bool sameGoogleAccount(String? a, String? b) =>
    a != null && b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

class StarSyncConfig {
  const StarSyncConfig({this.googleEmail});

  final String? googleEmail;

  Map<String, Object?> toJson() => {
    'backend': 'googleDrive',
    'googleEmail': googleEmail,
  };

  factory StarSyncConfig.fromJson(Map<String, dynamic> json) {
    if (json['backend'] != 'googleDrive') throw const FormatException();
    return StarSyncConfig(googleEmail: json['googleEmail'] as String?);
  }
}
