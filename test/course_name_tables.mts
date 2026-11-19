import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {stripTypeScriptTypes} from 'node:module';
import vm from 'node:vm';

const source = stripTypeScriptTypes(
  (await readFile(process.argv[2] || 'web_scripts/src/course_name_tables/main.ts', 'utf8'))
    .replace('export {};', '')
);
const cases = [
  ['<tr><th>科目名</th><th>担当教員</th></tr><tr><td>物理学</td><td>Teacher</td></tr>', '物理学'],
  ['<tr><th>担当教員</th><th>科目名</th></tr><tr><td>Teacher</td><td>物理学</td></tr>', '物理学'],
  ['<tr><th>科目名</th><td>物理学</td></tr>', '物理学'],
  ['<tr><td>科目名</td><td>物理学</td></tr>', '物理学'],
  ['<tr><th>科目名</th><th>担当教員</th><td>物理学</td></tr>', '物理学'],
  ['<tr><th>科目名</th><td> </td></tr><tr><td>物理学</td></tr>', '物理学'],
  ['<tr><th>担当教員</th><td>Teacher</td></tr>', ''],
];
function candidates(html: string) {
  const rows = [...html.matchAll(/<tr>(.*?)<\/tr>/g)].map(row => ({
    cells: [...row[1].matchAll(/<(th|td)>(.*?)<\/\1>/g)].map(cell => ({
      tagName: cell[1].toUpperCase(), textContent: cell[2]
    }))
  }));
  const document = {querySelectorAll(selector: string) {
    assert.equal(selector, 'table');
    return [{rows}];
  }};
  const context = {window: {document, frames: []}, __mbgEntryResult: ''};
  vm.runInNewContext(source, context);
  const {courseNameCandidates} = JSON.parse(context.__mbgEntryResult);
  assert.ok(Array.isArray(courseNameCandidates));
  return courseNameCandidates;
}
for (const [html, expected] of cases) {
  assert.deepEqual(candidates(html), expected ? [expected] : [], html);
}
const column = '<tr><th>科目名</th><th>担当教員</th></tr>';
const row = (course: string) => `<tr><td>${course}</td><td>Teacher</td></tr>`;
assert.deepEqual(candidates(column + row('Physics') + row('Chemistry')), ['Physics', 'Chemistry']);
assert.deepEqual(candidates(column + row('Physics') + row('ABC123 Physics')), ['Physics', 'ABC123 Physics']);
assert.deepEqual(candidates('<tr><th>科目名</th><td>Physics</td><td>Teacher</td></tr>' +
  '<tr><th>担当教員</th><td>Teacher</td></tr>'), ['Physics']);
assert.deepEqual(candidates(column + '<tr><th>Physics</th><td>Teacher</td></tr>'), ['Physics']);
assert.deepEqual(candidates(column + row('Physics') +
  '<tr><th>Room</th><th>Time</th></tr><tr><td>Lab</td><td>Noon</td></tr>'), ['Physics']);
assert.deepEqual(candidates('<tr><th>科目名</th><td> </td><td>Physics</td><td>Teacher</td></tr>'),
  ['Physics']);
assert.deepEqual(candidates('<tr><th>科目名</th><td> </td><th>担当教員</th><td>Teacher</td></tr>'),
  []);
console.log('Course name table cases passed.');
