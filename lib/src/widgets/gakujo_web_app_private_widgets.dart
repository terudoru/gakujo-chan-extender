part of '../gakujo_web_app.dart';

class _AmbiguousCalendarCourseTermSelector extends StatelessWidget {
  const _AmbiguousCalendarCourseTermSelector({
    required this.course,
    required this.selectedTerms,
    required this.onChanged,
  });

  final GakujoCalendarCourse course;
  final Set<int> selectedTerms;
  final void Function(int term, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final title = GakujoCalendarExport.displayTitleForCourse(course);
    final details = [
      if (course.courseCode.trim().isNotEmpty) '開講番号: ${course.courseCode}',
      '${_weekdayLabel(course.weekday)}曜 ${course.period}限',
      if (GakujoCalendarExport.displayLocationForCourse(course).isNotEmpty)
        GakujoCalendarExport.displayLocationForCourse(course),
    ].join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(details),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var term = 1; term <= 4; term += 1)
              FilterChip(
                label: Text('第$termターム'),
                selected: selectedTerms.contains(term),
                onSelected: (selected) => onChanged(term, selected),
              ),
          ],
        ),
      ],
    );
  }

  static String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => '月',
      DateTime.tuesday => '火',
      DateTime.wednesday => '水',
      DateTime.thursday => '木',
      DateTime.friday => '金',
      DateTime.saturday => '土',
      DateTime.sunday => '日',
      _ => '曜日未定',
    };
  }
}

class _DataCountTile extends StatelessWidget {
  const _DataCountTile({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text('$count件'),
    );
  }
}
