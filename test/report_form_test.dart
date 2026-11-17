import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/report_form.dart';

const receipt = 'R-ABCDEFGH29';
final endpoint = Uri.parse('https://script.google.com/macros/s/test/exec');
const redirect = 'https://script.googleusercontent.com/macros/echo?test=1';

ReportSubmission submission({
  ReportType type = ReportType.bug,
  String? diagnostic = '{"downloadHistoryCount":2}',
  bool omitted = false,
  String content = '内容',
}) => ReportSubmission(
  submissionKey: '12345678-1234-4123-8123-123456789abc',
  type: type,
  title: ' 件名\u0000 ',
  content: content,
  steps: ' 手順\n次へ ',
  expected: '期待する動作',
  version: '0.71.0',
  platform: 'windows',
  diagnostic: diagnostic,
  diagnosticOmitted: omitted,
);

void main() {
  test('release default is disabled; keys are unique lowercase UUID v4', () {
    expect(reportEndpointUrl, isNull);
    expect(ReportType.values.map((type) => type.name), [
      'bug',
      'request',
      'improvement',
      'other',
    ]);
    final keys = List.generate(100, (_) => createReportSubmissionKey());
    expect(keys.toSet(), hasLength(100));
    for (final key in keys) {
      expect(
        key,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    }
  });

  test(
    'POST JSON contains exactly contract keys and exact diagnostic text',
    () async {
      final http = FakeReportHttp([
        Reply.json({'ok': true, 'receipt': receipt}),
      ]);
      final result = await ReportClient(
        endpoint: endpoint,
        httpClientFactory: () => http,
      ).submit(submission());
      expect(result.receipt, receipt);
      expect(http.connectionTimeout, const Duration(seconds: 10));
      expect(http.closed, isTrue);
      final request = http.requests.single;
      expect(request.method, 'POST');
      expect(request.uri, endpoint);
      expect(request.followRedirects, isFalse);
      expect(request.headers.contentType!.mimeType, 'application/json');
      expect(jsonDecode(utf8.decode(request.body)), {
        'v': 1,
        'client': 'app',
        'submissionKey': '12345678-1234-4123-8123-123456789abc',
        'type': 'bug',
        'title': '件名',
        'content': '内容',
        'steps': '手順\n次へ',
        'expected': '期待する動作',
        'version': '0.71.0',
        'platform': 'windows',
        'consent': true,
        'diagnostic': '{"downloadHistoryCount":2}',
        'diagnosticOmitted': false,
      });
    },
  );

  test(
    'requests force bug fields empty; only explicit omission sends null',
    () {
      final request = submission(
        type: ReportType.request,
        omitted: true,
      ).toJson();
      expect(request['steps'], '');
      expect(request['expected'], '');
      expect(request['diagnostic'], isNull);
      expect(request['diagnosticOmitted'], isFalse);
      expect(submission(omitted: true).toJson()['diagnostic'], isNull);
      expect(submission(omitted: true).toJson()['diagnosticOmitted'], isTrue);
      expect(submission().toJson()['diagnosticOmitted'], isFalse);
    },
  );

  for (final status in [302, 303]) {
    test(
      '$status redirects use GET with no POST body; duplicate is success',
      () async {
        final http = FakeReportHttp([
          Reply(status, location: redirect),
          Reply.json({'ok': true, 'receipt': receipt, 'duplicate': true}),
        ]);
        final result = await ReportClient(
          endpoint: endpoint,
          httpClientFactory: () => http,
        ).submit(submission());
        expect(result.receipt, receipt);
        expect(http.requests.map((r) => r.method), ['POST', 'GET']);
        expect(http.requests.last.uri, Uri.parse(redirect));
        expect(http.requests.last.body, isEmpty);
        expect(http.requests.every((r) => !r.followRedirects), isTrue);
      },
    );
  }

  test('two redirects are allowed and the third is refused', () async {
    for (final hops in [2, 3]) {
      final http = FakeReportHttp([
        for (var i = 0; i < hops; i++) Reply(302, location: redirect),
        Reply.json({'ok': true, 'receipt': receipt}),
      ]);
      final result = await ReportClient(
        endpoint: endpoint,
        httpClientFactory: () => http,
      ).submit(submission());
      expect(result.isSuccess, hops == 2);
      expect(http.requests, hasLength(3));
      expect(http.requests.skip(1).every((r) => r.body.isEmpty), isTrue);
    }
  });

  for (final location in <String?>[
    'https://accounts.google.com/login',
    'http://script.googleusercontent.com/echo',
    'https://script.googleusercontent.com.attacker.example/echo',
    'https://user@script.googleusercontent.com/echo',
    'https://script.googleusercontent.com:8443/echo',
    '/relative',
    null,
  ]) {
    test('unsafe redirect rejected: $location', () async {
      final http = FakeReportHttp([Reply(302, location: location)]);
      final result = await ReportClient(
        endpoint: endpoint,
        httpClientFactory: () => http,
      ).submit(submission());
      expect(result.code, 'not_public');
      expect(http.requests, hasLength(1));
    });
  }

  for (final body in [
    '<html>login</html>',
    '[]',
    '{"ok":"true","receipt":"$receipt"}',
    '{"ok":true}',
    '{"ok":true,"receipt":"R-0000000000"}',
    '{"ok":true,"receipt":"$receipt-extra"}',
    jsonEncode({'ok': true, 'receipt': '$receipt\n'}),
    '{}',
  ]) {
    test('malformed success fails: $body', () async {
      final http = FakeReportHttp([Reply(200, body: body)]);
      final result = await ReportClient(
        endpoint: endpoint,
        httpClientFactory: () => http,
      ).submit(submission());
      expect(result.code, 'unexpected');
      expect(result.isSuccess, isFalse);
    });
  }

  for (final code in [
    'unavailable',
    'conflict',
    'invalid',
    'too_large',
    'rate_limited',
    'busy',
    'full',
  ]) {
    test(
      'ok:false $code maps Japanese message and optional field errors',
      () async {
        final http = FakeReportHttp([
          Reply.json({
            'ok': false,
            'code': code,
            'fields': {'title': '件名を確認してください。'},
            'retryAfterSeconds': 121,
          }),
        ]);
        final result = await ReportClient(
          endpoint: endpoint,
          httpClientFactory: () => http,
        ).submit(submission());
        expect(result.code, code);
        expect(result.fields['title'], '件名を確認してください。');
        expect(result.message, isNotEmpty);
        if (code == 'rate_limited') expect(result.message, contains('3分'));
        if (['busy', 'unavailable'].contains(code)) {
          expect(result.message, contains('しばらく待って'));
        }
        if (code == 'full') {
          expect(
            result.message,
            '保存できる件数の上限に達しています。時間をおいて試すか、GitHub から報告してください。',
          );
        }
      },
    );
  }

  test(
    'network error and total timeout are uncertain and close the client',
    () async {
      for (final reply in [Reply.error(), Reply.pending()]) {
        final http = FakeReportHttp([reply]);
        final result = await ReportClient(
          endpoint: endpoint,
          httpClientFactory: () => http,
          requestTimeout: const Duration(milliseconds: 5),
        ).submit(submission());
        expect(result.code, 'network');
        expect(result.message, '送信できたか確認できませんでした。内容を変えずにもう一度送れば、二重には登録されません。');
        expect(http.closed, isTrue);
      }
    },
  );

  test(
    'missing and oversized diagnostics fail before creating HTTP client',
    () async {
      var created = 0;
      final client = ReportClient(
        endpoint: endpoint,
        httpClientFactory: () {
          created++;
          return FakeReportHttp([]);
        },
      );
      for (final diagnostic in [null, 'a' * 20001]) {
        final result = await client.submit(submission(diagnostic: diagnostic));
        expect(result.code, 'invalid');
      }
      expect(created, 0);
    },
  );

  test(
    'UTF-8 body byte cap is checked without truncation or network',
    () async {
      final client = ReportClient(
        endpoint: endpoint,
        httpClientFactory: () => throw StateError('no network'),
      );
      final result = await client.submit(
        submission(diagnostic: 'あ' * 20000, content: 'あ' * 4000),
      );
      expect(result.code, 'too_large');
    },
  );
}

class Reply {
  Reply(this.status, {this.body = '', this.location})
    : pending = false,
      error = false;
  Reply.json(Map<String, Object?> value) : this(200, body: jsonEncode(value));
  Reply.pending()
    : status = 200,
      body = '',
      location = null,
      pending = true,
      error = false;
  Reply.error()
    : status = 200,
      body = '',
      location = null,
      pending = false,
      error = true;
  final int status;
  final String body;
  final String? location;
  final bool pending, error;
}

class FakeReportHttp extends Fake implements HttpClient {
  FakeReportHttp(this.replies);
  final List<Reply> replies;
  final requests = <FakeReportRequest>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _open('POST', url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _open('GET', url);
  Future<HttpClientRequest> _open(String method, Uri url) async {
    final request = FakeReportRequest(method, url, replies[requests.length]);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;
}

class FakeReportRequest extends Fake implements HttpClientRequest {
  FakeReportRequest(this.method, this.uri, this.reply);
  @override
  final String method;
  @override
  final Uri uri;
  final Reply reply;
  final body = <int>[];
  @override
  final headers = FakeReportHeaders();
  @override
  bool followRedirects = true;
  @override
  void add(List<int> data) => body.addAll(data);
  @override
  Future<HttpClientResponse> close() {
    if (reply.pending) return Completer<HttpClientResponse>().future;
    if (reply.error) return Future.error(const SocketException('offline'));
    return Future.value(FakeReportResponse(reply));
  }
}

class FakeReportHeaders extends Fake implements HttpHeaders {
  FakeReportHeaders([this.location]);
  final String? location;
  @override
  ContentType? contentType;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
}

class FakeReportResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeReportResponse(this.reply);
  final Reply reply;
  @override
  int get statusCode => reply.status;
  @override
  HttpHeaders get headers => FakeReportHeaders(reply.location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(reply.body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
