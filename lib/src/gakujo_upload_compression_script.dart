import 'gakujo_upload_compression_libraries.dart';
import 'generated/upload_compression_teardown.g.dart';
import 'generated/upload_compression.g.dart';

/// Shrinks files chosen in Gakujo file inputs that exceed the 5 MB upload
/// limit, before the page sees them. Every file keeps its name and format:
///
/// - JPEG, PNG and WebP images are re-encoded in the same format.
/// - PDFs retain their structure and have embedded images compressed with qpdf.
/// - Word, PowerPoint and Excel files keep their content and have their
///   embedded pictures re-encoded.
///
/// PDF and Office support uses bundled libraries that the app injects on
/// request through [GakujoUploadCompressionLibraries.channelName].
class GakujoUploadCompressionScript {
  const GakujoUploadCompressionScript._();

  static const limitBytes = 5000000;

  static String build() {
    return gakujoUploadCompressionJs({
      'libraryChannelName': GakujoUploadCompressionLibraries.channelName,
    });
  }

  static String buildTeardown() {
    return gakujoUploadCompressionTeardownJs;
  }
}
