enum RadarNoticeFilter { all, solicitations, earlyLeads }

enum RadarResultSort { relevance, deadline }

/// A displayed notice and its index in the original search response.
///
/// Saving a notice uses [sourceIndex], even after filtering or sorting it.
class RadarResult {
  const RadarResult({required this.sourceIndex, required this.data});

  final int sourceIndex;
  final Map<String, dynamic> data;
}

/// Parses the API's date-only format without normalizing invalid dates.
DateTime? radarDeadlineDate(dynamic value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final year = int.parse(value.substring(0, 4));
  final month = int.parse(value.substring(5, 7));
  final day = int.parse(value.substring(8, 10));
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

List<RadarResult> filterRadarResults(
  List<Map<String, dynamic>> results, {
  String query = '',
  RadarNoticeFilter noticeFilter = RadarNoticeFilter.all,
  RadarResultSort sort = RadarResultSort.relevance,
  bool hidePastDeadlines = false,
  DateTime? now,
}) {
  final keyword = query.trim().toLowerCase();
  final utcNow = (now ?? DateTime.now()).toUtc();
  final today = DateTime.utc(utcNow.year, utcNow.month, utcNow.day);
  const searchableFields = [
    'title',
    'agency',
    'location',
    'summary',
    'matchReason',
  ];
  final matches = <RadarResult>[];

  for (var index = 0; index < results.length; index++) {
    final data = results[index];
    final noticeType = data['noticeType'];
    final matchesType = switch (noticeFilter) {
      RadarNoticeFilter.all => true,
      RadarNoticeFilter.solicitations => noticeType == 'solicitation',
      RadarNoticeFilter.earlyLeads =>
        noticeType == 'sources_sought' || noticeType == 'presolicitation',
    };
    if (!matchesType) continue;
    if (keyword.isNotEmpty &&
        !searchableFields.any(
          (field) =>
              (data[field] ?? '').toString().toLowerCase().contains(keyword),
        )) {
      continue;
    }
    final deadline = radarDeadlineDate(data['deadline']);
    if (hidePastDeadlines && deadline != null && deadline.isBefore(today)) {
      continue;
    }
    matches.add(RadarResult(sourceIndex: index, data: data));
  }

  if (sort == RadarResultSort.deadline) {
    matches.sort((a, b) {
      final left = radarDeadlineDate(a.data['deadline']);
      final right = radarDeadlineDate(b.data['deadline']);
      if (left == null && right != null) return 1;
      if (left != null && right == null) return -1;
      final order = left == null ? 0 : left.compareTo(right!);
      return order == 0 ? a.sourceIndex.compareTo(b.sourceIndex) : order;
    });
  }
  return matches;
}
