import 'generated/message_reader.g.dart';
import 'generated/message_reader_teardown.g.dart';

class GakujoMessageReaderScript {
  const GakujoMessageReaderScript._();

  static String build() {
    return gakujoMessageReaderJs;
  }

  static String buildTeardown() {
    return gakujoMessageReaderTeardownJs;
  }
}
