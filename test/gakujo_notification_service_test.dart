import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('net.yoshida.morebettergakujo/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('requestPermission returns native permission result', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestPermission');
      return true;
    });

    expect(await GakujoNotificationService().requestPermission(), isTrue);
  });

  test('notifyDeadline forwards title body and url', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'notifyDeadline');
      expect(call.arguments, {
        'title': '課題A',
        'body': '提出期限 2026/07/01 17:00',
        'url': 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
      });
      return false;
    });

    final notified = await GakujoNotificationService().notifyDeadline(
      GakujoDeadlineEntry(
        title: '課題A',
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
        dueText: '提出期限 2026/07/01 17:00',
        detectedAt: DateTime.utc(2026, 6, 26),
      ),
    );

    expect(notified, isFalse);
  });

  test('notification calls fail closed when the platform channel is missing',
      () async {
    final service = GakujoNotificationService();

    expect(await service.requestPermission(), isFalse);
    expect(
      await service.notifyDeadline(
        GakujoDeadlineEntry(
          title: '課題A',
          url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
          dueText: '提出期限 2026/07/01 17:00',
          detectedAt: DateTime.utc(2026, 6, 26),
        ),
      ),
      isFalse,
    );
  });

  test('takePendingNotificationUrl consumes the native pending URL', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takePendingNotificationUrl');
      return '  https://gakujo.iess.niigata-u.ac.jp/campusweb/report  ';
    });

    expect(
      await GakujoNotificationService().takePendingNotificationUrl(),
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
    );
  });

  test('routes a native notification tap to the registered handler', () async {
    final service = GakujoNotificationService();
    String? tappedUrl;
    service.setDeadlineNotificationTappedHandler((url) {
      tappedUrl = url;
    });

    const codec = StandardMethodCodec();
    final response = await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
        const MethodCall(
          'deadlineNotificationTapped',
          {
            'url': '  https://gakujo.iess.niigata-u.ac.jp/campusweb/report  ',
          },
        ),
      ),
      null,
    );

    expect(codec.decodeEnvelope(response!), isTrue);
    expect(
      tappedUrl,
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
    );
    service.setDeadlineNotificationTappedHandler(null);
  });

  group('deadlineNotificationTargetUrl', () {
    const baseUrl = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/';

    test('accepts an allowed Gakujo URL', () {
      expect(
        deadlineNotificationTargetUrl(
          '  https://gakujo.iess.niigata-u.ac.jp/campusweb/report  ',
          debugAllowed: false,
        ),
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
      );
    });

    test('accepts portal tabs and stable message notification links', () {
      for (final target in [
        'campusportal.do?page=main&tabId=kj',
        'campusportal.do?page=main&tabId=en',
        'campusportal.do?page=main&tabId=sch',
        'campusportal.do?page=main&tabId=si',
        'campussquare.do?_flowId=KJW0001100-flow'
            '&keijitype=1&genrecd=40&seqNo=507795',
        'reportList.do',
      ]) {
        final url = '$baseUrl$target';
        expect(
          deadlineNotificationTargetUrl(url, debugAllowed: false),
          url,
          reason: target,
        );
      }
    });

    test('rejects action and flow execution parameter names', () {
      for (final query in [
        '_eventId=delete',
        '_eventId=',
        '_eventId',
        '_flowExecutionKey=e1s1',
        '_flowExecutionKey=',
        '_eventId_xxx=delete',
        '_eventId_=delete',
        '_EvEnTiD=delete',
        '_FlOwExEcUtIoNkEy=e1s1',
        '_EvEnTiD_XxX=delete',
        '%5Fevent%49d=delete',
        '%5FflowExecution%4Bey=e1s1',
        '%5FeventId%5Fxxx=delete',
        'page=main&_eventId=delete',
        'page=main&page=other&_eventId=delete',
      ]) {
        expect(
          deadlineNotificationTargetUrl(
            '${baseUrl}campussquare.do?$query',
            debugAllowed: false,
          ),
          isNull,
          reason: query,
        );
      }
    });

    test('checks query names without treating values or fragments as names', () {
      for (final target in [
        'campusportal.do?keyword=_eventId',
        'campusportal.do?keyword=%26_eventId%3Ddelete',
        'campusportal.do?keyword=%E9%80%A3%E7%B5%A1',
        'campusportal.do?keyword=連絡',
        'campusportal.do?_eventIdentity=example',
        'campusportal.do#?_eventId=delete',
        'campusportal.do?page=main#?_eventId=delete',
      ]) {
        final url = '$baseUrl$target';
        expect(
          deadlineNotificationTargetUrl(url, debugAllowed: false),
          url,
          reason: target,
        );
      }
    });

    test('rejects malformed query encoding', () {
      for (final query in [
        '%FF=value',
        'keyword=%FF',
        'keyword=%E3%81',
        'keyword=%',
        'keyword=%2',
        'keyword=%GG',
        '%GG=value',
        '=%FF',
      ]) {
        expect(
          deadlineNotificationTargetUrl(
            '${baseUrl}campusportal.do?$query',
            debugAllowed: false,
          ),
          isNull,
          reason: query,
        );
      }
    });

    test('keeps debug fixtures gated and rejects their action links', () {
      const fixtureUrl = 'file:///android_asset/qa/two_factor.html';
      expect(
        deadlineNotificationTargetUrl(fixtureUrl, debugAllowed: true),
        fixtureUrl,
      );
      expect(
        deadlineNotificationTargetUrl(fixtureUrl, debugAllowed: false),
        isNull,
      );
      expect(
        deadlineNotificationTargetUrl(
          '$fixtureUrl?_eventId=delete',
          debugAllowed: true,
        ),
        isNull,
      );
    });

    test('rejects external and malformed URLs', () {
      expect(
        deadlineNotificationTargetUrl(
          'https://www.niigata-u.ac.jp/',
          debugAllowed: false,
        ),
        isNull,
      );
      expect(
        deadlineNotificationTargetUrl('not a url', debugAllowed: false),
        isNull,
      );
    });

    test('rejects null and empty URLs', () {
      expect(
        deadlineNotificationTargetUrl(null, debugAllowed: false),
        isNull,
      );
      expect(
        deadlineNotificationTargetUrl('  ', debugAllowed: false),
        isNull,
      );
    });
  });

  test('concurrent scans notify each deadline only once', () async {
    final activityStore = _NotificationRaceActivityStore();
    final notificationService = _BlockingNotificationService();
    final coordinator = GakujoDeadlineNotificationCoordinator(
      activityStore: activityStore,
      notificationService: notificationService,
    );

    final first = coordinator.notifyPendingDeadlines(
      notificationsEnabled: true,
    );
    final second = coordinator.notifyPendingDeadlines(
      notificationsEnabled: true,
    );

    await notificationService.firstNotificationStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(notificationService.notifyCalls, 1);

    notificationService.releaseFirstNotification.complete();
    await Future.wait([first, second]);

    expect(notificationService.notifyCalls, 1);
    expect(activityStore.notifiedKeys, {activityStore.deadline.key});
  });
}

class _NotificationRaceActivityStore extends GakujoActivityStore {
  final Set<String> notifiedKeys = {};

  final GakujoDeadlineEntry deadline = GakujoDeadlineEntry(
    title: '課題A',
    url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/report',
    dueText: '提出期限 2099/07/31 17:00',
    detectedAt: DateTime(2026, 7, 22),
  );

  @override
  Future<List<GakujoDeadlineEntry>> loadDeadlines() async => [deadline];

  @override
  Future<Set<String>> loadNotifiedDeadlineKeys() async {
    return Set<String>.from(notifiedKeys);
  }

  @override
  Future<void> addNotifiedDeadlineKeys(Iterable<String> deadlineKeys) async {
    notifiedKeys.addAll(deadlineKeys);
  }
}

class _BlockingNotificationService extends GakujoNotificationService {
  final Completer<void> firstNotificationStarted = Completer<void>();
  final Completer<void> releaseFirstNotification = Completer<void>();
  int notifyCalls = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notifyDeadline(GakujoDeadlineEntry entry) async {
    notifyCalls += 1;
    if (!firstNotificationStarted.isCompleted) {
      firstNotificationStarted.complete();
    }
    await releaseFirstNotification.future;
    return true;
  }
}
