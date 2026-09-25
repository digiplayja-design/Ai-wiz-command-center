import 'funnel_meta_delivery.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_website_consent.dart';
import 'funnel_google_destination.dart';
import 'funnel_meta_destination.dart';
import 'funnel_google_delivery.dart';

const conversionIntakeBoundary =
    'These are local inquiry consent receipts. Consented click means a visitor allowed measurement and supplied a supported click identifier in the campaign URL. The identifier is unverified. This intake view does not report uploads or provider acceptance. Open Google conversion delivery to review its upload attempts and processing status. Meta delivery remains off.';
const _bad = FunnelException(
  'Conversion intake could not be verified. Refresh it.',
  503,
);
bool _date(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse('${v}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        v;
bool _count(dynamic v) => v is int && v >= 0 && v <= 1000000000;
Map<String, dynamic> validateConversionIntake(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
  int days,
) {
  if (d['source'] != 'conversion_intake' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['name'] is! String ||
      (d['name'] as String).isEmpty ||
      (d['name'] as String).runes.length > 100 ||
      !['google', 'meta', 'other'].contains(d['platform']) ||
      d['enabled'] is! bool ||
      d['collecting'] is! bool ||
      d['can_enable'] is! bool ||
      d['collecting'] != (d['enabled'] && d['can_enable']) ||
      d['enabled'] && d['revision'] == null ||
      d['revision'] != null &&
          (d['revision'] is! String ||
              !RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              ).hasMatch(d['revision'])) ||
      d['event_name'] != 'inquiry_submitted' ||
      d['policy_version'] != 'measurement_v1' ||
      ![
        'not_implemented',
        'separate_workflow',
      ].contains(d['provider_delivery']) ||
      d['provider_verified'] != false ||
      ![7, 30, 90].contains(days) ||
      d['days'] != days ||
      !_date(d['from_day']) ||
      !_date(d['through_day']) ||
      d['timezone'] != 'UTC' ||
      d['includes_today'] != true ||
      d['checked_at'] is! String ||
      DateTime.tryParse(
            d['checked_at'],
          )?.toUtc().toIso8601String().substring(0, 10) !=
          d['through_day'] ||
      d['rows'] is! List ||
      (d['rows'] as List).length != days ||
      d['totals'] is! Map) {
    throw _bad;
  }
  final start = DateTime.parse('${d['from_day']}T00:00:00Z');
  if (start.add(Duration(days: days - 1)).toIso8601String().substring(0, 10) !=
      d['through_day']) {
    throw _bad;
  }
  final sums = {
    'receipts': 0,
    'declined': 0,
    'missing_click': 0,
    'awaiting_setup': 0,
  };
  for (var i = 0; i < days; i++) {
    final r = d['rows'][i];
    if (r is! Map ||
        r['day'] !=
            start.add(Duration(days: i)).toIso8601String().substring(0, 10) ||
        sums.keys.any((k) => !_count(r[k])) ||
        r['receipts'] !=
            r['declined'] + r['missing_click'] + r['awaiting_setup']) {
      throw _bad;
    }
    for (final k in sums.keys) {
      sums[k] = sums[k]! + (r[k] as int);
    }
  }
  if (sums.keys.any(
    (k) => !_count(d['totals'][k]) || d['totals'][k] != sums[k],
  )) {
    throw _bad;
  }
  return d;
}

class FunnelConversionIntake extends StatefulWidget {
  const FunnelConversionIntake({
    super.key,
    required this.client,
    required this.funnelId,
    required this.campaignId,
    this.scope,
  });
  final FunnelClient client;
  final String funnelId, campaignId;
  final ValueListenable<int>? scope;
  @override
  State<FunnelConversionIntake> createState() => _FunnelConversionIntakeState();
}

class _FunnelConversionIntakeState extends State<FunnelConversionIntake> {
  Map<String, dynamic>? _data;
  int _generation = 0, _days = 30;
  bool _busy = false;
  String? _error, _unavailable, _notice;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/measurement';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_request());
  }

  void _invalidate(String message) {
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    _busy = false;
    _error = null;
    _notice = null;
    _unavailable = message;
    void redraw() {
      if (mounted && g == _generation) setState(() {});
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => redraw());
    } else {
      redraw();
    }
  }

  void _deny() =>
      _invalidate('Sign in with Enterprise access to view conversion intake.');
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close conversion intake and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelConversionIntake old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      old.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
    }
    if (old.scope != widget.scope) {
      old.scope?.removeListener(_scopeChanged);
      widget.scope?.addListener(_scopeChanged);
    }
    if (old.client != widget.client ||
        old.scope != widget.scope ||
        old.funnelId != widget.funnelId ||
        old.campaignId != widget.campaignId) {
      _generation++;
      _data = null;
      _busy = false;
      _unavailable = null;
      _days = 30;
      unawaited(_request());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    super.dispose();
  }

  Future<void> _request({bool? enabled}) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        days = _days,
        revision = _data?['revision'];
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _notice = null;
    });
    try {
      final result = await client.request(
        enabled != null ? 'POST' : 'GET',
        enabled != null ? '$path/settings' : '$path?days=$days',
        body: enabled != null
            ? {'days': days, 'enabled': enabled, 'expected_revision': revision}
            : null,
      );
      if (!_current(g)) return;
      final d = validateConversionIntake(result, funnel, campaign, days);
      if (enabled != null && d['enabled'] != enabled) throw _bad;
      setState(() {
        _data = d;
        _notice = enabled == null
            ? null
            : enabled
            ? 'Consent collection enabled for future recognized-link visits.'
            : 'Consent collection disabled. Existing receipts are retained until their inquiry is removed.';
      });
    } catch (e) {
      if (_current(g)) {
        setState(
          () => _error = e is FunnelException
              ? e.message
              : 'Conversion intake could not load. Refresh it.',
        );
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Widget _note(String s) =>
      Text(s, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Conversion intake',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close conversion intake',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _note(conversionIntakeBoundary),
                      const SizedBox(height: 16),
                      if (_unavailable != null) Text(_unavailable!),
                      if (_unavailable == null) ...[
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<int>(
                              value: _days,
                              items: [7, 30, 90]
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('Last $n UTC days'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (n) {
                                      if (n != null) {
                                        setState(() => _days = n);
                                        unawaited(_request());
                                      }
                                    },
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _request(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh conversion intake'),
                            ),
                          ],
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_notice!),
                          ),
                        if (d != null) ...[
                          if (d['platform'] == 'meta') ...[
                            OutlinedButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FunnelMetaDelivery(
                                  client: widget.client,
                                  funnelId: widget.funnelId,
                                  campaignId: widget.campaignId,
                                  scope: widget.scope,
                                ),
                              ),
                              child: const Text('Meta conversion delivery'),
                            ),
                            OutlinedButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FunnelMetaWebsiteConsent(
                                  client: widget.client,
                                  funnelId: widget.funnelId,
                                  campaignId: widget.campaignId,
                                  scope: widget.scope,
                                ),
                              ),
                              child: const Text('Meta website consent'),
                            ),

                            OutlinedButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FunnelMetaDestination(
                                  client: widget.client,
                                  funnelId: widget.funnelId,
                                  campaignId: widget.campaignId,
                                  scope: widget.scope,
                                ),
                              ),
                              child: const Text('Meta conversion destination'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (d['platform'] == 'google') ...[
                            OutlinedButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FunnelGoogleDestination(
                                  client: widget.client,
                                  funnelId: widget.funnelId,
                                  campaignId: widget.campaignId,
                                  scope: widget.scope,
                                ),
                              ),
                              child: const Text(
                                'Google conversion destination',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => FunnelGoogleDelivery(
                                  client: widget.client,
                                  funnelId: widget.funnelId,
                                  campaignId: widget.campaignId,
                                  scope: widget.scope,
                                ),
                              ),
                              child: const Text('Google conversion delivery'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            d['name'],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            '${d['from_day']} through ${d['through_day']} UTC · Includes today, which is incomplete.',
                          ),
                          const SizedBox(height: 18),
                          Text(
                            d['collecting']
                                ? 'Consent collection is on'
                                : d['enabled']
                                ? 'Consent collection is suspended'
                                : 'Consent collection is off',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            'When enabled, visitors using this campaign’s recognized link see an optional advertising measurement choice. Declining never blocks their inquiry. Only an allowed click identifier and inquiry time are retained for future provider setup; names, emails, phone numbers and messages are excluded from measurement data.',
                          ),
                          const SizedBox(height: 12),
                          if (!d['can_enable'])
                            _note(
                              'To collect consent, publish the page with a privacy policy, reopen the campaign if archived, choose Google or Meta, and create its recognized link under Inquiry attribution.',
                            ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: d['enabled'] || d['can_enable']
                                ? () => _request(enabled: !d['enabled'])
                                : null,
                            child: Text(
                              d['enabled']
                                  ? 'Disable consent collection'
                                  : 'Enable consent collection',
                            ),
                          ),
                          const SizedBox(height: 18),
                          _note(
                            'New inquiries only. No historical backfill. Disabling stops future capture, including forms already open. Existing receipts and identifiers are removed when their inquiry is removed. Provider delivery and acceptance will require separate setup.',
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final entry in {
                                'receipts': 'Consent receipts',
                                'declined': 'Measurement declined',
                                'missing_click': 'Allowed, no supported click',
                                'awaiting_setup': 'Awaiting conversion setup',
                              }.entries)
                                Container(
                                  width: 210,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: WfStyle.surface,
                                    border: Border.all(color: WfStyle.line),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${d['totals'][entry.key]}',
                                        style: const TextStyle(
                                          fontSize: 27,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      _note(entry.value),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _note(
                            'The three receipt states sum to the receipt total. Inquiries captured before collection was enabled, after it was disabled, or without a measurement form context have no receipt. Counts are inquiries, not unique people, bookings or sales.',
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Daily consent receipts',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('UTC day')),
                                DataColumn(
                                  label: Text('Receipts'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Declined'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('No click'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Consented click'),
                                  numeric: true,
                                ),
                              ],
                              rows: [
                                for (final r in (d['rows'] as List).reversed)
                                  DataRow(
                                    cells: [
                                      for (final k in [
                                        'day',
                                        'receipts',
                                        'declined',
                                        'missing_click',
                                        'awaiting_setup',
                                      ])
                                        DataCell(Text('${r[k]}')),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
