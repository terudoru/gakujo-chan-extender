class AllowedWebOrigins {
  static const gakujoUrl =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
  static const _gakujoHost = 'gakujo.iess.niigata-u.ac.jp';
  static const _debugFixturePrefix = 'file:///android_asset/qa/';

  const AllowedWebOrigins._();

  static bool canLoad(String? url, {required bool debugAllowed}) {
    if (url == null || url.trim().isEmpty) {
      return false;
    }

    return _isGakujoUrl(url) ||
        (debugAllowed && url.startsWith(_debugFixturePrefix));
  }

  static bool canAutofill(String? url, {required bool debugAllowed}) {
    return canLoad(url, debugAllowed: debugAllowed);
  }

  static bool canRestoreLastPage(String? url, {required bool debugAllowed}) {
    return canLoad(url, debugAllowed: debugAllowed) && !_isTransientPage(url);
  }

  static bool _isTransientPage(String? url) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null) {
      return false;
    }
    return uri.path.endsWith('/TimeoutAlert.html');
  }

  static bool _isGakujoUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host == _gakujoHost;
  }
}
