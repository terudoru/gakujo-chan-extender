import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('windows/runner/flutter_window.cpp').readAsStringSync();
  final start = source.indexOf('void CopyWideString(');
  final end = source.indexOf('\nbool ShowDeadlineToast(', start);
  final copy = source.substring(start, end);

  test('balloon strings preserve code points at the 64 and 256 unit limits',
      () async {
    final result = await Process.run('node', ['-e', _copyHarness, copy]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('both balloon buffers use the surrogate-safe copy', () {
    expect(
      source,
      contains(
        'CopyWideString(data.szInfoTitle, ARRAYSIZE(data.szInfoTitle), title)',
      ),
    );
    expect(
      source,
      contains('CopyWideString(data.szInfo, ARRAYSIZE(data.szInfo), body)'),
    );
  });
}

// Exercise the production helper's scalar statements with UTF-16 code units.
// Only C++ type/string access syntax and the CRT copy call need adapters;
// compiling that call itself remains part of the Windows build.
const _copyHarness = r'''
const assert = require('node:assert/strict');
const source = process.argv[1];
const body = source.slice(source.indexOf('{') + 1, source.lastIndexOf('}'))
  .replace(/size_t length/g, 'let length')
  .replace(/value\.size\(\)/g, 'value.length')
  .replace(/value\.c_str\(\)/g, 'value');
const copy = new Function(
  'destination', 'destination_count', 'value', 'wcsncpy_s', body
);
function copied(text, capacity) {
  const destination = new Uint16Array(capacity).fill(0xFFFF);
  const value = Uint16Array.from(
    {length: text.length}, (_, index) => text.charCodeAt(index)
  );
  copy(destination, capacity, value, (dst, count, src, length) => {
    assert(length >= 0 && length < count);
    dst.set(src.subarray(0, length));
    dst[length] = 0;
  });
  if (capacity === 0) return '';
  const terminator = destination.indexOf(0);
  assert(terminator >= 0);
  const result = String.fromCharCode(...destination.subarray(0, terminator));
  assert(result.isWellFormed());
  return result;
}
assert.equal(copied('A', 0), '');
assert.equal(copied('A', 1), '');
for (const capacity of [64, 256]) {
  const prefix = 'A'.repeat(capacity - 2);
  assert.equal(copied(prefix + '\u{1F600}Z', capacity), prefix);
  const fits = 'A'.repeat(capacity - 3) + '\u{1F600}';
  assert.equal(copied(fits, capacity), fits);
  assert.equal(copied('A'.repeat(capacity), capacity), 'A'.repeat(capacity - 1));
  assert.equal(copied('\u{1F600}'.repeat(capacity), capacity),
    '\u{1F600}'.repeat((capacity - 2) / 2));
  assert.equal(copied('\u8AB2\u984C\u{1F600}', capacity), '\u8AB2\u984C\u{1F600}');
  assert.equal(copied('', capacity), '');
}
''';
