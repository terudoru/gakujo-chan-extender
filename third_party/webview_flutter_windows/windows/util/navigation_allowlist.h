#pragma once

// More Better Gakujo patch: host allow-list checked in NavigationStarting so a
// blocked navigation is cancelled before any request is sent.

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

namespace util {

struct NavigationAllowlist {
  // Exact host names, lowercase.
  std::vector<std::string> hosts;
  // Suffixes including the leading dot, such as ".example.jp".
  std::vector<std::string> host_suffixes;
};

inline std::string AsciiLower(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return value;
}

// Allows about:blank and https URLs without credentials on the default port
// whose host is listed or ends with a listed suffix.
inline bool IsNavigationAllowed(const std::string& url,
                                const NavigationAllowlist& allowlist) {
  const std::string lower = AsciiLower(url);
  if (lower == "about:blank") {
    return true;
  }
  const std::string scheme = "https://";
  if (lower.compare(0, scheme.size(), scheme) != 0) {
    return false;
  }
  const size_t start = scheme.size();
  const size_t end = lower.find_first_of("/?#\\", start);
  std::string host = lower.substr(
      start, end == std::string::npos ? std::string::npos : end - start);
  if (host.empty() || host.find('@') != std::string::npos || host[0] == '[') {
    return false;
  }
  const size_t colon = host.find(':');
  if (colon != std::string::npos) {
    if (host.substr(colon + 1) != "443") {
      return false;
    }
    host.resize(colon);
  }
  for (const auto& allowed : allowlist.hosts) {
    if (host == allowed) {
      return true;
    }
  }
  for (const auto& suffix : allowlist.host_suffixes) {
    if (host.size() > suffix.size() &&
        host.compare(host.size() - suffix.size(), suffix.size(), suffix) == 0) {
      return true;
    }
  }
  return false;
}

inline bool IsReplayableGakujoDownload(const std::string& url) {
  const NavigationAllowlist gakujo{{"gakujo.iess.niigata-u.ac.jp"}, {}};
  const size_t query = url.find('?');
  const size_t fragment = url.find('#');
  if (!IsNavigationAllowed(url, gakujo) || query == std::string::npos ||
      (fragment != std::string::npos && query > fragment)) {
    return false;
  }
  const size_t end = fragment == std::string::npos ? url.size() : fragment;
  const std::string parameters =
      AsciiLower(url.substr(query + 1, end - query - 1));
  size_t start = 0;
  while (start < parameters.size()) {
    const size_t separator = parameters.find('&', start);
    if (parameters.substr(start, separator == std::string::npos
                                    ? std::string::npos : separator - start) ==
        "_eventid=download") {
      return true;
    }
    if (separator == std::string::npos) {
      break;
    }
    start = separator + 1;
  }
  return false;
}

}  // namespace util
