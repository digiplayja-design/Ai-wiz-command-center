import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_images.dart';
import 'funnel_meta_preparation.dart';
import 'funnel_meta_creative.dart';
import 'funnel_meta_targeting.dart';
import 'funnel_meta_radius.dart';
import 'funnel_meta_locations.dart';

const metaCreationBoundary =
    'Uploads your image and creates a Meta traffic campaign, one ad set, one creative and one ad. Campaign, ad set and ad are requested paused. Facebook Feed only, with link-click optimization and impression billing. This does not activate ads or verify conversions. Local edits and archiving do not change Meta resources.';
const metaCreationBudget =
    'Meta uses an average daily budget and may spend more on individual days after activation. The planned total is not a hard spending cap. This step does not activate the campaign.';
const metaCreationReview =
    'Review Meta Ads Manager before any future activation: Meta can normalize targeting and apply creative defaults. Your image description is saved for local preparation; it is not sent as Meta alt text. Partial resources may need manual cleanup in Meta.';
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

bool _id(dynamic v) => v is String && RegExp(r'^[1-9][0-9]{0,39}$').hasMatch(v);
const _resourceNames = ['image_hash', 'campaign', 'ad_set', 'creative', 'ad'];
void _snapshot(dynamic s, String campaign, String attempt, Map catalog) {
  if (s is! Map ||
      s['plan'] is! Map ||
      s['page'] is! Map ||
      s['identity'] is! Map ||
      s['creative'] is! Map ||
      s['image'] is! Map ||
      !metaTargetingValid(s['targeting'], catalog) ||
      !metaTargetingComplete(s['targeting']) ||
      s['targeting']['placements'] != 'facebook_feed' ||
      !_same(s['targeting']['categories'], ['NONE'])) {
    throw _bad;
  }
  final p = s['plan'],
      i = s['identity'],
      a = i['account'],
      page = i['page'],
      cr = s['creative'],
      im = s['image'];
  if (p['id'] != campaign ||
      !_text(p['name'], 100) ||
      !_int(p['daily_cents'], 100, 1000000) ||
      !_int(p['days'], 1, 90) ||
      p['currency'] != 'USD' ||
      p['planned_total_cents'] != p['daily_cents'] * p['days'] ||
      a is! Map ||
      a['id'] is! String ||
      !RegExp(r'^act_[1-9][0-9]{0,39}$').hasMatch(a['id']) ||
      !_text(a['name'], 200) ||
      a['currency'] != 'USD' ||
      a['status'] != 1 ||
      !_text(a['timezone'], 100) ||
      page is! Map ||
      !_id(page['id']) ||
      !_text(page['name'], 200) ||
      page['category'] is! String ||
      !_int(i['connection_version'], 1, 2147483647) ||
      !_date(s['start_date']) ||
      !_date(s['end_date']) ||
      !_stamp(s['start_time']) ||
      !_stamp(s['end_time']) ||
      s['provider_name'] != 'KORLIX $attempt' ||
      s['budget_acknowledged'] != true) {
    throw _bad;
  }
  final expectedEnd = DateTime.parse('${s['start_date']}T00:00:00Z')
      .add(Duration(days: (p['days'] as int) - 1))
      .toIso8601String()
      .substring(0, 10);
  final seconds = DateTime.parse(
    s['end_time'],
  ).difference(DateTime.parse(s['start_time'])).inSeconds;
  if (s['end_date'] != expectedEnd ||
      seconds <= 0 ||
      (seconds - (p['days'] * 86400 - 1)).abs() > 86400) {
    throw _bad;
  }
  final destination = s['page']['destination'] is String
      ? Uri.tryParse(s['page']['destination'])
      : null;
  if (destination == null ||
      destination.scheme != 'https' ||
      destination.host.isEmpty ||
      destination.userInfo.isNotEmpty ||
      destination.hasFragment ||
      destination.queryParameters['utm_source'] != 'facebook' ||
      destination.queryParameters['utm_campaign'] !=
          'k143_${campaign.replaceAll('-', '')}') {
    throw _bad;
  }
  if (cr.length != 6 ||
      !metaCreativeCtas.containsKey(cr['cta']) ||
      !_uuid(cr['image_id']) ||
      cr['primary_text'] == '' ||
      cr['headline'] == '' ||
      cr['image_alt'] == '' ||
      im['id'] != cr['image_id'] ||
      !_text(im['label'], 100) ||
      !_int(im['width'], 1, 1600) ||
      !_int(im['height'], 1, 1600) ||
      im['sha256'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(im['sha256'])) {
    throw _bad;
  }
  for (final e in metaCreativeLimits.entries) {
    if (cr[e.key] is! String ||
        metaCreativeTextError(cr[e.key], e.value) != null) {
      throw _bad;
    }
  }
}

Map<String, dynamic> validateMetaCreation(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (d['source'] != 'meta_paused_creation' ||
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
  final prep = validateMetaTargeting(d['preparation'], funnel, campaign),
      setup = prep['creative']['setup'],
      current = setup['current_snapshot'];
  final expected = {
    'plan': current['campaign'],
    'page': current['landing_page'],
    'identity': current['meta'],
    'creative': prep['creative']['assets'],
    'image': prep['creative']['image'],
    'targeting': prep['assets'],
  };
  if (!_same(d['draft'], expected)) throw _bad;
  final checks = d['checks'] as Map, attempt = d['attempt'];
  if (checks.length != 7 ||
      checks.values.any((v) => v is! bool) ||
      checks['platform_enabled'] is! bool ||
      checks['setup_review_current'] != setup['review_current'] ||
      checks['creative_targeting_review_current'] != prep['review_current'] ||
      checks['facebook_feed'] !=
          (expected['targeting']['placements'] == 'facebook_feed') ||
      checks['no_special_category'] !=
          _same(expected['targeting']['categories'], ['NONE']) ||
      checks['account_calendar'] != (d['today'] != null) ||
      checks['no_previous_attempt'] != (attempt == null) ||
      d['create_ready'] !=
          (checks.values.every((v) => v == true) && attempt == null)) {
    throw _bad;
  }
  if (d['today'] == null) {
    if (d['earliest_start'] != null || d['latest_start'] != null) throw _bad;
  } else {
    if (!_date(d['today']) ||
        !_date(d['earliest_start']) ||
        !_date(d['latest_start']) ||
        DateTime.parse(
              d['earliest_start'],
            ).difference(DateTime.parse(d['today'])).inDays !=
            1 ||
        DateTime.parse(
              d['latest_start'],
            ).difference(DateTime.parse(d['today'])).inDays !=
            30) {
      throw _bad;
    }
  }
  if (attempt != null) {
    if (attempt is! Map ||
        !_uuid(attempt['id']) ||
        !['unknown', 'created'].contains(attempt['state']) ||
        !_stamp(attempt['created_at'])) {
      throw _bad;
    }
    _snapshot(attempt['snapshot'], campaign, attempt['id'], prep['catalog']);
    final r = attempt['resources'];
    if (r is! Map ||
        r.length > 5 ||
        r.keys.any((k) => !_resourceNames.contains(k))) {
      throw _bad;
    }
    for (final k in _resourceNames.take(r.length)) {
      if (k == 'image_hash'
          ? (r[k] is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(r[k]))
          : !_id(r[k])) {
        throw _bad;
      }
    }
    if (r.entries
            .where((e) => e.key != 'image_hash')
            .map((e) => e.value)
            .toSet()
            .length !=
        r.length - (r.containsKey('image_hash') ? 1 : 0)) {
      throw _bad;
    }
    if (attempt['state'] == 'created'
        ? (r.length != 5 || !_stamp(attempt['completed_at']))
        : attempt['completed_at'] != null) {
      throw _bad;
    }
  }
  return d;
}

String metaCreationSummary(Map<String, dynamic> d) {
  final attempt = d['attempt'],
      s = attempt == null ? d['draft'] : attempt['snapshot'],
      p = s['plan'],
      i = s['identity'],
      a = i['account'],
      page = i['page'],
      cr = s['creative'],
      im = s['image'],
      t = s['targeting'];
  final out = StringBuffer('KORLIX META PAUSED CREATION\n');
  out.writeln(
    'Plan: ${p['name']}\nStatus: ${attempt == null
        ? 'NOT CREATED'
        : attempt['state'] == 'created'
        ? 'CREATION RECORDED'
        : 'OUTCOME NEEDS CHECKING'}',
  );
  out.writeln(
    'Account: ${a == null ? '(not selected)' : '${a['name']} (${a['id']})'}\nAccount timezone: ${a?['timezone'] ?? '(unavailable)'}\nFacebook Page: ${page == null ? '(not selected)' : '${page['name']} (${page['id']})'}\nAverage daily budget: \$${(p['daily_cents'] / 100).toStringAsFixed(2)} USD\nPlanned duration: ${p['days']} days',
  );
  if (attempt != null) {
    out.writeln(
      'Creation name: ${s['provider_name']}\nStart: ${s['start_date']} 00:00:00\nEnd: ${s['end_date']} 23:59:59\nStart instant: ${s['start_time']}\nEnd instant: ${s['end_time']}\nRecorded: ${attempt['created_at']}\nCompleted: ${attempt['completed_at'] ?? '(unconfirmed)'}',
    );
  }
  out.writeln(
    'Destination: ${s['page']['destination']}\nPrimary text: ${cr['primary_text']}\nHeadline: ${cr['headline']}\nDescription: ${cr['description']}\nButton: ${metaCreativeCtas[cr['cta']]}\nImage: ${im == null ? '(not selected)' : '${im['label']} — ${im['width']} × ${im['height']} — ${im['id']}'}\nLocal image description: ${cr['image_alt']}',
  );
  out.writeln(
    'Countries: ${(t['countries'] as List).join(', ')}\n${t.containsKey('geo_locations') ? metaLocationsSummary(t) : metaRadiusSummary(t)}\nAges: ${t['age_min']}–${t['age_max'] == 65 ? '65+' : t['age_max']} · all genders\nPlacement: ${metaPlacements[t['placements']]}\nAd categories: ${(t['categories'] as List).map((v) => metaAdCategories[v]).join(', ')}',
  );
  if (attempt != null) {
    out.writeln('Saved Meta resources:');
    for (final k in _resourceNames) {
      out.writeln('$k: ${attempt['resources'][k] ?? '(not confirmed)'}');
    }
  }
  out.writeln(
    '\n$metaCreationBoundary\n$metaCreationBudget\n$metaCreationReview\nCreation records are historical. Current delivery and policy status are not monitored here. Reporting links are managed separately.',
  );
  return out.toString();
}

class FunnelMetaCreate extends StatefulWidget {
  const FunnelMetaCreate({
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
  State<FunnelMetaCreate> createState() => _FunnelMetaCreateState();
}

class _FunnelMetaCreateState extends State<FunnelMetaCreate> {
  Map<String, dynamic>? _data;
  final _start = TextEditingController();
  bool _busy = false, _paused = false, _budget = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-create';
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
  void _resetConfirmation() {
    _paused = false;
    _budget = false;
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
  void didUpdateWidget(covariant FunnelMetaCreate old) {
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
      final d = validateMetaCreation(r, widget.funnelId, widget.campaignId);
      setState(() {
        _data = d;
        _message = d['notice'];
        if (d['attempt'] == null) _start.text = d['earliest_start'] ?? '';
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
        !_budget) {
      return;
    }
    final date = _start.text.trim();
    if (!_date(date) ||
        date.compareTo(d['earliest_start']) < 0 ||
        date.compareTo(d['latest_start']) > 0) {
      setState(
        () => _error =
            'Choose a date from ${d['earliest_start']} through ${d['latest_start']} in the account timezone.',
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
      builder: (_) => FunnelMetaTargeting(
        client: widget.client,
        funnelId: widget.funnelId,
        campaignId: widget.campaignId,
        scope: widget.scope,
      ),
    );
    if (_current(g)) await _request();
  }

  Future<void> _setupReview() async {
    if (_busy || _unavailable != null) return;
    final g = _generation;
    setState(() {
      _busy = true;
      _resetConfirmation();
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FunnelMetaPreparation(
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
      await Clipboard.setData(ClipboardData(text: metaCreationSummary(d)));
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
                    'Create paused Meta campaign',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              _line(metaCreationBoundary, color: WfStyle.muted),
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
                _line(
                  'Facebook Page: ${s['identity']['page']?['name'] ?? '(not selected)'}',
                ),
                _line(metaCreationBudget, color: WfStyle.gold),
                _line(metaCreationReview, color: WfStyle.muted),
                if (s['image'] != null) ...[
                  const SizedBox(height: 16),
                  FunnelPrivateImage(
                    key: ValueKey('${_generation}_${s['image']['id']}'),
                    client: widget.client,
                    id: s['image']['id'],
                    description: s['creative']['image_alt'],
                  ),
                  _line(s['image']['label']),
                ],
                _line('Primary text: ${s['creative']['primary_text']}'),
                _line('Headline: ${s['creative']['headline']}'),
                _line('Description: ${s['creative']['description']}'),
                _line('Button: ${metaCreativeCtas[s['creative']['cta']]}'),
                _line('Destination: ${s['page']['destination']}'),
                if (attempt == null) ...[
                  if (d['checks']['platform_enabled'] != true)
                    _line(
                      'Paused creation will be available after KORLIX Meta platform activation.',
                    ),
                  if (d['checks']['setup_review_current'] != true ||
                      d['checks']['creative_targeting_review_current'] != true)
                    _line(
                      'Complete the current Meta setup review and the combined creative and targeting review.',
                    ),
                  if (d['checks']['facebook_feed'] != true ||
                      d['checks']['no_special_category'] != true)
                    _line(
                      'Paused creation supports Facebook Feed and no special ad category. Update and review the targeting draft.',
                    ),
                  if (d['checks']['account_calendar'] != true)
                    _line(
                      'Refresh the selected ad account to obtain a supported timezone.',
                    ),
                  if (d['create_ready'] == true) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _start,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: 'Start date (YYYY-MM-DD)',
                        helperText:
                            '${d['earliest_start']} through ${d['latest_start']}',
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
                        'Upload this image and create the campaign, ad set and ad paused. I am not activating ad delivery.',
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
                    FilledButton.icon(
                      onPressed: _busy || !_paused || !_budget ? null : _create,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Confirm paused creation'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: _busy ? null : _setupReview,
                    child: const Text('Review Meta setup'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _preparation,
                    child: const Text('Review creative and targeting'),
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
                      'The request may have reached Meta. KORLIX will not resend or continue it. Partial resources may already exist. Checking is read-only; a missing result does not prove failure.',
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
                      'Meta campaign ID: ${attempt['resources']['campaign']}',
                    ),
                  ],
                ],
                if (attempt != null)
                  for (final k in _resourceNames)
                    _line(
                      '$k: ${attempt['resources'][k] ?? '(not confirmed)'}',
                    ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Review requested campaign details'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(metaCreationSummary(d)),
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
