import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'funnel_client.dart';
import 'funnel_meta_website_consent.dart';

const metaDestinationBoundary =
    'Choose a listed Meta data source for future inquiry events. This saves its identity only. Listing does not verify permission to send events. Delivery and visitor consent need separate setup.';
const _bad = FunnelException(
  'Meta conversion destination could not be verified. Refresh it.',
  503,
);
const _fields = ['pixel_id', 'name'];
bool _keys(dynamic d, List<String> keys) =>
    d is Map && d.length == keys.length && keys.every(d.containsKey);
bool _id(dynamic v) => v is String && RegExp(r'^[0-9]{1,40}$').hasMatch(v);
bool _accountId(dynamic v) =>
    v is String && RegExp(r'^act_[0-9]{1,40}$').hasMatch(v);
bool _hash(dynamic v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
bool _stamp(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v) &&
    DateTime.tryParse(v) != null;
Map<String, dynamic> validateMetaDestination(dynamic d) {
  if (!_keys(d, _fields) ||
      !_id(d['pixel_id']) ||
      d['name'] is! String ||
      (d['name'] as String).isEmpty ||
      (d['name'] as String).length > 1000 ||
      (d['name'] as String).trim() != d['name'] ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(d['name'])) {
    throw _bad;
  }
  return Map<String, dynamic>.from(d);
}

bool _context(dynamic d) {
  if (!_keys(d, [
        'account',
        'connection_version',
        'provider_campaign_id',
        'link_current',
        'editable',
      ]) ||
      d['connection_version'] is! int ||
      d['connection_version'] < 0 ||
      d['provider_campaign_id'] != null && !_id(d['provider_campaign_id']) ||
      d['link_current'] is! bool ||
      d['editable'] is! bool) {
    return false;
  }
  final a = d['account'];
  return a == null ||
      _keys(a, ['id', 'name', 'currency', 'timezone', 'status']) &&
          _accountId(a['id']) &&
          a['name'] is String &&
          a['currency'] is String &&
          RegExp(r'^[A-Z]{3}$').hasMatch(a['currency']) &&
          a['timezone'] is String &&
          (a['timezone'] as String).isNotEmpty &&
          a['status'] is int;
}

bool _ready(dynamic d) =>
    d['account'] != null &&
    d['account']['status'] == 1 &&
    d['connection_version'] > 0 &&
    d['provider_campaign_id'] != null &&
    d['link_current'] == true &&
    d['editable'] == true;
bool _sameContext(Map a, Map b) =>
    a.keys.every((k) => k == 'account' ? mapEquals(a[k], b[k]) : a[k] == b[k]);
Map<String, dynamic> validateMetaDestinationState(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (!_keys(d, [
        'source',
        'funnel_id',
        'campaign_id',
        'campaign_name',
        'version',
        'fingerprint',
        'context',
        'lookup_ready',
        'selection_current',
        'selection',
        'event_name',
        'delivery_state',
        'send_ready',
        'provider_verified',
      ]) ||
      d['source'] != 'meta_conversion_destination' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['campaign_name'] is! String ||
      (d['campaign_name'] as String).isEmpty ||
      d['version'] is! int ||
      d['version'] < 0 ||
      d['version'] > 2147483647 ||
      !_hash(d['fingerprint']) ||
      !_context(d['context']) ||
      d['lookup_ready'] is! bool ||
      d['selection_current'] is! bool ||
      d['lookup_ready'] && !_ready(d['context']) ||
      d['event_name'] != 'Lead' ||
      d['delivery_state'] != 'not_implemented' ||
      d['send_ready'] != false ||
      d['provider_verified'] != false) {
    throw _bad;
  }
  final s = d['selection'];
  if (s != null) {
    if (!_keys(s, ['destination', 'context', 'checked_at', 'saved_at']) ||
        !_context(s['context']) ||
        !_ready(s['context']) ||
        !_stamp(s['checked_at']) ||
        !_stamp(s['saved_at']) ||
        d['version'] == 0) {
      throw _bad;
    }
    validateMetaDestination(s['destination']);
  }
  if (d['selection_current'] &&
      (!d['lookup_ready'] ||
          s == null ||
          !_sameContext(d['context'], s['context']))) {
    throw _bad;
  }
  return d;
}

List<Map<String, dynamic>> validateMetaDestinationChoices(
  Map<String, dynamic> d,
  Map<String, dynamic> state,
  String funnel,
  String campaign,
) {
  if (!_keys(d, [
        'source',
        'funnel_id',
        'campaign_id',
        'fingerprint',
        'checked_at',
        'expires_at',
        'choices',
        'send_ready',
        'provider_verified',
      ]) ||
      d['source'] != 'meta_conversion_choices' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['fingerprint'] != state['fingerprint'] ||
      !state['lookup_ready'] ||
      !_stamp(d['checked_at']) ||
      !_stamp(d['expires_at']) ||
      d['choices'] is! List ||
      (d['choices'] as List).length > 500 ||
      d['send_ready'] != false ||
      d['provider_verified'] != false) {
    throw _bad;
  }
  final ttl = DateTime.parse(
    d['expires_at'],
  ).difference(DateTime.parse(d['checked_at'])).inMilliseconds;
  if (ttl <= 0 || ttl > 301000) throw _bad;
  final seen = <String>{}, out = <Map<String, dynamic>>[];
  for (final c in d['choices']) {
    if (!_keys(c, ['destination', 'proof']) ||
        c['proof'] is! String ||
        !RegExp(r'^\d{13}\.[a-f0-9]{64}$').hasMatch(c['proof'])) {
      throw _bad;
    }
    final a = validateMetaDestination(c['destination']);
    if (!seen.add(a['pixel_id'])) throw _bad;
    out.add(Map<String, dynamic>.from(c));
  }
  return out;
}

class FunnelMetaDestination extends StatefulWidget {
  const FunnelMetaDestination({
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
  State<FunnelMetaDestination> createState() => _FunnelMetaDestinationState();
}

class _FunnelMetaDestinationState extends State<FunnelMetaDestination> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>>? _choices;
  String? _selected, _error, _notice, _unavailable;
  bool _busy = false, _confirmed = false, _clearConfirmed = false;
  int _generation = 0;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-conversion-destination';
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
  void _discard() {
    _choices = null;
    _selected = null;
    _confirmed = false;
    _clearConfirmed = false;
  }

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
    _discard();
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
    'Sign in with Enterprise access to view conversion destinations.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close destination setup and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaDestination old) {
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
      _discard();
      _busy = false;
      _unavailable = null;
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

  Future<void> _request([String action = 'read']) async {
    if (_busy || _unavailable != null) return;
    final state = _data,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        g = ++_generation;
    final choice = _choices
        ?.where((c) => c['destination']['pixel_id'] == _selected)
        .firstOrNull;
    if (action != 'read' && state == null ||
        action == 'save' && (choice == null || !_confirmed) ||
        action == 'clear' && !_clearConfirmed) {
      return;
    }
    final body = action == 'save' || action == 'clear'
        ? <String, dynamic>{
            'version': state!['version'],
            'fingerprint': state['fingerprint'],
            'confirmed': true,
            if (action == 'save') ...{
              'destination': choice!['destination'],
              'proof': choice['proof'],
            },
          }
        : null;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _discard();
      if (action != 'choices') _data = null;
    });
    try {
      final result = await client.request(
        body == null ? 'GET' : 'POST',
        action == 'read'
            ? path
            : action == 'choices'
            ? '$path/choices?fingerprint=${state!['fingerprint']}'
            : '$path/$action',
        body: body,
      );
      if (!_current(g)) return;
      if (action == 'choices') {
        final choices = validateMetaDestinationChoices(
          result,
          state!,
          funnel,
          campaign,
        );
        setState(() => _choices = choices);
      } else {
        final d = validateMetaDestinationState(result, funnel, campaign);
        if (action == 'save' &&
                (!d['selection_current'] ||
                    d['version'] != state!['version'] + 1 ||
                    !mapEquals(
                      d['selection']['destination'],
                      choice!['destination'],
                    )) ||
            action == 'clear' &&
                (d['selection'] != null ||
                    d['version'] != state!['version'] + 1)) {
          throw _bad;
        }
        setState(() {
          _data = d;
          _notice = action == 'save'
              ? 'Destination saved. Uploads remain off.'
              : action == 'clear'
              ? 'Saved destination cleared.'
              : null;
        });
      }
    } catch (e) {
      if (_current(g)) {
        setState(() {
          _data = null;
          _discard();
          _error =
              '${e is FunnelException ? e.message : 'Destination setup could not load.'}${body != null ? ' Refresh to check the saved state before trying again.' : ''}';
        });
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Widget _note(String s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(s, style: const TextStyle(height: 1.45)),
  );
  Widget _details(Map a) => _note(
    'Data source (Pixel) ID: ${a['pixel_id']}\nPlanned event: Lead · Delivery is not configured',
  );
  @override
  Widget build(BuildContext context) {
    final d = _data, s = d?['selection'];
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
                      'Meta conversion destination',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close destination setup',
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
                      _note(metaDestinationBoundary),
                      if (_unavailable != null) _note(_unavailable!),
                      if (_unavailable == null) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _request(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh destination setup'),
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        if (_error != null) _note(_error!),
                        if (_notice != null) _note(_notice!),
                        if (d != null) ...[
                          _note(d['campaign_name']),
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

                          if (s == null)
                            _note('No conversion destination saved.'),
                          if (s != null) ...[
                            Text(
                              d['selection_current']
                                  ? 'Saved for the current Meta campaign'
                                  : 'Saved destination needs review',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            _note(s['destination']['name']),
                            _details(s['destination']),
                            _note('Last checked with Meta: ${s['checked_at']}'),
                            if (!d['selection_current'])
                              _note(
                                'The campaign or Meta connection changed. Load the current data sources and save a new selection before future delivery setup.',
                              ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _clearConfirmed,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                      () => _clearConfirmed = v == true,
                                    ),
                              title: const Text(
                                'Clear this saved destination.',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: !_busy && _clearConfirmed
                                  ? () => _request('clear')
                                  : null,
                              child: const Text('Clear destination'),
                            ),
                          ],
                          const SizedBox(height: 18),
                          if (!d['lookup_ready'])
                            _note(
                              'Platform setup, an active Meta ad account and a linked Meta campaign are required. Reopen the campaign if it is archived.',
                            ),
                          OutlinedButton(
                            onPressed: !_busy && d['lookup_ready']
                                ? () => _request('choices')
                                : null,
                            child: const Text('Load Meta data sources'),
                          ),
                          _note(
                            'Only data sources listed for the selected ad account appear here. The saved choice must be checked again during delivery setup.',
                          ),
                          if (_choices != null && _choices!.isEmpty)
                            _note(
                              'No data sources were listed for this account. Review its shared assets in Meta, then load the list again.',
                            ),
                          if (_choices != null && _choices!.isNotEmpty) ...[
                            _note(
                              'Choose a data source. Choices expire after five minutes; saving checks the source again.',
                            ),
                            RadioGroup<String>(
                              groupValue: _selected,
                              onChanged: (v) => setState(() {
                                _selected = v;
                                _confirmed = false;
                              }),
                              child: Column(
                                children: [
                                  for (final c in _choices!)
                                    RadioListTile<String>(
                                      contentPadding: EdgeInsets.zero,
                                      value: c['destination']['pixel_id'],
                                      title: Text(c['destination']['name']),
                                      subtitle: _details(c['destination']),
                                    ),
                                ],
                              ),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _confirmed,
                              onChanged: _selected == null
                                  ? null
                                  : (v) =>
                                        setState(() => _confirmed = v == true),
                              title: const Text(
                                'Save this data source for future Lead events. This does not enable uploads.',
                              ),
                            ),
                            FilledButton(
                              onPressed:
                                  !_busy && _selected != null && _confirmed
                                  ? () => _request('save')
                                  : null,
                              child: const Text('Save destination'),
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
