import 'package:flutter_test/flutter_test.dart';
import 'package:morebettergakujo_flutter/src/gakujo_activity_store.dart';
import 'package:morebettergakujo_flutter/src/gakujo_starred_message_query.dart';

GakujoStarredMessage entry(
  String id,
  String title,
  String posted, {
  String sender = '',
  String body = '',
  int starDay = 1,
}) => GakujoStarredMessage(
  keijitype: '1',
  genrecd: '1',
  seqNo: id,
  title: title,
  postedAt: posted,
  sender: sender,
  body: body,
  starredAt: DateTime(2026, 10, starDay),
);

void main() {
  final entries = [
    entry(
      '1',
      'Physics',
      '2026/10/02 09:30',
      sender: 'Teacher',
      body: 'Quantum',
    ),
    entry('2', 'Languages', '2026年10月10日', body: 'Español', starDay: 2),
    entry('3', 'Unknown', '', starDay: 3),
    entry('4', 'Bad date', '2026/99/01', starDay: 4),
  ];
  test('searches multiple saved fields case-insensitively', () {
    expect(
      queryStarredMessages(
        entries,
        'TEACHER quantum',
        GakujoStarredMessageSort.title,
      ).map((e) => e.seqNo),
      ['1'],
    );
    expect(
      queryStarredMessages(
        entries,
        'español',
        GakujoStarredMessageSort.title,
      ).map((e) => e.seqNo),
      ['2'],
    );
    expect(
      queryStarredMessages(entries, 'missing', GakujoStarredMessageSort.title),
      isEmpty,
    );
  });
  test('sorts parsed dates with missing or invalid dates last', () {
    expect(
      queryStarredMessages(
        entries,
        '',
        GakujoStarredMessageSort.postedNewest,
      ).map((e) => e.seqNo),
      ['2', '1', '3', '4'],
    );
    expect(
      queryStarredMessages(
        entries,
        '',
        GakujoStarredMessageSort.postedOldest,
      ).map((e) => e.seqNo),
      ['1', '2', '3', '4'],
    );
    expect(
      queryStarredMessages(
        entries,
        '',
        GakujoStarredMessageSort.starredNewest,
      ).first.seqNo,
      '4',
    );
    expect(entries.first.seqNo, '1', reason: 'the saved order is not changed');
  });

  for (final whitespace in [
    '\u00A0', '\u202F', '\u2003', '\u3000', '\u0085', '\t', '\r\n'
  ]) {
    test('sorts normalized posting dates with whitespace ${whitespace.codeUnits}',
        () {
      final entries = [
        entry('0', 'Unknown', ''),
        entry('1', 'Midnight', '2026/10/02'),
        entry('2', 'Earlier', '2026/10/02 09:29'),
        entry('3', 'Unicode space', '2026/10/02${whitespace}09:30'),
        entry('4', 'Full-width', '２０２６／１０／０２$whitespace０９：３０：１５'),
        entry('5', 'Later', '2026/10/02 09:31'),
        entry('6', 'Bad date', '２０２６／９９／０１'),
      ];
      expect(
        queryStarredMessages(entries, '', GakujoStarredMessageSort.postedOldest)
            .map((e) => e.seqNo),
        ['1', '2', '3', '4', '5', '0', '6'],
      );
      expect(
        queryStarredMessages(entries, '', GakujoStarredMessageSort.postedNewest)
            .map((e) => e.seqNo),
        ['5', '4', '3', '2', '1', '0', '6'],
      );
    });
  }
}
