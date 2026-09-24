import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_google_preflight.dart';
import 'funnel_google_creative.dart';
import 'funnel_google_keywords.dart';
import 'funnel_google_targeting.dart';
import 'funnel_google_radius.dart';
import 'funnel_google_locations.dart';

const googleCreationBoundary =
    'Creates a Google Search campaign, one ad group and one responsive search ad, all paused. Uses your saved keywords and geographic targets. Google matches languages from your ads and landing page; content languages are planning notes. Google Search only; Search Partners and Display are off. This does not start ad delivery, authorize activation or verify conversions. Local edits and archiving do not change Google resources.';
const googleCreationBudget =
    'Google uses an average daily budget and may spend more on individual days after activation. Your planned total is not a hard spending cap. This step does not activate the campaign.';
const _bad = FunnelException(
  'The creation details could not be verified. Refresh the record before continuing.',
  503,
);
bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a is List && b is List
    ? a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]))
    : a == b;
bool _int(dynamic v, int min, int max) => v is int && v >= min && v <= max;
bool _date(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse('${v}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        v;
bool _stamp(dynamic v) => v is String && DateTime.tryParse(v) != null;
bool _text(dynamic v, int max) =>
    v is String &&
    v.isNotEmpty &&
    v.length <= max &&
    v.trim() == v &&
    !v.contains('\u0000');
bool _uuid(dynamic v) =>
    v is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(v);
bool _customer(dynamic v) => v is String && RegExp(r'^\d{10}$').hasMatch(v);
bool _id(String v) =>
    RegExp(r'^[1-9]\d{0,18}$').hasMatch(v) &&
    BigInt.parse(v) <= BigInt.parse('9223372036854775807');
bool _resource(dynamic v, String account, String type) {
  if (v is! String || !v.startsWith('customers/$account/$type/')) return false;
  final pieces = v.substring('customers/$account/$type/'.length).split('~');
  return pieces.length == (type == 'adGroupAds' ? 2 : 1) && pieces.every(_id);
}

void _snapshot(dynamic s, String campaign, String attempt, Map catalog) {
  if (s is! Map ||
      (s.containsKey('search_language_mode') &&
          s['search_language_mode'] != 'automatic_from_creative_v1') ||
      s['plan'] is! Map ||
      s['page'] is! Map ||
      s['identity'] is! Map ||
      s['creative'] is! Map ||
      !googleKeywordsValid(s['keywords']) ||
      !googleTargetingValid(s['targeting'], catalog) ||
      !googleTargetingComplete(s['targeting']) ||
      s['targeting']['bidding'] != 'maximize_clicks') {
    throw _bad;
  }
  final p = s['plan'], i = s['identity'], a = i['account'], cr = s['creative'];
  if (p['id'] != campaign ||
      !_text(p['name'], 100) ||
      !_int(p['daily_cents'], 100, 1000000) ||
      !_int(p['days'], 1, 90) ||
      p['currency'] != 'USD' ||
      p['planned_total_cents'] != p['daily_cents'] * p['days'] ||
      a is! Map ||
      !_customer(a['id']) ||
      !_text(a['name'], 200) ||
      a['currency'] != 'USD' ||
      a['manager'] != false ||
      a['test_account'] != false ||
      a['status'] != 'ENABLED' ||
      !_text(a['timezone'], 100) ||
      !_customer(i['root_id']) ||
      !(i['login_customer_id'] == i['root_id'] ||
          (i['login_customer_id'] == null && i['root_id'] == a['id'])) ||
      !_int(i['connection_version'], 1, 2147483647) ||
      !_date(s['start_date']) ||
      !_date(s['end_date']) ||
      s['provider_name'] != 'KORLIX $attempt' ||
      s['no_eu_political_ads'] != true ||
      s['budget_acknowledged'] != true) {
    throw _bad;
  }
  final expectedEnd = DateTime.parse('${s['start_date']}T00:00:00Z')
      .add(Duration(days: (p['days'] as int) - 1))
      .toIso8601String()
      .substring(0, 10);
  if (s['end_date'] != expectedEnd) throw _bad;
  final destination = s['page']['destination'] is String
      ? Uri.tryParse(s['page']['destination'])
      : null;
  if (destination == null ||
      destination.scheme != 'https' ||
      destination.host.isEmpty ||
      destination.userInfo.isNotEmpty ||
      destination.hasFragment ||
      destination.queryParameters['utm_source'] != 'google' ||
      destination.queryParameters['utm_campaign'] !=
          'k143_${campaign.replaceAll('-', '')}') {
    throw _bad;
  }
  for (final (key, min, max, limit) in [
    ('headlines', 3, 15, 30),
    ('descriptions', 2, 4, 90),
  ]) {
    final list = cr[key];
    if (list is! List ||
        list.length < min ||
        list.length > max ||
        list.any(
          (v) =>
              v is! String ||
              v.isEmpty ||
              googleDraftTextError(v, limit) != null,
        )) {
      throw _bad;
    }
  }
  for (final key in ['path1', 'path2']) {
    if (cr[key] is! String ||
        googleDraftTextError(cr[key], 15, path: true) != null) {
      throw _bad;
    }
  }
}

Map<String, dynamic> validateGoogleCreation(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (d['source'] != 'google_paused_creation' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['fingerprint']) ||
      d['activation_supported'] != false ||
      d['ad_publishing_ready'] != false ||
      d['create_ready'] is! bool ||
      d['preparation'] is! Map<String, dynamic> ||
      d['checks'] is! Map ||
      d['draft'] is! Map ||
      (d['notice'] != null && !_text(d['notice'], 1000))) {
    throw _bad;
  }
  final prep = validateGooglePreflight(d['preparation'], funnel, campaign),
      setup = prep['setup']['current_snapshot'];
  final expected = {
    'search_language_mode': 'automatic_from_creative_v1',
    'plan': setup['campaign'],
    'page': setup['landing_page'],
    'identity': setup['google_ads'],
    'creative': prep['creative']['assets'],
    'keywords': prep['keywords']['assets'],
    'targeting': prep['targeting']['assets'],
  };
  if (!_same(d['draft'], expected)) throw _bad;
  final checks = d['checks'] as Map, attempt = d['attempt'];
  if (checks.length != 5 ||
      checks.values.any((v) => v is! bool) ||
      checks['platform_enabled'] is! bool ||
      checks['preparation_complete'] != prep['preparation_complete'] ||
      checks['maximize_clicks'] !=
          (expected['targeting']['bidding'] == 'maximize_clicks') ||
      checks['account_calendar'] != (d['today'] != null) ||
      checks['no_previous_attempt'] != (attempt == null) ||
      d['create_ready'] !=
          (checks.values.every((v) => v == true) && attempt == null)) {
    throw _bad;
  }
  if (d['today'] == null
      ? d['latest_start'] != null
      : !_date(d['today']) ||
            !_date(d['latest_start']) ||
            DateTime.parse(
                  d['latest_start'],
                ).difference(DateTime.parse(d['today'])).inDays !=
                30) {
    throw _bad;
  }
  if (attempt != null) {
    if (attempt is! Map ||
        !_uuid(attempt['id']) ||
        !['unknown', 'created'].contains(attempt['state']) ||
        !_stamp(attempt['created_at'])) {
      throw _bad;
    }
    _snapshot(
      attempt['snapshot'],
      campaign,
      attempt['id'],
      prep['targeting']['catalog'],
    );
    if (attempt['state'] == 'unknown') {
      if (attempt['resources'] != null || attempt['completed_at'] != null) {
        throw _bad;
      }
    } else {
      final r = attempt['resources'],
          account = attempt['snapshot']['identity']['account']['id'] as String;
      if (!_stamp(attempt['completed_at']) ||
          r is! Map ||
          r.length != 4 ||
          !_resource(r['budget'], account, 'campaignBudgets') ||
          !_resource(r['campaign'], account, 'campaigns') ||
          !_resource(r['ad_group'], account, 'adGroups') ||
          !_resource(r['ad'], account, 'adGroupAds') ||
          (r['ad'] as String).split('/').last.split('~').first !=
              (r['ad_group'] as String).split('/').last) {
        throw _bad;
      }
    }
  }
  return d;
}

String googleCreationSummary(Map<String, dynamic> d) {
  final attempt = d['attempt'],
      s = attempt == null ? d['draft'] : attempt['snapshot'],
      p = s['plan'],
      i = s['identity'],
      a = i['account'],
      t = s['targeting'];
  final out = StringBuffer('KORLIX GOOGLE PAUSED CREATION\n');
  out.writeln(
    'Plan: ${p['name']}\nStatus: ${attempt == null
        ? 'NOT CREATED'
        : attempt['state'] == 'created'
        ? 'CREATION RECORDED'
        : 'OUTCOME NEEDS CHECKING'}',
  );
  out.writeln(
    'Account: ${a == null ? '(not selected)' : '${a['name']} (${a['id']})'}\nAccount timezone: ${a?['timezone'] ?? '(unavailable)'}\nAccess account: ${i['root_id'] ?? '(none)'}\nAverage daily budget: \$${(p['daily_cents'] / 100).toStringAsFixed(2)} USD\nPlanned duration: ${p['days']} days',
  );
  if (attempt != null) {
    out.writeln(
      'Creation name: ${s['provider_name']}\nStart: ${s['start_date']} 00:00:00\nEnd: ${s['end_date']} 23:59:59\nRecorded: ${attempt['created_at']}\nCompleted: ${attempt['completed_at'] ?? '(unconfirmed)'}\nEU political advertising: declared not present',
    );
  }
  out.writeln(
    'Destination: ${s['page']['destination']}\nSearch-ad headlines:\n${(s['creative']['headlines'] as List).join('\n')}\nDescriptions:\n${(s['creative']['descriptions'] as List).join('\n')}\nDisplay paths: ${s['creative']['path1']} / ${s['creative']['path2']}',
  );
  for (final key in googleKeywordLabels.keys) {
    out.writeln(
      '${googleKeywordLabels[key]}: ${(s['keywords'][key] as List).join(', ')}',
    );
  }
  out.writeln(
    'Target countries: ${(t['countries'] as List).join(', ')}\nExcluded countries: ${(t['excluded_countries'] as List).join(', ')}\nContent languages (planning): ${(t['content_languages'] as List).join(', ')}\nLocation reach: ${googleLocationModes[t['location_mode']]}\nCountry exclusions: presence\nBidding: ${googleBiddingPlans[t['bidding']]}',
  );
  out.writeln(
    s['search_language_mode'] == 'automatic_from_creative_v1'
        ? 'Language matching: automatic from ads and landing page. No manual language criteria are sent.'
        : 'Language settings: historical manual criteria preserved in this creation record; Google now matches Search languages from content.',
  );
  if (t.containsKey('geo_locations')) out.writeln(googleLocationsSummary(t));
  if (t.containsKey('proximities')) out.writeln(googleRadiusSummary(t));
  if (attempt?['resources'] != null) {
    for (final e in (attempt['resources'] as Map).entries) {
      out.writeln('${e.key}: ${e.value}');
    }
  }
  out.writeln(
    '\n$googleCreationBoundary\n$googleCreationBudget\nCreation records are historical. Current Google delivery status is not monitored here. Reporting associations are managed separately.',
  );
  return out.toString();
}

class FunnelGoogleCreate extends StatefulWidget {
  const FunnelGoogleCreate({
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
  State<FunnelGoogleCreate> createState() => _FunnelGoogleCreateState();
}

class _FunnelGoogleCreateState extends State<FunnelGoogleCreate> {
  Map<String, dynamic>? _data;
  final _start = TextEditingController();
  bool _busy = false, _paused = false, _budget = false, _political = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-create';
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
  void _resetConfirmation() {
    _paused = false;
    _budget = false;
    _political = false;
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
    _busy = false;
    _error = null;
    _message = null;
    _unavailable = message;
    _resetConfirmation();
    _start.clear();
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
    'Sign in with Enterprise access to view this creation record.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close this record and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleCreate old) {
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
      _unavailable = null;
      _data = null;
      _start.clear();
      unawaited(_request());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    _start.dispose();
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
      _message = null;
      _resetConfirmation();
    });
    try {
      final r = await widget.client.request(
        action.isEmpty ? 'GET' : 'POST',
        '$_path${action.isEmpty ? '' : '/$action'}',
        body: body,
      );
      if (!_current(g)) return;
      final d = validateGoogleCreation(r, widget.funnelId, widget.campaignId);
      setState(() {
        _data = d;
        _message = d['notice'];
        if (d['attempt'] == null) _start.text = d['today'] ?? '';
      });
    } catch (e) {
      if (!_current(g)) return;
      if (e is FunnelException && [401, 403].contains(e.status)) {
        _deny();
      } else if (e is FunnelException && e.status == 404) {
        _invalidate('This campaign is no longer available.');
      } else {
        setState(
          () => _error =
              '${e is FunnelException ? e.message : 'Creation details are unavailable.'} Refresh the saved record before continuing.',
        );
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final d = _data;
    if (_busy ||
        d == null ||
        d['create_ready'] != true ||
        !_paused ||
        !_budget ||
        !_political) {
      return;
    }
    final date = _start.text.trim();
    if (!_date(date) ||
        date.compareTo(d['today']) < 0 ||
        date.compareTo(d['latest_start']) > 0) {
      setState(
        () => _error =
            'Choose a date from ${d['today']} through ${d['latest_start']} in the account timezone.',
      );
      return;
    }
    await _request(
      action: 'create',
      body: {
        'fingerprint': d['fingerprint'],
        'start_date': date,
        'confirmed': true,
        'budget_acknowledged': true,
        'no_eu_political_ads': true,
      },
    );
  }

  Future<void> _preparation() async {
    if (_busy || _unavailable != null) return;
    final g = _generation;
    setState(() {
      _busy = true;
      _resetConfirmation();
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FunnelGooglePreflight(
        client: widget.client,
        funnelId: widget.funnelId,
        campaignId: widget.campaignId,
        scope: widget.scope,
      ),
    );
    if (_current(g)) await _request();
  }

  Future<void> _copy() async {
    final d = _data, g = _generation;
    if (_busy || d == null || _unavailable != null) return;
    try {
      await Clipboard.setData(ClipboardData(text: googleCreationSummary(d)));
      if (_current(g)) setState(() => _message = 'Creation summary copied.');
    } catch (_) {
      if (_current(g)) {
        setState(() => _error = 'The summary could not be copied.');
      }
    }
  }

  Widget _line(String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(text, style: TextStyle(color: color, height: 1.4)),
  );
  @override
  Widget build(BuildContext context) {
    final d = _data;
    final attempt = d?['attempt'];
    final s = attempt == null ? (d?['draft']) : attempt['snapshot'];
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
                    'Create paused Google campaign',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              _line(googleCreationBoundary, color: WfStyle.muted),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_unavailable != null) _line(_unavailable!),
              if (_error != null) _line(_error!, color: WfStyle.gold),
              if (_message != null) _line(_message!, color: WfStyle.cyan),
              if (d != null && s != null) ...[
                _line(s['plan']['name']),
                _line(
                  'Account: ${s['identity']['account'] == null ? '(not selected)' : '${s['identity']['account']['name']} (${s['identity']['account']['id']})'}',
                ),
                _line(
                  'Account timezone: ${s['identity']['account']?['timezone'] ?? '(unavailable)'}',
                ),
                _line(
                  'Average daily budget: \$${(s['plan']['daily_cents'] / 100).toStringAsFixed(2)} USD · ${s['plan']['days']} days planned',
                ),
                _line(googleCreationBudget, color: WfStyle.gold),
                if (attempt == null) ...[
                  if (d['checks']['platform_enabled'] != true)
                    _line(
                      'Paused creation will be available after KORLIX Google platform activation.',
                    ),
                  if (d['checks']['preparation_complete'] != true)
                    _line(
                      'Complete the current campaign, account, copy, keyword and targeting reviews.',
                    ),
                  if (d['checks']['maximize_clicks'] != true)
                    _line(
                      'This first creation version supports Maximize Clicks. Update and review the targeting draft to use it.',
                    ),
                  if (d['create_ready'] == true) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _start,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'Start date (YYYY-MM-DD)',
                        helperText:
                            '${d['today']} through ${d['latest_start']}',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(_resetConfirmation),
                    ),
                    if (_date(_start.text.trim()))
                      _line(
                        'Creation window: ${_start.text.trim()} 00:00:00 through ${DateTime.parse('${_start.text.trim()}T00:00:00Z').add(Duration(days: (s['plan']['days'] as int) - 1)).toIso8601String().substring(0, 10)} 23:59:59 in the account timezone.',
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _paused,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _paused = v == true),
                      title: const Text(
                        'Create the campaign, ad group and ad paused. I am not activating ad delivery.',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _budget,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _budget = v == true),
                      title: const Text(
                        'I understand this is an average daily budget, not a hard daily or total cap.',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _political,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _political = v == true),
                      title: const Text(
                        'I confirm this campaign does not contain EU political advertising.',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || !_paused || !_budget || !_political
                          ? null
                          : _create,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Confirm paused creation'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: _busy ? null : _preparation,
                    child: const Text('Open preparation checklist'),
                  ),
                ] else ...[
                  _line(
                    attempt['state'] == 'created'
                        ? 'CREATION RECORDED'
                        : 'OUTCOME NEEDS CHECKING',
                    color: attempt['state'] == 'created'
                        ? WfStyle.cyan
                        : WfStyle.gold,
                  ),
                  _line(
                    'Creation name: ${s['provider_name']}\nStart: ${s['start_date']} 00:00:00\nEnd: ${s['end_date']} 23:59:59',
                  ),
                  if (attempt['state'] == 'unknown') ...[
                    _line(
                      'The request may have reached Google. KORLIX will not resend it. Checking is read-only; a missing result does not prove failure.',
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _request(
                              action: 'reconcile',
                              body: {'attempt_id': attempt['id']},
                            ),
                      child: const Text('Check creation result'),
                    ),
                  ] else ...[
                    _line(
                      'Created in a paused state. This historical record does not monitor current delivery or policy approval. Activation is not available here.',
                    ),
                    _line(
                      'Google campaign ID: ${(attempt['resources']['campaign'] as String).split('/').last}',
                    ),
                  ],
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Review exact campaign details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(googleCreationSummary(d)),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy ? null : _copy,
                  child: const Text('Copy creation summary'),
                ),
              ],
              if (_unavailable == null)
                OutlinedButton(
                  onPressed: _busy ? null : () => _request(),
                  child: const Text('Refresh creation record'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
