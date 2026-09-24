import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_create.dart';

const metaControlsBoundary =
    'Activation enables paused ads and ad sets first, then the saved Meta campaign. These are separate changes; an incomplete result blocks further KORLIX commands. Delivery may incur charges. Pause changes the campaign only. Local edits and archiving do not change Meta delivery. Status is a point-in-time observation; Meta review and eligibility still apply.';
const metaControlsBudget =
    'Meta uses an average daily budget and may spend more on individual days. The planned total is not a hard spending cap. Budget changes need a separate review below. Schedule changes are not available here.';
const metaBudgetImpact =
    'Changing the average daily budget can change spending on an active campaign. Lowering it does not undo earlier charges or guarantee a lower bill today. Meta may spend more on individual days. This is not a hard total cap and does not pause or activate the campaign.';
bool _cents(dynamic v) => v is int && v >= 100 && v <= 1000000;
String _money(dynamic cents) => '\$${(cents / 100).toStringAsFixed(2)} USD';
int? parseMetaBudget(String value) {
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
bool _same(dynamic a, dynamic b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}

bool _keys(dynamic v, List<String> names) =>
    v is Map && v.length == names.length && names.every(v.containsKey);
bool _effective(dynamic v) =>
    v is String && RegExp(r'^[A-Z_]{1,40}$').hasMatch(v);
void _observation(dynamic o, Map creation) {
  final resources = creation['attempt']?['resources'];
  if (o is! Map ||
      creation['attempt']?['state'] != 'created' ||
      o['status'] is! Map ||
      !_text(o['status']['name']) ||
      ![
        'ACTIVE',
        'PAUSED',
        'ARCHIVED',
        'DELETED',
      ].contains(o['status']['status']) ||
      !_effective(o['status']['effective_status']) ||
      o['status']['resource'] != resources['campaign'] ||
      o['can_activate'] is! bool ||
      o['can_pause'] is! bool ||
      (o['reason'] != null && !_text(o['reason']))) {
    throw _bad;
  }
  final g = o['graph'];
  if (g != null) {
    const effective = {
      'campaign': ['ACTIVE', 'PAUSED'],
      'ad_set': ['ACTIVE', 'PAUSED', 'CAMPAIGN_PAUSED', 'IN_PROCESS'],
      'ad': [
        'ACTIVE',
        'PAUSED',
        'CAMPAIGN_PAUSED',
        'ADSET_PAUSED',
        'PENDING_REVIEW',
        'IN_PROCESS',
        'PREAPPROVED',
      ],
    };
    if (g is! Map ||
        !_same(g['resources'], resources) ||
        !_keys(g['statuses'], ['campaign', 'ad_set', 'ad']) ||
        !_keys(g['effective_statuses'], ['campaign', 'ad_set', 'ad']) ||
        g['statuses']['campaign'] != 'PAUSED' ||
        o['status']['status'] != 'PAUSED' ||
        g['effective_statuses']['campaign'] !=
            o['status']['effective_status'] ||
        [
          'ad_set',
          'ad',
        ].any((k) => !['ACTIVE', 'PAUSED'].contains(g['statuses'][k])) ||
        effective.keys.any(
          (k) => !effective[k]!.contains(g['effective_statuses'][k]),
        )) {
      throw _bad;
    }
  }
  if (o['can_activate'] && (g == null || o['status']['status'] != 'PAUSED') ||
      o['can_pause'] && o['status']['status'] != 'ACTIVE') {
    throw _bad;
  }
}

void _budgetObservation(dynamic o, Map creation) {
  final resources = creation['attempt']?['resources'];
  if (o is! Map ||
      creation['attempt']?['state'] != 'created' ||
      o['kind'] != 'budget' ||
      !_cents(o['daily_cents']) ||
      o['status'] is! Map ||
      !_text(o['status']['name']) ||
      o['status']['resource'] != resources['campaign'] ||
      !['ACTIVE', 'PAUSED'].contains(o['status']['status']) ||
      !_effective(o['status']['effective_status']) ||
      o['budget'] is! Map ||
      o['budget']['resource'] != resources['ad_set'] ||
      !_cents(o['budget']['daily_cents']) ||
      o['daily_cents'] == o['budget']['daily_cents'] ||
      !['ACTIVE', 'PAUSED'].contains(o['budget']['status']) ||
      !_effective(o['budget']['effective_status']) ||
      o['increase'] != (o['daily_cents'] > o['budget']['daily_cents'])) {
    throw _bad;
  }
  final g = o['graph'];
  if (o['increase']) {
    const effective = {
      'campaign': ['ACTIVE', 'PAUSED'],
      'ad_set': ['ACTIVE', 'PAUSED', 'CAMPAIGN_PAUSED', 'IN_PROCESS'],
      'ad': [
        'ACTIVE',
        'PAUSED',
        'CAMPAIGN_PAUSED',
        'ADSET_PAUSED',
        'PENDING_REVIEW',
        'IN_PROCESS',
        'PREAPPROVED',
      ],
    };
    if (g is! Map ||
        !_same(g['resources'], resources) ||
        !_keys(g['statuses'], ['campaign', 'ad_set', 'ad']) ||
        !_keys(g['effective_statuses'], ['campaign', 'ad_set', 'ad']) ||
        g['statuses']['campaign'] != o['status']['status'] ||
        g['statuses']['ad_set'] != o['budget']['status'] ||
        g['effective_statuses']['campaign'] !=
            o['status']['effective_status'] ||
        g['effective_statuses']['ad_set'] != o['budget']['effective_status'] ||
        g['statuses'].values.any((v) => !['ACTIVE', 'PAUSED'].contains(v)) ||
        effective.keys.any(
          (k) => !effective[k]!.contains(g['effective_statuses'][k]),
        )) {
      throw _bad;
    }
  } else if (g != null) {
    throw _bad;
  }
}

Map<String, dynamic> validateMetaControls(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (d['source'] != 'meta_campaign_controls' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      !_hash(d['fingerprint']) ||
      d['creation'] is! Map<String, dynamic> ||
      d['checks'] is! Map ||
      d['activation_ready'] is! bool ||
      d['budget_enabled'] is! bool ||
      (d['budget_enabled'] == true &&
          d['checks']['platform_enabled'] != true) ||
      (d['notice'] != null && !_text(d['notice']))) {
    throw _bad;
  }
  final creation = validateMetaCreation(d['creation'], funnel, campaign),
      checks = d['checks'] as Map,
      cmd = d['latest_command'],
      snapshot = creation['attempt']?['snapshot'],
      draft = creation['draft'];
  const names = [
    'platform_enabled',
    'creation_recorded',
    'no_uncertain_command',
    'command_capacity',
    'preparation_current',
    'saved_content_current',
    'identity_current',
    'schedule_open',
  ];
  final saved = snapshot == null
      ? null
      : (Map.from(snapshot)..removeWhere(
          (k, v) => [
            'identity',
            'start_date',
            'end_date',
            'start_time',
            'end_time',
            'provider_name',
            'budget_acknowledged',
          ].contains(k),
        ));
  final current = Map.from(draft)..remove('identity');
  if (!_keys(checks, names) ||
      checks.values.any((v) => v is! bool) ||
      d['activation_ready'] != checks.values.every((v) => v == true) ||
      checks['creation_recorded'] !=
          (creation['attempt']?['state'] == 'created') ||
      checks['preparation_current'] !=
          (creation['preparation']['review_current'] &&
              creation['preparation']['creative']['setup']['review_current']) ||
      checks['saved_content_current'] !=
          (saved != null && _same(saved, current)) ||
      checks['identity_current'] !=
          (snapshot != null &&
              _same(
                snapshot['identity']['account'],
                draft['identity']['account'],
              ) &&
              _same(snapshot['identity']['page'], draft['identity']['page']))) {
    throw _bad;
  }
  if (cmd != null) {
    if (cmd is! Map ||
        !_uuid(cmd['id']) ||
        !['activate', 'pause', 'budget'].contains(cmd['action']) ||
        !['unknown', 'confirmed'].contains(cmd['state']) ||
        cmd['sequence'] is! int ||
        cmd['sequence'] < 1 ||
        cmd['sequence'] > 1000 ||
        !_stamp(cmd['created_at']) ||
        (cmd['state'] == 'confirmed'
            ? !_stamp(cmd['confirmed_at'])
            : cmd['confirmed_at'] != null)) {
      throw _bad;
    }
    final observed = cmd['observed'];
    if (cmd['action'] == 'budget') {
      _budgetObservation(observed, creation);
      if (!_cents(cmd['daily_cents']) ||
          cmd['daily_cents'] != observed['daily_cents'] ||
          !_same(cmd['steps'], ['budget']) ||
          !(_same(cmd['progress'], {}) ||
              _same(cmd['progress'], {'budget': cmd['daily_cents']})) ||
          (cmd['state'] == 'confirmed' &&
              !_same(cmd['progress'], {'budget': cmd['daily_cents']}))) {
        throw _bad;
      }
    } else {
      if (cmd['daily_cents'] != null) throw _bad;
      _observation(observed, creation);
      if (observed[cmd['action'] == 'activate'
              ? 'can_activate'
              : 'can_pause'] !=
          true) {
        throw _bad;
      }
      final steps = cmd['action'] == 'pause'
          ? ['campaign']
          : ['ad', 'ad_set', 'campaign']
                .where((k) => observed['graph']['statuses'][k] == 'PAUSED')
                .toList();
      final progress = cmd['progress'];
      if (!_same(cmd['steps'], steps) ||
          progress is! Map ||
          progress.length > steps.length ||
          progress.keys.any((k) => !steps.take(progress.length).contains(k)) ||
          progress.values.any(
            (v) => v != (cmd['action'] == 'activate' ? 'ACTIVE' : 'PAUSED'),
          ) ||
          (cmd['state'] == 'confirmed' && progress.length != steps.length)) {
        throw _bad;
      }
    }
  }
  if (checks['no_uncertain_command'] != (cmd?['state'] != 'unknown') ||
      checks['command_capacity'] != ((cmd?['sequence'] ?? 0) < 1000)) {
    throw _bad;
  }
  final managed = d['managed_budget'];
  if (checks['creation_recorded']) {
    if (!_keys(managed, [
          'daily_cents',
          'original_daily_cents',
          'command_id',
          'confirmed_at',
        ]) ||
        !_cents(managed['daily_cents']) ||
        managed['original_daily_cents'] != snapshot['plan']['daily_cents'] ||
        (managed['command_id'] == null
            ? managed['confirmed_at'] != null ||
                  managed['daily_cents'] != managed['original_daily_cents']
            : !_uuid(managed['command_id']) ||
                  !_stamp(managed['confirmed_at']))) {
      throw _bad;
    }
    if (cmd?['action'] == 'budget') {
      if (cmd['state'] == 'confirmed') {
        if (managed['command_id'] != cmd['id'] ||
            managed['daily_cents'] != cmd['daily_cents'] ||
            managed['confirmed_at'] != cmd['confirmed_at']) {
          throw _bad;
        }
      } else if (managed['command_id'] == cmd['id'] ||
          managed['daily_cents'] != cmd['observed']['budget']['daily_cents']) {
        throw _bad;
      }
    }
  } else if (managed != null) {
    throw _bad;
  }
  final proposal = d['budget_preview'];
  if (proposal != null) {
    _budgetObservation(proposal, creation);
    if (d['observation'] != null ||
        d['budget_enabled'] != true ||
        checks['creation_recorded'] != true ||
        checks['no_uncertain_command'] != true ||
        checks['command_capacity'] != true ||
        proposal['budget']['daily_cents'] != managed['daily_cents'] ||
        (proposal['increase'] && d['activation_ready'] != true) ||
        !_stamp(proposal['checked_at']) ||
        !_proof(proposal['proof'])) {
      throw _bad;
    }
  }
  final o = d['observation'];
  if (o != null) {
    _observation(o, creation);
    if (!_stamp(o['checked_at'])) throw _bad;
    final available =
        checks['platform_enabled'] &&
        checks['creation_recorded'] &&
        checks['no_uncertain_command'] &&
        checks['command_capacity'];
    if (o['can_activate'] !=
            (available &&
                d['activation_ready'] &&
                o['status']['status'] == 'PAUSED' &&
                o['graph'] != null) ||
        o['can_pause'] != (available && o['status']['status'] == 'ACTIVE')) {
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

class FunnelMetaControls extends StatefulWidget {
  const FunnelMetaControls({
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
  State<FunnelMetaControls> createState() => _FunnelMetaControlsState();
}

class _FunnelMetaControlsState extends State<FunnelMetaControls> {
  final _budget = TextEditingController();
  Map<String, dynamic>? _data;
  bool _busy = false, _confirm = false, _spend = false;
  int _generation = 0;
  String? _error, _unavailable;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-controls';
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
    'Sign in with Enterprise access to view campaign controls. Use Meta Ads Manager directly if you need to stop delivery.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close controls and open them again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaControls old) {
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
      final d = validateMetaControls(r, widget.funnelId, widget.campaignId);
      setState(() => _data = d);
    } catch (e) {
      if (!_current(g)) return;
      if (e is FunnelException && [401, 403].contains(e.status)) {
        _deny();
      } else if (e is FunnelException && e.status == 404) {
        _invalidate(
          'This campaign is no longer available. Use Meta Ads Manager directly for delivery controls.',
        );
      } else {
        setState(
          () => _error =
              '${e is FunnelException ? e.message : 'Campaign controls are unavailable.'} Refresh the command record. If a command was sent, its outcome may be uncertain; check Meta Ads Manager for delivery and charges.',
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
    final cents = parseMetaBudget(_budget.text);
    if (_busy || cents == null) return;
    await _request(action: 'budget-preview', body: {'daily_cents': cents});
  }

  Future<void> _applyBudget() async {
    final p = _data?['budget_preview'];
    if (_busy ||
        p == null ||
        !_confirm ||
        !_spend ||
        parseMetaBudget(_budget.text) != p['daily_cents']) {
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
        s = created?['state'] == 'created' ? created['snapshot'] : null;
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
                    'Meta campaign controls',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              _line(metaControlsBoundary, color: WfStyle.muted),
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
                    'Delivery controls will be available after KORLIX Meta platform activation.',
                  ),
                if (s != null) ...[
                  _line('Saved plan: ${s['plan']['name']}'),
                  _line(
                    'Meta account: ${s['identity']['account']['name']} (${s['identity']['account']['id']})',
                  ),
                  if (created?['resources'] != null)
                    _line('Campaign ID: ${created['resources']['campaign']}'),
                  _line(
                    'Original average daily budget: \$${(s['plan']['daily_cents'] / 100).toStringAsFixed(2)} USD',
                  ),
                  _line(
                    'Saved schedule: ${s['start_date']} 00:00:00 through ${s['end_date']} 23:59:59 (${s['identity']['account']['timezone']}).',
                  ),
                  _line(metaControlsBudget, color: WfStyle.gold),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Review saved campaign content'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          metaCreationSummary(d['creation']),
                        ),
                      ),
                    ],
                  ),
                ],
                if (managed != null) ...[
                  _line(
                    'Latest confirmed average daily budget: ${_money(managed['daily_cents'])}',
                  ),
                  _line(
                    'This is the saved receipt value. Review Meta to verify its current value. The original plan and creation history remain unchanged.',
                  ),
                ],
                if (cmd != null) ...[
                  _line(
                    'Last command: ${cmd['action'] == 'activate'
                        ? 'ACTIVATE'
                        : cmd['action'] == 'budget'
                        ? 'BUDGET CHANGE'
                        : 'PAUSE'} · ${cmd['state'] == 'confirmed' ? 'META ACCEPTED' : 'OUTCOME UNCERTAIN'}',
                  ),
                  _line('Requested: ${cmd['created_at']}'),
                  if (cmd['action'] == 'budget')
                    _line(
                      'Requested average daily budget: ${_money(cmd['daily_cents'])}',
                    ),
                  if (cmd['confirmed_at'] != null)
                    _line('Accepted: ${cmd['confirmed_at']}'),
                  for (final stage in cmd['steps'])
                    _line(
                      '${stage == 'ad_set'
                          ? 'Ad set'
                          : stage == 'ad'
                          ? 'Ad'
                          : stage == 'budget'
                          ? 'Ad set budget'
                          : 'Campaign'}: ${cmd['progress'][stage] == null
                          ? 'not confirmed'
                          : stage == 'budget'
                          ? _money(cmd['progress'][stage])
                          : cmd['progress'][stage]}',
                    ),
                  if (cmd['state'] == 'unknown')
                    _line(
                      'Ads may be spending. Check and control this campaign directly in Meta Ads Manager. Further KORLIX commands are blocked; observing a status will not clear the uncertain request.',
                      color: WfStyle.gold,
                    ),
                ],
                if (o != null) ...[
                  _line('Observed Meta status: ${o['status']['status']}'),
                  _line(
                    'Effective campaign status: ${o['status']['effective_status']}',
                  ),
                  _line('Observed at: ${o['checked_at']}'),
                  if (o['reason'] != null)
                    _line(o['reason'], color: WfStyle.gold),
                  if (o['graph'] != null) ...[
                    _line(
                      'Saved campaign details matched at this observation. Activation may trigger Meta review and does not guarantee delivery.',
                    ),
                    for (final stage in ['ad_set', 'ad'])
                      _line(
                        '${stage == 'ad_set' ? 'Ad set' : 'Ad'} status: ${o['graph']['statuses'][stage]} · effective: ${o['graph']['effective_statuses'][stage]}',
                      ),
                  ],
                  if (o['can_activate'] == true || o['can_pause'] == true) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _confirm,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _confirm = v == true),
                      title: Text(
                        o['can_activate'] == true
                            ? 'I confirm activation of this saved campaign, ad set and ad.'
                            : 'I confirm pausing this Meta campaign. Earlier charges may still appear.',
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
                      'Confirmation expires after five minutes. Meta details are checked again before sending. Avoid editing this campaign in another tool during confirmation.',
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
                            ? 'Activate Meta campaign'
                            : 'Pause Meta campaign',
                      ),
                    ),
                  ],
                ],
                if (created?['state'] == 'created') ...[
                  const Divider(height: 32),
                  const Text(
                    'Change Meta budget',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  _line(metaBudgetImpact, color: WfStyle.muted),
                  if (d['budget_enabled'] != true)
                    _line(
                      'Budget changes will be available after KORLIX Meta budget activation.',
                    )
                  else if (d['checks']['no_uncertain_command'] == true &&
                      d['checks']['command_capacity'] == true) ...[
                    _line(
                      'Enter \$1.00–\$10,000.00 USD. Increases require current preparation, matching saved content and an open schedule. A reduction still requires a fresh matching Meta budget.',
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
                              parseMetaBudget(_budget.text) == null ||
                              parseMetaBudget(_budget.text) ==
                                  managed?['daily_cents']
                          ? null
                          : _reviewBudget,
                      child: const Text('Review budget change'),
                    ),
                    if (proposal != null) ...[
                      _line(
                        'Meta budget observed: ${_money(proposal['budget']['daily_cents'])} → ${_money(proposal['daily_cents'])}',
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
                          'I authorize this budget and acknowledge the spending impact, including earlier charges and variable daily spending.',
                        ),
                      ),
                      FilledButton(
                        onPressed: _busy || !_confirm || !_spend
                            ? null
                            : _applyBudget,
                        child: const Text('Apply Meta budget change'),
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
                        child: const Text('Load current Meta status'),
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
