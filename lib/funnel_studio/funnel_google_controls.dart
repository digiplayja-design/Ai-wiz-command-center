import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_google_create.dart';
import 'funnel_google_keywords.dart';
import 'funnel_google_targeting.dart';
import 'funnel_google_radius.dart';
import 'funnel_google_locations.dart';

const googleControlsBoundary =
    'Activation enables the saved Google campaign, ad group and ad. Delivery may begin within its schedule and incur charges. Pause changes the campaign only. Local edits and archiving do not change Google delivery. Status is a point-in-time observation; policy approval does not guarantee delivery.';
const googleControlsBudget =
    'Google uses an average daily budget and may spend more on individual days. The planned total is not a hard spending cap. Budget changes need a separate review below. Schedule changes are not available here.';
const googleBudgetImpact =
    'Changing an average daily budget can change spending immediately on an enabled campaign. Lowering it does not undo earlier charges. For most campaigns, today’s charge limit uses the highest average daily budget set today, up to twice that amount. The monthly limit also changes. This is not a hard total cap and does not pause or activate the campaign.';
bool _cents(dynamic v) => v is int && v >= 100 && v <= 1000000;
String _money(dynamic cents) => '\$${(cents / 100).toStringAsFixed(2)} USD';
int? parseGoogleBudget(String value) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,4})(\.[0-9]{1,2})?$').hasMatch(value.trim())) {
    return null;
  }
  final parts = value.trim().split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  return _cents(cents) ? cents : null;
}

bool _proof(dynamic v) =>
    v is String &&
    v.length <= 3000 &&
    RegExp(r'^[-_A-Za-z0-9]+\.[-_A-Za-z0-9]{43}$').hasMatch(v);
const _bad = FunnelException(
  'Campaign controls could not be verified. Refresh the record.',
  503,
);
bool _stamp(dynamic v) => v is String && DateTime.tryParse(v) != null;
bool _hash(dynamic v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
bool _uuid(dynamic v) =>
    v is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(v);
bool _text(dynamic v) =>
    v is String && v.length <= 1000 && !v.contains('\u0000');
Map<String, dynamic> validateGoogleControls(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (d['source'] != 'google_campaign_controls' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      !_hash(d['fingerprint']) ||
      d['creation'] is! Map<String, dynamic> ||
      d['checks'] is! Map ||
      d['activation_ready'] is! bool ||
      (d['notice'] != null && !_text(d['notice']))) {
    throw _bad;
  }
  final creation = validateGoogleCreation(d['creation'], funnel, campaign),
      checks = d['checks'] as Map,
      cmd = d['latest_command'];
  const names = [
    'platform_enabled',
    'creation_recorded',
    'no_uncertain_command',
    'command_capacity',
    'preparation_current',
    'saved_content_current',
    'schedule_open',
  ];
  if (checks.length != names.length ||
      names.any((k) => checks[k] is! bool) ||
      d['activation_ready'] != checks.values.every((v) => v == true) ||
      checks['creation_recorded'] !=
          (creation['attempt']?['state'] == 'created') ||
      checks['preparation_current'] !=
          creation['preparation']['preparation_complete']) {
    throw _bad;
  }
  if (cmd != null) {
    if (cmd is! Map ||
        !_uuid(cmd['id']) ||
        !['activate', 'pause', 'budget'].contains(cmd['action']) ||
        (cmd['action'] == 'budget'
            ? !_cents(cmd['daily_cents'])
            : cmd['daily_cents'] != null) ||
        !['unknown', 'confirmed'].contains(cmd['state']) ||
        cmd['sequence'] is! int ||
        cmd['sequence'] < 1 ||
        cmd['sequence'] > 1000 ||
        !_stamp(cmd['created_at']) ||
        cmd['observed'] is! Map ||
        (cmd['state'] == 'confirmed'
            ? !_stamp(cmd['confirmed_at'])
            : cmd['confirmed_at'] != null)) {
      throw _bad;
    }
  }
  if (checks['no_uncertain_command'] != (cmd?['state'] != 'unknown') ||
      checks['command_capacity'] != ((cmd?['sequence'] ?? 0) < 1000)) {
    throw _bad;
  }
  if (d['budget_enabled'] is! bool ||
      (d['budget_enabled'] == true && checks['platform_enabled'] != true)) {
    throw _bad;
  }
  final managed = d['managed_budget'];
  if (checks['creation_recorded'] == true) {
    if (managed is! Map ||
        managed.length != 4 ||
        !_cents(managed['daily_cents']) ||
        managed['original_daily_cents'] !=
            creation['attempt']['snapshot']['plan']['daily_cents'] ||
        (managed['command_id'] == null
            ? managed['confirmed_at'] != null ||
                  managed['daily_cents'] != managed['original_daily_cents']
            : !_uuid(managed['command_id']) ||
                  !_stamp(managed['confirmed_at']))) {
      throw _bad;
    }
    if (cmd?['action'] == 'budget' &&
        cmd?['state'] == 'confirmed' &&
        (managed['command_id'] != cmd['id'] ||
            managed['daily_cents'] != cmd['daily_cents'] ||
            managed['confirmed_at'] != cmd['confirmed_at'])) {
      throw _bad;
    }
  } else if (managed != null) {
    throw _bad;
  }
  final proposal = d['budget_preview'];
  if (proposal != null) {
    if (proposal is! Map ||
        d['observation'] != null ||
        d['budget_enabled'] != true ||
        checks['creation_recorded'] != true ||
        checks['no_uncertain_command'] != true ||
        checks['command_capacity'] != true ||
        proposal['kind'] != 'budget' ||
        !_cents(proposal['daily_cents']) ||
        proposal['daily_cents'] == managed['daily_cents'] ||
        proposal['increase'] !=
            (proposal['daily_cents'] > managed['daily_cents']) ||
        proposal['status'] is! Map ||
        !_text(proposal['status']['name']) ||
        !['PAUSED', 'ENABLED'].contains(proposal['status']['status']) ||
        proposal['status']['resource'] !=
            creation['attempt']['resources']['campaign'] ||
        proposal['budget'] is! Map ||
        proposal['budget']['resource'] !=
            creation['attempt']['resources']['budget'] ||
        proposal['budget']['daily_cents'] != managed['daily_cents'] ||
        !_stamp(proposal['checked_at']) ||
        !_proof(proposal['proof'])) {
      throw _bad;
    }
    final graph = proposal['graph'];
    if (proposal['increase'] == true) {
      final resources = creation['attempt']['resources'];
      if (d['activation_ready'] != true ||
          graph is! Map ||
          graph['policy'] != 'APPROVED' ||
          graph['resources'] is! Map ||
          graph['resources'].length != 4 ||
          resources.keys.any((k) => graph['resources'][k] != resources[k]) ||
          graph['statuses'] is! Map ||
          graph['statuses']['campaign'] != proposal['status']['status'] ||
          [
            'ad_group',
            'ad',
          ].any((k) => !['PAUSED', 'ENABLED'].contains(graph['statuses'][k]))) {
        throw _bad;
      }
    } else if (graph != null) {
      throw _bad;
    }
  }
  final o = d['observation'];
  if (o != null) {
    if (o is! Map ||
        o['status'] is! Map ||
        !_stamp(o['checked_at']) ||
        o['can_activate'] is! bool ||
        o['can_pause'] is! bool ||
        !_text(o['status']['name']) ||
        !['ENABLED', 'PAUSED', 'REMOVED'].contains(o['status']['status']) ||
        o['status']['resource'] !=
            creation['attempt']?['resources']?['campaign'] ||
        (o['reason'] != null && !_text(o['reason']))) {
      throw _bad;
    }
    final available =
        checks['platform_enabled'] &&
        checks['creation_recorded'] &&
        checks['no_uncertain_command'] &&
        checks['command_capacity'];
    final g = o['graph'];
    if (g != null) {
      final resources = creation['attempt']['resources'];
      if (g is! Map ||
          g['resources'] is! Map ||
          g['resources'].length != 4 ||
          resources.keys.any((k) => g['resources'][k] != resources[k]) ||
          g['policy'] != 'APPROVED' ||
          g['statuses'] is! Map ||
          g['statuses']['campaign'] != 'PAUSED' ||
          [
            'ad_group',
            'ad',
          ].any((k) => !['ENABLED', 'PAUSED'].contains(g['statuses'][k]))) {
        throw _bad;
      }
    }
    if (o['can_activate'] !=
            (available &&
                d['activation_ready'] &&
                o['status']['status'] == 'PAUSED' &&
                g != null) ||
        o['can_pause'] != (available && o['status']['status'] == 'ENABLED')) {
      throw _bad;
    }
    if (o['can_activate'] || o['can_pause']) {
      if (o['proof'] is! String ||
          o['proof'].length > 3000 ||
          !RegExp(
            r'^[-_A-Za-z0-9]+\.[-_A-Za-z0-9]{43}$',
          ).hasMatch(o['proof'])) {
        throw _bad;
      }
    } else if (o['proof'] != null) {
      throw _bad;
    }
  }
  return d;
}

class FunnelGoogleControls extends StatefulWidget {
  const FunnelGoogleControls({
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
  State<FunnelGoogleControls> createState() => _FunnelGoogleControlsState();
}

class _FunnelGoogleControlsState extends State<FunnelGoogleControls> {
  final _budget = TextEditingController();
  Map<String, dynamic>? _data;
  bool _busy = false, _confirm = false, _spend = false;
  int _generation = 0;
  String? _error, _unavailable;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-controls';
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
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
    _budget.clear();
    _busy = false;
    _error = null;
    _unavailable = message;
    _confirm = false;
    _spend = false;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && g == _generation) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _deny() => _invalidate(
    'Sign in with Enterprise access to view campaign controls. Use Google Ads directly if you need to stop delivery.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close controls and open them again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleControls old) {
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
      _budget.clear();
      _unavailable = null;
      _data = null;
      unawaited(_request());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    _budget.dispose();
    super.dispose();
  }

  Future<void> _request({
    String action = '',
    Map<String, dynamic>? body,
  }) async {
    if (_unavailable != null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _confirm = false;
      _spend = false;
    });
    try {
      final r = await widget.client.request(
        action.isEmpty ? 'GET' : 'POST',
        '$_path${action.isEmpty ? '' : '/$action'}',
        body: body,
      );
      if (!_current(g)) return;
      final d = validateGoogleControls(r, widget.funnelId, widget.campaignId);
      setState(() => _data = d);
    } catch (e) {
      if (!_current(g)) return;
      if (e is FunnelException && [401, 403].contains(e.status)) {
        _deny();
      } else if (e is FunnelException && e.status == 404) {
        _invalidate(
          'This campaign is no longer available. Use Google Ads directly for delivery controls.',
        );
      } else {
        setState(
          () => _error =
              '${e is FunnelException ? e.message : 'Campaign controls are unavailable.'} Refresh the command record. If a command was sent, its outcome may be uncertain; check Google Ads for delivery and charges.',
        );
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _apply(String action) async {
    final o = _data?['observation'];
    if (_busy ||
        o == null ||
        !_confirm ||
        o[action == 'activate' ? 'can_activate' : 'can_pause'] != true ||
        (action == 'activate' && !_spend)) {
      return;
    }
    await _request(
      action: 'apply',
      body: {
        'proof': o['proof'],
        'action': action,
        'confirmed': true,
        'spend_acknowledged': action == 'activate',
      },
    );
  }

  Future<void> _reviewBudget() async {
    final cents = parseGoogleBudget(_budget.text);
    if (_busy || cents == null) return;
    await _request(action: 'budget-preview', body: {'daily_cents': cents});
  }

  Future<void> _applyBudget() async {
    final p = _data?['budget_preview'];
    if (_busy ||
        p == null ||
        !_confirm ||
        !_spend ||
        parseGoogleBudget(_budget.text) != p['daily_cents']) {
      return;
    }
    await _request(
      action: 'budget-apply',
      body: {
        'proof': p['proof'],
        'daily_cents': p['daily_cents'],
        'confirmed': true,
        'spend_acknowledged': true,
      },
    );
  }

  Widget _line(String s, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(s, style: TextStyle(color: color, height: 1.4)),
  );
  @override
  Widget build(BuildContext context) {
    final d = _data,
        o = d?['observation'],
        cmd = d?['latest_command'],
        proposal = d?['budget_preview'],
        managed = d?['managed_budget'],
        created = d?['creation']['attempt'],
        s = created?['snapshot'];
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  const Text(
                    'Google campaign controls',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              _line(googleControlsBoundary, color: WfStyle.muted),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_unavailable != null) _line(_unavailable!),
              if (_error != null) _line(_error!, color: WfStyle.gold),
              if (d?['notice'] != null)
                _line(d!['notice'], color: WfStyle.gold),
              if (d != null) ...[
                if (created == null || created['state'] != 'created')
                  _line(
                    'Complete paused creation and resolve its result before using delivery controls.',
                  ),
                if (d['checks']['platform_enabled'] != true)
                  _line(
                    'Delivery controls will be available after KORLIX Google platform activation.',
                  ),
                if (s != null) ...[
                  _line('Saved plan: ${s['plan']['name']}'),
                  _line(
                    'Google account: ${s['identity']['account']['name']} (${s['identity']['account']['id']})',
                  ),
                  if (created?['resources'] != null)
                    _line(
                      'Campaign ID: ${(created['resources']['campaign'] as String).split('/').last}',
                    ),
                  _line(
                    'Original average daily budget: \$${(s['plan']['daily_cents'] / 100).toStringAsFixed(2)} USD',
                  ),
                  _line(
                    'Saved schedule: ${s['start_date']} 00:00:00 through ${s['end_date']} 23:59:59 (${s['identity']['account']['timezone']}).',
                  ),
                  _line(googleControlsBudget, color: WfStyle.gold),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Review saved campaign content'),
                    children: [
                      _line('Destination: ${s['page']['destination']}'),
                      _line(
                        'Headlines: ${(s['creative']['headlines'] as List).join(' · ')}',
                      ),
                      _line(
                        'Descriptions: ${(s['creative']['descriptions'] as List).join(' · ')}',
                      ),
                      for (final key in googleKeywordLabels.keys)
                        _line(
                          '${googleKeywordLabels[key]}: ${(s['keywords'][key] as List).join(', ')}',
                        ),
                      _line(
                        'Target countries: ${(s['targeting']['countries'] as List).join(', ')}',
                      ),
                      _line(
                        'Excluded countries: ${(s['targeting']['excluded_countries'] as List).join(', ')}',
                      ),
                      _line(
                        'Content languages: ${(s['targeting']['content_languages'] as List).join(', ')}',
                      ),
                      _line(
                        'Location reach: ${googleLocationModes[s['targeting']['location_mode']]}',
                      ),
                      _line(
                        'Bidding: ${googleBiddingPlans[s['targeting']['bidding']]}',
                      ),
                      if (s['targeting'].containsKey('geo_locations'))
                        _line(googleLocationsSummary(s['targeting'])),
                      if (s['targeting'].containsKey('proximities'))
                        _line(googleRadiusSummary(s['targeting'])),
                    ],
                  ),
                ],
                if (managed != null) ...[
                  _line(
                    'Latest confirmed average daily budget: ${_money(managed['daily_cents'])}',
                  ),
                  _line(
                    'This is the saved receipt value. Review Google to verify its current value. The original plan and creation history remain unchanged.',
                  ),
                ],
                if (cmd != null) ...[
                  _line(
                    'Last command: ${cmd['action'] == 'activate'
                        ? 'ACTIVATE'
                        : cmd['action'] == 'budget'
                        ? 'BUDGET CHANGE'
                        : 'PAUSE'} · ${cmd['state'] == 'confirmed' ? 'GOOGLE ACCEPTED' : 'OUTCOME UNCERTAIN'}',
                  ),
                  _line('Requested: ${cmd['created_at']}'),
                  if (cmd['action'] == 'budget')
                    _line(
                      'Requested average daily budget: ${_money(cmd['daily_cents'])}',
                    ),
                  if (cmd['state'] == 'unknown')
                    _line(
                      'Ads may be spending. Check and control this campaign directly in Google Ads. Further KORLIX commands are blocked; observing a status will not clear the uncertain request.',
                      color: WfStyle.gold,
                    ),
                ],
                if (o != null) ...[
                  _line('Observed Google status: ${o['status']['status']}'),
                  _line('Observed at: ${o['checked_at']}'),
                  if (o['reason'] != null)
                    _line(o['reason'], color: WfStyle.gold),
                  if (o['graph'] != null)
                    _line(
                      'Saved structure and approved ad verified at this observation.',
                    ),
                  if (o['can_activate'] == true || o['can_pause'] == true) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirm,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _confirm = v == true),
                      title: Text(
                        o['can_activate'] == true
                            ? 'I confirm activation of this saved campaign, ad group and ad.'
                            : 'I confirm pausing this Google campaign. Earlier charges may still appear.',
                      ),
                    ),
                    if (o['can_activate'] == true)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _spend,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _spend = v == true),
                        title: const Text(
                          'I authorize ad spending using the latest confirmed average daily budget and saved schedule. The planned total is not a hard cap.',
                        ),
                      ),
                    _line(
                      'Confirmation expires after five minutes. Google details are checked again before sending. Avoid editing this campaign in another tool during confirmation.',
                    ),
                    FilledButton(
                      onPressed:
                          _busy ||
                              !_confirm ||
                              (o['can_activate'] == true && !_spend)
                          ? null
                          : () => _apply(
                              o['can_activate'] == true ? 'activate' : 'pause',
                            ),
                      child: Text(
                        o['can_activate'] == true
                            ? 'Activate Google campaign'
                            : 'Pause Google campaign',
                      ),
                    ),
                  ],
                ],
                if (created?['state'] == 'created') ...[
                  const Divider(height: 32),
                  const Text(
                    'Change Google budget',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  _line(googleBudgetImpact, color: WfStyle.muted),
                  if (d['budget_enabled'] != true)
                    _line(
                      'Budget changes will be available after KORLIX Google budget activation.',
                    )
                  else if (d['checks']['no_uncertain_command'] == true &&
                      d['checks']['command_capacity'] == true) ...[
                    _line(
                      'Enter \$1.00–\$10,000.00 USD. Increases require current preparation, matching saved content and an open schedule. A reduction still requires a fresh matching Google budget.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _budget,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'New average daily budget (USD)',
                        hintText: '25.00',
                      ),
                      onChanged: (_) => setState(() {
                        _data?.remove('budget_preview');
                        _data?.remove('observation');
                        _confirm = false;
                        _spend = false;
                      }),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed:
                          _busy ||
                              parseGoogleBudget(_budget.text) == null ||
                              parseGoogleBudget(_budget.text) ==
                                  managed?['daily_cents']
                          ? null
                          : _reviewBudget,
                      child: const Text('Review budget change'),
                    ),
                    if (proposal != null) ...[
                      _line(
                        'Google budget observed: ${_money(proposal['budget']['daily_cents'])} → ${_money(proposal['daily_cents'])}',
                      ),
                      _line(
                        'Campaign status: ${proposal['status']['status']} · Observed at: ${proposal['checked_at']}',
                      ),
                      _line(
                        'This review expires after five minutes. Avoid editing the campaign in another tool while confirming.',
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _confirm,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _confirm = v == true),
                        title: Text(
                          'I confirm changing the average daily budget to ${_money(proposal['daily_cents'])}.',
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _spend,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _spend = v == true),
                        title: const Text(
                          'I authorize this budget and acknowledge the spending impact, including earlier charges and today’s highest budget.',
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy || !_confirm || !_spend
                            ? null
                            : _applyBudget,
                        child: const Text('Apply Google budget change'),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (d['checks']['platform_enabled'] == true &&
                        created?['state'] == 'created')
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _request(action: 'inspect', body: {}),
                        child: const Text('Load current Google status'),
                      ),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _request(),
                      child: const Text('Refresh command record'),
                    ),
                  ],
                ),
              ],
              if (d == null && _unavailable == null && !_busy)
                OutlinedButton(
                  onPressed: () => _request(),
                  child: const Text('Refresh command record'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
