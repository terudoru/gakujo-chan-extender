import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'allowed_web_origins.dart';

class GakujoLastPageStore {
  GakujoLastPageStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const lastUrlKey = 'more_better_gakujo_last_url';

  final FlutterSecureStorage _secureStorage;

  Future<String?> load({required bool debugAllowed}) async {
    final url = await _secureStorage.read(key: lastUrlKey);
    if (AllowedWebOrigins.canRestoreLastPage(
      url,
      debugAllowed: debugAllowed,
    )) {
      return url;
    }

    if (url != null) {
      await clear();
    }
    return null;
  }

  Future<void> saveIfAllowed(
    String? url, {
    required bool debugAllowed,
  }) async {
    if (!AllowedWebOrigins.canRestoreLastPage(
      url,
      debugAllowed: debugAllowed,
    )) {
      return;
    }

    await _secureStorage.write(key: lastUrlKey, value: url);
  }

  Future<void> clear() {
    return _secureStorage.delete(key: lastUrlKey);
  }
}
