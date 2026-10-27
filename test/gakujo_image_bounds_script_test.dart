import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_image_bounds_script.dart';
import 'package:test/test.dart';

void main() {
  test('checks image headers before decoding for supported formats', () async {
    final result = await Process.run('node', [
      '-e',
      r'''
const vm = require('node:vm');
const c = vm.createContext({Promise, Uint8Array, DataView, Array, Math, Error});
vm.runInContext(process.argv[1], c);
function file(bytes) {
  return {size: bytes.length, slice() { return {arrayBuffer: async () => Uint8Array.from(bytes).buffer}; }};
}
const png = [137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,10,0,0,0,20,
  8,2,0,0,0,0,0,0,0,0,0,0,0,73,68,65,84,0,0,0,0];
const jpeg = [255,216,255,192,0,8,8,0,20,0,10,1];
const webp = [82,73,70,70,0,0,0,0,87,69,66,80,86,80,56,88,0,0,0,0,0,0,0,0,9,0,0,19,0,0];
(async () => {
  for (const bytes of [png, jpeg, webp]) {
    const size = await c.mbgValidateImage(file(bytes));
    if (size.width !== 10 || size.height !== 20) throw Error('valid dimensions');
  }
  const huge = png.slice(); huge[16]=0; huge[17]=0; huge[18]=39; huge[19]=17;
  const apng = png.slice(0,33).concat([0,0,0,0,97,99,84,76,0,0,0,0], png.slice(33));
  const animatedWebp = webp.slice(); animatedWebp[20] = 2;
  for (const bytes of [huge, apng, animatedWebp, [1,2,3]]) {
    let rejected = false;
    try { await c.mbgValidateImage(file(bytes)); } catch (_) { rejected = true; }
    if (!rejected) throw Error('unsafe header accepted');
  }
})().catch(e => { console.error(e); process.exit(1); });
''',
      GakujoImageBoundsScript.source,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
