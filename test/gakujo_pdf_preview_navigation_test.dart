import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_pdf_preview_server.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  test(
    'Linux permits only the active viewer capability when frame is unknown',
    () async {
      final server = GakujoPdfPreviewServer();
      addTearDown(server.close);
      final viewer = await server.start();
      bool allows(String url, bool mainFrame, TargetPlatform platform) =>
          allowsGakujoPdfPreviewNavigation(
            GakujoNavigationRequest(url: url, isMainFrame: mainFrame),
            platform: platform,
            isViewerUrl: server.isViewerUrl,
          );

      expect(allows(viewer.toString(), true, TargetPlatform.linux), isTrue);
      expect(allows(viewer.toString(), false, TargetPlatform.linux), isTrue);
      expect(allows(viewer.toString(), false, TargetPlatform.windows), isTrue);
      expect(allows(viewer.toString(), true, TargetPlatform.windows), isFalse);
      for (final url in [
        '$viewer?extra=1',
        viewer.replace(path: '/other/index.html').toString(),
        viewer.replace(host: 'localhost').toString(),
        viewer
            .replace(port: viewer.port == 65535 ? 65534 : viewer.port + 1)
            .toString(),
        'http://127.0.0.1/index.html',
        'https://example.com/index.html',
      ]) {
        for (final mainFrame in [true, false]) {
          expect(allows(url, mainFrame, TargetPlatform.linux), isFalse);
        }
      }
      await server.close();
      expect(allows(viewer.toString(), true, TargetPlatform.linux), isFalse);
    },
  );
}
