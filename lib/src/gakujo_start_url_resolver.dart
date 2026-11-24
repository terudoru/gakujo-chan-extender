import 'allowed_web_origins.dart';
import 'gakujo_quick_jump_destination.dart';
import 'gakujo_startup_settings.dart';

class GakujoStartUrlResolver {
  const GakujoStartUrlResolver._();

  static String resolve({
    required bool debugAllowed,
    String? debugStartUrl,
    String? savedUrl,
    String? fallbackUrl,
    String? notificationUrl,
    GakujoStartupPage startupPage = GakujoStartupPage.previous,
  }) {
    if (notificationUrl != null &&
        AllowedWebOrigins.canLoad(
          notificationUrl,
          debugAllowed: debugAllowed,
        )) {
      return notificationUrl;
    }
    if (debugStartUrl != null &&
        AllowedWebOrigins.canLoad(debugStartUrl, debugAllowed: debugAllowed)) {
      return debugStartUrl;
    }

    switch (startupPage) {
      case GakujoStartupPage.home:
        return fallbackUrl ?? AllowedWebOrigins.gakujoUrl;
      case GakujoStartupPage.reports:
        return GakujoQuickJumpDestination.reports.portalUrl;
      case GakujoStartupPage.messages:
        return GakujoQuickJumpDestination.messages.portalUrl;
      case GakujoStartupPage.previous:
        break;
    }
    if (savedUrl != null &&
        AllowedWebOrigins.canLoad(savedUrl, debugAllowed: debugAllowed)) {
      return savedUrl;
    }

    return fallbackUrl ?? AllowedWebOrigins.gakujoUrl;
  }
}
