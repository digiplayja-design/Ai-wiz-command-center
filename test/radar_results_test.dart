import 'package:ai_wiz_command_center/contract_radar/radar_results.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> notice({
  String title = 'Notice',
  String type = 'solicitation',
  dynamic deadline,
  String agency = '',
  String location = '',
  String summary = '',
  String matchReason = '',
}) => {
  'title': title,
  'noticeType': type,
  'deadline': deadline,
  'agency': agency,
  'location': location,
  'summary': summary,
  'matchReason': matchReason,
};

List<int> indices(List<RadarResult> results) =>
    results.map((result) => result.sourceIndex).toList();

void main() {
  group('radarDeadlineDate', () {
    test('returns a UTC date and accepts valid leap days', () {
      expect(radarDeadlineDate('2026-10-03'), DateTime.utc(2026, 10, 3));
      expect(radarDeadlineDate('2024-02-29'), DateTime.utc(2024, 2, 29));
      expect(radarDeadlineDate('2000-02-29')?.isUtc, isTrue);
    });

    test('rejects impossible dates rather than rolling into another month', () {
      for (final value in [
        '2026-02-29',
        '1900-02-29',
        '2026-04-31',
        '2026-00-01',
        '2026-13-01',
        '2026-10-00',
        '2026-10-32',
        '0000-01-01',
      ]) {
        expect(radarDeadlineDate(value), isNull, reason: value);
      }
    });

    test('only accepts date-only strings from the API', () {
      for (final value in <dynamic>[
        null,
        '',
        20261003,
        DateTime.utc(2026, 10, 3),
        '2026-1-03',
        '2026-10-3',
        '2026/10/03',
        '2026-10-03T12:00:00Z',
        ' 2026-10-03 ',
        'unknown',
      ]) {
        expect(radarDeadlineDate(value), isNull, reason: '$value');
      }
    });
  });

  group('filterRadarResults', () {
    test('default ordering and data remain untouched', () {
      final results = [notice(title: 'Second'), notice(title: 'First')];
      final displayed = filterRadarResults(results);
      expect(indices(displayed), [0, 1]);
      expect(identical(displayed[0].data, results[0]), isTrue);
      expect(results.map((row) => row['title']), ['Second', 'First']);
      expect(filterRadarResults([]), isEmpty);
    });

    test('keyword matches every visible descriptive field, ignoring case', () {
      final results = [
        notice(title: 'Office CLEANING'),
        notice(agency: 'Cleaning Authority'),
        notice(location: 'Cleaning District'),
        notice(summary: 'Includes cleaning services'),
        notice(matchReason: 'Your cleaning experience fits'),
        notice(title: 'Road resurfacing'),
      ];
      expect(indices(filterRadarResults(results, query: '  cLeAnInG  ')), [
        0,
        1,
        2,
        3,
        4,
      ]);
      expect(indices(filterRadarResults(results, query: '  ')), [
        0,
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(filterRadarResults(results, query: 'unmatched'), isEmpty);
    });

    test('missing fields are safe and URLs do not match the keyword', () {
      final results = <Map<String, dynamic>>[
        {},
        {'title': null, 'summary': null, 'sourceUrl': 'https://cleaning.gov'},
      ];
      expect(filterRadarResults(results, query: 'cleaning'), isEmpty);
      expect(indices(filterRadarResults(results)), [0, 1]);
    });

    test('separates bid notices from both kinds of early leads', () {
      final results = [
        notice(type: 'sources_sought'),
        notice(type: 'solicitation'),
        notice(type: 'presolicitation'),
        notice(type: 'unknown'),
      ];
      expect(
        indices(
          filterRadarResults(
            results,
            noticeFilter: RadarNoticeFilter.solicitations,
          ),
        ),
        [1],
      );
      expect(
        indices(
          filterRadarResults(
            results,
            noticeFilter: RadarNoticeFilter.earlyLeads,
          ),
        ),
        [0, 2],
      );
      expect(indices(filterRadarResults(results)), [0, 1, 2, 3]);
    });

    test(
      'sorts actual dates first with stable ties and unknown dates last',
      () {
        final results = [
          notice(deadline: null),
          notice(deadline: '2027-01-01'),
          notice(deadline: '2026-02-30'),
          notice(deadline: '2026-10-03'),
          notice(deadline: '2026-10-03'),
          notice(deadline: ''),
        ];
        expect(
          indices(filterRadarResults(results, sort: RadarResultSort.deadline)),
          [3, 4, 1, 0, 2, 5],
        );
        expect(results[0]['deadline'], isNull);
        expect(results[1]['deadline'], '2027-01-01');
      },
    );

    test('hides only dates before today, keeping today and unknown dates', () {
      final results = [
        notice(deadline: '2026-10-02'),
        notice(deadline: '2026-10-03'),
        notice(deadline: '2026-10-04'),
        notice(deadline: null),
        notice(deadline: '2026-02-30'),
      ];
      expect(
        indices(
          filterRadarResults(
            results,
            hidePastDeadlines: true,
            now: DateTime.utc(2026, 10, 3, 23, 59),
          ),
        ),
        [1, 2, 3, 4],
      );
    });

    test(
      'compares deadlines to the UTC calendar day, not the supplied offset',
      () {
        final results = [
          notice(deadline: '2026-10-02'),
          notice(deadline: '2026-10-03'),
        ];
        expect(
          indices(
            filterRadarResults(
              results,
              hidePastDeadlines: true,
              now: DateTime.parse('2026-10-02T23:30:00-04:00'),
            ),
          ),
          [1],
        );
      },
    );

    test(
      'combined controls retain server indices for saving the right notice',
      () {
        final results = [
          notice(title: 'Cleaning', deadline: '2026-09-30'),
          notice(
            title: 'Cleaning',
            type: 'sources_sought',
            deadline: '2026-10-04',
          ),
          notice(title: 'Cleaning', deadline: '2026-10-20'),
          notice(title: 'Security', deadline: '2026-10-05'),
          notice(title: 'Cleaning', deadline: '2026-10-10'),
        ];
        final displayed = filterRadarResults(
          results,
          query: 'cleaning',
          noticeFilter: RadarNoticeFilter.solicitations,
          sort: RadarResultSort.deadline,
          hidePastDeadlines: true,
          now: DateTime.utc(2026, 10, 3),
        );
        expect(indices(displayed), [4, 2]);
        expect(identical(displayed.first.data, results[4]), isTrue);
      },
    );
  });
}
