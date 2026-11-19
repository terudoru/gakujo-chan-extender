const coursePlannerUrl = 'https://gakujo.terudoru.com/planner/';
const coursePlannerRegistrationUrl =
    'https://gakujo.iess.niigata-u.ac.jp/campusweb/campussquare.do?_flowId=RSW0001000-flow';

String coursePlannerBase(String configured, {required bool debug}) {
  final uri = Uri.tryParse(configured);
  if (debug &&
      uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    return uri.path.isEmpty
        ? uri.replace(path: '/').toString()
        : uri.toString();
  }
  return coursePlannerUrl;
}

bool isCoursePlannerDocument(Uri uri, Uri target) =>
    uri.hasAuthority &&
    uri.scheme == target.scheme &&
    uri.userInfo.isEmpty &&
    uri.host == target.host &&
    uri.port == target.port &&
    uri.path == target.path &&
    !uri.hasQuery;

bool isCoursePlannerPublicLink(Uri uri) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    (uri.host.endsWith('.niigata-u.ac.jp') ||
        uri.host == 'niigata-u.ac.jp' ||
        uri.host == 'public1.legalcrud.com');

Uri coursePlannerLink(
  String? syllabusUrl, {
  String baseUrl = coursePlannerUrl,
}) {
  final base = Uri.parse(baseUrl);
  final syllabus = syllabusUrl == null ? null : Uri.tryParse(syllabusUrl);
  if (syllabus == null ||
      syllabus.scheme != 'https' ||
      syllabus.userInfo.isNotEmpty ||
      syllabus.port != 443 ||
      syllabus.host != 'syllabus.niigata-u.ac.jp') {
    return base;
  }
  final course = RegExp(
    r'^/syllabusHtml/(\d{4})/([A-Z0-9]{2})/\2_(\d{3}[A-Z][A-Z0-9]{4,5})_(?:ja_JP|en_US)\.html$',
  ).firstMatch(syllabus.path);
  if (course == null) return base;
  return base.replace(fragment: 'course=${course[1]}-${course[3]}');
}
