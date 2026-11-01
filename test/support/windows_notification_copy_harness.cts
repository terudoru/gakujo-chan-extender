// Exercise the production helper's scalar statements with UTF-16 code units.
// Only C++ type/string access syntax and the CRT copy call need adapters;
// compiling that call itself remains part of the Windows build.
import type {} from 'node:fs';
const assert: any = require('node:assert/strict');
const source: any = process.argv[2];
const body: any = source.slice(source.indexOf('{') + 1, source.lastIndexOf('}'))
  .replace(/size_t length/g, 'let length')
  .replace(/value\.size\(\)/g, 'value.length')
  .replace(/value\.c_str\(\)/g, 'value');
const copy: any = new Function(
  'destination', 'destination_count', 'value', 'wcsncpy_s', body
);
function copied(text: any, capacity: any) {
  const destination: any = new Uint16Array(capacity).fill(0xFFFF);
  const value: any = Uint16Array.from(
    {length: text.length}, (_: any, index: any) => text.charCodeAt(index)
  );
  copy(destination, capacity, value, (dst: any, count: any, src: any, length: any) => {
    assert(length >= 0 && length < count);
    dst.set(src.subarray(0, length));
    dst[length] = 0;
  });
  if (capacity === 0) return '';
  const terminator: any = destination.indexOf(0);
  assert(terminator >= 0);
  const result: any = String.fromCharCode(...destination.subarray(0, terminator));
  assert(result.isWellFormed());
  return result;
}
assert.equal(copied('A', 0), '');
assert.equal(copied('A', 1), '');
for (const capacity of [64, 256]) {
  const prefix: any = 'A'.repeat(capacity - 2);
  assert.equal(copied(prefix + '\u{1F600}Z', capacity), prefix);
  const fits: any = 'A'.repeat(capacity - 3) + '\u{1F600}';
  assert.equal(copied(fits, capacity), fits);
  assert.equal(copied('A'.repeat(capacity), capacity), 'A'.repeat(capacity - 1));
  assert.equal(copied('\u{1F600}'.repeat(capacity), capacity),
    '\u{1F600}'.repeat((capacity - 2) / 2));
  assert.equal(copied('\u8AB2\u984C\u{1F600}', capacity), '\u8AB2\u984C\u{1F600}');
  assert.equal(copied('', capacity), '');
}
