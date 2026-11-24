enum GakujoQuickJumpDestination {
  grades,
  reports,
  messages,
  downloads,
  syllabus,
  schedule,
}

extension GakujoQuickJumpDestinationLabels on GakujoQuickJumpDestination {
  String get label {
    return switch (this) {
      GakujoQuickJumpDestination.grades => '成績',
      GakujoQuickJumpDestination.reports => 'レポート',
      GakujoQuickJumpDestination.messages => '連絡通知',
      GakujoQuickJumpDestination.downloads => 'ダウンロード',
      GakujoQuickJumpDestination.syllabus => 'シラバス',
      GakujoQuickJumpDestination.schedule => 'スケジュール',
    };
  }

  String get portalTabId {
    return switch (this) {
      GakujoQuickJumpDestination.grades => 'si',
      GakujoQuickJumpDestination.reports => 'en',
      GakujoQuickJumpDestination.messages => 'kj',
      GakujoQuickJumpDestination.downloads => 'sd',
      GakujoQuickJumpDestination.syllabus => 'sy',
      GakujoQuickJumpDestination.schedule => 'sch',
    };
  }

  String get portalUrl =>
      'https://gakujo.iess.niigata-u.ac.jp/campusweb/campusportal.do?page=main&tabId=$portalTabId';
}
