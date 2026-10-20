import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_libraries.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles pdf.js with its worker and pdf-lib for PDFs', () async {
    final script = await GakujoUploadCompressionLibraries.scriptFor('pdf');

    expect(script, isNotNull);
    // The worker must load first so pdf.js runs it on the page thread.
    expect(
      script!.indexOf('WorkerMessageHandler'),
      lessThan(script.indexOf('PDFLib')),
    );
    expect(script, contains('pdfjsLib'));
    expect(
      script.trimRight(),
      endsWith("window.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED(\"pdf\"); }"),
    );
  });

  test('bundles JSZip for Office files', () async {
    final script = await GakujoUploadCompressionLibraries.scriptFor('office');

    expect(script, contains('JSZip'));
  });

  test('ignores unknown requests', () async {
    expect(await GakujoUploadCompressionLibraries.scriptFor('exe'), isNull);
  });

  test('shields libraries from page module loaders', () {
    final script = GakujoUploadCompressionLibraries.buildInjectionScript(
      'office',
      ['window.JSZip = 1;'],
    );

    expect(script, startsWith('(function(define, module, exports) {'));
  });
}
