import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const metaWebsiteConsentBoundary =
    'Prepare future Meta website measurement with a separate visitor choice for the click identifier, inquiry time, browser information and page address. Prepared means local evidence only; delivery remains off. Older click-only receipts stay separate.';
const _bad = FunnelException(
  'Meta website consent could not be verified. Refresh it.',
  503,
);
bool _date(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse('${v}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        v;
bool _count(dynamic v) => v is int && v >= 0 && v <= 1000000000;
Map<String, dynamic> validateMetaWebsiteConsent(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
  int days,
) {
  const fields = [
    'source',
    'funnel_id',
    'campaign_id',
    'name',
    'configured',
    'context_current',
    'armed_at',
    'enabled',
    'collecting',
    'can_enable',
    'revision',
    'event_name',
    'action_source',
    'send_ready',
    'provider_verified',
    'policy_version',
    'days',
    'from_day',
    'through_day',
    'timezone',
    'includes_today',
    'checked_at',
    'rows',
    'totals',
  ];
  if (d.length != fields.length ||
      !fields.every(d.containsKey) ||
      d['source'] != 'meta_website_consent' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['name'] is! String ||
      (d['name'] as String).isEmpty ||
      (d['name'] as String).runes.length > 100 ||
      d['configured'] is! bool ||
      d['context_current'] is! bool ||
      d['can_enable'] == true && d['configured'] != true ||
      d['enabled'] is! bool ||
      d['collecting'] is! bool ||
      d['can_enable'] is! bool ||
      d['collecting'] !=
          (d['enabled'] && d['can_enable'] && d['context_current']) ||
      (d['enabled'] || d['context_current']) && d['revision'] == null ||
      !d['enabled'] && d['armed_at'] != null ||
      d['revision'] != null &&
          (d['revision'] is! String ||
              !RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
              ).hasMatch(d['revision'])) ||
      d['event_name'] != 'Lead' ||
      d['action_source'] != 'website' ||
      d['send_ready'] != false ||
      d['enabled'] &&
          (d['armed_at'] is! String ||
              DateTime.tryParse(d['armed_at']) == null) ||
      d['policy_version'] != 'meta_measurement_v2' ||
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
    'missing_browser': 0,
    'prepared': 0,
  };
  for (var i = 0; i < days; i++) {
    final r = d['rows'][i];
    if (r is! Map ||
        r.length != 6 ||
        r['day'] !=
            start.add(Duration(days: i)).toIso8601String().substring(0, 10) ||
        sums.keys.any((k) => !_count(r[k])) ||
        r['receipts'] !=
            r['declined'] +
                r['missing_click'] +
                r['missing_browser'] +
                r['prepared']) {
      throw _bad;
    }
    for (final k in sums.keys) {
      sums[k] = sums[k]! + (r[k] as int);
    }
  }
  if (d['totals'].length != sums.length ||
      sums.keys.any(
        (k) => !_count(d['totals'][k]) || d['totals'][k] != sums[k],
      )) {
    throw _bad;
  }
  return d;
}

class FunnelMetaWebsiteConsent extends StatefulWidget {
  const FunnelMetaWebsiteConsent({
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
  State<FunnelMetaWebsiteConsent> createState() =>
      _FunnelMetaWebsiteConsentState();
}

class _FunnelMetaWebsiteConsentState extends State<FunnelMetaWebsiteConsent> {
  Map<String, dynamic>? _data;
  int _generation = 0, _days = 30;
  bool _busy = false, _confirmed = false;
  String? _error, _unavailable, _notice;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-website-consent';
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
    _confirmed = false;
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

  void _deny() => _invalidate(
    'Sign in with Enterprise access to view Meta website consent.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close Meta website consent and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaWebsiteConsent old) {
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
      _confirmed = false;
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
    if (_busy || _unavailable != null || enabled != null && !_confirmed) return;
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
      _confirmed = false;
      _error = null;
      _notice = null;
    });
    try {
      final result = await client.request(
        enabled != null ? 'POST' : 'GET',
        enabled != null ? '$path/settings' : '$path?days=$days',
        body: enabled != null
            ? {
                'days': days,
                'enabled': enabled,
                'expected_revision': revision,
                'confirmed': true,
              }
            : null,
      );
      if (!_current(g)) return;
      final d = validateMetaWebsiteConsent(result, funnel, campaign, days);
      if (enabled != null && d['enabled'] != enabled) throw _bad;
      setState(() {
        _data = d;
        _notice = enabled == null
            ? null
            : enabled
            ? 'Website consent enabled for future recognized-link visits.'
            : 'Website consent disabled. Existing receipts remain until their inquiry is removed.';
      });
    } catch (e) {
      if (_current(g)) {
        setState(
          () => _error = e is FunnelException
              ? '${e.message}${enabled != null ? ' Refresh to check the saved state before trying again.' : ''}'
              : 'Meta website consent could not load. Refresh it.',
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
                      'Meta website consent',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close Meta website consent',
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
                      _note(metaWebsiteConsentBoundary),
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
                              label: const Text('Refresh Meta website consent'),
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
                                ? 'Website consent collection is on'
                                : d['enabled']
                                ? 'Website consent collection is suspended'
                                : 'Website consent collection is off',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            'Visitors can allow a supported Meta click identifier, inquiry time, browser user agent and the published page address without query parameters. No name, email, phone, message or IP address is stored in this measurement receipt. Declining leaves the inquiry available.',
                          ),
                          const SizedBox(height: 12),
                          if (!d['can_enable'])
                            _note(
                              'Platform setup, a published page with a privacy policy, an open Meta campaign and its recognized link are required.',
                            ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: (v) =>
                                setState(() => _confirmed = v == true),
                            title: Text(
                              d['enabled']
                                  ? 'Stop website context collection.'
                                  : 'Collect website context for future consenting inquiries.',
                            ),
                          ),
                          FilledButton(
                            onPressed:
                                _confirmed && (d['enabled'] || d['can_enable'])
                                ? () => _request(enabled: !d['enabled'])
                                : null,
                            child: Text(
                              d['enabled']
                                  ? 'Disable website consent'
                                  : 'Enable website consent',
                            ),
                          ),
                          const SizedBox(height: 18),
                          _note(
                            'New inquiries only. This setting takes priority over click-only intake for new visits when active. Disabling stops website-context capture, including open forms; the separate click-only intake setting is unchanged. Inquiry deletion removes its evidence. Uploads require separate setup.',
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
                                'missing_browser':
                                    'Allowed, missing browser context',
                                'prepared': 'Prepared website receipt',
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
                            'These four states sum to the receipt total. Declined and incomplete receipts retain no click identifier, browser information or page address. Counts cover this consent version only and do not measure attributed conversions.',
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
                                  label: Text('No browser'),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: Text('Prepared'),
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
                                        'missing_browser',
                                        'prepared',
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
