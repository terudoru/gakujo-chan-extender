import 'dart:io' show Platform;

import '../gakujo_download_service.dart';
import '../web_view_service.dart';

abstract class GakujoPlatformService {
  const GakujoPlatformService();

  static GakujoPlatformService current() {
    if (Platform.isAndroid) {
      return const AndroidGakujoPlatformService();
    }
    if (Platform.isIOS) {
      return const IosGakujoPlatformService();
    }
    if (Platform.isMacOS || Platform.isWindows) {
      return const DesktopGakujoPlatformService();
    }
    return const UnsupportedGakujoPlatformService();
  }

  GakujoWebViewService createWebViewService();

  GakujoDownloadService createDownloadService();
}

class AndroidGakujoPlatformService extends GakujoPlatformService {
  const AndroidGakujoPlatformService();

  @override
  GakujoWebViewService createWebViewService() {
    return const WebViewFlutterGakujoWebViewService();
  }

  @override
  GakujoDownloadService createDownloadService() {
    return const MethodChannelGakujoDownloadService();
  }
}

class IosGakujoPlatformService extends GakujoPlatformService {
  const IosGakujoPlatformService();

  @override
  GakujoWebViewService createWebViewService() {
    return const WebViewFlutterGakujoWebViewService();
  }

  @override
  GakujoDownloadService createDownloadService() {
    return const UnsupportedGakujoDownloadService(
      'iOS download saving is not implemented yet.',
    );
  }
}

class DesktopGakujoPlatformService extends GakujoPlatformService {
  const DesktopGakujoPlatformService();

  @override
  GakujoWebViewService createWebViewService() {
    return const WebViewFlutterGakujoWebViewService();
  }

  @override
  GakujoDownloadService createDownloadService() {
    return const UnsupportedGakujoDownloadService(
      'Desktop download saving is not implemented yet.',
    );
  }
}

class UnsupportedGakujoPlatformService extends GakujoPlatformService {
  const UnsupportedGakujoPlatformService();

  @override
  GakujoWebViewService createWebViewService() {
    return const WebViewFlutterGakujoWebViewService();
  }

  @override
  GakujoDownloadService createDownloadService() {
    return const UnsupportedGakujoDownloadService('Unsupported platform.');
  }
}
