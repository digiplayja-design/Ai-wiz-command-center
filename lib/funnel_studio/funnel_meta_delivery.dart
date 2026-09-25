import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'funnel_client.dart';

const metaDeliveryBoundary =
    'Prepare future consented website inquiries, then confirm each send. Meta receives the advertising click identifier, inquiry time, browser information, page address without query parameters and a random event reference. Names, contact details, messages and IP addresses are excluded. A receipt does not prove matching, attributed conversion credit or a sale.';
const _bad = FunnelException(
  'Meta delivery status could not be verified. Refresh it.',
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
const metaDeliveryLabels = {
  'ready': 'Ready for your confirmation',
  'ineligible': 'Not eligible for this setup',
  'checking': 'Checking access and inquiry',
  'blocked': 'Stopped before upload',
  'uncertain': 'Outcome uncertain — do not resend',
  'received': 'Meta receipt received — attribution unverified',
};
Map<String, dynamic> validateMetaDelivery(
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
        'can_authorize',
        'can_enable',
        'enabled',
        'current',
        'fingerprint',
        'since',
        'authorization',
        'destination',
        'rows',
        'row_limit',
        'provider_verified',
      ]) ||
      d['source'] != 'meta_conversion_delivery' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['campaign_name'] is! String ||
      d['campaign_name'].isEmpty ||
      d['campaign_name'].length > 200 ||
      [
        'configured',
        'can_authorize',
        'can_enable',
        'enabled',
        'current',
      ].any((k) => d[k] is! bool) ||
      d['can_authorize'] && !d['configured'] ||
      d['can_enable'] && !d['can_authorize'] ||
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
  final a = d['authorization'], dest = d['destination'];
  if (!_keys(a, ['connected', 'current', 'expires_at', 'checked_at']) ||
      a['connected'] is! bool ||
      a['current'] is! bool ||
      a['current'] && (!a['connected'] || !d['can_authorize']) ||
      a['expires_at'] != null && !_stamp(a['expires_at']) ||
      a['connected'] && !_stamp(a['checked_at']) ||
      !a['connected'] && (a['checked_at'] != null || a['expires_at'] != null) ||
      d['can_enable'] && !a['current']) {
    throw _bad;
  }
  if (dest != null &&
      (!_keys(dest, ['name', 'pixel_id']) ||
          dest['name'] is! String ||
          dest['name'].isEmpty ||
          dest['name'].length > 1000 ||
          dest['pixel_id'] is! String ||
          !RegExp(r'^\d{1,40}$').hasMatch(dest['pixel_id']))) {
    throw _bad;
  }
  if (d['can_authorize'] && dest == null) throw _bad;
  final seen = <String>{};
  for (final r in d['rows']) {
    if (!_keys(r, [
          'event_id',
          'captured_at',
          'state',
          'received_at',
          'has_warnings',
        ]) ||
        !_uuid(r['event_id']) ||
        !seen.add(r['event_id']) ||
        !_stamp(r['captured_at']) ||
        !metaDeliveryLabels.containsKey(r['state']) ||
        r['has_warnings'] is! bool ||
        r['state'] == 'ready' && !d['current'] ||
        r['state'] == 'received' && !_stamp(r['received_at']) ||
        r['state'] != 'received' &&
            (r['received_at'] != null || r['has_warnings'])) {
      throw _bad;
    }
  }
  return d;
}

class FunnelMetaDelivery extends StatefulWidget {
  const FunnelMetaDelivery({
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
  State<FunnelMetaDelivery> createState() => _FunnelMetaDeliveryState();
}

class _FunnelMetaDeliveryState extends State<FunnelMetaDelivery> {
  Map<String, dynamic>? _data;
  String? _error, _unavailable, _selected;
  bool _busy = false,
      _accessConfirmed = false,
      _enableConfirmed = false,
      _sendConfirmed = false,
      _stopConfirmed = false,
      _disconnectConfirmed = false;
  final _token = TextEditingController();
  int _generation = 0;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-delivery';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  void _clear() {
    _data = null;
    _selected = null;
    _token.clear();
    _accessConfirmed = false;
    _enableConfirmed = false;
    _sendConfirmed = false;
    _stopConfirmed = false;
    _disconnectConfirmed = false;
  }

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
    _clear();
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
      _invalidate('Sign in with Enterprise access to view Meta delivery.');
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close Meta delivery and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaDelivery old) {
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
      _clear();
      _busy = false;
      _unavailable = null;
      unawaited(_run());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    _token.dispose();
    super.dispose();
  }

  Future<void> _run([String action = 'read']) async {
    if (_busy || _unavailable != null) return;
    final d = _data;
    if (action != 'read' && d == null) return;
    if (action == 'authorize' &&
            (!d!['can_authorize'] ||
                !_accessConfirmed ||
                _token.text.isEmpty) ||
        action == 'disconnect' &&
            (!d!['authorization']['connected'] || !_disconnectConfirmed) ||
        action == 'enable' && (!d!['can_enable'] || !_enableConfirmed) ||
        action == 'disable' && (!d!['enabled'] || !_stopConfirmed) ||
        action == 'send' &&
            (!d!['current'] || !_sendConfirmed || _selected == null)) {
      return;
    }
    final client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        g = ++_generation;
    final body = action == 'read'
        ? null
        : <String, dynamic>{
            'fingerprint': d!['fingerprint'],
            'confirmed': true,
            if (action == 'authorize') 'access_token': _token.text,
            if (action == 'enable' || action == 'disable')
              'enabled': action == 'enable',
            if (action == 'send') 'event_id': _selected,
          };
    setState(() {
      _busy = true;
      _clear();
      _error = null;
    });
    try {
      final result = await client.request(
        action == 'read' ? 'GET' : 'POST',
        action == 'read'
            ? path
            : '$path/${['enable', 'disable'].contains(action) ? 'settings' : action}',
        body: body,
      );
      if (!_current(g)) return;
      final state = validateMetaDelivery(result, funnel, campaign);
      if (action == 'enable' && !state['current'] ||
          action == 'disable' && state['enabled'] ||
          action == 'authorize' && !state['authorization']['current'] ||
          action == 'disconnect' && state['authorization']['connected']) {
        throw _bad;
      }
      setState(() => _data = state);
    } catch (e) {
      if (!_current(g)) return;
      Map<String, dynamic>? fresh;
      if (action != 'read') {
        try {
          fresh = validateMetaDelivery(
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
            '${e is FunnelException ? e.message : 'Meta delivery could not complete.'} Check the saved status. No action is retried automatically.';
      });
    } finally {
      body?.remove('access_token');
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Text(text, style: const TextStyle(height: 1.45)),
  );
  Widget _confirm(
    String text,
    bool value,
    ValueChanged<bool> change, {
    bool enabled = true,
  }) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: enabled ? (v) => setState(() => change(v == true)) : null,
    title: Text(text),
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
                      'Meta conversion delivery',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close Meta delivery',
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
                      _note(metaDeliveryBoundary),
                      if (_unavailable != null) _note(_unavailable!),
                      if (_unavailable == null) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh saved Meta delivery'),
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
                              'Meta data source: ${d['destination']['name']} · Pixel ${d['destination']['pixel_id']}',
                            ),
                          _note(
                            !d['configured']
                                ? 'Meta conversion delivery is awaiting platform setup.'
                                : d['current']
                                ? 'Future website inquiries are prepared for your review.'
                                : d['enabled']
                                ? 'Setup changed. Review access, destination and website consent, then start a new window.'
                                : 'Meta delivery is off.',
                          ),
                          const Divider(height: 24),
                          const Text(
                            'Conversion authorization',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            d['authorization']['current']
                                ? 'A separate conversion credential is saved for this data source. Access is rechecked before each send.'
                                : d['authorization']['connected']
                                ? 'Saved conversion access needs renewal.'
                                : 'No conversion credential is saved.',
                          ),
                          _note(
                            'Meta setup and approval must be completed first. Use a system-user token for the KORLIX Meta app and the selected data source. Advertising read access alone does not authorize conversion uploads.',
                          ),
                          if (d['authorization']['expires_at'] != null)
                            _note(
                              'Credential expires: ${d['authorization']['expires_at']}',
                            ),
                          if (d['can_authorize']) ...[
                            TextField(
                              controller: _token,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              autofillHints: const [],
                              maxLength: 12000,
                              decoration: const InputDecoration(
                                labelText: 'Meta system-user token',
                                helperText:
                                    'Hidden after submission. Never shown in saved status.',
                              ),
                            ),
                            _confirm(
                              'Authorize this credential for the selected Meta data source.',
                              _accessConfirmed,
                              (v) => _accessConfirmed = v,
                            ),
                            FilledButton(
                              onPressed: _accessConfirmed
                                  ? () => _run('authorize')
                                  : null,
                              child: const Text(
                                'Save conversion authorization',
                              ),
                            ),
                          ],
                          if (d['authorization']['connected']) ...[
                            _confirm(
                              'Remove saved conversion access and stop preparing inquiries.',
                              _disconnectConfirmed,
                              (v) => _disconnectConfirmed = v,
                            ),
                            OutlinedButton(
                              onPressed: _disconnectConfirmed
                                  ? () => _run('disconnect')
                                  : null,
                              child: const Text('Disconnect conversion access'),
                            ),
                          ],
                          const Divider(height: 24),
                          if (d['since'] != null)
                            _note(
                              'Current inquiry window starts ${d['since']}. Earlier inquiries are excluded when a new window starts.',
                            ),
                          if (!d['current']) ...[
                            _confirm(
                              'Prepare future consented website inquiries. I will confirm each Meta upload.',
                              _enableConfirmed,
                              (v) => _enableConfirmed = v,
                              enabled: d['can_enable'],
                            ),
                            FilledButton(
                              onPressed: _enableConfirmed && d['can_enable']
                                  ? () => _run('enable')
                                  : null,
                              child: const Text(
                                'Prepare future Meta inquiries',
                              ),
                            ),
                          ],
                          if (d['enabled']) ...[
                            _confirm(
                              'Stop preparing Meta inquiries for delivery.',
                              _stopConfirmed,
                              (v) => _stopConfirmed = v,
                            ),
                            OutlinedButton(
                              onPressed: _stopConfirmed
                                  ? () => _run('disable')
                                  : null,
                              child: const Text(
                                'Stop preparing Meta inquiries',
                              ),
                            ),
                          ],
                          _note(
                            'One send attempt is allowed per inquiry. Stopped and uncertain attempts are never resent automatically. Deleting an inquiry removes local evidence; it cannot recall information already sent to Meta.',
                          ),
                          const Divider(height: 24),
                          const Text(
                            'Recent Meta delivery',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            'Showing up to 50 recent inquiries and attempts. Meta receipts acknowledge receipt only. Review matching and attribution separately in Meta Events Manager.',
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
                                    _note(r['captured_at']),
                                    _note('Reference: ${r['event_id']}'),
                                    Text(
                                      metaDeliveryLabels[r['state']]!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (r['received_at'] != null)
                                      _note(
                                        'Meta receipt saved: ${r['received_at']}',
                                      ),
                                    if (r['has_warnings'])
                                      _note(
                                        'Meta returned warnings. Review the event in Events Manager.',
                                      ),
                                    if (r['state'] == 'ready')
                                      OutlinedButton(
                                        onPressed: () => setState(() {
                                          _selected = r['event_id'];
                                          _sendConfirmed = false;
                                        }),
                                        child: Text(
                                          _selected == r['event_id']
                                              ? 'Meta inquiry selected'
                                              : 'Select Meta inquiry',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (_selected != null) ...[
                            _note('Selected inquiry: ${_selected!}'),
                            _confirm(
                              'Send this inquiry to the displayed Meta data source once. This may affect advertising measurement and optimization.',
                              _sendConfirmed,
                              (v) => _sendConfirmed = v,
                            ),
                            FilledButton(
                              onPressed: _sendConfirmed
                                  ? () => _run('send')
                                  : null,
                              child: const Text('Send selected Meta inquiry'),
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
