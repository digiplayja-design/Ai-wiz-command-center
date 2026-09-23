import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_format.dart' show metaCount, metaMoney;

Map<String, dynamic> googlePerformanceReport(
  Map<String, dynamic> report,
  Map<String, dynamic> connection,
  int days,
) {
  Never invalid() => throw const FunnelException(
    'Google performance data could not be verified. Check your connection and try again.',
  );
  DateTime day(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      invalid();
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    if (date == null || date.toIso8601String().substring(0, 10) != value) {
      invalid();
    }
    return date;
  }

  BigInt spend(dynamic value) {
    if (value is! String || !RegExp(r'^\d{1,13}\.\d{2,6}$').hasMatch(value)) {
      invalid();
    }
    final parts = value.split('.');
    final amount =
        BigInt.parse(parts[0]) * BigInt.from(1000000) +
        BigInt.parse(parts[1].padRight(6, '0'));
    if (amount > BigInt.parse('1000000000000000000')) invalid();
    return amount;
  }

  int count(dynamic value) {
    if (value is! int || value < 0 || value > 9007199254740991) invalid();
    return value;
  }

  final account = report['account'],
      range = report['range'],
      rows = report['rows'],
      totals = report['totals'];
  if (report['source'] != 'google_ads' ||
      report['scope'] != 'account' ||
      report['connection_version'] != connection['version'] ||
      report['root_id'] != connection['root_id'] ||
      account is! Map ||
      account['id'] != connection['selected_account'] ||
      account['name'] is! String ||
      account['name'].isEmpty ||
      account['name'].length > 200 ||
      account['currency'] is! String ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(account['currency']) ||
      account['timezone'] is! String ||
      account['timezone'].isEmpty ||
      account['timezone'].length > 100 ||
      account['test_account'] is! bool ||
      range is! Map ||
      range['days'] != days ||
      rows is! List ||
      rows.length > days ||
      report['reported_days'] != rows.length ||
      totals is! Map ||
      report['fetched_at'] is! String ||
      DateTime.tryParse(report['fetched_at']) == null) {
    invalid();
  }
  final from = day(range['from']), to = day(range['to']);
  if (to.difference(from).inDays + 1 != days) invalid();
  var totalSpend = BigInt.zero, impressions = BigInt.zero, clicks = BigInt.zero;
  final dates = <String>{};
  DateTime? previous;
  for (final row in rows) {
    if (row is! Map) invalid();
    final date = day(row['date']);
    if (date.isBefore(from) ||
        date.isAfter(to) ||
        !dates.add(row['date']) ||
        (previous != null && date.isAfter(previous))) {
      invalid();
    }
    previous = date;
    totalSpend += spend(row['spend']);
    impressions += BigInt.from(count(row['impressions']));
    clicks += BigInt.from(count(row['clicks']));
  }
  if (spend(totals['spend']) != totalSpend ||
      BigInt.from(count(totals['impressions'])) != impressions ||
      BigInt.from(count(totals['clicks'])) != clicks) {
    invalid();
  }
  return report;
}

class FunnelGooglePerformance extends StatefulWidget {
  const FunnelGooglePerformance({
    super.key,
    required this.client,
    required this.connection,
    required this.available,
  });
  final FunnelClient client;
  final Map<String, dynamic>? connection;
  final bool available;
  @override
  State<FunnelGooglePerformance> createState() =>
      _FunnelGooglePerformanceState();
}

class _FunnelGooglePerformanceState extends State<FunnelGooglePerformance> {
  int _days = 7, _generation = 0;
  bool _busy = false, _denied = false;
  Map<String, dynamic>? _report;
  String? _error;
  String get _binding =>
      '${widget.connection?['version']}:${widget.connection?['root_id']}:${widget.connection?['login_customer_id']}:${widget.connection?['selected_account']}';
  bool get _ready =>
      widget.available &&
      !_denied &&
      widget.connection?['selected_account'] != null;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
  }

  void _clear() {
    _generation++;
    _report = null;
    _error = null;
    _busy = false;
  }

  void _deny() {
    if (mounted) {
      setState(() {
        _denied = true;
        _clear();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FunnelGooglePerformance oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.connection;
    final oldBinding =
        '${old?['version']}:${old?['root_id']}:${old?['login_customer_id']}:${old?['selected_account']}';
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
      _denied = false;
      _clear();
    }
    if (oldBinding != _binding || oldWidget.available != widget.available) {
      _clear();
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_ready || _busy) return;
    final generation = ++_generation, binding = _binding, days = _days;
    final connection = Map<String, dynamic>.from(widget.connection!);
    setState(() {
      _busy = true;
      _report = null;
      _error = null;
    });
    bool current() =>
        mounted && generation == _generation && binding == _binding && _ready;
    try {
      final r = await widget.client.request(
        'GET',
        '/google-ads/performance',
        query: {
          'days': '$days',
          'version': '${connection['version']}',
          'root_id': '${connection['root_id']}',
          'account_id': '${connection['selected_account']}',
        },
      );
      if (!current()) return;
      final checked = googlePerformanceReport(r, connection, days);
      setState(() => _report = checked);
    } catch (e) {
      if (current()) {
        setState(() {
          _report = null;
          _error = e is FunnelException
              ? e.message
              : 'Google performance could not be loaded. Try again.';
        });
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  Widget _caption(String text) =>
      Text(text, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  Widget _gap([double height = 12]) => SizedBox(height: height);
  Widget _metric(String label, String value, double width) => Container(
    width: width,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WfStyle.background,
      border: Border.all(color: WfStyle.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _caption(label),
        _gap(8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: WfStyle.cyan,
          ),
        ),
      ],
    ),
  );
  Widget _results(Map<String, dynamic> r) {
    final account = r['account'] as Map,
        rows = r['rows'] as List,
        totals = r['totals'] as Map,
        currency = '${account['currency']}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gap(18),
        SelectableText(
          '${account['name']}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        _gap(6),
        _caption('${account['id']} · ${account['timezone']}'),
        _gap(6),
        _caption(
          '${r['range']['from']} – ${r['range']['to']} · completed account-calendar days',
        ),
        _gap(6),
        _caption(
          'Retrieved: ${DateTime.parse(r['fetched_at']).toLocal().toString().split('.').first} (device time)',
        ),
        if (account['test_account'] == true) ...[
          _gap(),
          const WfBadge('GOOGLE TEST ACCOUNT'),
        ],
        _gap(16),
        if (rows.isEmpty)
          _caption(
            'Google returned no daily rows for this period. No totals are displayed.',
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 580
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    'Amount spent',
                    metaMoney(currency, totals['spend']),
                    width,
                  ),
                  _metric(
                    'Impressions',
                    metaCount(totals['impressions']),
                    width,
                  ),
                  _metric('Clicks', metaCount(totals['clicks']), width),
                ],
              );
            },
          ),
          _gap(16),
          _caption(
            '${r['reported_days']} daily rows returned. Totals sum these rows. Dates without returned activity are not filled in; Google may omit zero-activity days and revise reporting.',
          ),
          _gap(),
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              key: ValueKey('google-daily-$_generation'),
              tilePadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: const Text(
                'Google daily results',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                for (final row in rows)
                  Container(
                    key: ValueKey('google-day-${row['date']}'),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: WfStyle.line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['date']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        _gap(8),
                        Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          children: [
                            Text('Spent: ${metaMoney(currency, row['spend'])}'),
                            Text(
                              'Impressions: ${metaCount(row['impressions'])}',
                            ),
                            Text('Clicks: ${metaCount(row['clicks'])}'),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        _gap(),
        _caption(
          'Account totals cover all campaigns. They are not this funnel’s attributed results, verified leads, revenue, ROAS or a billing statement. Manual campaign reports remain separate.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('google-performance'),
    width: double.infinity,
    margin: const EdgeInsets.only(top: 22),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      border: Border.all(color: WfStyle.line),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Google Ads account performance',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        _gap(8),
        _caption(
          'Entire selected advertising account · all campaigns. Load a fresh report from Google when you need it.',
        ),
        _gap(14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                key: ValueKey('google-period-$days'),
                label: Text('$days completed days'),
                selected: _days == days,
                onSelected: (_) => setState(() {
                  _days = days;
                  _clear();
                }),
              ),
          ],
        ),
        _gap(14),
        FilledButton.icon(
          key: const ValueKey('google-load-performance'),
          onPressed: _ready && !_busy ? _load : null,
          icon: const Icon(Icons.insights_outlined),
          label: Text(
            _busy ? 'Loading Google report…' : 'Load Google performance',
          ),
        ),
        if (!_ready) ...[
          _gap(),
          _caption(
            _denied
                ? 'Sign in with Enterprise access to view Google reporting.'
                : 'Connect Google Ads, select an advertising account, and finish any connection changes to load reporting.',
          ),
        ],
        if (_busy) ...[_gap(), const LinearProgressIndicator(minHeight: 2)],
        if (_error != null) ...[
          _gap(),
          Text(
            _error!,
            style: const TextStyle(color: Colors.orangeAccent, height: 1.5),
          ),
        ],
        if (_report != null) _results(_report!),
      ],
    ),
  );
}
