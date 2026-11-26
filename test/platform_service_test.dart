import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/file_system_gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/platform/platform_service.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  const factories = [
    (
      AndroidGakujoPlatformService(),
      WebViewFlutterGakujoWebViewService,
      MethodChannelGakujoDownloadService,
      MethodChannelGakujoCalendarService,
    ),
    (
      IosGakujoPlatformService(),
      WebViewFlutterGakujoWebViewService,
      FileSystemGakujoDownloadService,
      MethodChannelGakujoCalendarService,
    ),
    (
      MacosGakujoPlatformService(),
      WebViewFlutterGakujoWebViewService,
      FileSystemGakujoDownloadService,
      MethodChannelGakujoCalendarService,
    ),
    (
      LinuxGakujoPlatformService(),
      WebViewFlutterGakujoWebViewService,
      FileSystemGakujoDownloadService,
      UnsupportedGakujoCalendarService,
    ),
    (
      DesktopGakujoPlatformService(),
      WindowsGakujoWebViewService,
      FileSystemGakujoDownloadService,
      UnsupportedGakujoCalendarService,
    ),
    (
      UnsupportedGakujoPlatformService(),
      WebViewFlutterGakujoWebViewService,
      UnsupportedGakujoDownloadService,
      UnsupportedGakujoCalendarService,
    ),
  ];

  for (final (platform, webViewType, downloadType, calendarType) in factories) {
    test('${platform.runtimeType} selects its platform services', () {
      expect(platform.createWebViewService().runtimeType, webViewType);
      final download = platform.createDownloadService();
      expect(download.runtimeType, downloadType);
      if (download is FileSystemGakujoDownloadService) {
        expect(platform.createDownloadService(), isNot(same(download)));
      }
      final calendar = platform.createCalendarService();
      expect(calendar.runtimeType, calendarType);
      expect(
        calendar.supportsDirectSync,
        calendarType == MethodChannelGakujoCalendarService,
      );
    });
  }
}
