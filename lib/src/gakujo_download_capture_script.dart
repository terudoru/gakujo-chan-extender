import 'generated/download_capture.g.dart';
import 'generated/download_capture_teardown.g.dart';

class GakujoDownloadCaptureScript {
  const GakujoDownloadCaptureScript._();

  static const channelName = 'MoreBetterGakujoDownloads';

  static String build() {
    return gakujoDownloadCaptureJs;
  }

  static String buildTeardown() {
    return gakujoDownloadCaptureTeardownJs;
  }
}
