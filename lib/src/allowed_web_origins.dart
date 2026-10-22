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

  /// Exact hosts accepted by [canNavigate], for WebViews that enforce the
  /// policy natively before a request is sent.
  static Set<String> get navigationHosts => {
        _gakujoHost,
        _externalUniversityRootHost,
        _externalCoopRootHost,
        ..._allowedExternalHosts,
      };

  /// Host suffixes (with their leading dot) accepted by [canNavigate].
  static Set<String> get navigationHostSuffixes => {
        _externalUniversityHostSuffix,
        _externalCoopHostSuffix,
        ..._allowedExternalHostSuffixes,
      };

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
        !isTransientPage(normalized);
  }

  static bool isTransientPage(String? url) {
    return _isTransientPage(url, includeSessionFlow: true);
  }

  /// A session-bound flow page can be authenticated even though it cannot be
  /// restored after restarting the app.
  static bool isLoginOrTimeoutPage(String? url) {
    return _isTransientPage(url, includeSessionFlow: false);
  }

  static bool _isTransientPage(String? url,
      {required bool includeSessionFlow}) {
    final uri = Uri.tryParse(url ?? '');
    if (uri == null) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('/timeoutalert.html') ||
        path.contains('login') ||
        path.contains('logout') ||
        path.contains('timeout')) {
      return true;
    }
    const transitionQueryKeys = {
      'action',
      'command',
      'eventid',
      '_eventid',
    };
    final Map<String, List<String>> query;
    try {
      query = uri.queryParametersAll;
    } on FormatException {
      // A syntactically valid URI may still contain invalid UTF-8 escapes.
      // Do not persist an unclassifiable URL as the next startup page.
      return true;
    }
    return query.entries.any((entry) {
      final key = entry.key.toLowerCase();
      if (includeSessionFlow && key == '_flowexecutionkey') {
        return true;
      }
      if (!transitionQueryKeys.contains(key)) {
        return false;
      }
      return entry.value.any((value) {
        final normalized = value.toLowerCase();
        return normalized.contains('login') ||
            normalized.contains('logout') ||
            normalized.contains('timeout');
      });
    });
  }

  static bool _isGakujoUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == _gakujoHost &&
        (!uri.hasPort || uri.port == 443) &&
        uri.userInfo.isEmpty;
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
