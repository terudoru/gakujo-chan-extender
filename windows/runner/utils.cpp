#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <cstring>
#include <iostream>
#include <limits>

namespace {

constexpr char kDeadlineNotificationPrefix[] =
    "morebettergakujo://notification?url=";

int HexDigit(char value) {
  if (value >= '0' && value <= '9') {
    return value - '0';
  }
  if (value >= 'a' && value <= 'f') {
    return value - 'a' + 10;
  }
  if (value >= 'A' && value <= 'F') {
    return value - 'A' + 10;
  }
  return -1;
}

}  // namespace

std::string DeadlineNotificationActivationUrl(const std::string& url) {
  constexpr char hex[] = "0123456789ABCDEF";
  std::string argument = kDeadlineNotificationPrefix;
  for (const unsigned char value : url) {
    if ((value >= 'a' && value <= 'z') ||
        (value >= 'A' && value <= 'Z') ||
        (value >= '0' && value <= '9') || value == '-' || value == '.' ||
        value == '_' || value == '~') {
      argument.push_back(static_cast<char>(value));
    } else {
      argument.push_back('%');
      argument.push_back(hex[value >> 4]);
      argument.push_back(hex[value & 0x0F]);
    }
  }
  return argument;
}

std::string DeadlineNotificationUrlFromArgument(const std::string& argument) {
  constexpr char authority[] = "morebettergakujo://notification";
  constexpr size_t authority_length = sizeof(authority) - 1;
  if (argument.size() < authority_length ||
      _strnicmp(argument.c_str(), authority, authority_length) != 0) {
    return std::string();
  }

  size_t prefix_length = authority_length;
  if (prefix_length < argument.size() && argument[prefix_length] == '/') {
    ++prefix_length;
  }
  constexpr char query[] = "?url=";
  if (argument.compare(prefix_length, sizeof(query) - 1, query) != 0) {
    return std::string();
  }
  prefix_length += sizeof(query) - 1;

  std::string url;
  for (size_t i = prefix_length; i < argument.size(); ++i) {
    if (argument[i] != '%') {
      url.push_back(argument[i]);
      continue;
    }
    if (i + 2 >= argument.size()) {
      return std::string();
    }
    const int high = HexDigit(argument[i + 1]);
    const int low = HexDigit(argument[i + 2]);
    if (high < 0 || low < 0) {
      return std::string();
    }
    url.push_back(static_cast<char>((high << 4) | low));
    i += 2;
  }
  return IsDeadlineNotificationUrl(url) ? url : std::string();
}

bool IsDeadlineNotificationUrl(const std::string& url) {
  constexpr char prefix[] = "https://gakujo.iess.niigata-u.ac.jp/";
  if (url.compare(0, sizeof(prefix) - 1, prefix) != 0 ||
      url.find('\0') != std::string::npos ||
      url.size() > static_cast<size_t>((std::numeric_limits<int>::max)())) {
    return false;
  }

  // The protocol argument has already had its one outer decode. Escapes in
  // target values (such as title=Report%20A) must remain encoded.
  for (const unsigned char value : url) {
    if (value <= 0x20 || value == 0x7F) {
      return false;
    }
  }

  // Scheme launches are untrusted: only durable links, never flow actions.
  const size_t fragment = url.find('#');
  const size_t query_end = fragment == std::string::npos ? url.size() : fragment;
  const size_t query_start = url.find('?');
  if (query_start < query_end) {
    for (size_t i = query_start + 1; i < query_end; ++i) {
      if (url[i] == '%' &&
          (i + 2 >= query_end || HexDigit(url[i + 1]) < 0 ||
           HexDigit(url[i + 2]) < 0)) {
        return false;
      }
    }
    size_t parameter_start = query_start + 1;
    while (parameter_start < query_end) {
      const size_t ampersand = url.find('&', parameter_start);
      const size_t parameter_end =
          ampersand < query_end ? ampersand : query_end;
      const size_t separator = url.find_first_of("=&", parameter_start);
      const size_t name_end =
          separator < parameter_end ? separator : parameter_end;
      std::string name;
      for (size_t i = parameter_start; i < name_end; ++i) {
        char value = url[i] == '+' ? ' ' : url[i];
        if (value == '%' && i + 2 < name_end) {
          const int high = HexDigit(url[i + 1]);
          const int low = HexDigit(url[i + 2]);
          if (high >= 0 && low >= 0) {
            value = static_cast<char>((high << 4) | low);
            i += 2;
          }
        }
        if (static_cast<unsigned char>(value) <= 0x20 || value == 0x7F) {
          return false;
        }
        if (value >= 'A' && value <= 'Z') {
          value = static_cast<char>(value - 'A' + 'a');
        }
        name.push_back(value);
      }
      if (name == "_eventid" || name == "_flowexecutionkey" ||
          name.compare(0, sizeof("_eventid_") - 1, "_eventid_") == 0) {
        return false;
      }
      parameter_start = parameter_end + 1;
    }
  }
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, url.data(),
                             static_cast<int>(url.size()), nullptr, 0) > 0;
}

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
