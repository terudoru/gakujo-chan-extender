import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart'
    as windows;

import 'course_planner_link.dart';
import 'generated/course_planner_capture.g.dart';
import 'generated/course_planner_delivery.g.dart';
import 'web_view_service.dart';

String _attempt() {
  final random = Random.secure();
  return base64Url.encode(List<int>.generate(18, (_) => random.nextInt(256)));
}

// Android / WebView2 may return a quoted JSON string, whereas WebKit
// returns the JavaScript string itself.
String? _bridgeString(Object? result) {
  if (result is! String || result.length > 2 * 1024 * 1024) return null;
  return result.startsWith('"') ? jsonDecode(result) as String? : result;
}

enum CoursePlannerImportKind {
  grades('成績'),
  registration('履修登録状況'),
  balances('区分別の既修得単位数');

  const CoursePlannerImportKind(this.label);
  final String label;
}

/// Lives only while the student is choosing and reviewing this import.
class CoursePlannerSource {
  CoursePlannerSource(this.controller, this.stillCurrent);
  final GakujoWebViewController controller;
  final bool Function() stillCurrent;
  final String attempt = _attempt();

  Future<Object?> _read([CoursePlannerImportKind? kind]) async {
    if (!stillCurrent()) return null;
    final result = await controller.runJavaScriptReturningResult(
      coursePlannerCaptureJs({
        'attempt': attempt,
        if (kind != null) 'kind': kind.name,
      }),
    );
    if (!stillCurrent()) return null;
    final str = _bridgeString(result);
    if (str == null) return null;
    return jsonDecode(str);
  }

  Future<List<CoursePlannerImportKind>> choices() async {
    final names = await _read();
    if (names is! List) return [];
    return CoursePlannerImportKind.values
        .where((k) => names.contains(k.name))
        .toList();
  }

  Future<Map<String, dynamic>?> capture(CoursePlannerImportKind kind) async {
    final packet = await _read(kind);
    if (packet is! Map<String, dynamic> ||
        packet['v'] != 1 ||
        packet['kind'] != kind.name ||
        !packet.keys.every(const {'v', 'kind', 'tables', 'year'}.contains)) {
      return null;
    }
    final year = packet['year'];
    if (year != null &&
        (year is! String || !RegExp(r'^(19|20)\d\d$').hasMatch(year))) {
      return null;
    }
    final tables = packet['tables'];
    if (tables is! List || tables.isEmpty || tables.length > 50) return null;
    final (headings, columns) = switch (kind) {
      CoursePlannerImportKind.grades => (
        const {'単位修得状況照会'},
        const {
          '開講番号',
          '科目名',
          '単位数',
          '修得単位数',
          '評価',
          '合否',
          '年度',
          '開講所属',
          'クラス',
          '学期',
          '科目区分',
          '重複',
        },
      ),
      CoursePlannerImportKind.registration => (
        const {'履修登録・登録状況照会', '不許可となった科目'},
        const {'開講番号', '科目名', '単位数', '登録状況', '年度'},
      ),
      CoursePlannerImportKind.balances => (
        const {'履修科目確認表'},
        const {'科目区分', '既修得単位数'},
      ),
    };
    for (final table in tables) {
      if (table is! Map ||
          table.length != 2 ||
          !headings.contains(table['heading'])) {
        return null;
      }
      final rows = table['rows'];
      if (rows is! List || rows.length < 2 || rows.first is! List) return null;
      final headers = rows.first as List;
      if (headers.isEmpty ||
          !headers.every(columns.contains) ||
          headers.length != headers.toSet().length) {
        return null;
      }
      for (final row in rows.skip(1)) {
        if (row is! List ||
            row.length != headers.length ||
            !row.every((value) => value is String && value.length <= 140)) {
          return null;
        }
      }
    }
    return packet;
  }
}

class CoursePlannerPage extends StatefulWidget {
  const CoursePlannerPage({
    super.key,
    required this.service,
    required this.url,
    required this.onExternalLink,
    this.source,
    this.kind,
  });
  final GakujoWebViewService service;
  final Uri url;
  final CoursePlannerSource? source;
  final CoursePlannerImportKind? kind;
  final ValueChanged<Uri> onExternalLink;

  @override
  State<CoursePlannerPage> createState() => _CoursePlannerPageState();
}

class _CoursePlannerPageState extends State<CoursePlannerPage> {
  late final GakujoWebViewController _controller;
  final _ticket = _attempt();
  bool _bound = false;
  bool _sent = false;
  bool _busy = false;
  bool _closed = false;
  bool _loaded = false;
  String? _error;
  bool get _active =>
      mounted && !_closed && (ModalRoute.of(context)?.isCurrent ?? false);
  bool get _canDeliver => _active && !_sent && widget.source!.stillCurrent();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final windowsView = widget.service is WindowsGakujoWebViewService
          ? windows.WebviewController()
          : null;
      _controller = windowsView == null
          ? widget.service.createController()
          : WindowsGakujoWebViewController(windowsView);
      await _controller.setJavaScriptModeUnrestricted();
      if (!mounted || _closed) return;
      if (windowsView != null) {
        await windowsView.setPopupWindowPolicy(
          windows.WebviewPopupWindowPolicy.sameWindow,
        );
        await windowsView.setDevToolsEnabled(kDebugMode);
        if (widget.url.origin == Uri.parse(coursePlannerUrl).origin) {
          await windowsView.setNavigationAllowlist(
            hosts: [widget.url.host],
            hostSuffixes: [],
          );
        }
      } else {
        await widget.service.configureController(
          _controller,
          debugAllowed: false,
          downloadInterceptionEnabled: false,
        );
      }
      if (!mounted || _closed) return;
      await _controller.setNavigationDelegate(
        GakujoNavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && isCoursePlannerDocument(uri, widget.url)) {
              return GakujoNavigationDecision.navigate;
            }
            if (request.isMainFrame &&
                _active &&
                uri != null &&
                isCoursePlannerPublicLink(uri)) {
              widget.onExternalLink(uri);
            }
            return GakujoNavigationDecision.prevent;
          },
          onPageFinished: (url) async {
            final uri = Uri.tryParse(url);
            if (!_active ||
                uri == null ||
                !isCoursePlannerDocument(uri, widget.url)) {
              return;
            }
            setState(() {
              _loaded = true;
              _error = null;
            });
            // Make public syllabus / registration links work in single-view hosts
            // which ignore target=_blank. The navigation delegate vets the URL.
            await _controller.runJavaScript('''
            if (document.documentElement.dataset.plannerHost !== 'app') {
              document.documentElement.dataset.plannerHost = 'app';
              window.dispatchEvent(new Event('mbg:planner-host'));
              document.addEventListener('click', event => {
                const link = event.target.closest?.('a[target="_blank"]');
                if (link) link.target = '_self';
              }, true);
            }
          ''');
            if (widget.kind != null) await _deliver();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted && !_closed) {
              setState(() {
                _loaded = false;
                _error = '履修プランナーを読み込めませんでした。';
              });
            }
          },
        ),
      );
      if (mounted && !_closed) await _controller.loadUrl(widget.url.toString());
    } on Object {
      if (mounted && !_closed) setState(() => _error = '履修プランナーを開けませんでした。');
    }
  }

  Future<String?> _step(String phase, [Map<String, dynamic>? packet]) async {
    if (!_canDeliver) return null;
    final result = await _controller.runJavaScriptReturningResult(
      coursePlannerDeliveryJs({
        'phase': phase,
        'origin': widget.url.origin,
        'path': widget.url.path,
        'attempt': _ticket,
        'packet': ?packet,
      }),
    );
    return _bridgeString(result);
  }

  Future<void> _deliver() async {
    if (!_active || _sent || _busy) return;
    _busy = true;
    try {
      if (!_bound) {
        if (await _step('bind') != 'bound') throw const FormatException();
        _bound = true;
      }
      for (int i = 0; i < 24; i++) {
        final result = await _step('probe');
        if (result == 'sent') {
          _sent = true;
          return;
        }
        if (result == 'ready' && _canDeliver) {
          // Read the currently approved portal frame only after the receiver
          // is ready. Do not retain academic data for delayed retries.
          final packet = await widget.source!.capture(widget.kind!);
          if (packet == null || !_canDeliver) throw const FormatException();
          if (await _step('deliver', packet) == 'sent') {
            _sent = true;
            return;
          }
        } else if (result != 'waiting') {
          throw const FormatException();
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (_active) setState(() => _error = '取り込み画面の準備ができていません。');
    } on Object {
      if (_active) {
        setState(() => _error = '取り込み元または表示先を確認できません。学務の照会画面からやり直してください。');
      }
    } finally {
      _busy = false;
      if (_sent && _active && _error != null) setState(() => _error = null);
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('履修プランナー')),
    body: Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: Text(_error!)),
                TextButton(
                  onPressed: () {
                    if (!_loaded) {
                      unawaited(
                        _controller
                            .loadUrl(widget.url.toString())
                            .catchError((Object _) {}),
                      );
                    } else if (widget.kind != null) {
                      unawaited(_deliver());
                    }
                  },
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        Expanded(child: widget.service.buildWidget(_controller)),
      ],
    ),
  );
}
