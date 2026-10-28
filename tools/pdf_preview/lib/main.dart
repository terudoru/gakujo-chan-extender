import 'dart:async';
import 'dart:math' as math;
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:synchronized/synchronized.dart';

import 'outline_view.dart';
import 'search_view.dart';
import 'selection_menu.dart';
import 'thumbnails_view.dart';

void main(List<String> args) {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(fontFamily: 'MBGPreviewUI');
    return MaterialApp(
      title: 'PDFプレビュー',
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamilyFallback: const ['Unifont']),
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  final documentRef = ValueNotifier<PdfDocumentRef?>(null);
  final controller = PdfViewerController();
  final showLeftPane = ValueNotifier<bool>(false);
  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);
  final textSearcher = ValueNotifier<PdfTextSearcher?>(null);
  final _fontManager = SerialPdfFontManager();
  VoidCallback? _releaseDocument;
  Future<String?>? _pendingPassword;
  String? _lastPassword;

  late final JSFunction _previewListener;

  void _update() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<String?> _requestPassword() {
    // pdfrx reloads a successfully opened document when fallback fonts arrive.
    // Reuse its password only after the first load succeeded; wrong passwords
    // must still prompt again. The value remains in memory for this preview.
    if (documentRef.value?.resolveListenable().document != null &&
        _lastPassword != null) {
      return Future.value(_lastPassword);
    }
    return _pendingPassword ??= _showPasswordDialog().whenComplete(() {
      _pendingPassword = null;
    });
  }

  Future<String?> _showPasswordDialog() async {
    if (!mounted) return null;
    web.window.parent?.postMessage(
      'mbg-preview-password-requested'.toJS,
      '*'.toJS,
    );
    try {
      final password = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PasswordDialog(),
      );
      _lastPassword = password;
      return password;
    } finally {
      web.window.parent?.postMessage(
        'mbg-preview-password-finished'.toJS,
        '*'.toJS,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previewListener = ((web.Event event) {
      final message = event as web.MessageEvent;
      if (!identical(message.source, web.window.parent)) return;
      final data = message.data;
      if (data == null || !data.isA<JSArrayBuffer>()) return;
      final bytes = (data as JSArrayBuffer).toDart.asUint8List();
      if (bytes.isEmpty || bytes.lengthInBytes > 64 * 1024 * 1024) return;
      _lastPassword = null;
      final ref = PdfDocumentRefData(
        bytes,
        sourceName: 'preview.pdf',
        passwordProvider: _requestPassword,
        useProgressiveLoading: true,
      );
      _releaseDocument?.call();
      // Keep one shared load alive while viewport/keyboard changes rebuild the
      // viewer. Otherwise an in-flight password prompt can be orphaned.
      _releaseDocument = ref.resolveListenable().addListener(() {});
      documentRef.value = ref;
    }).toJS;
    web.window.addEventListener('message', _previewListener);
    web.window.parent?.postMessage('mbg-preview-ready'.toJS, '*'.toJS);
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _previewListener);
    WidgetsBinding.instance.removeObserver(this);
    textSearcher.value?.dispose();
    textSearcher.dispose();
    showLeftPane.dispose();
    outline.dispose();
    _lastPassword = null;
    _releaseDocument?.call();
    documentRef.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) setState(() {});
  }

  static bool determineWhetherMobileDeviceOrNot() {
    final data = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.single,
    );
    return data.size.shortestSide < 600;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '検索・目次・ページ一覧',
          icon: const Icon(Icons.menu),
          onPressed: () => showLeftPane.value = !showLeftPane.value,
        ),
        title: determineWhetherMobileDeviceOrNot()
            ? null
            : const Text('PDFプレビュー'),
        actions: [
          IconButton(
            tooltip: 'ページの並びを変更',
            onPressed: _changeLayoutType,
            icon: const Icon(Icons.view_agenda),
          ),
          IconButton(
            tooltip: '縮小',
            onPressed: () {
              if (controller.isReady) unawaited(controller.zoomDown());
            },
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: '拡大',
            onPressed: () {
              if (controller.isReady) unawaited(controller.zoomUp());
            },
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: '最初のページ',
            onPressed: () {
              if (controller.isReady) {
                unawaited(controller.goToPage(pageNumber: 1));
              }
            },
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: '最後のページ',
            onPressed: () {
              if (controller.isReady) {
                unawaited(
                  controller.goToPage(pageNumber: controller.pageCount),
                );
              }
            },
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
      body: Row(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: ValueListenableBuilder(
              valueListenable: showLeftPane,
              builder: (context, isLeftPaneShown, child) {
                final isMobileDevice = determineWhetherMobileDeviceOrNot();
                return SizedBox(
                  width: isLeftPaneShown
                      ? (isMobileDevice
                            ? MediaQuery.sizeOf(context).width * .8
                            : 300)
                      : 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(1, 0, 4, 0),
                    child: DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          ClipRect(
                            // NOTE: without ClipRect, TabBar shown even if the width is 0
                            child: const TabBar(
                              tabs: [
                                Tab(icon: Icon(Icons.search), text: '検索'),
                                Tab(icon: Icon(Icons.menu_book), text: '目次'),
                                Tab(icon: Icon(Icons.image), text: 'ページ'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                ValueListenableBuilder(
                                  valueListenable: textSearcher,
                                  builder: (context, textSearcher, child) {
                                    if (textSearcher == null) return SizedBox();
                                    return TextSearchView(
                                      textSearcher: textSearcher,
                                    );
                                  },
                                ),
                                ValueListenableBuilder(
                                  valueListenable: outline,
                                  builder: (context, outline, child) =>
                                      OutlineView(
                                        outline: outline,
                                        controller: controller,
                                      ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: documentRef,
                                  builder: (context, documentRef, child) =>
                                      ThumbnailsView(
                                        documentRef: documentRef,
                                        controller: controller,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ValueListenableBuilder(
                  valueListenable: documentRef,
                  builder: (context, docRef, child) {
                    if (docRef == null) {
                      return const Center(
                        child: Text(
                          'PDFを読み込んでいます',
                          style: TextStyle(fontSize: 20),
                        ),
                      );
                    }
                    return PdfViewer(
                      docRef,
                      controller: controller,
                      fontManager: _fontManager,
                      params: PdfViewerParams(
                        layoutPages: _layoutPages[_layoutTypeIndex],
                        maxImageBytesCachedOnMemory:
                            determineWhetherMobileDeviceOrNot()
                            ? 16 * 1024 * 1024
                            : 32 * 1024 * 1024,
                        horizontalCacheExtent: .25,
                        verticalCacheExtent: .25,
                        onePassRenderingSizeThreshold:
                            determineWhetherMobileDeviceOrNot() ? 1400 : 2000,
                        getPageRenderingScale:
                            (context, page, controller, estimatedScale) {
                              final area = page.width * page.height;
                              if (!area.isFinite || area <= 0) {
                                return estimatedScale;
                              }
                              final pixelLimit =
                                  determineWhetherMobileDeviceOrNot()
                                  ? 2500000
                                  : 8000000;
                              return math.min(
                                estimatedScale,
                                math.sqrt(pixelLimit / area),
                              );
                            },
                        scrollHorizontallyByMouseWheel: isHorizontalLayout,
                        pageAnchor: isHorizontalLayout
                            ? PdfPageAnchor.left
                            : PdfPageAnchor.top,
                        pageAnchorEnd: isHorizontalLayout
                            ? PdfPageAnchor.right
                            : PdfPageAnchor.bottom,
                        textSelectionParams: const PdfTextSelectionParams(),
                        buildContextMenu: buildSelectionMenu,
                        keyHandlerParams: PdfViewerKeyHandlerParams(
                          autofocus: true,
                        ),
                        sizeDelegateProvider:
                            PdfViewerSizeDelegateProviderLegacy(
                              useAlternativeFitScaleAsMinScale: false,
                              maxScale: 8,
                            ),
                        // #547: At least, on Flutter Web on Windows, the default scroll physics
                        // seems to have some issues with zooming and we don't use it here.
                        //scrollPhysics: PdfViewerParams.getScrollPhysics(context),
                        viewerOverlayBuilder: (context, size, handleLinkTap) => [
                          //
                          // Example use of PdfOverlayInteractionRegion to handle double-tap for zooming
                          //
                          PdfOverlayInteractionRegion(
                            onDoubleTap: (details) {
                              unawaited(controller.zoomUp(loop: true));
                              return true;
                            },
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                            ),
                          ),
                          // Scroll-thumbs example
                          //
                          // Show vertical scroll thumb on the right; it has page number on it
                          PdfViewerScrollThumb(
                            controller: controller,
                            orientation: ScrollbarOrientation.right,
                            thumbSize: const Size(40, 25),
                            thumbBuilder:
                                (context, thumbSize, pageNumber, controller) =>
                                    Container(
                                      color: Colors.black,
                                      child: isHorizontalLayout
                                          ? null
                                          : Center(
                                              child: Text(
                                                pageNumber.toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                          ),
                          // Just a simple horizontal scroll thumb on the bottom
                          PdfViewerScrollThumb(
                            controller: controller,
                            orientation: ScrollbarOrientation.bottom,
                            thumbSize: const Size(40, 25),
                            thumbBuilder:
                                (context, thumbSize, pageNumber, controller) =>
                                    Container(
                                      color: Colors.black,
                                      child: !isHorizontalLayout
                                          ? null
                                          : Center(
                                              child: Text(
                                                pageNumber.toString(),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                          ),
                        ],
                        //
                        // Loading progress indicator example
                        //
                        loadingBannerBuilder:
                            (context, bytesDownloaded, totalBytes) => Center(
                              child: CircularProgressIndicator(
                                value: totalBytes != null
                                    ? bytesDownloaded / totalBytes
                                    : null,
                                backgroundColor: Colors.grey,
                              ),
                            ),
                        //
                        // Link handling example
                        //
                        linkHandlerParams: PdfLinkHandlerParams(
                          onLinkTap: (link) {
                            if (link.dest != null) {
                              unawaited(controller.goToDest(link.dest));
                            }
                          },
                        ),
                        pagePaintCallbacks: [
                          if (textSearcher.value != null)
                            textSearcher.value!.pageTextMatchPaintCallback,
                        ],
                        onDocumentChanged: (document) async {
                          if (document == null) {
                            textSearcher.value?.dispose();
                            textSearcher.value = null;
                            outline.value = null;
                          }
                        },
                        errorBannerBuilder: (context, error, stack, ref) {
                          unawaited(
                            Future.microtask(
                              () => web.window.parent?.postMessage(
                                'mbg-preview-failed'.toJS,
                                '*'.toJS,
                              ),
                            ),
                          );
                          return const Center(child: Text('PDFを開けませんでした。'));
                        },
                        onViewerReady: (document, controller) async {
                          web.window.parent?.postMessage(
                            'mbg-preview-loaded'.toJS,
                            '*'.toJS,
                          );
                          textSearcher.value?.dispose();
                          textSearcher.value = PdfTextSearcher(controller)
                            ..addListener(_update);
                          try {
                            final entries = await document.loadOutline();
                            if (mounted) outline.value = entries;
                          } catch (_) {
                            // A document reload may invalidate a pending outline request.
                          }
                          if (!mounted) return;
                          controller.requestFocus();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _layoutTypeIndex = 0;

  /// Change the layout logic; see [_layoutPages] for the logics
  void _changeLayoutType() {
    setState(() {
      _layoutTypeIndex = (_layoutTypeIndex + 1) % _layoutPages.length;
    });
  }

  bool get isHorizontalLayout => _layoutTypeIndex == 1;

  /// Page reading order; true to L-to-R that is commonly used by books like manga or such
  var isRightToLeftReadingOrder = false;

  /// Use the first page as cover page
  var needCoverPage = true;

  late final List<PdfPageLayoutFunction?> _layoutPages = [
    // The default layout
    null,
    // Horizontal layout
    (pages, params) {
      final height =
          pages.fold(0.0, (prev, page) => math.max(prev, page.height)) +
          params.margin * 2;
      final pageLayouts = <Rect>[];
      double x = params.margin;
      for (var page in pages) {
        pageLayouts.add(
          Rect.fromLTWH(
            x,
            (height - page.height) / 2, // center vertically
            page.width,
            page.height,
          ),
        );
        x += page.width + params.margin;
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size(x, height),
      );
    },
    // Facing pages layout
    (pages, params) {
      final width = pages.fold(0.0, (prev, page) => math.max(prev, page.width));

      final pageLayouts = <Rect>[];
      final offset = needCoverPage ? 1 : 0;
      double y = params.margin;
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        final pos = i + offset;
        final isLeft = isRightToLeftReadingOrder
            ? (pos & 1) == 1
            : (pos & 1) == 0;

        final otherSide = (pos ^ 1) - offset;
        final h = 0 <= otherSide && otherSide < pages.length
            ? math.max(page.height, pages[otherSide].height)
            : page.height;

        pageLayouts.add(
          Rect.fromLTWH(
            isLeft
                ? width + params.margin - page.width
                : params.margin * 2 + width,
            y + (h - page.height) / 2,
            page.width,
            page.height,
          ),
        );
        if (pos & 1 == 1 || i + 1 == pages.length) {
          y += h + params.margin;
        }
      }
      return PdfPageLayout(
        pageLayouts: pageLayouts,
        documentSize: Size((params.margin + width) * 2 + params.margin, y),
      );
    },
  ];
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('PDFのパスワード'),
    content: TextField(
      controller: _password,
      autofocus: true,
      obscureText: true,
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('キャンセル'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_password.text),
        child: const Text('開く'),
      ),
    ],
  );
}

class LocalPdfFontResolver implements PdfFontResolver {
  final Map<String, Future<Uint8List>> _fonts = {};

  @override
  Future<PdfFontResolution?> resolve(
    PdfFontQuery query,
    PdfFontResolveContext context,
  ) async {
    final isCjk = {
      PdfFontCharset.shiftJis,
      PdfFontCharset.hangul,
      PdfFontCharset.gb2312,
      PdfFontCharset.chineseBig5,
    }.contains(query.charset);
    final path = isCjk
        ? 'assets/NotoSansCJK-Regular.ttc'
        : 'assets/unifont.otf';
    return PdfFontResolution(
      targetFace: isCjk ? '__mbg_cjk' : '__mbg_default',
      resolvedFace: isCjk ? 'Noto Sans CJK JP' : 'Unifont',
      loadData: ({onProgress}) async => Uint8List.fromList(
        await _fonts.putIfAbsent(path, () async {
          final data = await rootBundle.load(path);
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        }),
      ),
    );
  }
}

/// Concurrent page loads can request the same large fallback at once.
/// Serialize registrations so the upstream manager can deduplicate them.
class SerialPdfFontManager extends PdfFontManager {
  SerialPdfFontManager() : super(resolvers: [LocalPdfFontResolver()]);

  final _lock = Lock();

  @override
  Future<PdfFontLoadResult> loadMissingFonts(
    Iterable<PdfFontQuery> queries, {
    PdfFontResolveContext context = const PdfFontResolveContext(),
    bool reloadFonts = true,
    PdfFontLoadProgressCallback? onProgress,
  }) => _lock.synchronized(
    () => super.loadMissingFonts(
      queries,
      context: context,
      reloadFonts: reloadFonts,
      onProgress: onProgress,
    ),
  );
}
