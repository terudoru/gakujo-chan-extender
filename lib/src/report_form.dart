import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// 匿名送信を確認済みの共通受付。停止時は null（report_form/README.md）。
const _reportEndpointUrl =
    'https://script.google.com/macros/s/AKfycbz0NObSZdcrMBX2TGZYsrM0NPPtcNm35nzzMLeiWsJnnGr1LoyHjlSyIfA1RxWJw6-Y/exec';

String? get reportEndpointUrl => _reportEndpointUrl;

enum ReportType {
  bug,
  request,
  improvement,
  other;

  String get label => switch (this) {
    bug => 'バグ報告',
    request => '機能追加の要望',
    improvement => '既存機能の改善要望',
    other => 'その他',
  };

  String get contentLabel => switch (this) {
    bug => '起きたこと',
    request => '実現したい機能',
    improvement => '今困っている点と、どう変わると良いか',
    other => '内容',
  };

  String? get contentHint => switch (this) {
    bug => '何をしたら何が起きたか',
    request => '何に困っていて、何ができると嬉しいか',
    improvement => '使っている機能と、困っている点・変えてほしい点',
    other => '伝えたい内容',
  };
}

String createReportSubmissionKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String cleanReportText(String text) =>
    text.replaceAll(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'), '').trim();

class ReportSubmission {
  const ReportSubmission({
    required this.submissionKey,
    required this.type,
    required this.title,
    required this.content,
    required this.steps,
    required this.expected,
    required this.version,
    required this.platform,
    required this.diagnostic,
    required this.diagnosticOmitted,
  });

  final String submissionKey,
      title,
      content,
      steps,
      expected,
      version,
      platform;
  final ReportType type;
  final String? diagnostic;
  final bool diagnosticOmitted;

  Map<String, Object?> toJson() => {
    'v': 1,
    'client': 'app',
    'submissionKey': submissionKey,
    'type': type.name,
    'title': cleanReportText(title),
    'content': cleanReportText(content),
    'steps': type == ReportType.bug ? cleanReportText(steps) : '',
    'expected': type == ReportType.bug ? cleanReportText(expected) : '',
    'version': cleanReportText(version),
    'platform': platform,
    'consent': true,
    'diagnostic': type == ReportType.bug && !diagnosticOmitted
        ? diagnostic
        : null,
    'diagnosticOmitted': type == ReportType.bug && diagnosticOmitted,
  };
}

class ReportResult {
  const ReportResult.success(this.receipt)
    : code = null,
      fields = const {},
      retryAfterSeconds = null;
  const ReportResult.failure(
    this.code, {
    this.fields = const {},
    this.retryAfterSeconds,
  }) : receipt = null;

  final String? receipt, code;
  final Map<String, String> fields;
  final int? retryAfterSeconds;
  bool get isSuccess => receipt != null;

  String get message => messageFor();

  String messageFor({bool includesDiagnostics = false}) => switch (code) {
    'network' => '送信できたか確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。',
    'conflict' => '内容が変わったため、もう一度送ってください。',
    'rate_limited' =>
      '報告が集中しています。${max(1, ((retryAfterSeconds ?? 60) / 60).ceil())}分ほど待ってから、もう一度送ってください。',
    'busy' || 'unavailable' => '現在、報告を受け付けられません。しばらく待ってから、もう一度送ってください。',
    'full' => '保存できる件数の上限に達しています。時間をおいて試すか、GitHub から報告してください。',
    'invalid' => '入力内容を確認してください。各項目の下に理由を表示しています。',
    'too_large' =>
      includesDiagnostics
          ? '送る内容が大きすぎます。文章を短くするか、「診断情報を付けずに送る」にチェックを入れて、もう一度送ってください。'
          : '送る内容が大きすぎます。文章を短くして、もう一度送ってください。',
    'not_public' => '現在アプリからは送信できません。アプリを更新するか、ブラウザーの報告ページか GitHub からお試しください。',
    _ => '受付結果を確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。',
  };
}

class ReportClient {
  const ReportClient({
    required this.endpoint,
    this.httpClientFactory,
    this.requestTimeout = const Duration(seconds: 30),
  });

  final Uri endpoint;
  final HttpClient Function()? httpClientFactory;
  final Duration requestTimeout;

  Future<ReportResult> submit(ReportSubmission submission) async {
    if (endpoint.scheme != 'https' || endpoint.userInfo.isNotEmpty) {
      return const ReportResult.failure('not_public');
    }
    final payload = submission.toJson();
    final diagnostic = payload['diagnostic'];
    if (submission.type == ReportType.bug &&
        !submission.diagnosticOmitted &&
        (diagnostic is! String || diagnostic.length > 20000)) {
      return const ReportResult.failure(
        'invalid',
        fields: {'diagnostic': '診断情報を確認するか、付けずに送ることを選んでください。'},
      );
    }
    final body = utf8.encode(jsonEncode(payload));
    if (body.length > 65536) {
      return const ReportResult.failure('too_large');
    }
    HttpClient? client;
    try {
      client = httpClientFactory?.call() ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      return await _send(client, body).timeout(requestTimeout);
    } on FormatException {
      return const ReportResult.failure('unexpected');
    } on Object {
      // Do not log bodies, diagnostics, or redirect URLs.
      return const ReportResult.failure('network');
    } finally {
      client?.close(force: true);
    }
  }

  Future<ReportResult> _send(HttpClient client, List<int> body) async {
    var uri = endpoint;
    for (var hops = 0; ; hops++) {
      final request = hops == 0
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      request.followRedirects = false;
      if (hops == 0) {
        request.headers.contentType = ContentType.json;
        request.add(body);
      }
      final response = await request.close();
      if (response.statusCode == 302 || response.statusCode == 303) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final next = location == null ? null : Uri.tryParse(location);
        if (next == null ||
            next.scheme != 'https' ||
            next.host != 'script.googleusercontent.com' ||
            next.userInfo.isNotEmpty ||
            (next.hasPort && next.port != 443)) {
          return const ReportResult.failure('not_public');
        }
        if (hops >= 2) return const ReportResult.failure('unexpected');
        await response.drain<void>();
        uri = next;
        continue;
      }
      if (response.statusCode != 200) {
        return const ReportResult.failure('unexpected');
      }
      final decoded = jsonDecode(await utf8.decodeStream(response));
      if (decoded is! Map<String, dynamic>) {
        return const ReportResult.failure('unexpected');
      }
      if (decoded['ok'] == true) {
        final receipt = decoded['receipt'];
        return receipt is String &&
                receipt.length == 12 &&
                RegExp(r'^R-[A-Z2-9]{10}$').hasMatch(receipt)
            ? ReportResult.success(receipt)
            : const ReportResult.failure('unexpected');
      }
      if (decoded['ok'] != false) {
        return const ReportResult.failure('unexpected');
      }
      final fields = decoded['fields'];
      return ReportResult.failure(
        decoded['code'] is String ? decoded['code'] as String : 'unexpected',
        fields: fields is Map
            ? {
                for (final entry in fields.entries)
                  if (entry.key is String && entry.value is String)
                    entry.key as String: entry.value as String,
              }
            : const {},
        retryAfterSeconds: decoded['retryAfterSeconds'] is int
            ? decoded['retryAfterSeconds'] as int
            : null,
      );
    }
  }
}
