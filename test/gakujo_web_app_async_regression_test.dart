import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/desktop_page_zoom_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_app_settings.dart';
import 'package:morebettergakujo_flutter/src/gakujo_calendar_export.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_capture_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_request.dart';
import 'package:morebettergakujo_flutter/src/gakujo_download_service.dart';
import 'package:morebettergakujo_flutter/src/gakujo_message_star_script.dart';
import 'package:morebettergakujo_flutter/src/gakujo_upload_compression_libraries.dart';
import 'package:morebettergakujo_flutter/src/gakujo_web_app.dart';
import 'package:morebettergakujo_flutter/src/login_autofill_assist_script.dart';
import 'package:morebettergakujo_flutter/src/web_view_service.dart';

void main() {
  group('native download routing', () {
    test('uses the captured GET path with a suggested name and course estimate',
        () async {
      final requests = <GakujoDownloadRequest>[];
      final messages = <String>[];
      await handleGakujoNativeDownload(
        const GakujoWebViewDownload(
          url: 'https://gakujo.iess.niigata-u.ac.jp/download.do'
              '?fileId=42&_eventId=download',
          resultFilePath: r'C:\Users\student\Downloads\講義資料.pdf',
          mimeType: 'application/pdf',
        ),
        onDownload: requests.add,
        showSnackBar: messages.add,
      );
      final request = requests.single;
      expect(
        request.url,
        'https://gakujo.iess.niigata-u.ac.jp/download.do'
        '?fileId=42&_eventId=download',
      );
      expect(request.method, 'GET');
      expect(request.fileName, '講義資料.pdf');
      // An empty course takes the existing page/course estimation path.
      expect(request.courseName, isEmpty);
      expect(request.formFields, isEmpty);
      expect(messages, isEmpty);
    });

    test('drops the Downloads-folder " (n)" WebView2 adds to the name',
        () async {
      final requests = <GakujoDownloadRequest>[];
      await handleGakujoNativeDownload(
        const GakujoWebViewDownload(
          url:
              'https://gakujo.iess.niigata-u.ac.jp/download.do?_eventId=download',
          resultFilePath: r'C:\Users\student\Downloads\02 (1).pdf',
          mimeType: 'application/pdf',
        ),
        onDownload: requests.add,
        showSnackBar: (_) {},
      );
      expect(requests.single.fileName, '02.pdf');
    });

    test('uses MIME metadata when the suggested path is unavailable', () async {
      final requests = <GakujoDownloadRequest>[];
      await handleGakujoNativeDownload(
        const GakujoWebViewDownload(
          url: 'https://gakujo.iess.niigata-u.ac.jp/campussquare.do'
              '?_EVENTID=DOWNLOAD&fileId=42',
          mimeType: 'application/pdf',
        ),
        onDownload: requests.add,
        showSnackBar: (_) => fail('A Gakujo download should be accepted'),
      );
      expect(requests.single.fileName, 'document.pdf');
    });

    for (final suffix in [
      '',
      '?',
      '?fileId=42',
      '?title=Report%20A',
      '?_eventId=confirm',
      '?_eventId=infoDownload',
      '?x_eventId=download',
      '?next=_eventId=download',
      '?_eventId=downloadLater',
      '#section?_eventId=download',
      '?fileId=42#?_eventId=download',
    ]) {
      test('leaves a non-attachment POST download ($suffix) to WebView2',
          () async {
        await handleGakujoNativeDownload(
          GakujoWebViewDownload(
            url: 'https://gakujo.iess.niigata-u.ac.jp/download.do$suffix',
          ),
          onDownload: (_) =>
              fail('A POST response must not be replayed as GET'),
          showSnackBar: (_) => fail('WebView2 displays its download UI'),
        );
      });
    }

    test('native cancellation follows the replayability guard', () {
      final source = File(
        'third_party/webview_flutter_windows/windows/webview.cc',
      ).readAsStringSync();
      final handler = source.substring(
        source.indexOf('webview24->add_DownloadStarting('),
      );
      final guard = handler.indexOf('!util::IsReplayableGakujoDownload(url)');
      expect(guard, greaterThan(0));
      final fallback = handler.indexOf('return S_OK;', guard);
      expect(handler, contains('args->put_Cancel(FALSE)'));
      expect(handler, contains('args->put_Handled(FALSE)'));
      expect(handler.indexOf('args->put_Cancel(FALSE)'), lessThan(guard));
      expect(handler.indexOf('args->put_Handled(FALSE)'), lessThan(guard));
      expect(handler.indexOf('args->put_Cancel(TRUE)'), greaterThan(fallback));
      expect(handler.indexOf('args->put_Handled(TRUE)'), greaterThan(fallback));
      expect(
          handler.indexOf('download_event_callback_('), greaterThan(fallback));
      expect(
        handler.indexOf('!download_interception_enabled_'),
        inExclusiveRange(0, guard),
      );
      expect(
        File('third_party/webview_flutter_windows/windows/webview.h')
            .readAsStringSync(),
        contains('bool download_interception_enabled_ = false;'),
      );
    });

    test('native feature updates run even when page scripts cannot run', () {
      final source = File('lib/src/gakujo_web_app.dart').readAsStringSync();
      final runtime = source.substring(
        source.indexOf('Future<void> _applyFeatureFlagRuntimeState('),
        source.indexOf('Future<void> _applyChangedRuntimeFeatureFlags('),
      );
      expect(
        runtime.indexOf('.setDownloadInterceptionEnabled(enabled)'),
        inExclusiveRange(0, runtime.indexOf('if (!_canRunPageScripts)')),
      );
      final startup = source.substring(
        source.indexOf('Future<void> _loadInitialPage()'),
        source.indexOf('Future<void> _handleDeadlineNotificationTapped('),
      );
      expect(startup, contains('downloadInterceptionEnabled: false'));
      expect(
        startup.indexOf('GakujoFeatureFlag.downloadCapture'),
        inExclusiveRange(startup.indexOf('await _loadAppSettings()'),
            startup.indexOf('await _controller.loadUrl(')),
      );
      final downloads =
          File('lib/src/gakujo_web_app_downloads.dart').readAsStringSync();
      final handler = downloads.substring(
        downloads.indexOf('Future<void> _handleNativeDownload('),
        downloads.indexOf('Future<void> _handleDownloadMessage('),
      );
      expect(
        handler.indexOf('GakujoFeatureFlag.downloadCapture'),
        inExclusiveRange(
            0, handler.indexOf('await handleGakujoNativeDownload(')),
      );
    });

    for (final url in [
      'https://example.com/file.pdf',
      'https://www.niigata-u.ac.jp/file.pdf',
      'http://gakujo.iess.niigata-u.ac.jp/file.pdf',
      'https://gakujo.iess.niigata-u.ac.jp.example.com/file.pdf',
      'https://user@gakujo.iess.niigata-u.ac.jp/file.pdf',
      'https://gakujo.iess.niigata-u.ac.jp:8443/file.pdf',
      'file:///android_asset/qa/file.pdf',
      '',
      'https://[invalid',
    ]) {
      test('blocks a native download from $url', () async {
        final messages = <String>[];
        await handleGakujoNativeDownload(
          GakujoWebViewDownload(url: url),
          onDownload: (_) => fail('Blocked downloads must not be fetched'),
          showSnackBar: messages.add,
        );
        expect(messages, ['Gakujo以外のダウンロードをブロックしました']);
      });
    }

    for (final url in [
      'blob:https://gakujo.iess.niigata-u.ac.jp/id',
      'blob:https://example.com/id',
      'data:application/pdf;base64,JVBERg==',
    ]) {
      test('explains why $url cannot be refetched', () async {
        final messages = <String>[];
        await handleGakujoNativeDownload(
          GakujoWebViewDownload(url: url),
          onDownload: (_) => fail('Blob/data downloads cannot be refetched'),
          showSnackBar: messages.add,
        );
        expect(messages, ['このファイルは保存できませんでした']);
      });
    }
  });

  group('JavaScript channel origin guard', () {
    for (final channel in [
      GakujoDownloadCaptureScript.channelName,
      LoginAutofillAssistScript.channelName,
      GakujoUploadCompressionLibraries.channelName,
      GakujoMessageStarScript.channelName,
      DesktopPageZoomScript.channelName,
    ]) {
      test('$channel trusts the current page rather than the payload URL',
          () async {
        const payload =
            '{"url":"https://gakujo.iess.niigata-u.ac.jp/private.pdf"}';
        final handled = <String>[];
        for (final url in [
          null,
          '',
          'about:blank',
          'file:///android_asset/qa/two_factor.html',
          'https://www.niigata-u.ac.jp/',
          'https://accounts.google.com/',
          'https://docs.google.com/',
          'https://univcoop.jp/',
          'http://gakujo.iess.niigata-u.ac.jp/',
          'https://gakujo.iess.niigata-u.ac.jp:8443/',
          'https://user@gakujo.iess.niigata-u.ac.jp/',
          'https://gakujo.iess.niigata-u.ac.jp.example.com/',
        ]) {
          await handleGakujoJavaScriptMessage(
            currentUrl: url,
            channelName: channel,
            message: payload,
            onMessageReceived: handled.add,
          );
          expect(handled, isEmpty, reason: '$channel on $url');
        }
        await handleGakujoJavaScriptMessage(
          currentUrl:
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          channelName: channel,
          message: payload,
          onMessageReceived: handled.add,
        );
        expect(handled, [payload]);
      });

      test('$channel accepts an internal blank page only after Gakujo',
          () async {
        final handled = <String>[];
        for (final lastAllowed in [
          null,
          'https://example.com/',
          'http://gakujo.iess.niigata-u.ac.jp/',
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        ]) {
          await handleGakujoJavaScriptMessage(
            currentUrl: 'about:blank',
            lastAllowedUrl: lastAllowed,
            channelName: channel,
            message: 'download or zoom response',
            onMessageReceived: handled.add,
          );
        }
        expect(handled, ['download or zoom response']);
        await handleGakujoJavaScriptMessage(
          currentUrl: 'https://example.com/',
          lastAllowedUrl: 'https://gakujo.iess.niigata-u.ac.jp/',
          channelName: channel,
          message: 'untrusted response',
          onMessageReceived: handled.add,
        );
        expect(handled, ['download or zoom response']);
      });
    }
  });

  group('pending message navigation ownership', () {
    const target =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do';
    const other =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';

    test('portal iframe navigation preserves the pending message open', () {
      final navigation = GakujoMessageOpenNavigation()..record(target, 7);
      const iframe = GakujoNavigationRequest(
        url: 'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
        isMainFrame: false,
      );
      expect(navigation.shouldCancelFor(iframe, 7), isFalse);
      expect(navigation.consume(target, 7), isTrue);
      navigation.record(target, 8);
      expect(
        navigation.shouldCancelFor(
          GakujoNavigationRequest(url: iframe.url, isMainFrame: true),
          8,
        ),
        isTrue,
      );
    });

    test('only the recorded app navigation can consume its page start', () {
      final navigation = GakujoMessageOpenNavigation()..record(target, 7);
      expect(navigation.owns(target, 7), isTrue);
      expect(navigation.consume(target, 7), isTrue);
      expect(navigation.owns(target, 7), isFalse);
      expect(navigation.consume(other, 8), isFalse);
      expect(navigation.consume(target, 8), isFalse);
    });

    test('an ordinary link invalidates an uncompleted app navigation', () {
      final navigation = GakujoMessageOpenNavigation()..record(target, 7);
      expect(navigation.owns(other, 7), isFalse);
      expect(navigation.consume(other, 7), isFalse);
      expect(navigation.consume(target, 7), isFalse);
    });

    test('reload and history revisions invalidate the old navigation', () {
      final navigation = GakujoMessageOpenNavigation()..record(target, 7);
      expect(navigation.consume(target, 8), isFalse);
    });

    test('the post-login restore records a new app navigation', () {
      final navigation = GakujoMessageOpenNavigation()..record(target, 7);
      expect(navigation.consume(target, 7), isTrue);
      navigation.record(null, 8); // The app's autofill submits the login form.
      expect(navigation.consume(other, 8), isTrue);
      expect(navigation.owns(other, 8), isFalse);
      navigation.record(target, 9);
      expect(navigation.consume(target, 9), isTrue);
      expect(navigation.consume(other, 10), isFalse);
    });
  });

  group('resource error status and recovery', () {
    void checkError(
      GakujoWebResourceError error, {
      required List<String> expectedStatuses,
      int offlineAutoReloads = 0,
      int expectedRetries = 0,
    }) {
      final statuses = <String>[];
      var retries = 0;
      handleGakujoWebResourceError(
        error,
        offlineAutoReloads: offlineAutoReloads,
        setStatus: statuses.add,
        startOfflineRetry: () => retries++,
      );
      expect(statuses, expectedStatuses);
      expect(retries, expectedRetries);
    }

    test('an offline iframe shows manual recovery without starting a retry',
        () {
      for (final reloads in [0, 3]) {
        checkError(
          const GakujoWebResourceError(
            description: 'iframe offline',
            isForMainFrame: false,
            isConnectivityError: true,
          ),
          offlineAutoReloads: reloads,
          expectedStatuses: ['オフラインのようです。接続が戻ったら再読込してください'],
        );
      }
    });

    test('other sub-resource errors leave the visible status unchanged', () {
      checkError(
        const GakujoWebResourceError(
          description: 'blocked image',
          isForMainFrame: false,
        ),
        expectedStatuses: [],
      );
    });

    test('main-frame connectivity errors retain automatic recovery and cap',
        () {
      const error = GakujoWebResourceError(
        description: 'main frame offline',
        isConnectivityError: true,
      );
      checkError(
        error,
        expectedStatuses: ['オフラインのようです。接続が戻ると自動で再読み込みします'],
        expectedRetries: 1,
      );
      checkError(
        error,
        offlineAutoReloads: 3,
        expectedStatuses: ['読み込めませんでした。接続を確認して再読込を押してください'],
      );
    });

    test('other main-frame errors retain their error status', () {
      checkError(
        const GakujoWebResourceError(description: 'certificate failure'),
        expectedStatuses: ['読込エラー: certificate failure'],
      );
    });

    test('the renderer recovery limit appears in status without offline retry',
        () {
      checkError(
        const GakujoWebResourceError(
          description: '表示が繰り返し停止したため再読み込みを止めました。再読込を押してください',
        ),
        expectedStatuses: [
          '読込エラー: 表示が繰り返し停止したため再読み込みを止めました。再読込を押してください',
        ],
      );
    });
  });

  group('message notification links', () {
    const messageUrl =
        'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do'
        '?_flowId=KJW0001100-flow&keijitype=4&genrecd=406&seqNo=174198';

    test('extracts the message identity from a stable notification link', () {
      expect(
        gakujoMessageTargetFromUrl(messageUrl),
        (keijitype: '4', genrecd: '406', seqNo: '174198'),
      );
    });

    test('rejects a link without seqNo', () {
      expect(
        gakujoMessageTargetFromUrl(
            messageUrl.replaceFirst('&seqNo=174198', '')),
        isNull,
      );
    });

    for (final parameter in ['keijitype=4', 'genrecd=406', 'seqNo=174198']) {
      test('rejects non-numeric $parameter', () {
        expect(
          gakujoMessageTargetFromUrl(
            messageUrl.replaceFirst(parameter, '${parameter}x'),
          ),
          isNull,
        );
      });
    }

    test('rejects another flow', () {
      expect(
        gakujoMessageTargetFromUrl(
          messageUrl.replaceFirst('KJW0001100-flow', 'KJW0001200-flow'),
        ),
        isNull,
      );
    });

    test('rejects another host', () {
      expect(
        gakujoMessageTargetFromUrl(
          messageUrl.replaceFirst('gakujo.iess.niigata-u.ac.jp', 'example.com'),
        ),
        isNull,
      );
    });

    test('rejects another path, insecure URLs and malformed query encoding',
        () {
      for (final url in [
        messageUrl.replaceFirst('campussquare.do', 'campusportal.do'),
        messageUrl.replaceFirst('https:', 'http:'),
        messageUrl.replaceFirst('seqNo=174198', 'seqNo='),
        messageUrl.replaceFirst('seqNo=174198', 'seqNo=%FF'),
      ]) {
        expect(gakujoMessageTargetFromUrl(url), isNull, reason: url);
      }
    });
  });

  group('portal authentication state', () {
    test('detects login fields when name and id repeat the same userId',
        () async {
      final result = await _evaluateAuthProbe([
        {
          'tag': 'input',
          'type': 'text',
          'name': 'userId',
          'id': 'userId',
        },
        {
          'tag': 'input',
          'type': 'password',
          'name': 'password',
          'id': 'password',
        },
      ]);

      expect(result['hasLoginFields'], isTrue, reason: jsonEncode(result));
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(result),
        GakujoPortalAuthState.login,
      );
    });

    test('detects 2FA and authenticated DOM markers', () async {
      final twoFactor = await _evaluateAuthProbe([
        {
          'tag': 'input',
          'type': 'password',
          'name': 'ninshoCode',
          'id': 'ninshoCode',
        },
      ]);
      final authenticated = await _evaluateAuthProbe([
        {'tag': 'button', 'text': 'ログアウト'},
      ]);

      expect(
        gakujoPortalAuthStateFromJavaScriptResult(twoFactor),
        GakujoPortalAuthState.twoFactor,
      );
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(authenticated),
        GakujoPortalAuthState.authenticated,
      );
    });

    test('detects the PC portal logout list', () async {
      // <ul id="logout"><li><img alt=""></li><li><span>ログアウト</span></li></ul>
      final portal = await _evaluateAuthProbe([
        {'tag': 'img', 'alt': ''},
        {'tag': 'ul', 'id': 'logout', 'text': 'ログアウト'},
      ]);
      final strayText = await _evaluateAuthProbe([
        {'tag': 'span', 'text': 'ログアウト'},
      ]);

      expect(
        gakujoPortalAuthStateFromJavaScriptResult(portal),
        GakujoPortalAuthState.authenticated,
      );
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(strayText),
        GakujoPortalAuthState.unknown,
      );
    });

    test('ignores hidden authenticated controls', () async {
      final hiddenLogout = await _evaluateAuthProbe([
        {'tag': 'button', 'text': 'ログアウト', 'display': 'none'},
      ]);

      expect(hiddenLogout['hasAuthenticatedMarker'], isFalse);
      expect(
        gakujoPortalAuthStateFromJavaScriptResult(hiddenLogout),
        GakujoPortalAuthState.unknown,
      );
    });

    test('restores the protected page once after login and 2FA', () {
      const protectedUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';
      const dynamicLoginUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';
      const authenticatedLandingUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do';

      String? sessionRecoveryUrl = protectedUrl;
      String? pendingRestoreUrl;
      var restoreAttempted = true;
      var loadCount = 0;

      void observeChallenge(GakujoPortalAuthState authState) {
        if (shouldResetGakujoLoginRestoreAttempt(
          authState: authState,
          urlLooksLikeLoginOrTimeout: false,
          hasRecoveryUrl: sessionRecoveryUrl != null,
        )) {
          pendingRestoreUrl = sessionRecoveryUrl;
          restoreAttempted = false;
        }
      }

      // campussmart.do is also an authenticated portal URL, so the DOM probe
      // must identify the dynamically revealed login form.
      expect(dynamicLoginUrl, isNot(contains('login')));
      observeChallenge(GakujoPortalAuthState.login);
      expect(sessionRecoveryUrl, protectedUrl);
      expect(pendingRestoreUrl, protectedUrl);

      observeChallenge(GakujoPortalAuthState.twoFactor);
      expect(sessionRecoveryUrl, protectedUrl);
      expect(pendingRestoreUrl, protectedUrl);

      sessionRecoveryUrl = authenticatedLandingUrl;
      if (shouldRestorePendingGakujoPage(
        authState: GakujoPortalAuthState.authenticated,
        restoreAttempted: restoreAttempted,
        hasRestoreUrl: pendingRestoreUrl != null,
        currentUrlMatchesRestoreUrl:
            pendingRestoreUrl == authenticatedLandingUrl,
      )) {
        loadCount += 1;
        restoreAttempted = true;
        pendingRestoreUrl = null;
      }
      // A duplicate/stale authenticated callback cannot load it again.
      if (shouldRestorePendingGakujoPage(
        authState: GakujoPortalAuthState.authenticated,
        restoreAttempted: restoreAttempted,
        hasRestoreUrl: pendingRestoreUrl != null,
        currentUrlMatchesRestoreUrl:
            pendingRestoreUrl == authenticatedLandingUrl,
      )) {
        loadCount += 1;
      }

      expect(loadCount, 1);
      expect(pendingRestoreUrl, isNull);
    });

    test('preserves a saved page without requiring stored credentials', () {
      const savedUrl =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';

      expect(
        gakujoInitialPendingRestoreUrl(
          pendingNotificationUrl: null,
          savedUrl: savedUrl,
        ),
        savedUrl,
      );
    });

    test('notification target is reserved during an existing login challenge',
        () {
      const target =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_eventId=reportList';
      expect(
        gakujoNotificationRestoreTarget(target, debugAllowed: false),
        target,
      );
      expect(
        gakujoNotificationRestoreTarget(
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/login.do',
          debugAllowed: false,
        ),
        isNull,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: target,
          authenticatedUrl:
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do',
          pendingRestoreUrl: target,
        ),
        target,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: null,
          authenticatedUrl:
              'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/list.do',
          pendingRestoreUrl: target,
        ),
        target,
        reason: 'a same-URL login challenge must not discard notification B',
      );
    });

    test('consumes a pending target already reached by authentication', () {
      const target =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';

      expect(
        shouldConsumePendingGakujoPage(
          authState: GakujoPortalAuthState.authenticated,
          currentUrl: target,
          restoreUrl: target,
        ),
        isTrue,
      );
      expect(
        shouldConsumePendingGakujoPage(
          authState: GakujoPortalAuthState.login,
          currentUrl: target,
          restoreUrl: target,
        ),
        isFalse,
      );
    });

    test('freezes protected navigation B ahead of login shell redirects', () {
      const authenticatedA =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/message/list.do';
      const requestedB =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';
      const sharedLoginShell =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussmart.do';

      expect(
        isGakujoNavigationRecoveryCandidateUrl(
          requestedB,
          debugAllowed: false,
        ),
        isTrue,
      );
      expect(
        isGakujoNavigationRecoveryCandidateUrl(
          sharedLoginShell,
          debugAllowed: false,
        ),
        isFalse,
      );
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: requestedB,
          authenticatedUrl: authenticatedA,
          pendingRestoreUrl: null,
        ),
        requestedB,
      );

      final challengeAtCandidate = usableGakujoNavigationCandidateForChallenge(
        navigationCandidateUrl: requestedB,
        challengeUrl: requestedB,
      );
      expect(challengeAtCandidate, requestedB);
      expect(
        selectGakujoSessionRecoveryUrl(
          navigationCandidateUrl: challengeAtCandidate,
          authenticatedUrl: authenticatedA,
          pendingRestoreUrl: null,
        ),
        requestedB,
      );
    });

    test('flow-key pages never replace the previous durable recovery URL', () {
      const durable =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do'
          '?page=main&tabId=en';
      for (final query in [
        '_flowExecutionKey=e1s2',
        '_FLOWEXECUTIONKEY=e1s2&_eventId=confirm',
        '%5FflowExecutionKey=e1s2',
        '_flowExecutionKey',
      ]) {
        final flowUrl =
            'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?$query';
        expect(
          usableGakujoNavigationCandidateForChallenge(
            navigationCandidateUrl: flowUrl,
            challengeUrl: flowUrl,
          ),
          isNull,
        );
        expect(
          selectGakujoSessionRecoveryUrl(
            navigationCandidateUrl: flowUrl,
            pendingRestoreUrl: flowUrl,
            authenticatedUrl: durable,
          ),
          durable,
        );
        expect(
          selectGakujoSessionRecoveryUrl(
            navigationCandidateUrl: null,
            pendingRestoreUrl: null,
            authenticatedUrl: flowUrl,
          ),
          isNull,
        );
      }
    });

    test('login, logout and timeout challenges cannot become destinations', () {
      const durable =
          'https://gakujo.iess.niigata-u.ac.jp/campusweb/report/list.do';
      for (final page in ['login.do', 'logout.do', 'timeout.do']) {
        final challenge = 'https://gakujo.iess.niigata-u.ac.jp/campusweb/$page';
        expect(
          usableGakujoNavigationCandidateForChallenge(
            navigationCandidateUrl: challenge,
            challengeUrl: challenge,
          ),
          isNull,
        );
        expect(
          selectGakujoSessionRecoveryUrl(
            navigationCandidateUrl: challenge,
            pendingRestoreUrl: challenge,
            authenticatedUrl: durable,
          ),
          durable,
        );
      }
    });

    test('autofill runtime features expose timer teardown scripts', () {
      final login = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.loginAutofill,
      );
      final twoFactor = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.twoFactorAutofill,
      );
      final gpa = gakujoRuntimeTeardownScriptForFeature(
        GakujoFeatureFlag.gpaDisplay,
      );

      expect(login, contains('__MBG_LOGIN_AUTOFILL_DISABLED'));
      expect(login, contains('clearTimeout'));
      expect(twoFactor, contains('__MBG_2FA_AUTOFILL_DISABLED'));
      expect(twoFactor, contains('clearTimeout'));
      expect(gpa, isNotNull);
    });

    test('authenticated reset clears session and document attempt guards',
        () async {
      expect(
        gakujoPortalAuthStateFromSignals(
          hasLoginFields: true,
          hasTwoFactorField: false,
          hasAuthenticatedMarker: false,
        ),
        GakujoPortalAuthState.login,
      );
      expect(gakujoAuthenticatedSessionResetScript, contains('removeItem'));
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_ERROR:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_2FA_AUTOFILL_ERROR:'),
      );
      expect(
        gakujoAuthenticatedSessionResetScript,
        contains('MBG_2FA_AUTOFILL_SUBMIT_COUNT:'),
      );
      expect(gakujoAuthenticatedSessionResetScript, isNot(contains('clear()')));
      final reset = await _evaluateAuthenticatedSessionReset();
      expect(reset['hasLoginDocumentGuard'], isFalse);
      expect(reset['hasTwoFactorDocumentGuard'], isFalse);
      expect(
        reset['keys'],
        ['UNRELATED'],
        reason: jsonEncode(reset),
      );
    });
  });

  group('calendar extraction evidence', () {
    test('generic extraction must be broad but official can be nonempty', () {
      final narrow = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 1, 1, 1]),
        termRange: null,
      );
      final broad = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 1]),
        termRange: null,
      );

      expect(isBroadGakujoScheduleExtraction(narrow), isFalse);
      expect(
        isUsableGakujoScheduleExtraction(narrow, isOfficial: false),
        isFalse,
      );
      expect(
        isUsableGakujoScheduleExtraction(narrow, isOfficial: true),
        isTrue,
      );
      expect(
        isUsableGakujoScheduleExtraction(broad, isOfficial: false),
        isTrue,
      );
    });

    test('term range and best course list are retained independently', () {
      final range = GakujoCalendarTermRange(
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 8, 8),
      );
      final rangeWithOneCourse = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1]),
        termRange: range,
      );
      final completeWithoutRange = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 4, 5, 1, 2, 3, 4, 5]),
        termRange: null,
      );

      final merged = mergeGakujoScheduleExtractionEvidence(
        rangeWithOneCourse,
        completeWithoutRange,
      );

      expect(merged.courses, hasLength(10));
      expect(merged.termRange, same(range));
      expect(isBroadGakujoScheduleExtraction(merged), isTrue);
    });

    test('winning course evidence keeps its own term range in either order',
        () {
      final firstRange = GakujoCalendarTermRange(
        start: DateTime(2026, 4, 1),
        end: DateTime(2026, 6, 10),
      );
      final secondRange = GakujoCalendarTermRange(
        start: DateTime(2026, 6, 11),
        end: DateTime(2026, 8, 8),
      );
      final narrowFirst = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1]),
        termRange: firstRange,
      );
      final broadSecond = GakujoCalendarExtraction(
        courses: _coursesForWeekdays([1, 2, 3, 4, 5, 1, 2, 3, 4, 5]),
        termRange: secondRange,
      );

      final broadFirst = mergeGakujoScheduleExtractionEvidence(
        broadSecond,
        narrowFirst,
      );
      final broadCandidate = mergeGakujoScheduleExtractionEvidence(
        narrowFirst,
        broadSecond,
      );

      expect(broadFirst.courses, hasLength(10));
      expect(broadFirst.termRange, same(secondRange));
      expect(broadCandidate.courses, hasLength(10));
      expect(broadCandidate.termRange, same(secondRange));
    });
  });

  group('calendar integration safety', () {
    test('calendar validation advances by civil dates', () {
      final next = gakujoCalendarDateAfterDays(DateTime(2026, 10, 31), 1);
      expect(next, DateTime(2026, 11, 1));
      expect(next.hour, 0);
    });

    test('manual calendar identity survives small range corrections', () {
      final original = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 6, 11),
          end: DateTime(2026, 8, 8),
        ),
      );
      final corrected = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 6, 12),
          end: DateTime(2026, 8, 7),
        ),
      );
      final firstTerm = gakujoManualCalendarUidNamespace(
        termRange: GakujoCalendarTermRange(
          start: DateTime(2026, 4, 8),
          end: DateTime(2026, 6, 8),
        ),
      );

      expect(corrected, original);
      expect(firstTerm, isNot(original));
      expect(original, 'niigata-2026-第2ターム');
      expect(
        gakujoLegacyManualIcsUidNamespace(
          GakujoCalendarTermRange(
            start: DateTime(2026, 6, 11),
            end: DateTime(2026, 8, 8),
          ),
        ),
        'manual-20260611-20260808',
      );
    });

    test('accepts only canonical HTTPS Google host boundaries', () {
      expect(
        isAllowedGakujoGoogleCalendarUrl(
          'https://calendar.google.com/calendar/render',
        ),
        isTrue,
      );
      expect(
        isAllowedGakujoGoogleCalendarUrl(
          'https://calendar.google.com:443/calendar/render',
        ),
        isTrue,
      );
      for (final url in [
        'http://calendar.google.com/calendar/render',
        'https://drive.google.com/calendar/render',
        'https://google.com/calendar/render',
        'https://evilgoogle.com/calendar/render',
        'https://google.com.evil.example/calendar/render',
        'https://google.com@evil.example/calendar/render',
        'https://calendar.google.com:444/calendar/render',
      ]) {
        expect(
          isAllowedGakujoGoogleCalendarUrl(url),
          isFalse,
          reason: url,
        );
      }
    });

    test('ambiguous courses initialize from their own hints only', () {
      const withHints = GakujoCalendarCourse(
        title: '複数ターム授業',
        weekday: 1,
        period: 1,
        courseCode: '260A0001',
        termHint: '第1ターム 第3ターム',
      );
      const withoutHints = GakujoCalendarCourse(
        title: '期間不明授業',
        weekday: 2,
        period: 2,
        courseCode: '260B0001',
      );

      expect(initialGakujoAmbiguousCourseTermSelections(withHints), {1, 3});
      expect(initialGakujoAmbiguousCourseTermSelections(withoutHints), isEmpty);
    });

    test('unselected ambiguous courses are omitted instead of reappearing', () {
      const ambiguous = GakujoCalendarCourse(
        title: '期間不明授業',
        weekday: 1,
        period: 1,
        courseCode: '260A0001',
      );
      const regular = GakujoCalendarCourse(
        title: '第1ターム授業',
        weekday: 2,
        period: 2,
        courseCode: '261B0001',
      );
      final key = GakujoCalendarExport.courseIdentityKey(ambiguous);

      expect(
        applyGakujoAmbiguousCourseTermSelections(
          const [ambiguous, regular],
          const {},
        ),
        [regular],
      );
      expect(
        applyGakujoAmbiguousCourseTermSelections(
          const [ambiguous, regular],
          {key: <int>{}},
        ),
        [regular],
      );
      final selected = applyGakujoAmbiguousCourseTermSelections(
        const [ambiguous, regular],
        {
          key: {4, 2},
        },
      );
      expect(selected, hasLength(2));
      expect(selected.first.termHint, '第2ターム 第4ターム');
    });

    test('native calendar export sends ICS bytes to the iOS picker bridge',
        () async {
      const channel = MethodChannel(
        'net.yoshida.morebettergakujo/downloads',
      );
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        capturedCall = call;
        return {
          'fileName': 'classes.ics',
          'courseName': '',
          'location': '/picked/classes.ics',
        };
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final result = await exportGakujoCalendarWithNativePicker(
        ics: 'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
        fileName: 'classes.ics',
      );

      expect(capturedCall?.method, 'exportDownloadedFile');
      final arguments = capturedCall?.arguments as Map<dynamic, dynamic>;
      expect(arguments['fileName'], 'classes.ics');
      expect(arguments['mimeType'], 'text/calendar');
      expect(arguments['bytes'], isA<Uint8List>());
      expect(
        utf8.decode(arguments['bytes'] as Uint8List),
        'BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n',
      );
      expect(result, isA<GakujoDownloadResult>());
      expect(result.location, '/picked/classes.ics');
    });
  });

  group('native file export', () {
    const channel = MethodChannel(
      'net.yoshida.morebettergakujo/downloads',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('sends JSON backup bytes and returns the picked name and location',
        () async {
      const json = '{"version":2,"favorites":[{"title":"情報リテラシー"}]}';
      const fileName = 'morebettergakujo-backup-20261024-0905.json';
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        capturedCall = call;
        return {
          'fileName': 'my-backup.json',
          'courseName': '',
          'location': '/picked/my-backup.json',
        };
      });

      final result = await exportGakujoFileWithNativePicker(
        bytes: Uint8List.fromList(utf8.encode(json)),
        fileName: fileName,
        mimeType: 'application/json',
      );

      expect(capturedCall?.method, 'exportDownloadedFile');
      final arguments = capturedCall?.arguments as Map<dynamic, dynamic>;
      expect(arguments['fileName'], fileName);
      expect(arguments['mimeType'], 'application/json');
      expect(arguments['bytes'], isA<Uint8List>());
      expect(arguments['bytes'], utf8.encode(json));
      expect(result.fileName, 'my-backup.json');
      expect(result.location, '/picked/my-backup.json');
    });

    test('preserves native picker cancellation for the download error helper',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'cancelled', message: '保存をキャンセルしました');
      });

      await expectLater(
        exportGakujoFileWithNativePicker(
          bytes: Uint8List.fromList(utf8.encode('{}')),
          fileName: 'backup.json',
          mimeType: 'application/json',
        ),
        throwsA(isA<PlatformException>().having(
          isCancelledDownloadError,
          'is cancelled',
          isTrue,
        )),
      );
    });

    test('preserves native export error codes and messages', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'export_failed', message: '保存先を開けませんでした');
      });

      await expectLater(
        exportGakujoFileWithNativePicker(
          bytes: Uint8List.fromList(utf8.encode('{}')),
          fileName: 'backup.json',
          mimeType: 'application/json',
        ),
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'export_failed')
            .having((error) => error.message, 'message', '保存先を開けませんでした')),
      );
    });
  });

  test('calendar operation gate rejects a concurrent operation', () {
    final gate = GakujoCalendarOperationGate();

    expect(gate.tryStart(), isTrue);
    expect(gate.isRunning, isTrue);
    expect(gate.tryStart(), isFalse);
    gate.finish();
    expect(gate.tryStart(), isTrue);
  });

  testWidgets('manual term dialog keeps its controllers until route closes',
      (tester) async {
    GakujoCalendarTermRange? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showGakujoCalendarTermRangeDialog(
                  context: context,
                  title: 'ターム期間を入力',
                  description: '期間を入力してください',
                  actionLabel: '書き出し',
                  initialDate: DateTime(2026, 6, 1),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).at(0), '2026/06/11');
    await tester.enterText(find.byType(TextField).at(1), '2026/08/08');
    await tester.tap(find.text('書き出し'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selected?.start, DateTime(2026, 6, 11));
    expect(selected?.end, DateTime(2026, 8, 8));
  });
}

List<GakujoCalendarCourse> _coursesForWeekdays(List<int> weekdays) {
  return [
    for (var index = 0; index < weekdays.length; index += 1)
      GakujoCalendarCourse(
        title: '授業${index + 1}',
        weekday: weekdays[index],
        period: (index % 5) + 1,
        courseCode: 'COURSE${index + 1}',
      ),
  ];
}

Future<Map<String, dynamic>> _evaluateAuthProbe(
  List<Map<String, String>> elements,
) async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _authProbeDomHarness,
        gakujoPortalAuthStateProbeScript,
        jsonEncode(elements),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _evaluateAuthenticatedSessionReset() async {
  final result = await Process.run(
      'node',
      [
        '-e',
        _authenticatedSessionResetHarness,
        gakujoAuthenticatedSessionResetScript,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
  expect(
    result.exitCode,
    0,
    reason: 'Node JavaScript evaluation failed: ${result.stderr}',
  );
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

const _authProbeDomHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const specs = JSON.parse(process.argv[2]);

class FakeElement {
  constructor(spec) {
    this.attributes = {...spec};
    this.innerText = spec.text || '';
    this.textContent = this.innerText;
    this.value = spec.value || '';
    this.ownerDocument = null;
  }
  getAttribute(name) { return this.attributes[name] ?? null; }
  getClientRects() { return this.attributes.display === 'none' ? [] : [{}]; }
}

const elements = specs.map((spec) => new FakeElement(spec));
const inputs = elements.filter((element) =>
  (element.getAttribute('tag') || '').toLowerCase() === 'input'
);
const document = {
  body: new FakeElement({tag: 'body', text: ''}),
  defaultView: null,
  querySelectorAll(selector) {
    if (selector === 'input') return inputs;
    if (selector === 'a, button, input, [role="button"], img, #logout') {
      return elements.filter((element) =>
        ['a', 'button', 'input', 'img'].includes(
          (element.getAttribute('tag') || '').toLowerCase()
        ) ||
        element.getAttribute('role') === 'button' ||
        element.getAttribute('id') === 'logout'
      );
    }
    return [];
  }
};
const window = {
  document,
  frames: [],
  getComputedStyle(element) {
    return {
      display: element.attributes.display || 'block',
      visibility: 'visible',
      opacity: '1'
    };
  }
};
window.window = window;
document.defaultView = window;
document.body.ownerDocument = document;
for (const element of elements) element.ownerDocument = document;

const output = vm.runInNewContext(generatedScript, {window, document});
process.stdout.write(output);
''';

const _authenticatedSessionResetHarness = r'''
const vm = require('node:vm');
const generatedScript = process.argv[1];
const values = new Map([
  ['MBG_LOGIN_AUTOFILL_ERROR:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_SUBMIT_COUNT:/login:key', '1'],
  ['MBG_LOGIN_AUTOFILL_LAST_CREDENTIAL:/login', 'key'],
  ['MBG_2FA_AUTOFILL_ERROR:/2fa:key', '1'],
  ['MBG_2FA_AUTOFILL_SUBMIT_COUNT:/2fa:key', '1'],
  ['UNRELATED', 'keep']
]);
const window = {
  __MBG_LOGIN_AUTOFILL_SUBMITTED_KEY: 'credentials',
  __MBG_2FA_AUTO_SUBMITTED_KEY: 'secret',
  sessionStorage: {
    get length() { return values.size; },
    key(index) { return Array.from(values.keys())[index] || null; },
    removeItem(key) { values.delete(key); }
  }
};
window.window = window;
vm.runInNewContext(generatedScript, {window});
process.stdout.write(JSON.stringify({
  hasLoginDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_LOGIN_AUTOFILL_SUBMITTED_KEY'),
  hasTwoFactorDocumentGuard:
    Object.prototype.hasOwnProperty.call(window, '__MBG_2FA_AUTO_SUBMITTED_KEY'),
  keys: Array.from(values.keys())
}));
''';
