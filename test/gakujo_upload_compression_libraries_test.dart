import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_libraries.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles qpdf worker and WebAssembly for PDF compression', () async {
    final script = await GakujoUploadCompressionLibraries.scriptFor('pdf');

    expect(script, isNotNull);
    expect(script, contains('__MBG_QPDF_WORKER_URL'));
    expect(script, contains('__MBG_QPDF_MODULE_URL'));
    expect(script, contains('__MBG_QPDF_WASM_URL'));
    expect(script, contains('URL.createObjectURL'));
    expect(
      script!.trimRight(),
      endsWith("window.__MBG_UPLOAD_COMPRESSION_LIBRARY_LOADED(\"pdf\"); }"),
    );
  });

  test('bundles pdf.js and its worker for preview', () async {
    final script = await GakujoUploadCompressionLibraries.scriptFor('preview');
    expect(script, contains('__MBG_PDF_WORKER_URL'));
    expect(script, contains('pdfjsLib'));
    expect(script, contains('pdfjsViewer'));
    expect(script, contains('__MBG_PDF_CMAPS'));
    expect(script, contains('__MBG_PDF_STANDARD_FONTS'));
    expect(script, contains('UniJIS-UCS2-H'));
    expect(script, contains('__MBG_UPLOAD_PREVIEW_LIBRARY_LOADED'));
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
