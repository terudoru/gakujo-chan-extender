import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _maxPages = 20;
const _maxPhotoBytes = 12 * 1024 * 1024;
const _maxPhotoPixels = 24000000;
const _photoSize = 1800;
const _uploadLimit = 5000000;
const _fileName = '撮影した答案.pdf';
const _directoryPrefix = 'mbg-photo-pdf-';
const _unreadablePhoto = '写真を読み込めませんでした。撮り直してください。';
const _oversizePdf = 'PDFを5 MB以内にできませんでした。ページを分けてください。';

typedef GakujoScannedPhoto = ({String path, int turns});

/// Opens a camera session and returns the temporary PDF chosen by the user.
/// The caller can discard it after transferring the bytes to an upload field.
Future<XFile?> showGakujoPhotoPdfScanner(
  BuildContext context, {
  XFile? Function()? takeRecoveredPhoto,
}) {
  unawaited(_pruneExpiredPdfs());
  return showDialog<XFile>(
    context: context,
    builder: (context) =>
        _PhotoPdfScanner(takeRecoveredPhoto: takeRecoveredPhoto),
  );
}

Future<void> discardGakujoPhotoPdf(XFile file) async {
  try {
    final directory = File(file.path).parent.absolute;
    final root = (await getTemporaryDirectory()).absolute;
    if (file.name == _fileName &&
        directory.parent.path == root.path &&
        _isScanDirectory(directory) &&
        await FileSystemEntity.type(directory.path, followLinks: false) ==
            FileSystemEntityType.directory) {
      await _deletePdfDirectory(directory);
    }
  } on Object {
    // The OS may already have evicted the temporary file.
  }
}

bool _isScanDirectory(Directory directory) => directory.uri.pathSegments
    .where((part) => part.isNotEmpty)
    .last
    .startsWith(_directoryPrefix);

Future<void> _pruneExpiredPdfs() async {
  try {
    final root = await getTemporaryDirectory();
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entry in root.list(followLinks: false)) {
      if (entry is Directory &&
          _isScanDirectory(entry) &&
          (await entry.stat()).modified.isBefore(cutoff)) {
        await _deletePdfDirectory(entry);
      }
    }
  } on Object {
    // Cleanup is best effort. Its failure must not prevent a new scan.
  }
}

Future<void> _deletePdfDirectory(Directory directory) async {
  await _deleteTemporaryPhoto(
    '${directory.path}${Platform.pathSeparator}$_fileName',
  );
  try {
    await directory.delete();
  } on FileSystemException {
    // Another cleanup can have removed the directory already.
  }
}

Future<void> _deleteTemporaryPhoto(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // The OS may already have evicted the cached photo.
  }
}

@visibleForTesting
Future<Uint8List> buildGakujoPhotoPdf(List<GakujoScannedPhoto> pages) async {
  if (pages.isEmpty || pages.length > _maxPages) {
    throw const FormatException('撮影できるのは1〜20ページです。');
  }

  final document = pw.Document();
  // Leave room for the page dictionaries and cross-reference table.
  final imageBudget = (_uploadLimit - 65536) ~/ pages.length;
  for (final page in pages) {
    final file = await File(page.path).open();
    final Uint8List bytes;
    try {
      bytes = await file.read(_maxPhotoBytes + 1);
    } finally {
      await file.close();
    }
    if (bytes.length > _maxPhotoBytes) {
      throw const FormatException(_unreadablePhoto);
    }
    final decoder = img.findDecoderForData(bytes);
    final dimensions = decoder?.startDecode(bytes);
    if (dimensions == null ||
        dimensions.width * dimensions.height > _maxPhotoPixels) {
      throw const FormatException(_unreadablePhoto);
    }
    final decoded = decoder!.decodeFrame(0);
    if (decoded == null) throw const FormatException(_unreadablePhoto);

    // JPEG decoding applies EXIF orientation. Remove remaining metadata
    // before encoding the page, including camera location.
    decoded.exif = img.ExifData();
    final turns = page.turns % 4;
    final rotated = turns == 0
        ? decoded
        : img.copyRotate(decoded, angle: turns * 90);
    final image = pw.MemoryImage(_encodePage(rotated, imageBudget));
    final paper = rotated.width > rotated.height
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    document.addPage(
      pw.Page(
        pageFormat: paper,
        margin: const pw.EdgeInsets.all(12),
        build: (context) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }

  final bytes = await document.save();
  if (bytes.length > _uploadLimit) {
    throw const FormatException(_oversizePdf);
  }
  return bytes;
}

Uint8List _encodePage(img.Image photo, int byteLimit) {
  final originalSize = math.max(photo.width, photo.height);
  for (final size in [_photoSize, 1440, 1120, 900]) {
    final page = originalSize <= size
        ? photo
        : img.copyResize(
            photo,
            width: photo.width >= photo.height ? size : null,
            height: photo.width < photo.height ? size : null,
            interpolation: img.Interpolation.average,
          );
    for (final quality in [86, 72, 58]) {
      final jpeg = img.encodeJpg(page, quality: quality);
      if (jpeg.length <= byteLimit) return jpeg;
    }
  }
  throw const FormatException(_oversizePdf);
}

class _PhotoPdfScanner extends StatefulWidget {
  const _PhotoPdfScanner({this.takeRecoveredPhoto});

  final XFile? Function()? takeRecoveredPhoto;

  @override
  State<_PhotoPdfScanner> createState() => _PhotoPdfScannerState();
}

class _PhotoPdfScannerState extends State<_PhotoPdfScanner> {
  final _picker = ImagePicker();
  final _pages = <GakujoScannedPhoto>[];
  late bool _canAddRecovered = widget.takeRecoveredPhoto != null;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final page in _pages) {
      unawaited(_deleteTemporaryPhoto(page.path));
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_busy || _pages.length >= _maxPages) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _photoSize.toDouble(),
        maxHeight: _photoSize.toDouble(),
        imageQuality: 92,
        requestFullMetadata: false,
      );
      if (photo == null || photo.path.isEmpty) return;
      if (mounted) {
        setState(() => _pages.add((path: photo.path, turns: 0)));
      } else {
        await _deleteTemporaryPhoto(photo.path);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'カメラを開けませんでした。端末のカメラの許可を確認してください。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addRecoveredPhoto() {
    final photo = widget.takeRecoveredPhoto?.call();
    setState(() {
      _canAddRecovered = false;
      if (photo != null && photo.path.isNotEmpty) {
        _pages.add((path: photo.path, turns: 0));
        _error = null;
      } else {
        _error = '撮影した写真が見つかりませんでした。';
      }
    });
  }

  void _removePhoto(int index) {
    final photo = _pages[index];
    setState(() {
      _pages.removeAt(index);
      _error = null;
    });
    unawaited(_deleteTemporaryPhoto(photo.path));
  }

  Future<void> _createPdf() async {
    if (_busy || _pages.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Directory? directory;
    var transferred = false;
    try {
      final bytes = await compute(buildGakujoPhotoPdf, List.of(_pages));
      if (!mounted) return;
      final root = await getTemporaryDirectory();
      directory = await root.createTemp(_directoryPrefix);
      final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      Navigator.of(context).pop(XFile(file.path, mimeType: 'application/pdf'));
      transferred = true;
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'PDFを作れませんでした。写真を確認してやり直してください。');
      }
    } finally {
      if (!transferred && directory != null) {
        await _deletePdfDirectory(directory);
      }
      if (!transferred && mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = !_busy && _pages.length < _maxPages;
    return PopScope(
      canPop: !_busy,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              tooltip: 'キャンセル',
              icon: const Icon(Icons.close),
            ),
            title: const Text('撮ってPDFにする'),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Expanded(
                  child: _pages.isEmpty
                      ? const Center(child: Text('答案を1ページずつ撮影してください。'))
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: _pages.length,
                          onReorderItem: (oldIndex, newIndex) {
                            if (_busy) return;
                            setState(() {
                              _pages.insert(
                                newIndex,
                                _pages.removeAt(oldIndex),
                              );
                            });
                          },
                          itemBuilder: (context, index) => _buildPage(index),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_canAddRecovered)
                        TextButton(
                          onPressed: canAdd ? _addRecoveredPhoto : null,
                          child: const Text('直前に撮った写真を追加'),
                        ),
                      OutlinedButton.icon(
                        onPressed: canAdd ? _takePhoto : null,
                        icon: const Icon(Icons.photo_camera),
                        label: Text(_pages.isEmpty ? '写真を撮る' : '続けて撮る'),
                      ),
                      FilledButton(
                        onPressed: _busy || _pages.isEmpty ? null : _createPdf,
                        child: Text('PDFを添付（${_pages.length}ページ）'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    final photo = _pages[index];
    return ListTile(
      key: ValueKey(photo.path),
      leading: SizedBox.square(
        dimension: 52,
        child: RotatedBox(
          quarterTurns: photo.turns,
          child: Image.file(
            File(photo.path),
            fit: BoxFit.contain,
            cacheWidth: 144,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image_outlined),
          ),
        ),
      ),
      title: Text('${index + 1}ページ'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '${index + 1}ページを右に回転',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _pages[index] = (
                      path: photo.path,
                      turns: (photo.turns + 1) % 4,
                    );
                  }),
            icon: const Icon(Icons.rotate_right),
          ),
          IconButton(
            tooltip: '${index + 1}ページを削除',
            onPressed: _busy ? null : () => _removePhoto(index),
            icon: const Icon(Icons.delete_outline),
          ),
          if (!_busy)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle),
              ),
            ),
        ],
      ),
    );
  }
}
