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
for (const [html, expected] of cases) {
  const rows = [...html.matchAll(/<tr>(.*?)<\/tr>/g)].map(row => ({
    querySelectorAll(selector: string) {
      assert.equal(selector, 'th,td');
      return [...row[1].matchAll(/<(th|td)>(.*?)<\/\1>/g)].map(cell => ({
        tagName: cell[1].toUpperCase(), textContent: cell[2]
      }));
    }
  }));
  const document = {querySelectorAll(selector: string) {
    assert.equal(selector, 'table');
    return [{querySelectorAll(selector: string) {
      assert.equal(selector, 'tr');
      return rows;
    }}];
  }};
  const context = {window: {document, frames: []}, __mbgEntryResult: ''};
  vm.runInNewContext(source, context);
  assert.equal(context.__mbgEntryResult, expected, html);
}
console.log('Course name tables: 7 cases passed.');
