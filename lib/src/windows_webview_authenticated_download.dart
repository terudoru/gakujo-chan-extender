import 'download_response_policy.dart';
import 'gakujo_download_request.dart';
import 'generated/authenticated_download_cleanup.g.dart';
import 'generated/authenticated_download_poll.g.dart';
import 'generated/authenticated_download_start.g.dart';

class WindowsWebViewAuthenticatedDownloadScript {
  const WindowsWebViewAuthenticatedDownloadScript._();

  static String start({
    required String requestId,
    required GakujoDownloadRequest request,
  }) => gakujoAuthenticatedDownloadStartJs({
    'requestId': requestId,
    'url': request.url,
    'method': request.method.toUpperCase() == 'POST' ? 'POST' : 'GET',
    'fields': request.formFields,
    'fileName': request.fileName,
    'byteLimit': maxGakujoDownloadBytes,
    'pageReturnedMessage': DownloadResponsePolicy.pageReturnedMessage,
  });

  static String poll(String requestId) =>
      gakujoAuthenticatedDownloadPollJs({'requestId': requestId});

  static String cleanup(String requestId) =>
      gakujoAuthenticatedDownloadCleanupJs({'requestId': requestId});
}
