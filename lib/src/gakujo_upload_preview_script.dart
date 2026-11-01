import 'generated/upload_preview.g.dart';

/// Adds a local preview of the file currently selected for upload.
class GakujoUploadPreviewScript {
  const GakujoUploadPreviewScript._();

  static String build({bool compactAndroid = false}) =>
      gakujoUploadPreviewJs({'compactAndroid': compactAndroid});
}
