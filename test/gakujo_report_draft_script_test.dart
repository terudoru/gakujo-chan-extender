import 'dart:convert';
import 'dart:io';

import 'package:morebettergakujo_flutter/src/gakujo_report_draft_script.dart';
import 'package:test/test.dart';

void main() {
  test('failed storage keeps pending text and reports failure until retry',
      () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '未保存の本文', initialText: '未保存の本文', scenario: 'saveFailure');
    expect(result['failureStatus'], contains('保存できませんでした'));
    expect(result['dirtyAfterFailure'], isTrue);
    expect(result['pendingAfterFailure'], isTrue);
    expect(result['storedAfterRetry'], '未保存の本文');
  });

  test('failed deletion can be retried without claiming success', () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '削除対象', initialText: '削除対象', scenario: 'deleteFailure');
    expect(result['failureStatus'], contains('削除できませんでした'));
    expect(result['hasRetry'], isTrue);
    expect(result['remainingAfterRetry'], 0);
  });

  test('deleted drafts stay deleted through debounce and pagehide', () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '削除対象',
        initialText: '削除対象',
        scenario: 'deletePending',
        deferSaveTimer: true);
    expect(result['remainingAfterPageHide'], 0);
    expect(result['storedAfterNewInput'], '新しい入力');
  });

  test('failed removal of empty text does not restore the older draft',
      () async {
    final result = await _evaluateContentEditableDraft(
        initialHtml: '古い下書き', initialText: '古い下書き', scenario: 'clearFailure');
    expect(result['textAfterUpdate'], '');
    expect(result['dirtyAfterFailure'], isTrue);
    expect(result['failureStatus'], contains('保存できませんでした'));
  });

  test('builds report submission draft autosave script', () {
    final script = GakujoReportDraftScript.build();

    expect(script, contains('__MBG_REPORT_DRAFT_VERSION'));
    expect(script, contains('var version = 9;'));
    expect(script, contains('document.querySelectorAll("iframe,frame")'));
    expect(script, contains('mbg-report-draft:v2:'));
    expect(script, contains('localStorage'));
    expect(
        script,
        contains(
            'doc.querySelectorAll("textarea,input,select,[contenteditable]")'));
    expect(script, contains('hasDraftWorthyField'));
    expect(script, contains('function stablePageTextForKey'));
    expect(script, contains('残り約'));
    expect(script, contains('前回ログイン日時'));
    expect(script, contains('レポート・小テスト・アンケート提出'));
    expect(script, contains('レポート提出(?!日)'));
    expect(script, contains('アンケート(?:提出(?!期限)|回答)'));
    expect(script, contains('下書きを保存しました'));
    expect(script, contains('保存済みの下書きを復元しました'));
    expect(script, contains('下書きを削除'));
    expect(script, contains('function removeStatus'));
    expect(script, contains('beforeunload'));
    expect(script, contains('pagehide'));
    expect(script, contains('visibilitychange'));
    expect(script, contains('function currentDraftContext'));
    expect(script, contains('#mbg-report-draft-status'));
    expect(script, contains('form.addEventListener'));
    expect(script, isNot(contains('field.innerHTML')));
  });

  test(
      'stores and restores contenteditable display text without executing HTML',
      () async {
    const payload = '<img src=x onerror="globalThis.xssExecuted=true">安全な本文';
    final result = await _evaluateContentEditableDraft(
      initialHtml: payload,
      initialText: '安全な本文',
    );

    expect(result['storedValue'], '安全な本文');
    expect(result['restoredText'], '安全な本文');
    expect(result['xssExecutionCount'], 0);
  });

  test('restores legacy HTML draft values as literal text', () async {
    const legacyValue = '<img src=x onerror="globalThis.xssExecuted=true">旧下書き';
    final result = await _evaluateContentEditableDraft(
      initialHtml: '保存形式を作るための本文',
      initialText: '保存形式を作るための本文',
      legacyValue: legacyValue,
    );

    expect(result['restoredText'], legacyValue);
    expect(result['xssExecutionCount'], 0);
  });

  test('migrates a v0.70.x draft when the reopened form counter reads 0',
      () async {
    final result = await _evaluateDraftScenario('legacyMigrationReopenedEmpty');
    expect(result['restored'], ['Legacy answer', 'Second legacy answer']);
    expect(result['legacyRemoved'], isTrue);
  });

  test('migrates v0.70.x drafts with their original page and field keys',
      () async {
    final result = await _evaluateDraftScenario('legacyMigration');
    expect(result['restored'], ['Legacy answer', 'Second legacy answer']);
    expect(result['key'], startsWith('mbg-report-draft:v2:'));
    expect(result['legacyRemoved'], isTrue);
    expect(result['savedAtPreserved'], isTrue);
    expect(result['restoredAgain'], result['restored']);
    expect(result['conflictingValue'], 'Server answer');
    expect(result['replacementVisible'], isTrue);
    expect(result['storedConflict'], 'Legacy answer');
    expect(result['afterReplace'], 'Legacy answer');
  });

  test('restores multiline contenteditable drafts with visible line breaks',
      () async {
    const text = '一段落目\n二段落目';
    final result = await _evaluateContentEditableDraft(
      initialHtml: '<p>一段落目</p><p>二段落目</p>',
      initialText: text,
    );

    expect(result['storedValue'], text);
    expect(result['restoredText'], text);
    expect(result['restoredHtml'], '一段落目<br>二段落目');
    expect(result['xssExecutionCount'], 0);
  });

  test('restores a field replaced in the same document after timeout',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: 'タイムアウト前の入力',
      initialText: 'タイムアウト前の入力',
      replaceFieldInSameDocument: true,
    );

    expect(result['sameDocumentRestoredText'], 'タイムアウト前の入力');
  });

  test('saves immediately when the page is hidden before debounce completes',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: '画面遷移直前の入力',
      initialText: '画面遷移直前の入力',
      deferSaveTimer: true,
      firePageHide: true,
    );

    expect(result['storedValue'], '画面遷移直前の入力');
  });

  test('keeps the pending value when timeout replaces the form before unload',
      () async {
    final result = await _evaluateContentEditableDraft(
      initialHtml: 'フォーム消失直前の入力',
      initialText: 'フォーム消失直前の入力',
      deferSaveTimer: true,
      dropFieldBeforePageHide: true,
      firePageHide: true,
    );

    expect(result['storedValue'], 'フォーム消失直前の入力');
  });

  for (final kind in ['textarea', 'text', 'checkbox', 'radio', 'select']) {
    for (final event in ['pagehide', 'beforeunload', 'visibilitychange']) {
      test('saves $kind edited before binding on $event', () async {
        final result = await _evaluateDraft({
          'scenario': 'beforeBinding',
          'kind': kind,
          'edited': true,
          'event': event,
        });
        expect(result['bound'], isTrue);
        expect(result['touched'], isTrue);
        expect(result['dirty'], isTrue);
        expect(result['countBeforeHide'], 0);
        expect(result['count'], 1);
        expect(result['savedValue'], result['expectedValue']);
      });
    }
  }

  for (final kind in [
    'textarea',
    'text',
    'checkbox',
    'radio',
    'select',
    'contenteditable',
  ]) {
    test('does not save untouched prefilled $kind on pagehide', () async {
      final result = await _evaluateDraft({
        'scenario': 'beforeBinding',
        'kind': kind,
        'edited': false,
        'event': 'pagehide',
      });
      expect(result['bound'], isTrue);
      expect(result['touched'], isFalse);
      expect(result['dirty'], isFalse);
      expect(result['count'], 0);
    });
  }

  test('counter changes save one draft and restore the latest text', () async {
    final result = await _evaluateDraftScenario('counterLatest');
    expect(result['count'], 1);
    expect(result['restoredText'], '文字数が変わった後の最新の本文');
    expect(result['fieldKey'], 'textarea||gakuComment|0');
    expect(result['savedStatus'], matches(r'下書きを保存しました（\d{2}:\d{2}）'));
    expect(result['restoredStatus'],
        matches(r'保存済みの下書きを復元しました（\d+/\d+ \d{2}:\d{2} 保存）'));
  });

  test('fresh and nonzero counter pages have identical v2 keys', () async {
    final result = await _evaluateDraftScenario('counterKeys');
    expect(result['keys'], everyElement(result['keys'][0]));
    expect(result['elementKeys'], everyElement(result['elementKeys'][0]));
    expect(result['keys'][0], startsWith('mbg-report-draft:v2:'));
    expect(result['anonymousKeys'], everyElement(result['anonymousKeys'][0]));
    expect(result['differentAssignmentKey'], isNot(result['keys'][0]));
  });

  test('document key is cached until fields are replaced', () async {
    final result = await _evaluateDraftScenario('keyCache');
    expect(result['cachedKey'], result['initialKey']);
    expect(result['replacementKey'], isNot(result['initialKey']));
  });

  test('replaces server choices and dispatches input and change', () async {
    final result = await _evaluateDraftScenario('choicesDefault');
    expect(result['radio'], [false, true]);
    expect(result['checkbox'], [false, true]);
    expect(result['select'], ['b']);
    expect(result['multiple'], ['b', 'c']);
    expect(
        result['kinds'], ['radio', 'checkbox', 'checkbox', 'select', 'select']);
    expect(result['eventsDispatched'], isTrue);
    expect(result['eventsAfterSecondUpdate'], result['eventsAfterRestore']);
    expect(result['pendingAfterRestore'], isFalse);
    expect(result['restoredSavedAt'], result['originalSavedAt']);
    expect(result['touchedAfterRestore'], isFalse);
    expect(result['dirtyAfterRestore'], isFalse);
    expect(result['unchangedAfterHide'], isTrue);
  });

  test('restored text stays untouched through rebinding and pagehide',
      () async {
    final result = await _evaluateDraftScenario('restoredUntouched');
    expect(result['restoredText'], '保存済みの本文');
    expect(result['touched'], isFalse);
    expect(result['dirty'], isFalse);
    expect(result['unchangedAfterHide'], isTrue);
  });

  test('does not restore choices touched even if saved back at defaults',
      () async {
    final result = await _evaluateDraftScenario('choicesTouched');
    expect(result['radio'], [true, false]);
    expect(result['checkbox'], [true, false]);
    expect(result['select'], ['a']);
    expect(result['multiple'], ['a']);
  });

  test('does not restore choices changed from defaults without events',
      () async {
    final result = await _evaluateDraftScenario('choicesNonDefault');
    expect(result['radio'], [false, true]);
    expect(result['checkbox'], [false, true]);
    expect(result['select'], ['c']);
    expect(result['multiple'], ['c']);
    expect(result['eventsAfterRestore'], 0);
  });

  test('preserves unchecked and empty choice answers', () async {
    final result = await _evaluateDraftScenario('choicesEmpty');
    expect(result['radio'], [false, false]);
    expect(result['checkbox'], [false, false]);
    expect(result['select'], isEmpty);
    expect(result['multiple'], isEmpty);
    expect(result['count'], 1);
  });

  test('checkboxes match by name and value after reordering', () async {
    final result = await _evaluateDraftScenario('choicesReordered');
    expect(result['sameKey'], isTrue);
    expect(result['checksByValue'], {'a': false, 'b': true});
  });

  test('choice-only quizzes are draft-worthy and login forms are ignored',
      () async {
    final result = await _evaluateDraftScenario('choiceOnly');
    expect(result['quizBound'], isTrue);
    expect(result['unrelatedBound'], isFalse);
    expect(result['loginBound'], isFalse);
    expect(result['count'], 1);
  });

  test('the report list page-size select is not treated as an answer',
      () async {
    final result = await _evaluateDraftScenario('reportList');
    expect(result['listBound'], isFalse);
    expect(result['count'], 0);
  });

  test('conflicting text requires the replacement button', () async {
    final result = await _evaluateDraftScenario('conflict');
    expect(result['beforeReplace'], 'サーバー側の一時保存');
    expect(
        result['beforeStatus'], matches(r'保存済みの下書きがあります（\d+/\d+ \d{2}:\d{2}）'));
    expect(result['storedAfterPageHide'], '端末の下書き');
    expect(result['afterReplace'], '端末の下書き');
    expect(result['afterStatus'], contains('保存済みの下書きを復元しました'));
    expect(result['replaceHidden'], isTrue);
    expect(result['events'], containsAll(['input', 'change']));
  });

  test('editing another field preserves an unresolved draft and replacement',
      () async {
    final result = await _evaluateDraftScenario('conflictOtherField');
    expect(result['beforeEdit'], 'server old');
    expect(result['storedQ1'], 'local newer');
    expect(result['storedQ2'], 'another answer');
    expect(result['replaceVisible'], isTrue);
    expect(result['afterReplace'], 'local newer');
    expect(result['afterOwnEdit'], 'student edit');
  });

  test('server choices conflict while implicit defaults restore automatically',
      () async {
    final result = await _evaluateDraftScenario('choiceServerAnswers');
    final server = result['server'] as Map<String, dynamic>;
    expect(server['before']['radio'], [true, false]);
    expect(server['before']['checkbox'], [true, true]);
    expect(server['before']['select'], ['a']);
    expect(server['before']['multiple'], ['a']);
    expect(server['replaceVisible'], isTrue);
    expect(server['unchangedAfterHide'], isTrue);
    for (final state in [server['after'], result['implicit']['before']]) {
      expect(state['radio'], [false, true]);
      expect(state['checkbox'], [false, true]);
      expect(state['select'], ['b']);
      expect(state['multiple'], ['b', 'c']);
    }
    expect(result['implicit']['replaceVisible'], isFalse);
    expect(result['implicit']['unchangedAfterHide'], isTrue);
  });

  for (final event in ['ArrowLeft', 'Ctrl+C', 'change']) {
    test('unchanged $event preserves the newer draft and replacement prompt',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'conflictNavigation',
        'event': event,
      });
      expect(result['storedUnchanged'], isTrue);
      expect(result['replaceVisible'], isTrue);
      expect(result['pending'], isFalse);
      expect(result['touched'], isFalse);
      expect(result['storedAfterEdit'], '実際の編集');
      if (event == 'Ctrl+C') {
        expect(result['inputSavedUnchangedValue'], isTrue);
      }
    });
  }

  for (final event in ['pagehide', 'beforeunload', 'visibilitychange']) {
    test('restoring a checkbox preserves a conflicting draft on $event',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'conflictWithCheckbox',
        'event': event,
      });
      expect(result['text'], 'サーバー側の一時保存');
      expect(result['checkbox'], isTrue);
      expect(result['touched'], isFalse);
      expect(result['dirty'], isFalse);
      expect(result['replaceVisible'], isTrue);
      expect(result['unchangedAfterHide'], isTrue);
      expect(result['storedAfterInput'], '実際の編集');
    });
  }

  for (final multiple in [false, true]) {
    test('skips a select with a missing saved option (multiple: $multiple)',
        () async {
      final result = await _evaluateDraft({
        'scenario': 'missingSelectOption',
        'multiple': multiple,
      });
      expect(result['selection'], ['a']);
      expect(result['events'], isEmpty);
      expect(result['status'], isNot(contains('復元しました')));
      expect(result['unchangedAfterHide'], isTrue);
    });
  }

  test('v2 heading joins course and assignment table values', () async {
    final result = await _evaluateDraftScenario('heading');
    expect(result['heading'], '263T0506 プログラミング基礎Ⅰ / レポート２');
    expect(result['fallback'], 'レポート提出');
  });

  test('lists v1 and v2 drafts from top and main frame newest first', () async {
    final result = await _evaluateDraftScenario('list');
    final entries = result['entries'] as List;
    expect(entries.map((entry) => entry['version']), [2, 1]);
    expect(entries[0]['heading'], '科目 / レポート２');
    expect(entries[0]['preview'], 'あ' * 120);
    expect(entries[0]['text'], '${'あ' * 130}\n\n次の回答');
    expect(entries[1]['heading'], '旧タイトル');
    expect(entries[1]['text'], '<b>旧本文</b>');
    expect(result['expiredAndInvalidRemoved'], isTrue);
    expect(result['unrelatedRetained'], isTrue);
    expect(result['crossOriginCount'], 2);
  });

  test('deletes only the given key and cancels its pending save', () async {
    final result = await _evaluateDraftScenario('delete');
    expect(result['deleted'], isTrue);
    expect(result['targetRemovedEverywhere'], isTrue);
    expect(result['otherKeysRetained'], isTrue);
    expect(result['pendingCancelled'], isTrue);
    expect(result['remainingAfterPageHide'], isFalse);
    expect(result['failedDelete'], isFalse);
    expect(result['retainedAfterFailure'], isTrue);
  });

  test('binding cleans expired and malformed v1 and v2 drafts', () async {
    final result = await _evaluateDraftScenario('cleanup');
    expect(result['remainingKeys'], ['mbg-report-draft:v1:valid', 'other-key']);
  });
}

Future<Map<String, dynamic>> _evaluateContentEditableDraft({
  required String initialHtml,
  required String initialText,
  String? legacyValue,
  bool replaceFieldInSameDocument = false,
  bool deferSaveTimer = false,
  bool firePageHide = false,
  bool dropFieldBeforePageHide = false,
  String? scenario,
}) async {
  return _evaluateDraft({
    'initialHtml': initialHtml,
    'initialText': initialText,
    'legacyValue': ?legacyValue,
    'replaceFieldInSameDocument': replaceFieldInSameDocument,
    'deferSaveTimer': deferSaveTimer,
    'firePageHide': firePageHide,
    'dropFieldBeforePageHide': dropFieldBeforePageHide,
    'scenario': scenario,
  });
}

Future<Map<String, dynamic>> _evaluateDraftScenario(String scenario) {
  return _evaluateDraft({'scenario': scenario});
}

Future<Map<String, dynamic>> _evaluateDraft(Map<String, dynamic> spec) async {
  final directory =
      await Directory.systemTemp.createTemp('gakujo-report-draft-');
  try {
    final input = File('${directory.path}/input.json');
    await input.writeAsString(jsonEncode({
      'generatedScript': GakujoReportDraftScript.build(),
      'spec': spec,
      'listScript': GakujoReportDraftScript.buildList(),
      'deleteScript': GakujoReportDraftScript.buildDelete(
          'mbg-report-draft:v2:delete"\\key'),
    }));
    final result = await Process.run(
        'node', ['test/support/report_draft_dom_harness.cts', input.path],
        stdoutEncoding: utf8, stderrEncoding: utf8);
    expect(
      result.exitCode,
      0,
      reason: 'Node JavaScript evaluation failed: ${result.stderr}',
    );
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  } finally {
    await directory.delete(recursive: true);
  }
}
