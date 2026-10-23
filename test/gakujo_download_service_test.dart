import 'package:morebettergakujo_flutter/src/gakujo_download_service.dart';
import 'package:test/test.dart';

void main() {
  test('download results default to a new save', () {
    const result =
        GakujoDownloadResult(fileName: 'x.pdf', courseName: 'course');
    expect(result.alreadySaved, isFalse);
  });

  test('fromMap reads alreadySaved and the existing file location', () {
    final result = GakujoDownloadResult.fromMap({
      'fileName': 'x (1).pdf',
      'courseName': 'course',
      'location': 'content://downloads/existing',
      'alreadySaved': true,
    });

    expect(result.alreadySaved, isTrue);
    expect(result.fileName, 'x (1).pdf');
    expect(result.courseName, 'course');
    expect(result.location, 'content://downloads/existing');
  });

  test('fromMap defaults missing or non-true alreadySaved to false', () {
    for (final raw in <Map<String, dynamic>>[
      {'fileName': 'x.pdf'},
      {'fileName': 'x.pdf', 'alreadySaved': false},
      {'fileName': 'x.pdf', 'alreadySaved': null},
      {'fileName': 'x.pdf', 'alreadySaved': 'true'},
    ]) {
      expect(GakujoDownloadResult.fromMap(raw).alreadySaved, isFalse);
    }
  });
}
