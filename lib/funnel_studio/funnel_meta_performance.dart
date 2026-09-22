import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_format.dart';
import 'funnel_meta_campaign_results.dart';
export 'funnel_meta_format.dart';

class FunnelMetaPerformance extends StatefulWidget {
  const FunnelMetaPerformance({
    super.key,
    required this.client,
    required this.connection,
    required this.available,
  });
  final FunnelClient client;
  final Map<String, dynamic>? connection;
  final bool available;
  @override
  State<FunnelMetaPerformance> createState() => _FunnelMetaPerformanceState();
}

class _FunnelMetaPerformanceState extends State<FunnelMetaPerformance> {
  int _days = 7, _request = 0;
  String _scope = 'account';
  bool _busy = false, _accessDenied = false;
  Map<String, dynamic>? _report;
  String? _error;
  String get _binding =>
      '${widget.connection?['version']}:${widget.connection?['selected_account']}';
  late String _lastBinding;
  bool get _ready =>
      widget.available &&
      !_accessDenied &&
      widget.connection?['selected_account'] != null;
  @override
  void initState() {
    super.initState();
    _lastBinding = _binding;
    widget.client.addAccessDeniedListener(_deny);
  }

  void _deny() {
    if (!mounted) return;
    setState(() {
      _accessDenied = true;
      _clear();
    });
  }

  void _clear() {
    _request++;
    _report = null;
    _error = null;
    _busy = false;
  }

  @override
  void didUpdateWidget(covariant FunnelMetaPerformance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
      _accessDenied = false;
      _clear();
    }
    if (_binding != _lastBinding || oldWidget.available != widget.available) {
      _lastBinding = _binding;
      _accessDenied = false;
      _clear();
    }
  }

  @override
  void dispose() {
    _request++;
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  Future<void> _load() async {
    if (!_ready || _busy) return;
    final request = ++_request,
        binding = _binding,
        account = widget.connection!['selected_account'],
        version = widget.connection!['version'];
    setState(() {
      _busy = true;
      _report = null;
      _error = null;
    });
    try {
      final result = await widget.client.request(
        'GET',
        _scope == 'campaign'
            ? '/meta/campaign-performance'
            : '/meta/performance',
        query: {
          'days': '$_days',
          'account_id': '$account',
          'version': '$version',
        },
      );
      if (!mounted || request != _request || binding != _binding || !_ready) {
        return;
      }
      if (result['source'] != 'meta' ||
          result['scope'] != _scope ||
          result['account'] is! Map ||
          result['account']['id'] != account ||
          result['connection_version'] != version ||
          result['rows'] is! List ||
          result['totals'] is! Map ||
          result['range'] is! Map) {
        throw const FunnelException(
          'Meta returned an unreadable report. Check the connection and try again.',
        );
      }
      setState(() => _report = result);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = e.toString());
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  Widget _caption(String value) => Text(
    value,
    style: const TextStyle(color: WfStyle.muted, fontSize: 12, height: 1.5),
  );
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
        const SizedBox(height: 8),
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
  Widget _results(Map r) {
    final account = r['account'] as Map,
        rows = r['rows'] as List,
        totals = r['totals'] as Map,
        currency = '${account['currency']}';
    final campaign = r['scope'] == 'campaign';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          '${account['name']}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _caption('${account['id']} · ${account['timezone']}'),
        const SizedBox(height: 6),
        _caption(
          '${r['range']['from']} – ${r['range']['to']} · completed account-calendar days',
        ),
        const SizedBox(height: 6),
        _caption(
          'Retrieved: ${DateTime.tryParse('${r['fetched_at']}')?.toLocal().toString().split('.').first ?? 'Unknown'} (device time)',
        ),
        const SizedBox(height: 16),
        if (rows.isEmpty)
          Text(
            campaign
                ? 'Meta returned no campaign rows for this period. No totals are available.'
                : 'Meta returned no daily rows for this period. No totals are available.',
            style: const TextStyle(color: WfStyle.muted, height: 1.5),
          )
        else ...[
          if (campaign) ...[
            _caption(
              'Totals for all returned campaigns · search does not change these totals.',
            ),
            const SizedBox(height: 10),
          ],
          LayoutBuilder(
            builder: (c, constraints) {
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
                  _metric('Clicks (all)', metaCount(totals['clicks']), width),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _caption(
            campaign
                ? '${r['reported_campaigns']} campaigns returned for the full period. Campaigns without returned data are not listed. Meta may revise reporting.'
                : '${r['reported_days']} daily rows returned. Totals sum these rows; missing days are not filled in. Meta may revise reporting.',
          ),
          const SizedBox(height: 18),
          if (campaign)
            FunnelMetaCampaignResults(
              key: ValueKey('meta-campaign-results-$_request'),
              rows: rows.cast<Map>(),
              currency: currency,
            )
          else
            Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: ValueKey('meta-daily-${r['fetched_at']}'),
                tilePadding: EdgeInsets.zero,
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                title: const Text(
                  'Daily results',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                children: [
                  for (final row in rows)
                    Container(
                      key: ValueKey('meta-day-${row['date']}'),
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
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 20,
                            runSpacing: 8,
                            children: [
                              Text(
                                'Spent: ${metaMoney(currency, row['spend'])}',
                              ),
                              Text(
                                'Impressions: ${metaCount(row['impressions'])}',
                              ),
                              Text('Clicks (all): ${metaCount(row['clicks'])}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        _caption(
          campaign
              ? 'Campaigns belong to the selected Meta account. They are not linked to this funnel’s plans or attributed results. Matching names do not verify a link. Manual campaign reports remain separate.'
              : 'Account totals cover all campaigns. They are not this funnel’s attributed results, verified leads, revenue or ROAS. Manual campaign reports remain separate.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('meta-performance'),
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
          'Meta account performance',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _caption(
          'Entire selected ad account · all campaigns. Load a fresh report from Meta when you need it.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in ['account', 'campaign'])
              ChoiceChip(
                key: ValueKey('meta-scope-$scope'),
                label: Text(
                  scope == 'account' ? 'Account totals' : 'Campaign comparison',
                ),
                selected: _scope == scope,
                onSelected: (_) => setState(() {
                  _scope = scope;
                  _clear();
                }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                key: ValueKey('meta-period-$days'),
                label: Text('$days completed days'),
                selected: _days == days,
                onSelected: _busy
                    ? null
                    : (_) => setState(() {
                        _days = days;
                        _clear();
                      }),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('meta-load-performance'),
          onPressed: _ready && !_busy ? _load : null,
          icon: const Icon(Icons.insights_outlined),
          label: Text(
            _busy
                ? 'Loading report…'
                : _scope == 'campaign'
                ? 'Load campaign comparison'
                : 'Load Meta performance',
          ),
        ),
        if (!_ready) ...[
          const SizedBox(height: 12),
          _caption(
            _accessDenied
                ? 'Sign in with Enterprise access to view reporting.'
                : 'Connect Meta, select an ad account, and finish any connection changes to load reporting.',
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
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
