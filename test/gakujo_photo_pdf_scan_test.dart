import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:morebettergakujo_flutter/src/gakujo_photo_pdf_scan.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mbg-photo-pdf-test-');
  });

  tearDown(() async {
    for (final entry in await directory.list().toList()) {
      await entry.delete();
    }
    await directory.delete();
  });

  Future<String> writePortrait(String name, {int? orientation}) async {
    final pixels = img.Image(width: 16, height: 32);
    pixels.exif.imageIfd.orientation = orientation;
    final file = File('${directory.path}${Platform.pathSeparator}$name.jpg');
    await file.writeAsBytes(img.encodeJpg(pixels));
    return file.path;
  }

  test(
    'writes pages in the requested order and applies both kinds of rotation',
    () async {
      final portrait = await writePortrait('portrait');
      final jpegRotated = await writePortrait('landscape', orientation: 6);

      final bytes = await buildGakujoPhotoPdf([
        (path: jpegRotated, turns: 0),
        (path: portrait, turns: 0),
        (path: portrait, turns: 1),
      ]);
      expect(bytes.length, lessThanOrEqualTo(5000000));

      final content = latin1.decode(bytes);
      expect(content, startsWith('%PDF-'));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(content), hasLength(3));
      final sizes = [
        for (final box in RegExp(
          r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
        ).allMatches(content))
          double.parse(box.group(1)!) > double.parse(box.group(2)!),
      ];
      expect(sizes, [true, false, true]);
    },
  );

  test('rejects an invalid photograph without creating a PDF', () async {
    final file = File('${directory.path}${Platform.pathSeparator}invalid.jpg');
    await file.writeAsString('not an image');
    await expectLater(
      buildGakujoPhotoPdf([(path: file.path, turns: 0)]),
      throwsFormatException,
    );
  });

  test('does not read sources when the page count is out of range', () async {
    await expectLater(buildGakujoPhotoPdf([]), throwsFormatException);
    await expectLater(
      buildGakujoPhotoPdf(List.filled(21, (path: 'not needed', turns: 0))),
      throwsFormatException,
    );
  });
}
