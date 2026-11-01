import 'generated/message_list_fetch.g.dart';

/// Fetches the newest rows of the 連絡通知 未読一覧 without leaving the
/// current page, in the shape the page scan reads them (title, link and row
/// text), so keyword notifications arrive without opening 連絡通知. Status
/// is "missing" when Gakujo answers with something else, such as its login
/// page.
const gakujoMessageListFetchScript = gakujoMessageListFetchJs;
