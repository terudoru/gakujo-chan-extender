import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../report_form.dart';

String reportPlatform(TargetPlatform platform) => switch (platform) {
  TargetPlatform.windows => 'windows',
  TargetPlatform.macOS => 'macos',
  TargetPlatform.linux => 'linux',
  TargetPlatform.android => 'android',
  TargetPlatform.iOS => 'ios',
  TargetPlatform.fuchsia => 'other',
};

class ReportDialog extends StatefulWidget {
  const ReportDialog({
    super.key,
    required this.client,
    required this.collectDiagnostics,
    required this.onOpenUrl,
    this.loadVersion,
  });

  final ReportClient client;
  final Future<String> Function() collectDiagnostics;
  final Future<void> Function(Uri) onOpenUrl;
  final Future<String> Function()? loadVersion;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _steps = TextEditingController();
  final _expected = TextEditingController();
  final _messageFocus = FocusNode();
  var _submissionKey = createReportSubmissionKey();
  var _type = ReportType.bug;
  var _consent = false;
  var _omitDiagnostics = false;
  var _collecting = false;
  var _loadingVersion = true;
  var _sending = false;
  var _diagnosticGeneration = 0;
  var _formRevision = 0;
  var _hasAttempted = false;
  var _editedSinceAttempt = false;
  String _version = '';
  String? _diagnostic, _diagnosticError, _consentError, _message, _receipt;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadVersion());
  }

  Future<void> _loadVersion() async {
    var version = '';
    try {
      version =
          await (widget.loadVersion?.call() ??
              PackageInfo.fromPlatform().then((info) => info.version));
    } on Object {
      // Version is optional; reporting remains available.
    }
    if (mounted) {
      setState(() {
        _version = version;
        _loadingVersion = false;
      });
    }
  }

  Future<void> _collectDiagnostics() async {
    if (_type != ReportType.bug) return;
    final generation = ++_diagnosticGeneration;
    setState(() {
      if (_hasAttempted) _editedSinceAttempt = true;
      _collecting = true;
      _diagnostic = null;
      _diagnosticError = null;
    });
    String? diagnostic, error;
    try {
      final collected = await widget.collectDiagnostics();
      if (collected.length > 20000) {
        error = '診断情報が20,000文字を超えているため、付けて送れません。';
      } else {
        diagnostic = collected;
      }
    } on Object {
      error = '診断情報を集められませんでした。';
    }
    if (!mounted || generation != _diagnosticGeneration) return;
    setState(() {
      _collecting = false;
      _diagnostic = diagnostic;
      _diagnosticError = error;
    });
  }

  void _markEdited() {
    _formRevision++;
    if (_hasAttempted) _editedSinceAttempt = true;
  }

  void _changeType(ReportType type) {
    if (type == _type) return;
    setState(() {
      _markEdited();
      _type = type;
      _fieldErrors = {};
      _diagnosticGeneration++;
      _diagnostic = null;
      _diagnosticError = null;
      _collecting = false;
    });
  }

  void _focusMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _messageFocus.requestFocus();
    });
  }

  String get _diagnosticBlockMessage {
    if (_collecting) {
      return '診断情報を集めています。終わるまで待つか、「診断情報を付けずに送る」にチェックを入れてください。';
    }
    if (_diagnosticError != null) {
      return '診断情報を付けて送れません。「もう一度集める」を押すか、「診断情報を付けずに送る」にチェックを入れてください。';
    }
    return '診断情報はまだ集めていません。「送る内容を見る」を開くか、「診断情報を付けずに送る」にチェックを入れてください。';
  }

  String _failureMessage(ReportResult result) {
    final visibleFields = {
      'type',
      'title',
      'content',
      'consent',
      if (_type == ReportType.bug) ...[
        'steps',
        'expected',
        'diagnostic',
        'diagnosticOmitted',
      ],
    };
    const labels = {
      'version': 'アプリのバージョン',
      'platform': 'OS',
      'steps': '問題が起きるまでの手順',
      'expected': '本来どうなってほしかったか',
      'diagnostic': '診断情報',
      'diagnosticOmitted': '診断情報の省略',
    };
    return [
      result.messageFor(
        includesDiagnostics:
            _type == ReportType.bug && !_omitDiagnostics && _diagnostic != null,
      ),
      for (final entry in result.fields.entries)
        if (!visibleFields.contains(entry.key))
          '${labels[entry.key] ?? '送る情報'}：${entry.value}',
    ].join('\n');
  }

  Future<void> _submit() async {
    if (_sending || _loadingVersion) return;
    setState(() {
      _fieldErrors = {};
      _consentError = _consent ? null : '確認してチェックを入れてください。';
      _message = null;
    });
    final valid = _formKey.currentState!.validate();
    if (!valid || !_consent) {
      setState(() => _message = '入力内容と確認欄を見直してください。');
      _focusMessage();
      return;
    }
    if (_type == ReportType.bug &&
        !_omitDiagnostics &&
        !_collecting &&
        _diagnostic == null &&
        _diagnosticError == null) {
      final revision = _formRevision;
      await _collectDiagnostics();
      if (!mounted || _receipt != null || _sending) return;
      if (revision != _formRevision) {
        setState(() => _message = '入力内容が変わりました。確認して、もう一度送ってください。');
        _focusMessage();
        return;
      }
    }
    if (_type == ReportType.bug &&
        !_omitDiagnostics &&
        (_collecting || _diagnostic == null)) {
      setState(() => _message = _diagnosticBlockMessage);
      _focusMessage();
      return;
    }
    if (_hasAttempted && _editedSinceAttempt) {
      _submissionKey = createReportSubmissionKey();
    }
    _hasAttempted = true;
    _editedSinceAttempt = false;
    setState(() => _sending = true);
    ReportResult result;
    try {
      result = await widget.client.submit(
        ReportSubmission(
          submissionKey: _submissionKey,
          type: _type,
          title: _title.text,
          content: _content.text,
          steps: _steps.text,
          expected: _expected.text,
          version: _version,
          platform: reportPlatform(defaultTargetPlatform),
          diagnostic: _type == ReportType.bug ? _diagnostic : null,
          diagnosticOmitted: _type == ReportType.bug && _omitDiagnostics,
        ),
      );
    } on Object {
      result = const ReportResult.failure('network');
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _receipt = result.receipt;
      _message = result.isSuccess ? null : _failureMessage(result);
      _fieldErrors = Map.of(result.fields);
      if (result.code == 'conflict') _editedSinceAttempt = true;
    });
    if (!result.isSuccess) {
      _formKey.currentState!.validate();
      _focusMessage();
    }
  }

  void _anotherReport() {
    _title.clear();
    _content.clear();
    _steps.clear();
    _expected.clear();
    setState(() {
      _submissionKey = createReportSubmissionKey();
      _type = ReportType.bug;
      _consent = false;
      _omitDiagnostics = false;
      _consentError = null;
      _message = null;
      _receipt = null;
      _fieldErrors = {};
      _hasAttempted = false;
      _editedSinceAttempt = false;
      _diagnosticGeneration++;
      _diagnostic = null;
      _diagnosticError = null;
      _collecting = false;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _steps.dispose();
    _expected.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  Widget _field(
    String name,
    String label,
    TextEditingController controller,
    int limit, {
    bool required = false,
    int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      key: ValueKey('report-$name'),
      controller: controller,
      enabled: !_sending,
      autofocus: name == 'title',
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 3,
      maxLength: limit,
      // Validate UTF-16 units, matching the intake contract, including emoji.
      maxLengthEnforcement: .none,
      buildCounter: (
        context, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => Text('${cleanReportText(controller.text).length}/$limit'),
      decoration: InputDecoration(
        labelText: required ? '$label（必須）' : label,
        hintText: hint,
        alignLabelWithHint: true,
      ),
      validator: (value) {
        if (_fieldErrors[name] case final error?) return error;
        final text = cleanReportText(value ?? '');
        if (required && text.isEmpty) return '$labelを入力してください。';
        if (text.length > limit) return '$limit文字以内で入力してください。';
        return null;
      },
      onChanged: (_) {
        _markEdited();
        if (_fieldErrors.remove(name) != null) {
          _formKey.currentState?.validate();
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: Text(_receipt == null ? 'アプリから報告する' : '報告を受け付けました'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: _receipt != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText('受付番号：$_receipt'),
                    const SizedBox(height: 12),
                    const Text('これは GitHub の Issue 番号ではありません。開発者が内容を確認します。'),
                    const SizedBox(height: 8),
                    const Text('受付番号は送信の控えです。個別の返信はありません。すべての報告が公開されるとは限りません。'),
                    TextButton(
                      onPressed: () => unawaited(
                        widget.onOpenUrl(
                          Uri.parse(
                            'https://github.com/terudoru/gakujo-chan-extender/issues',
                          ),
                        ),
                      ),
                      child: const Text('GitHub の Issue 一覧を見る'),
                    ),
                  ],
                )
              : AbsorbPointer(
                  absorbing: _sending,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<ReportType>(
                          key: const ValueKey('report-type'),
                          initialValue: _type,
                          decoration: InputDecoration(
                            labelText: '報告の種類（必須）',
                            errorText: _fieldErrors['type'],
                          ),
                          items: [
                            for (final type in ReportType.values)
                              DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                          ],
                          onChanged: _sending
                              ? null
                              : (type) => _changeType(type!),
                        ),
                        const SizedBox(height: 8),
                        const Text('どの種類も個別の返信はありません。手順と診断情報はバグ報告だけに含めます。'),
                        const SizedBox(height: 8),
                        Text(switch (_type) {
                          ReportType.bug => '動かない、表示がおかしいなど、起きた問題を教えてください。',
                          ReportType.request => '追加してほしい機能を教えてください。',
                          ReportType.improvement => '今ある機能をどう変えたいか教えてください。',
                          ReportType.other => '上の種類に当てはまらない内容を送れます。',
                        }),
                        _field('title', '件名', _title, 80, required: true),
                        _field(
                          'content',
                          _type.contentLabel,
                          _content,
                          4000,
                          required: true,
                          lines: 4,
                          hint: _type.contentHint,
                        ),
                        if (_type == ReportType.bug) ...[
                          _field(
                            'steps',
                            '問題が起きるまでの手順',
                            _steps,
                            2000,
                            lines: 2,
                          ),
                          _field(
                            'expected',
                            '本来どうなってほしかったか',
                            _expected,
                            1000,
                            lines: 2,
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (_type == ReportType.bug)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'アプリの設定の状態と、保存している履歴・お気に入りなどの件数です。名前や内容は含みません。送る前に「送る内容を見る」で確認できます。',
                                  ),
                                  const Text('診断情報は開発者だけが見て、公開しません。'),
                                  if (_collecting) const Text('診断情報を集めています…'),
                                  if (!_collecting &&
                                      _diagnostic == null &&
                                      _diagnosticError == null)
                                    const Text(
                                      '診断情報はまだ集めていません。「送る内容を見る」を開くか、「送信」を押すと集めます。',
                                    ),
                                  if (_diagnosticError case final error?)
                                    Text(
                                      error,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  if (_diagnosticError != null ||
                                      _diagnostic != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: _collecting || _sending
                                            ? null
                                            : () => unawaited(
                                                _collectDiagnostics(),
                                              ),
                                        child: const Text('もう一度集める'),
                                      ),
                                    ),
                                  ExpansionTile(
                                    title: const Text('送る内容を見る'),
                                    tilePadding: EdgeInsets.zero,
                                    onExpansionChanged: (expanded) {
                                      if (expanded &&
                                          !_omitDiagnostics &&
                                          !_collecting &&
                                          _diagnostic == null &&
                                          _diagnosticError == null) {
                                        unawaited(_collectDiagnostics());
                                      }
                                    },
                                    children: [
                                      if (_omitDiagnostics)
                                        const Text('診断情報は付けずに送ります。')
                                      else if (_diagnostic
                                          case final diagnostic?)
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: SelectableText(diagnostic),
                                        ),
                                    ],
                                  ),
                                  CheckboxListTile(
                                    key: const ValueKey('report-omit'),
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: const Text('診断情報を付けずに送る'),
                                    value: _omitDiagnostics,
                                    onChanged: _sending
                                        ? null
                                        : (value) => setState(() {
                                            _markEdited();
                                            _omitDiagnostics = value!;
                                          }),
                                  ),
                                  if (_fieldErrors['diagnostic']
                                      case final error?)
                                    Text(
                                      error,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  if (_fieldErrors['diagnosticOmitted']
                                      case final error?)
                                    Text(
                                      error,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          key: const ValueKey('report-consent'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            '氏名・学籍番号・パスワード・成績・学情の画面の内容など、個人情報を書いていないことを確認しました。件名・内容・再現手順・期待した動き・アプリのバージョン・OS が GitHub で公開される場合があることに同意します。（必須）',
                          ),
                          value: _consent,
                          onChanged: _sending
                              ? null
                              : (value) => setState(() {
                                  _markEdited();
                                  _consent = value!;
                                  _consentError = null;
                                }),
                        ),
                        if (_consentError case final error?)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (_fieldErrors['consent'] case final error?)
                          Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
      actions: [
        if (_receipt == null)
          SizedBox(
            width: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _type == ReportType.bug && !_omitDiagnostics
                      ? '送信すると、入力した内容・アプリのバージョンとOS・診断情報を開発者に送ります。'
                      : '送信すると、入力した内容・アプリのバージョンとOSを開発者に送ります。',
                ),
                const Text('GitHub アカウントは不要です。'),
                if (_message case final message?)
                  Focus(
                    focusNode: _messageFocus,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '$message\n入力内容は残っています。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        if (_receipt != null)
          FilledButton(onPressed: _anotherReport, child: const Text('もう1件送る'))
        else
          FilledButton(
            onPressed: _sending || _loadingVersion
                ? null
                : () => unawaited(_submit()),
            child: Text(_sending ? '送信中…' : '送信'),
          ),
      ],
    ),
  );
}
