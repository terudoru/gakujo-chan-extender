import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('course name tables read the column under a 科目名 header', () async {
    final result = await Process.run('node', ['test/course_name_tables.mts']);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
