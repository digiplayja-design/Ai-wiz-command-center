import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'funnel_client.dart';

const googleUploadBoundary =
    'Authorize Google Ads and Data Manager access for future inquiry uploads. Ads access is used here to check your selected account and conversion action. No inquiries are uploaded and no ad settings are changed in this step.';
const _bad = FunnelException(
  'Google upload access could not be verified. Refresh it.',
  503,
);
const _scopes = [
  'https://www.googleapis.com/auth/adwords',
  'https://www.googleapis.com/auth/datamanager',
];
bool _keys(dynamic d, List<String> keys) =>
    d is Map && d.length == keys.length && keys.every(d.containsKey);
bool _id(dynamic v) => v is String && RegExp(r'^[0-9]{10}$').hasMatch(v);
bool _uuid(dynamic v) =>
    v is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(v);
bool _opaque(dynamic v) =>
    v is String && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(v);
bool _stamp(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(v) &&
    DateTime.tryParse(v) != null;
bool _account(dynamic a) =>
    _keys(a, [
      'id',
      'name',
      'currency',
      'timezone',
      'status',
      'manager',
      'test_account',
    ]) &&
    _id(a['id']) &&
    a['name'] is String &&
    a['currency'] is String &&
    RegExp(r'^[A-Z]{3}$').hasMatch(a['currency']) &&
    a['timezone'] is String &&
    (a['timezone'] as String).isNotEmpty &&
    a['status'] == 'ENABLED' &&
    a['manager'] == false &&
    a['test_account'] == false;
Map<String, dynamic> validateGoogleUploadAccess(
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
        'destination_current',
        'can_authorize',
        'version',
        'fingerprint',
        'authorization',
        'pending',
        'scope_set',
        'delivery_state',
        'send_ready',
        'provider_verified',
      ]) ||
      d['source'] != 'google_upload_access' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['campaign_name'] is! String ||
      (d['campaign_name'] as String).isEmpty ||
      d['configured'] is! bool ||
      d['destination_current'] is! bool ||
      d['can_authorize'] is! bool ||
      d['can_authorize'] != (d['configured'] && d['destination_current']) ||
      d['version'] is! int ||
      d['version'] < 0 ||
      d['version'] > 2147483647 ||
      d['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['fingerprint']) ||
      d['scope_set'] != 'ads_datamanager_v1' ||
      d['delivery_state'] != 'not_implemented' ||
      d['send_ready'] != false ||
      d['provider_verified'] != false) {
    throw _bad;
  }
  final a = d['authorization'], p = d['pending'];
  if (a == null && d['version'] != 0) throw _bad;
  if (a != null &&
      (!_keys(a, [
            'account',
            'root_id',
            'login_customer_id',
            'connected_at',
            'checked_at',
            'needs_reconnect',
            'current',
          ]) ||
          !_account(a['account']) ||
          !_id(a['root_id']) ||
          !(a['login_customer_id'] == a['root_id'] ||
              a['login_customer_id'] == null &&
                  a['root_id'] == a['account']['id']) ||
          !_stamp(a['connected_at']) ||
          !_stamp(a['checked_at']) ||
          a['needs_reconnect'] is! bool ||
          a['current'] is! bool ||
          d['version'] == 0 ||
          a['current'] && (!d['can_authorize'] || a['needs_reconnect']))) {
    throw _bad;
  }
  if (p != null &&
      (!_keys(p, ['id', 'phase', 'expires_at', 'current']) ||
          !_uuid(p['id']) ||
          ![
            'waiting',
            'exchanging',
            'ready',
            'verifying',
            'failed',
          ].contains(p['phase']) ||
          !_stamp(p['expires_at']) ||
          p['current'] is! bool ||
          p['current'] && !d['can_authorize'])) {
    throw _bad;
  }
  return d;
}

Uri validateGoogleUploadAuthorization(Map<String, dynamic> d) {
  if (!_keys(d, ['source', 'id', 'proof', 'authorization_url', 'expires_in']) ||
      d['source'] != 'google_upload_authorization' ||
      !_uuid(d['id']) ||
      !_opaque(d['proof']) ||
      d['expires_in'] != 600 ||
      d['authorization_url'] is! String) {
    throw _bad;
  }
  final u = Uri.tryParse(d['authorization_url']);
  if (u == null ||
      u.scheme != 'https' ||
      u.host != 'accounts.google.com' ||
      u.port != 443 ||
      u.userInfo.isNotEmpty ||
      u.hasFragment ||
      u.path != '/o/oauth2/v2/auth') {
    throw _bad;
  }
  final q = u.queryParameters, all = u.queryParametersAll;
  if (!_keys(q, [
        'client_id',
        'redirect_uri',
        'response_type',
        'scope',
        'access_type',
        'prompt',
        'state',
        'code_challenge',
        'code_challenge_method',
      ]) ||
      all.values.any((v) => v.length != 1) ||
      !RegExp(
        r'^[A-Za-z0-9_-]{10,200}\.apps\.googleusercontent\.com$',
      ).hasMatch(q['client_id']!) ||
      q['scope'] != _scopes.join(' ') ||
      q['response_type'] != 'code' ||
      q['access_type'] != 'offline' ||
      q['prompt'] != 'consent select_account' ||
      q['code_challenge_method'] != 'S256' ||
      !_opaque(q['code_challenge']) ||
      q['state']!.split('.').length != 2 ||
      q['state']!.split('.').first != d['id'] ||
      !_opaque(q['state']!.split('.').last)) {
    throw _bad;
  }
  final callback = Uri.tryParse(q['redirect_uri']!);
  if (callback == null ||
      callback.scheme != 'https' ||
      callback.host.isEmpty ||
      callback.userInfo.isNotEmpty ||
      callback.hasQuery ||
      callback.hasFragment ||
      callback.path != '/api/funnels/google-upload-access/callback') {
    throw _bad;
  }
  return u;
}

class FunnelGoogleUploadAccess extends StatefulWidget {
  const FunnelGoogleUploadAccess({
    super.key,
    required this.client,
    required this.funnelId,
    required this.campaignId,
    this.scope,
    this.openUrl,
  });
  final FunnelClient client;
  final String funnelId, campaignId;
  final ValueListenable<int>? scope;
  final Future<bool> Function(Uri)? openUrl;
  @override
  State<FunnelGoogleUploadAccess> createState() =>
      _FunnelGoogleUploadAccessState();
}

class _FunnelGoogleUploadAccessState extends State<FunnelGoogleUploadAccess> {
  Map<String, dynamic>? _data, _attempt;
  Uri? _authorization;
  String? _error, _notice, _unavailable;
  bool _busy = false, _confirmed = false, _removeConfirmed = false;
  int _generation = 0;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-upload-access';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  void _clearAttempt() {
    _attempt = null;
    _authorization = null;
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
    _data = null;
    _clearAttempt();
    _busy = false;
    _confirmed = false;
    _removeConfirmed = false;
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
    'Sign in with Enterprise access to view Google upload access.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close upload access and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleUploadAccess old) {
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
      _clearAttempt();
      _busy = false;
      _unavailable = null;
      _confirmed = false;
      _removeConfirmed = false;
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

  void _apply(Map<String, dynamic> d) {
    _data = d;
    final p = d['pending'];
    if (p == null ||
        p['id'] != _attempt?['id'] ||
        !p['current'] ||
        !['waiting', 'exchanging', 'ready'].contains(p['phase'])) {
      _clearAttempt();
    } else if (p['phase'] != 'waiting') {
      _authorization = null;
    }
  }

  Future<void> _run([String action = 'read']) async {
    if (_busy || _unavailable != null) return;
    final d = _data,
        a = _attempt,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId;
    if (action == 'begin' &&
            (d == null || !_confirmed || !d['can_authorize']) ||
        action == 'finish' && a == null ||
        action == 'disconnect' && (d == null || !_removeConfirmed)) {
      return;
    }
    final g = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _confirmed = false;
      _removeConfirmed = false;
      _data = null;
      if (action == 'begin' || action == 'disconnect') _clearAttempt();
    });
    try {
      Map<String, dynamic> result;
      if (action == 'read') {
        result = await client.request('GET', path);
      } else if (action == 'begin') {
        final response = await client.request(
          'POST',
          '$path/begin',
          body: {
            'version': d!['version'],
            'fingerprint': d['fingerprint'],
            'confirmed': true,
          },
        );
        if (!_current(g)) return;
        final uri = validateGoogleUploadAuthorization(response);
        _attempt = {'id': response['id'], 'proof': response['proof']};
        _authorization = uri;
        result = await client.request('GET', path);
      } else if (action == 'finish') {
        result = await client.request(
          'POST',
          '$path/finish',
          body: {...a!, 'confirmed': true},
        );
      } else {
        result = await client.request(
          'POST',
          '$path/disconnect',
          body: {
            'version': d!['version'],
            'fingerprint': d['fingerprint'],
            'confirmed': true,
          },
        );
      }
      if (!_current(g)) return;
      final state = validateGoogleUploadAccess(result, funnel, campaign);
      if (action == 'finish' &&
              (state['authorization']?['current'] != true ||
                  state['pending'] != null ||
                  state['version'] <= (d?['version'] ?? 0)) ||
          action == 'disconnect' &&
              (state['authorization'] != null || state['pending'] != null)) {
        throw _bad;
      }
      setState(() {
        _apply(state);
        _notice = action == 'finish'
            ? 'Google upload permission saved. Inquiry uploads remain off.'
            : action == 'disconnect'
            ? 'Google upload access removed from KORLIX.'
            : null;
      });
    } catch (e) {
      if (!_current(g)) return;
      // An early Finish can be retried only if a fresh local read proves this
      // exact attempt is still unclaimed. Never automatically repeat OAuth writes.
      Map<String, dynamic>? fresh;
      if (action == 'finish') {
        try {
          fresh = validateGoogleUploadAccess(
            await client.request('GET', path),
            funnel,
            campaign,
          );
        } catch (_) {}
        if (!_current(g)) return;
      }
      setState(() {
        if (fresh != null) {
          _apply(fresh);
        } else {
          _data = null;
          _clearAttempt();
        }
        _error =
            '${e is FunnelException ? e.message : 'Google upload access could not load.'} Refresh to check the saved state before trying again.';
      });
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  void _open() {
    if (_authorization == null || _busy || _unavailable != null) return;
    final g = _generation;
    // Keep launch synchronous with the tap for Safari's user-gesture requirement.
    final opening =
        widget.openUrl?.call(_authorization!) ??
        launchUrl(
          _authorization!,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
    opening
        .then((ok) {
          if (_current(g)) {
            setState(() {
              _error = ok
                  ? null
                  : 'The Google window did not open. Tap Continue to Google again.';
              _notice = ok
                  ? 'Complete Google sign-in, then return here and finish upload authorization.'
                  : null;
            });
          }
        })
        .catchError((Object _) {
          if (_current(g)) {
            setState(
              () => _error =
                  'The Google window did not open. Tap Continue to Google again.',
            );
          }
        });
  }

  Widget _note(String s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Text(s, style: const TextStyle(height: 1.45)),
  );
  @override
  Widget build(BuildContext context) {
    final d = _data, a = d?['authorization'], p = d?['pending'];
    final checking = p?['current'] == true && p?['phase'] == 'verifying';
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
                      'Google upload access',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close upload access',
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
                      _note(googleUploadBoundary),
                      if (_unavailable != null) _note(_unavailable!),
                      if (_unavailable == null) ...[
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _run(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh upload access'),
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
                          Text(
                            a == null
                                ? 'Upload permission is not connected'
                                : a['current']
                                ? 'Upload permission saved for this account'
                                : 'Saved upload permission needs review',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (a != null) ...[
                            _note(
                              '${a['account']['name']} · ${a['account']['id']}',
                            ),
                            _note(
                              'Last account access check: ${a['checked_at']}',
                            ),
                            if (!a['current'])
                              _note(
                                'The Google account, destination or authorization changed. Review the connection and destination, then authorize again.',
                              ),
                          ],
                          _note(
                            'Permission alone does not prove that Google will accept conversions. Delivery setup and provider checks are still required.',
                          ),
                          if (!d['configured'])
                            _note(
                              'Google upload authorization is awaiting platform setup.',
                            ),
                          if (!d['destination_current'])
                            _note(
                              'Connect a production Google account and save its current conversion destination first.',
                            ),
                          if (p != null)
                            _note(
                              p['current']
                                  ? 'Authorization status: ${p['phase']}. Expires ${p['expires_at']}.'
                                  : 'The pending authorization is stale. Start again after reviewing setup.',
                            ),
                          if (p != null &&
                              p['current'] &&
                              p['phase'] == 'verifying')
                            _note(
                              'Account checks are in progress. Refresh to see the result; do not start another sign-in yet.',
                            ),
                          if (_attempt != null) ...[
                            if (_authorization != null)
                              FilledButton(
                                onPressed: _busy ? null : _open,
                                child: const Text('Continue to Google'),
                              ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: _busy ? null : () => _run('finish'),
                              child: const Text('Finish upload authorization'),
                            ),
                            _note(
                              'Finish in this same KORLIX window after Google confirms your choice. Closing this screen loses its finish code; start again if needed.',
                            ),
                          ],
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: !_busy && !checking && d['can_authorize']
                                ? (v) => setState(() => _confirmed = v == true)
                                : null,
                            title: const Text(
                              'I want to authorize Google Ads and Data Manager access for future inquiry conversion uploads.',
                            ),
                          ),
                          FilledButton(
                            onPressed:
                                !_busy &&
                                    !checking &&
                                    _confirmed &&
                                    d['can_authorize']
                                ? () => _run('begin')
                                : null,
                            child: const Text('Start upload authorization'),
                          ),
                          _note(
                            'Use a Google sign-in with access to the selected advertising account and its conversion action. Starting again replaces any unfinished upload sign-in for your KORLIX account. Existing Ads access and saved destinations stay in place.',
                          ),
                          if (a != null || p != null) ...[
                            const Divider(height: 32),
                            _note(
                              'Removing upload access applies to all your campaigns in this KORLIX account. It cancels unfinished upload sign-ins and removes the saved upload connection. Your Ads connection stays connected. This does not revoke permissions in your Google account.',
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _removeConfirmed,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                      () => _removeConfirmed = v == true,
                                    ),
                              title: const Text(
                                'Remove Google upload access for all my campaigns.',
                              ),
                            ),
                            OutlinedButton(
                              onPressed: !_busy && _removeConfirmed
                                  ? () => _run('disconnect')
                                  : null,
                              child: const Text('Remove upload access'),
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
