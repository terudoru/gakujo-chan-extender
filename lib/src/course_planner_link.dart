// The hosted planner and the app entry open the same browser storage origin.
const coursePlannerUrl = 'https://gakujo.terudoru.com/planner/';

Uri coursePlannerLink(
  String? syllabusUrl, {
  String baseUrl = coursePlannerUrl,
}) {
  final base = Uri.parse(baseUrl);
  final syllabus = syllabusUrl == null ? null : Uri.tryParse(syllabusUrl);
  if (syllabus == null ||
      syllabus.scheme != 'https' ||
      syllabus.host != 'syllabus.niigata-u.ac.jp') {
    return base;
  }
  final course = RegExp(
    r'^/syllabusHtml/(\d{4})/([A-Z0-9]{2})/\2_(\d{3}[A-Z][A-Z0-9]{4,5})_(?:ja_JP|en_US)\.html$',
  ).firstMatch(syllabus.path);
  if (course == null) return base;
  return base.replace(fragment: 'course=${course[1]}-${course[3]}');
}
