import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'funnel_client.dart';

const googleDeliveryBoundary =
    'Prepare future consented inquiries, then send each one explicitly. Only its advertising click identifier, inquiry time and a random event reference are shared. Names, contact details and messages are excluded. Upload receipt and successful processing do not prove ad attribution or a sale.';
const _bad = FunnelException(
  'Google delivery status could not be verified. Refresh it.',
  503,
);
bool _keys(dynamic d, List<String> keys) =>
    d is Map && d.length == keys.length && keys.every(d.containsKey);
bool _stamp(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v) &&
    DateTime.tryParse(v) != null;
bool _uuid(dynamic v) =>
    v is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(v);
const googleDeliveryLabels = {
  'ready': 'Ready for your confirmation',
  'ineligible': 'Not eligible for this setup',
  'checking': 'Checking account and inquiry',
  'blocked': 'Stopped before upload',
  'uncertain': 'Outcome uncertain — do not resend',
  'submitted': 'Upload received — processing unverified',
  'processing': 'Google is processing',
  'succeeded': 'Google processing succeeded',
  'rejected': 'Google processing failed',
  'partial': 'Google reported partial processing',
};
Map<String, dynamic> validateGoogleDelivery(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (!_keys(d, [
        'source',
        'funnel_id',
        'campaign_id',
        'campaign_name',
        'configured',
        'can_enable',
        'enabled',
        'current',
        'fingerprint',
        'since',
        'destination',
        'rows',
        'row_limit',
        'provider_verified',
      ]) ||
      d['source'] != 'google_conversion_delivery' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['campaign_name'] is! String ||
      d['campaign_name'].isEmpty ||
      d['configured'] is! bool ||
      d['can_enable'] is! bool ||
      d['enabled'] is! bool ||
      d['current'] is! bool ||
      d['can_enable'] && !d['configured'] ||
      d['current'] && (!d['enabled'] || !d['can_enable']) ||
      d['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['fingerprint']) ||
      d['enabled'] && !_stamp(d['since']) ||
      !d['enabled'] && d['since'] != null ||
      d['row_limit'] != 50 ||
      d['provider_verified'] != false ||
      d['rows'] is! List ||
      d['rows'].length > 50) {
    throw _bad;
  }
  final dest = d['destination'];
  if (dest != null &&
      (!_keys(dest, ['name', 'account_id', 'action_id']) ||
          dest['name'] is! String ||
          dest['name'].isEmpty ||
          dest['account_id'] is! String ||
          !RegExp(r'^\d{10}$').hasMatch(dest['account_id']) ||
          dest['action_id'] is! String ||
          !RegExp(r'^[1-9]\d{0,18}$').hasMatch(dest['action_id']))) {
    throw _bad;
  }
  if (d['can_enable'] && dest == null) throw _bad;
  final seen = <String>{};
  for (final r in d['rows']) {
    if (!_keys(r, [
          'event_id',
          'captured_at',
          'click_type',
          'state',
          'checked_at',
          'has_warnings',
          'errors',
          'warnings',
          'can_check',
        ]) ||
        !_uuid(r['event_id']) ||
        !seen.add(r['event_id']) ||
        !_stamp(r['captured_at']) ||
        !['gclid', 'gbraid', 'wbraid'].contains(r['click_type']) ||
        !googleDeliveryLabels.containsKey(r['state']) ||
        r['checked_at'] != null && !_stamp(r['checked_at']) ||
        r['has_warnings'] is! bool ||
        r['can_check'] is! bool ||
        r['can_check'] &&
            (!d['configured'] ||
                !['submitted', 'processing'].contains(r['state'])) ||
        r['state'] == 'ready' && !d['current'] ||
        [
              'succeeded',
              'rejected',
              'partial',
              'processing',
            ].contains(r['state']) &&
            r['checked_at'] == null) {
      throw _bad;
    }
    for (final key in ['errors', 'warnings']) {
      if (r[key] is! List || r[key].length > 100) throw _bad;
      for (final v in r[key]) {
        if (!_keys(v, ['reason', 'count']) ||
            v['reason'] is! String ||
            !RegExp(r'^[A-Z][A-Z0-9_]{0,159}$').hasMatch(v['reason']) ||
            v['count'] is! int ||
            ![0, 1].contains(v['count'])) {
          throw _bad;
        }
      }
    }
    if (r['state'] == 'succeeded' &&
        (r['errors'] as List).any((e) => e['count'] > 0)) {
      throw _bad;
    }
  }
  return d;
}

class FunnelGoogleDelivery extends StatefulWidget {
  const FunnelGoogleDelivery({
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
  State<FunnelGoogleDelivery> createState() => _FunnelGoogleDeliveryState();
}

class _FunnelGoogleDeliveryState extends State<FunnelGoogleDelivery> {
  Map<String, dynamic>? _data;
  String? _error, _unavailable, _selected;
  bool _busy = false, _enableConfirmed = false, _sendConfirmed = false;
  int _generation = 0;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-delivery';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_run());
  }

  void _invalidate(String message) {
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    _selected = null;
    _sendConfirmed = false;
    _enableConfirmed = false;
    _busy = false;
    _error = null;
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
      _invalidate('Sign in with Enterprise access to view Google delivery.');
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close Google delivery and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleDelivery old) {
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
      _selected = null;
      _busy = false;
      _unavailable = null;
      _sendConfirmed = false;
      _enableConfirmed = false;
      unawaited(_run());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    super.dispose();
  }

  Future<void> _run([String action = 'read', String? event]) async {
    if (_busy || _unavailable != null) return;
    final d = _data;
    if (action == 'enable' &&
            (d == null || !d['can_enable'] || !_enableConfirmed) ||
        action == 'send' &&
            (d == null ||
                !d['current'] ||
                !_sendConfirmed ||
                _selected == null)) {
      return;
    }
    final client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        id = event ?? _selected,
        g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _selected = null;
      _enableConfirmed = false;
      _sendConfirmed = false;
    });
    try {
      final result = await client.request(
        action == 'read' ? 'GET' : 'POST',
        action == 'read'
            ? path
            : '$path/${['enable', 'disable'].contains(action) ? 'settings' : action}',
        body: action == 'read'
            ? null
            : action == 'check'
            ? {'event_id': id}
            : action == 'send'
            ? {
                'event_id': id,
                'fingerprint': d!['fingerprint'],
                'confirmed': true,
              }
            : {
                'enabled': action == 'enable',
                'fingerprint': d!['fingerprint'],
                'confirmed': true,
              },
      );
      if (!_current(g)) return;
      final state = validateGoogleDelivery(result, funnel, campaign);
      if (action == 'enable' && !state['current'] ||
          action == 'disable' && state['enabled']) {
        throw _bad;
      }
      setState(() => _data = state);
    } catch (e) {
      if (!_current(g)) return;
      Map<String, dynamic>? fresh;
      if (action != 'read') {
        try {
          fresh = validateGoogleDelivery(
            await client.request('GET', path),
            funnel,
            campaign,
          );
        } catch (_) {}
        if (!_current(g)) return;
      }
      setState(() {
        _data = fresh;
        _error =
            '${e is FunnelException ? e.message : 'Google delivery could not complete.'} Check the saved status. No action is retried automatically.';
      });
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Widget _note(String s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Text(s, style: const TextStyle(height: 1.45)),
  );
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
                      'Google conversion delivery',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close Google delivery',
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
                      _note(googleDeliveryBoundary),
                      if (_unavailable != null) _note(_unavailable!),
                      if (_unavailable == null) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh saved delivery status'),
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        if (_error != null) _note(_error!),
                        if (d != null) ...[
                          _note(d['campaign_name']),
                          if (d['destination'] != null)
                            _note(
                              'Conversion action: ${d['destination']['name']} · Account ${d['destination']['account_id']} · Action ${d['destination']['action_id']}',
                            ),
                          _note(
                            !d['configured']
                                ? 'Google conversion delivery is awaiting platform setup.'
                                : d['current']
                                ? 'Future inquiries are prepared for your review.'
                                : d['enabled']
                                ? 'Setup changed. Review account, destination and consent collection, then enable a new window.'
                                : 'Google delivery is off.',
                          ),
                          if (d['since'] != null)
                            _note(
                              'Current inquiry window starts ${d['since']}. Earlier inquiries are excluded when a new window starts.',
                            ),
                          if (!d['current']) ...[
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _enableConfirmed,
                              onChanged: d['can_enable']
                                  ? (v) => setState(
                                      () => _enableConfirmed = v == true,
                                    )
                                  : null,
                              title: const Text(
                                'Prepare future consented inquiries for this conversion action. I will confirm each upload.',
                              ),
                            ),
                            FilledButton(
                              onPressed: _enableConfirmed && d['can_enable']
                                  ? () => _run('enable')
                                  : null,
                              child: const Text('Prepare future inquiries'),
                            ),
                          ],
                          if (d['enabled'])
                            OutlinedButton(
                              onPressed: () => _run('disable'),
                              child: const Text('Stop preparing inquiries'),
                            ),
                          _note(
                            'Each inquiry can be uploaded once. A stopped or uncertain attempt is never automatically resent. Removing an inquiry deletes its local measurement and delivery evidence; it cannot recall data already sent to Google.',
                          ),
                          const Divider(height: 24),
                          const Text(
                            'Recent inquiry delivery',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            'Showing up to 50 most recent prepared inquiries and attempts. Google status checks are manual and limited to once per minute per inquiry.',
                          ),
                          if ((d['rows'] as List).isEmpty)
                            _note('No inquiries in this delivery window.'),
                          for (final r in d['rows'])
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _note(
                                      '${r['captured_at']} · ${r['click_type']}',
                                    ),
                                    _note('Reference: ${r['event_id']}'),
                                    Text(
                                      googleDeliveryLabels[r['state']]!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (r['checked_at'] != null)
                                      _note(
                                        'Last Google processing check: ${r['checked_at']}',
                                      ),
                                    if (r['has_warnings'])
                                      _note(
                                        'Google reported warnings. Review this conversion in Google Ads.',
                                      ),
                                    for (final e in r['errors'])
                                      _note(
                                        'Google error: ${e['reason']} (${e['count']})',
                                      ),
                                    for (final e in r['warnings'])
                                      _note(
                                        'Google warning: ${e['reason']} (${e['count']})',
                                      ),
                                    if (r['state'] == 'ready')
                                      OutlinedButton(
                                        onPressed: () => setState(() {
                                          _selected = r['event_id'];
                                          _sendConfirmed = false;
                                        }),
                                        child: Text(
                                          _selected == r['event_id']
                                              ? 'Inquiry selected'
                                              : 'Select inquiry',
                                        ),
                                      ),
                                    if (r['can_check'])
                                      OutlinedButton(
                                        onPressed: () =>
                                            _run('check', r['event_id']),
                                        child: const Text(
                                          'Check Google processing',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (_selected != null) ...[
                            _note('Selected inquiry: $_selected'),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _sendConfirmed,
                              onChanged: (v) =>
                                  setState(() => _sendConfirmed = v == true),
                              title: const Text(
                                'Send this inquiry to the displayed Google conversion action once. This may affect conversion reporting and bidding.',
                              ),
                            ),
                            FilledButton(
                              onPressed: _sendConfirmed
                                  ? () => _run('send')
                                  : null,
                              child: const Text('Send selected inquiry'),
                            ),
                          ],
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
