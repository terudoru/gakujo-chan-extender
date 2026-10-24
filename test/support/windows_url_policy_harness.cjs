const assert = require('node:assert/strict');
const fs = require('node:fs');

// Execute the production predicates with adapters for C++ scalar/string syntax,
// as in windows_notification_source_test's CopyWideString harness. This does
// not compile Win32 calls; the reviewer still needs to build on Windows.
function predicate(source, name, parameter, env) {
  const start = source.indexOf('{', source.indexOf(` ${name}(`));
  assert(start >= 0, `missing ${name}`);
  let end = start + 1, depth = 1;
  while (depth) {
    const char = source[end++];
    if (char === '{') depth++;
    if (char === '}') depth--;
    assert(end <= source.length, `unterminated ${name}`);
  }
  const body = source.slice(start + 1, end - 1)
    .replace(/^\s*\/\/[^\n]*/gm, '')
    .replace(/const NavigationAllowlist gakujo\{\{"([^"]+)"\}, \{\}\};/g,
      'const gakujo = {hosts: ["$1"], host_suffixes: []};')
    .replace(/constexpr char (\w+)\[\]/g, 'const $1')
    .replace(/sizeof\((\w+|"[^"]*")\) - 1/g, '$1.length')
    .replace(/static_cast<size_t>\(\(std::numeric_limits<int>::max\)\(\)\)/g, '2147483647')
    .replace(/std::string::npos/g, 'Infinity')
    .replace(/std::string\(\)/g, '""')
    .replace(/std::string (\w+);/g, 'let $1 = "";')
    .replace(/(?:(?:const|constexpr) )?(?:size_t|int|char|std::string) (\w+)\s*=/g, 'let $1 =')
    .replace(/for \(const unsigned char (\w+) : (\w+)\)/g,
      'for (const $1 of Buffer.from($2, "utf8"))')
    .replace(/for \(const auto& (\w+) : ([\w.]+)\)/g, 'for (const $1 of $2)')
    .replace(/'(?:\\.|[^'\\])'/g, literal => String(new Function(`return ${literal}`)().charCodeAt(0)))
    .replace(/(\w+)\[([^\]]+)\]/g, '$1.charCodeAt($2)')
    .replace(/(\w+)\.size\(\)/g, '$1.length')
    .replace(/(\w+)\.(?:c_str|data)\(\)/g, '$1')
    .replace(/static_cast<[^>]+>\(/g, '(')
    .replace(/(\w+)\.empty\(\)/g, '($1.length === 0)')
    .replace(/(\w+)\.resize\((\w+)\)/g, '$1 = $1.substr(0, $2)')
    .replace(/(\w+)\.push_back\(([^;]+)\);/g, '$1 += String.fromCharCode($2);')
    .replace(/(\w+)\.find_first_of\(/g, 'findFirstOf($1, ')
    .replace(/(\w+)\.find\(/g, 'find($1, ')
    .replace(/(\w+)\.compare\(/g, 'compare($1, ')
    .replace(/\bnullptr\b/g, 'null');
  const run = new Function('env', parameter, `with (env) { ${body} }`);
  return value => run(env, value);
}

const env = {
  Buffer,
  AsciiLower: value => value.toLowerCase(),
  find: (text, needle, start = 0) => {
    const index = text.indexOf(typeof needle === 'number' ? String.fromCharCode(needle) : needle, start);
    return index < 0 ? Infinity : index;
  },
  findFirstOf: (text, chars, start = 0) => {
    for (let i = start; i < text.length; i++) if (chars.includes(text[i])) return i;
    return Infinity;
  },
  compare: (text, start, length, other) => text.substr(start, length) === other ? 0 : -1,
  _strnicmp: (left, right, length) => left.slice(0, length).toLowerCase() === right.slice(0, length).toLowerCase() ? 0 : -1,
  CP_UTF8: 65001,
  MB_ERR_INVALID_CHARS: 8,
  MultiByteToWideChar: (_codepage, _flags, value) => Buffer.from(value).length,
};
const runner = fs.readFileSync('windows/runner/utils.cpp', 'utf8');
env.HexDigit = predicate(runner, 'HexDigit', 'value', env);
env.IsDeadlineNotificationUrl = predicate(runner, 'IsDeadlineNotificationUrl', 'url', env);
const activationTarget = predicate(runner, 'DeadlineNotificationUrlFromArgument', 'argument', env);
const base = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';
for (const target of [
  'report?title=Report%20A', 'report?title=Report+A', 'report?title=Report%2520A',
  'report?title=%00%09%0A%7F', 'report?title=%26_eventId%3Ddelete',
  'Report%20A?title=%E9%80%A3%E7%B5%A1', 'report?a%2Bb=ok', 'report#?_eventId=delete',
]) {
  const url = base + target;
  assert.equal(env.IsDeadlineNotificationUrl(url), true, target);
  assert.equal(activationTarget('morebettergakujo://notification?url=' + encodeURIComponent(url)), url);
}
for (const code of [...Array.from({length: 33}, (_, i) => i), 127]) {
  const raw = String.fromCharCode(code), encoded = '%' + code.toString(16).padStart(2, '0');
  for (const target of [`report${raw}`, `report?title=A${raw}B`, `report#A${raw}B`,
    `report?_even${encoded}tId=delete`, `report?name${encoded}=ok`]) {
    assert.equal(env.IsDeadlineNotificationUrl(base + target), false, JSON.stringify(target));
  }
}
for (const query of ['_eventId=delete', '%5Fevent%49d=download', '_eventId_x=delete',
  '_flowExecutionKey=e1s1', 'name+with+spaces=ok', 'name%=ok', 'title=%GG']) {
  assert.equal(env.IsDeadlineNotificationUrl(base + 'report?' + query), false, query);
}

const navigation = fs.readFileSync('third_party/webview_flutter_windows/windows/util/navigation_allowlist.h', 'utf8');
const allowed = predicate(navigation, 'IsNavigationAllowed', 'url', env);
env.IsNavigationAllowed = (url, allowlist) => {
  env.allowlist = allowlist;
  return allowed(url);
};
const replayable = predicate(navigation, 'IsReplayableGakujoDownload', 'url', env);
for (const query of ['_eventId=download', 'fileId=42&_EVENTID=DOWNLOAD', '_eventId=download&fileId=42#file']) {
  assert.equal(replayable(base + 'file?' + query), true, query);
}
for (const suffix of ['', '?', '?fileId=42', '?_eventId=infoDownload', '?_eventId=downloadLater',
  '?x_eventId=download', '?next=_eventId=download', '#?_eventId=download',
  '?fileId=42#?_eventId=download']) {
  assert.equal(replayable(base + 'file' + suffix), false, suffix);
}
for (const origin of ['http://gakujo.iess.niigata-u.ac.jp/', 'https://example.com/',
  'https://user@gakujo.iess.niigata-u.ac.jp/', 'https://gakujo.iess.niigata-u.ac.jp:8443/',
  'https://gakujo.iess.niigata-u.ac.jp.example.com/', 'about:blank']) {
  assert.equal(replayable(origin + '?_eventId=download'), false, origin);
}
console.log('Native notification and download URL policy regressions passed (Win32 calls adapted).');
