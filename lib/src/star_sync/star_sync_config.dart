import 'star_sync_s3_transport.dart';
import 'star_sync_webdav_transport.dart';

enum StarSyncBackend { webDav, s3, googleDrive }

enum StarSyncStatus {
  disabled,
  ok,
  error,
  needsPassphrase,
  needsPairingCode,
  accountMismatch,
}

class StarSyncConfig {
  const StarSyncConfig({required this.backend, this.webDav, this.s3});

  final StarSyncBackend backend;
  final StarSyncWebDavConfig? webDav;
  final StarSyncS3Config? s3;

  Map<String, Object?> toJson() => {
    'backend': backend.name,
    if (backend != StarSyncBackend.googleDrive)
      if (webDav case final value?)
        'webDav': {
          'baseUrl': value.baseUrl.toString(),
          'username': value.username,
          'password': value.password,
        },
    if (backend != StarSyncBackend.googleDrive)
      if (s3 case final value?)
        's3': {
          'endpoint': value.endpoint.toString(),
          'region': value.region,
          'bucket': value.bucket,
          'prefix': value.prefix,
          'accessKeyId': value.accessKeyId,
          'secretAccessKey': value.secretAccessKey,
          'pathStyle': value.pathStyle,
        },
  };

  factory StarSyncConfig.fromJson(Map<String, dynamic> json) {
    final backend = StarSyncBackend.values.byName(json['backend'] as String);
    final dav = json['webDav'] as Map<String, dynamic>?;
    final s3 = json['s3'] as Map<String, dynamic>?;
    return StarSyncConfig(
      backend: backend,
      webDav: dav == null
          ? null
          : StarSyncWebDavConfig(
              baseUrl: Uri.parse(dav['baseUrl'] as String),
              username: dav['username'] as String,
              password: dav['password'] as String,
            ),
      s3: s3 == null
          ? null
          : StarSyncS3Config(
              endpoint: Uri.parse(s3['endpoint'] as String),
              region: s3['region'] as String,
              bucket: s3['bucket'] as String,
              prefix: s3['prefix'] as String,
              accessKeyId: s3['accessKeyId'] as String,
              secretAccessKey: s3['secretAccessKey'] as String,
              pathStyle: s3['pathStyle'] as bool,
            ),
    );
  }
}
