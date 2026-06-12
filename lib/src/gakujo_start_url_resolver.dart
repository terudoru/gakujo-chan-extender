import 'allowed_web_origins.dart';

class GakujoStartUrlResolver {
  const GakujoStartUrlResolver._();

  static String resolve({
    required bool debugAllowed,
    String? debugStartUrl,
    String? savedUrl,
    String? fallbackUrl,
  }) {
    if (debugStartUrl != null &&
        AllowedWebOrigins.canLoad(debugStartUrl, debugAllowed: debugAllowed)) {
      return debugStartUrl;
    }

    if (savedUrl != null &&
        AllowedWebOrigins.canLoad(savedUrl, debugAllowed: debugAllowed)) {
      return savedUrl;
    }

    return fallbackUrl ?? AllowedWebOrigins.gakujoUrl;
  }
}
