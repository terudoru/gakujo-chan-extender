import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mbg-upload-test-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<File> cachedFile(String name) async {
    return File('${temporary.path}${Platform.pathSeparator}$name')
        .writeAsBytes([80, 75, 3, 4, 42]);
  }

  test('copies a MIME-renamed cache file under the original display name',
      () async {
    final cached = await cachedFile('report.zip');
    final selected = _NamedXFile(cached.path, 'レポート.docx');
    final uri = await androidUploadFileUri(
      selected,
      temporaryDirectory: () async => temporary,
    );
    final copy = File.fromUri(Uri.parse(uri));

    expect(copy.uri.pathSegments.last, 'レポート.docx');
    expect(copy.parent.path, isNot(cached.parent.path));
    expect(await copy.readAsBytes(), await cached.readAsBytes());
    expect(await cached.exists(), isTrue);

    final second = await androidUploadFileUri(
      selected,
      temporaryDirectory: () async => temporary,
    );
    expect(second, isNot(uri));
    expect(await copy.readAsBytes(), await cached.readAsBytes());
  });

  test('keeps the cached URI when its name already matches', () async {
    final cached = await cachedFile('report.docx');
    final uri = await androidUploadFileUri(
      XFile(cached.path),
      temporaryDirectory: () async => throw StateError('copy not needed'),
    );
    expect(uri, cached.uri.toString());
  });

  test('sanitizes separators and control characters without changing extension',
      () async {
    final cached = await cachedFile('report.zip');
    final uri = await androidUploadFileUri(
      _NamedXFile(cached.path, '../資料\\report\u0000.docx'),
      temporaryDirectory: () async => temporary,
    );
    final copy = File.fromUri(Uri.parse(uri));
    expect(copy.uri.pathSegments.last, '.._資料_report_.docx');
    expect(copy.parent.parent.path, temporary.path);
    expect(await copy.readAsBytes(), await cached.readAsBytes());
  });

  test('rejects unusable display names', () async {
    final cached = await cachedFile('report.zip');
    for (final name in ['', '.', '..']) {
      await expectLater(
        androidUploadFileUri(_NamedXFile(cached.path, name)),
        throwsFormatException,
      );
    }
  });

  test('reports camera exceptions and still cancels the chooser', () async {
    final errors = <String>[];
    final result = await pickAndroidUploadFiles(
      const _SelectorParams(isCaptureEnabled: true),
      chooseSource: () async => throw StateError('capture skips source menu'),
      imagePicker: _FakeImagePicker(
        cameraError: PlatformException(
          code: 'no_available_camera',
          message: 'No cameras available',
        ),
      ),
      onError: errors.add,
    );
    expect(result, isEmpty);
    expect(errors, ['No cameras available']);
  });

  test('uses the platform error code when no message is available', () async {
    final errors = <String>[];
    final result = await pickAndroidUploadFiles(
      const _SelectorParams(isCaptureEnabled: true),
      chooseSource: () async => AndroidUploadSource.camera,
      imagePicker: _FakeImagePicker(
        cameraError: PlatformException(code: 'no_available_camera'),
      ),
      onError: errors.add,
    );
    expect(result, isEmpty);
    expect(errors, ['no_available_camera']);
  });

  test('reports an unreadable provider file instead of returning its URI',
      () async {
    final errors = <String>[];
    final result = await pickAndroidUploadFiles(
      const _SelectorParams(isCaptureEnabled: true),
      chooseSource: () async => AndroidUploadSource.camera,
      imagePicker: _FakeImagePicker(
        photo: XFile('${temporary.path}/missing-provider-file.jpg'),
      ),
      onError: errors.add,
    );
    expect(result, isEmpty);
    expect(errors.single, contains('missing-provider-file.jpg'));
  });

  test('cancelling the source menu or camera does not report an error',
      () async {
    final errors = <String>[];
    for (final source in [null, AndroidUploadSource.camera]) {
      final result = await pickAndroidUploadFiles(
        const _SelectorParams(),
        chooseSource: () async => source,
        imagePicker: _FakeImagePicker(),
        onError: errors.add,
      );
      expect(result, isEmpty);
    }
    expect(errors, isEmpty);
  });

  test('reports a missing recovered photo', () async {
    final errors = <String>[];
    final result = await pickAndroidUploadFiles(
      const _SelectorParams(),
      chooseSource: () async => AndroidUploadSource.recoveredPhoto,
      takeRecoveredPhoto: () => '${temporary.path}/missing-recovered.jpg',
      onError: errors.add,
    );
    expect(result, isEmpty);
    expect(errors.single, contains('missing-recovered.jpg'));
  });

  test('surfaces recovery response errors and thrown recovery errors',
      () async {
    for (final throwsError in [false, true]) {
      final errors = <String>[];
      final error = PlatformException(code: 'lost_photo', message: '写真の復元に失敗');
      final path = await recoverAndroidUploadPhoto(
        imagePicker: _FakeImagePicker(
          recovery: LostDataResponse(exception: error),
          recoveryError: throwsError ? error : null,
        ),
        onError: errors.add,
      );
      expect(path, isNull);
      expect(errors, ['写真の復元に失敗']);
    }
  });

  test('returns a readable recovered photo without an error', () async {
    final cached = await cachedFile('photo.jpg');
    final errors = <String>[];
    final path = await recoverAndroidUploadPhoto(
      imagePicker: _FakeImagePicker(
        recovery: LostDataResponse(file: XFile(cached.path)),
      ),
      onError: errors.add,
    );
    expect(path, cached.path);
    expect(errors, isEmpty);
  });
}

// cross_file currently ignores the constructor's name on dart:io. Model a
// provider that supplies a display name independently of its cache path.
class _NamedXFile extends XFile {
  _NamedXFile(super.path, this.name);

  @override
  final String name;
}

class _SelectorParams {
  const _SelectorParams({this.isCaptureEnabled = false});

  final bool isCaptureEnabled;
  List<Object?> get acceptTypes => ['image/*'];
}

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker({
    this.photo,
    this.cameraError,
    this.recovery,
    this.recoveryError,
  });

  final XFile? photo;
  final Object? cameraError;
  final LostDataResponse? recovery;
  final Object? recoveryError;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (cameraError case final error?) {
      throw error;
    }
    return photo;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    if (recoveryError case final error?) {
      throw error;
    }
    return recovery ?? LostDataResponse.empty();
  }
}
