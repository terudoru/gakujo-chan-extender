class AllowedWebOrigins {
  static const gakujoUrl =
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';
  static const _gakujoHost = 'gakujo.iess.niigata-u.ac.jp';
  static const _debugFixturePrefix = 'file:///android_asset/qa/';
  static const _externalUniversityHostSuffix = '.niigata-u.ac.jp';
  static const _externalUniversityRootHost = 'niigata-u.ac.jp';
  static const _externalCoopHostSuffix = '.univcoop.jp';
  static const _externalCoopRootHost = 'univcoop.jp';
  static const _allowedExternalHosts = {
    'accounts.google.com',
    'calendar.google.com',
    'docs.google.com',
    'drive.google.com',
    'forms.gle',
    'www.google.com',
    'youtube.com',
    'youtu.be',
    'zoom.us',
  };
  static const _allowedExternalHostSuffixes = {
    '.youtube.com',
    '.zoom.us',
  };

  const AllowedWebOrigins._();

  static bool canLoad(String? url, {required bool debugAllowed}) {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }

    return _isGakujoUrl(normalized) ||
        (debugAllowed && normalized.startsWith(_debugFixturePrefix));
  }

  static bool canNavigate(String? url, {required bool debugAllowed}) {
    final normalized = url?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }

    return canLoad(normalized, debugAllowed: debugAllowed) ||
        _isAllowedExternalUrl(normalized);
  }

  static bool canAutofill(String? url, {required bool debugAllowed}) {
    return canLoad(url, debugAllowed: debugAllowed);
  }

  static bool canRestoreLastPage(String? url, {required bool debugAllowed}) {
    final normalized = url?.trim();
    return canLoad(normalized, debugAllowed: debugAllowed) &&
        !_isTransientPage(normalized);
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

  static bool _isAllowedExternalUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == _externalUniversityRootHost ||
        host.endsWith(_externalUniversityHostSuffix) ||
        host == _externalCoopRootHost ||
        host.endsWith(_externalCoopHostSuffix) ||
        _allowedExternalHosts.contains(host) ||
        _allowedExternalHostSuffixes.any(host.endsWith);
  }
}
