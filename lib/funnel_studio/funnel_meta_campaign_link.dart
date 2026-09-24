import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta_destination.dart';
import 'funnel_meta_format.dart';

const metaCampaignLinkBoundary =
    'This is your reporting association. Inquiry tags are visitor-supplied, so they do not prove Meta conversions. The association covers the whole selected period, including dates before it was saved. No ads, spending limits or publishing permissions are changed.';
const _invalid = FunnelException(
  'The Meta campaign link response could not be verified. Refresh it.',
  503,
);
bool _integer(dynamic v, [int low = 0, int high = 9007199254740991]) =>
    v is int && v >= low && v <= high;
bool _id(dynamic v) => v is String && RegExp(r'^\d{1,40}$').hasMatch(v);
bool _name(dynamic v, int max) =>
    v is String &&
    v.isNotEmpty &&
    v.trim() == v &&
    v.length <= max &&
    !v.contains('\u0000');
bool _stamp(dynamic v) => v is String && DateTime.tryParse(v) != null;
bool _date(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse('${v}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        v;
bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a == b;
bool _account(dynamic a) =>
    a is Map &&
    a['id'] is String &&
    RegExp(r'^act_\d{1,40}$').hasMatch(a['id']) &&
    _name(a['name'], 200) &&
    a['currency'] is String &&
    (a['currency'] as String).length <= 8 &&
    a['timezone'] is String &&
    (a['timezone'] as String).length <= 100 &&
    _integer(a['status']);
bool _active(dynamic a) =>
    _account(a) &&
    a['status'] == 1 &&
    RegExp(r'^[A-Z]{3}$').hasMatch(a['currency']) &&
    (a['timezone'] as String).isNotEmpty;
bool _link(dynamic l) =>
    l is Map &&
    _active(l['account']) &&
    _id(l['provider_campaign_id']) &&
    _name(l['provider_campaign_name'], 1000) &&
    _stamp(l['linked_at']);
bool _money(dynamic v) {
  if (v is! String || !RegExp(r'^\d{1,13}(\.\d{1,6})?$').hasMatch(v)) {
    return false;
  }
  final parts = v.split('.');
  return BigInt.parse(parts[0]) * BigInt.from(1000000) +
          BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0')) <=
      BigInt.parse('1000000000000000000');
}

Map<String, dynamic> validateMetaCampaignLink(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  if (d['source'] != 'meta_campaign_link' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      !_name(d['campaign_name'], 200) ||
      !['draft', 'reviewed', 'archived'].contains(d['state']) ||
      !_integer(d['version'], 0, 2147483647) ||
      !_integer(d['connection_version'], 0, 2147483647) ||
      d['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(d['fingerprint']) ||
      [
        'configured',
        'editable',
        'lookup_ready',
        'link_current',
        'report_ready',
      ].any((k) => d[k] is! bool) ||
      d['editable'] != (d['state'] != 'archived') ||
      d['report_ready'] != d['link_current'] ||
      d['ad_publishing_ready'] != false ||
      d['attribution_verified'] != false ||
      !_stamp(d['checked_at']) ||
      (d['account'] != null && !_account(d['account'])) ||
      (d['link'] != null && !_link(d['link'])) ||
      (d['version'] == 0
          ? d['link'] != null || d['updated_at'] != null
          : !_stamp(d['updated_at']))) {
    throw _invalid;
  }
  if ((d['lookup_ready'] == true || d['link_current'] == true) &&
      (d['configured'] != true ||
          !_active(d['account']) ||
          d['connection_version'] == 0)) {
    throw _invalid;
  }
  if (d['lookup_ready'] == true && d['editable'] != true) throw _invalid;
  if (d['link_current'] == true &&
      (d['link'] == null ||
          [
            'id',
            'currency',
            'timezone',
          ].any((k) => d['account'][k] != d['link']['account'][k]))) {
    throw _invalid;
  }
  return d;
}

void _reportContext(
  Map<String, dynamic> r,
  Map<String, dynamic> d,
  String source,
  int days,
) {
  final range = r['range'];
  if (r['source'] != source ||
      r['funnel_id'] != d['funnel_id'] ||
      r['campaign_id'] != d['campaign_id'] ||
      r['fingerprint'] != d['fingerprint'] ||
      r['connection_version'] != d['connection_version'] ||
      !_same(r['account'], d['account']) ||
      !_active(r['account']) ||
      r['ad_publishing_ready'] != false ||
      r['attribution_verified'] != false ||
      !_stamp(r['fetched_at']) ||
      ![7, 30, 90].contains(days) ||
      range is! Map ||
      range['days'] != days ||
      !_date(range['from']) ||
      !_date(range['to']) ||
      DateTime.parse(
            '${range['to']}T00:00:00Z',
          ).difference(DateTime.parse('${range['from']}T00:00:00Z')).inDays !=
          days - 1) {
    throw _invalid;
  }
}

Map<String, dynamic> validateMetaCampaignChoices(
  Map<String, dynamic> r,
  Map<String, dynamic> d,
  int days,
) {
  _reportContext(r, d, 'meta_campaign_choices', days);
  if (d['lookup_ready'] != true ||
      r['choices'] is! List ||
      (r['choices'] as List).length > 300) {
    throw _invalid;
  }
  final ids = <String>{};
  for (final row in r['choices']) {
    if (row is! Map ||
        row.length != 3 ||
        !_id(row['provider_campaign_id']) ||
        !_name(row['provider_campaign_name'], 1000) ||
        row['proof'] is! String ||
        !RegExp(r'^\d{13}\.[a-f0-9]{64}$').hasMatch(row['proof']) ||
        !ids.add(row['provider_campaign_id'])) {
      throw _invalid;
    }
  }
  return r;
}

Map<String, dynamic> validateMetaLinkedPerformance(
  Map<String, dynamic> r,
  Map<String, dynamic> d,
  int days,
) {
  _reportContext(r, d, 'meta_linked_performance', days);
  final row = r['row'], m = r['measurement'];
  if (d['report_ready'] != true ||
      !_same(r['link'], d['link']) ||
      (row != null &&
          (row is! Map ||
              row['campaign_id'] != d['link']['provider_campaign_id'] ||
              !_name(row['campaign_name'], 1000) ||
              !_money(row['spend']) ||
              !_integer(row['clicks']) ||
              !_integer(row['impressions']))) ||
      m is! Map ||
      ['from', 'to', 'days'].any((k) => m[k] != r['range'][k]) ||
      m['timezone'] != r['account']['timezone'] ||
      !_stamp(m['start_inclusive']) ||
      !_stamp(m['end_exclusive']) ||
      !_stamp(m['checked_at']) ||
      !_integer(m['tagged_inquiries'])) {
    throw _invalid;
  }
  final span = DateTime.parse(
    m['end_exclusive'],
  ).difference(DateTime.parse(m['start_inclusive'])).inHours;
  if (span < (days - 2) * 24 || span > (days + 2) * 24) throw _invalid;
  return r;
}

String metaLinkedSummary(Map<String, dynamic> d, Map<String, dynamic>? report) {
  final out = StringBuffer(
    'KORLIX META CAMPAIGN ASSOCIATION\nPlan: ${d['campaign_name']}\nChecked: ${d['checked_at']}\n',
  );
  final l = d['link'];
  if (l == null) {
    out.writeln('No saved Meta campaign association.');
  } else {
    out.writeln(
      'Saved Meta campaign: ${l['provider_campaign_name']} (${l['provider_campaign_id']})\nSaved account: ${l['account']['name']} (${l['account']['id']})\nLinked: ${l['linked_at']}\nReporting available at check time: ${d['report_ready']}',
    );
  }
  if (report != null) {
    final r = report, row = r['row'], m = r['measurement'];
    out.writeln(
      '\nReport fetched: ${r['fetched_at']}\nPeriod: ${m['from']} through ${m['to']} · ${m['timezone']}\nUTC interval: ${m['start_inclusive']} inclusive to ${m['end_exclusive']} exclusive',
    );
    if (row == null) {
      out.writeln(
        'Meta returned no row for the linked campaign. Spend, clicks and impressions are unknown for this report.',
      );
    } else {
      out.writeln(
        'Current Meta name: ${row['campaign_name']}\nMeta spend: ${metaMoney(r['account']['currency'], row['spend'])}\nMeta clicks (all): ${row['clicks']}\nMeta impressions: ${row['impressions']}',
      );
    }
    out.writeln(
      'KORLIX tagged inquiries: ${m['tagged_inquiries']}\nInquiry count checked: ${m['checked_at']}',
    );
  }
  out.writeln(
    'Provider totals can be revised. No currency conversion, cost per conversion, revenue or ROAS is inferred.\n$metaCampaignLinkBoundary',
  );
  return out.toString();
}

class FunnelMetaCampaignLink extends StatefulWidget {
  const FunnelMetaCampaignLink({
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
  State<FunnelMetaCampaignLink> createState() => _FunnelMetaCampaignLinkState();
}

class _FunnelMetaCampaignLinkState extends State<FunnelMetaCampaignLink> {
  Map<String, dynamic>? _data, _choices, _report, _candidate;
  final _search = TextEditingController();
  String _query = '';
  int _generation = 0, _days = 7, _page = 0;
  bool _busy = false;
  String? _error, _message, _unavailable;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-link';
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_run('read'));
  }

  void _invalidate(String message) {
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    _choices = null;
    _report = null;
    _candidate = null;
    _busy = false;
    _error = null;
    _message = null;
    _unavailable = message;
    void redraw() {
      if (mounted && g == _generation) setState(() => _search.clear());
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => redraw());
    } else {
      redraw();
    }
  }

  void _deny() => _invalidate(
    'Sign in with Enterprise access to view campaign associations.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close this panel and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaCampaignLink old) {
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
      _choices = null;
      _report = null;
      _candidate = null;
      _busy = false;
      _unavailable = null;
      _query = '';
      _page = 0;
      _search.clear();
      unawaited(_run('read'));
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String action, [Map<String, dynamic>? body]) async {
    if (_busy || _unavailable != null) return;
    final d = _data, days = _days;
    final remote = action == 'campaigns' || action == 'performance';
    if (remote &&
        (d == null ||
            d[action == 'campaigns' ? 'lookup_ready' : 'report_ready'] !=
                true)) {
      return;
    }
    final g = ++_generation,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _choices = null;
      _report = null;
      _candidate = null;
      _page = 0;
      _query = '';
      _search.clear();
      if (!remote) _data = null;
    });
    try {
      final r = await client.request(
        action == 'save' || action == 'clear' ? 'POST' : 'GET',
        action == 'read' ? path : '$path/$action',
        body: body,
        query: remote
            ? {'days': '$days', 'fingerprint': d!['fingerprint']}
            : null,
      );
      if (!_current(g)) return;
      if (action == 'campaigns') {
        final clean = validateMetaCampaignChoices(r, d!, days);
        setState(() => _choices = clean);
      } else if (action == 'performance') {
        final clean = validateMetaLinkedPerformance(r, d!, days);
        setState(() => _report = clean);
      } else {
        final clean = validateMetaCampaignLink(r, funnel, campaign);
        setState(() {
          _data = clean;
          _message = action == 'save'
              ? 'Meta campaign association saved.'
              : action == 'clear'
              ? 'Association cleared. Provider campaigns and daily results are unchanged.'
              : null;
        });
      }
    } catch (e) {
      if (_current(g)) {
        setState(() {
          _data = null;
          _error = e is FunnelException
              ? e.message
              : 'The campaign association could not load. Refresh it.';
        });
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final d = _data, row = _candidate;
    if (d == null || row == null || _busy || d['lookup_ready'] != true) return;
    await _run('save', {
      'version': d['version'],
      'fingerprint': d['fingerprint'],
      'confirmed': true,
      ...row,
    });
  }

  Future<void> _clear() async {
    final d = _data, g = _generation;
    if (d == null || d['link'] == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear this campaign association?'),
        content: const Text(
          'This only removes the KORLIX reporting association. Provider campaigns and manual daily results stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep association'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear association'),
          ),
        ],
      ),
    );
    if (ok == true && _current(g)) {
      await _run('clear', {
        'version': d['version'],
        'fingerprint': d['fingerprint'],
        'confirmed': true,
      });
    }
  }

  Future<void> _copy() async {
    final d = _data, g = _generation;
    if (d == null || _busy || _candidate != null || _unavailable != null) {
      return;
    }
    try {
      await Clipboard.setData(
        ClipboardData(text: metaLinkedSummary(d, _report)),
      );
      if (_current(g)) {
        setState(() => _message = 'Saved association summary copied.');
      }
    } catch (_) {
      if (_current(g)) {
        setState(() => _error = 'The summary could not be copied. Try again.');
      }
    }
  }

  Widget _gap() => const SizedBox(height: 14);
  Widget _caption(String text) =>
      Text(text, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  Widget _card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: WfStyle.background,
      border: Border.all(color: WfStyle.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
  Widget _saved(Map d) {
    final l = d['link'];
    if (l == null) {
      return _caption(
        'No Meta campaign is linked to this plan. Load a reported campaign list to choose one.',
      );
    }
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const WfBadge('ASSOCIATION SAVED'),
              if (d['report_ready'] != true)
                const WfBadge('REPORTING UNAVAILABLE', color: WfStyle.gold),
            ],
          ),
          _gap(),
          SelectableText(
            '${l['provider_campaign_name']}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          _caption('Meta campaign ID: ${l['provider_campaign_id']}'),
          _caption(
            'Saved account: ${l['account']['name']} · ${l['account']['id']}',
          ),
          _caption(
            'Saved ${l['linked_at']}. The label is a snapshot; Meta may rename the campaign.',
          ),
          if (d['report_ready'] != true)
            _caption(
              'Connect and select the saved account, or reload campaign choices to refresh the association.',
            ),
          TextButton(
            onPressed: _busy ? null : _clear,
            child: const Text('Clear saved association'),
          ),
        ],
      ),
    );
  }

  Widget _selection() {
    final chosen = _candidate;
    if (chosen != null) {
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm the campaign to associate',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            _gap(),
            SelectableText('${chosen['provider_campaign_name']}'),
            _caption('Meta campaign ID: ${chosen['provider_campaign_id']}'),
            _caption(
              'Account: ${_choices!['account']['name']} · ${_choices!['account']['id']}',
            ),
            _gap(),
            _caption(
              'One Meta campaign can link to one of your KORLIX plans per account. This replaces any saved association for this plan.',
            ),
            _gap(),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Confirm campaign link'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _candidate = null),
                  child: const Text('Cancel selection'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    final choices = _choices!['choices'] as List;
    final filtered = choices
        .where(
          (r) => '${r['provider_campaign_name']} ${r['provider_campaign_id']}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    final start = _page * 20, visible = filtered.skip(start).take(20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gap(),
        _caption(
          'Reported campaigns: ${_choices!['range']['from']} through ${_choices!['range']['to']} · ${_choices!['account']['timezone']}. Only campaigns returned by Meta for this period are listed.',
        ),
        if (choices.isEmpty) ...[
          _gap(),
          _caption(
            'Meta returned no campaigns for this period. Try another period.',
          ),
        ] else ...[
          _gap(),
          TextField(
            controller: _search,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Search campaign name or ID',
            ),
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
          ),
          _gap(),
          Text(
            '${filtered.length} matches · ${choices.length} returned campaigns',
          ),
          if (filtered.isEmpty) _caption('No campaigns match this search.'),
          for (final row in visible)
            _card(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText('${row['provider_campaign_name']}'),
                  _caption('Meta campaign ID: ${row['provider_campaign_id']}'),
                  _gap(),
                  OutlinedButton(
                    key: ValueKey(
                      'meta-link-choice-${row['provider_campaign_id']}',
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _candidate = Map<String, dynamic>.from(row),
                          ),
                    child: const Text('Choose campaign'),
                  ),
                ],
              ),
            ),
          if (filtered.length > 20)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: _page == 0 || _busy
                      ? null
                      : () => setState(() => _page--),
                  child: const Text('Previous campaigns'),
                ),
                Text(
                  '${start + 1}–${start + visible.length} of ${filtered.length}',
                ),
                TextButton(
                  onPressed: start + 20 >= filtered.length || _busy
                      ? null
                      : () => setState(() => _page++),
                  child: const Text('Next campaigns'),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _results(Map r) {
    final row = r['row'], m = r['measurement'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _gap(),
        Text(
          '${m['from']} through ${m['to']} · ${m['timezone']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _caption(
          'Completed account-calendar days. Fetched ${r['fetched_at']}.',
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WfBadge('META REPORTED'),
              _gap(),
              if (row == null)
                _caption(
                  'Meta returned no row for this campaign. Spend, clicks and impressions are unknown for this report.',
                )
              else ...[
                SelectableText('${row['campaign_name']}'),
                _caption('Meta campaign ID: ${row['campaign_id']}'),
                _gap(),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    Text(
                      'Spend: ${metaMoney(r['account']['currency'], row['spend'])}',
                    ),
                    Text('${metaCount(row['clicks'])} clicks (all)'),
                    Text('${metaCount(row['impressions'])} impressions'),
                  ],
                ),
              ],
            ],
          ),
        ),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WfBadge('KORLIX INQUIRIES'),
              _gap(),
              Text(
                '${metaCount(m['tagged_inquiries'])} tagged inquiries in the same period',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              _caption(
                'Matches this plan’s tracking tag and Facebook source. These are KORLIX submissions, not verified Meta conversions.',
              ),
            ],
          ),
        ),
        _gap(),
        _caption(
          'Manual USD daily results and Budget pacing remain separate. Provider figures can be revised; no currency conversion, cost per conversion, revenue or ROAS is inferred.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Linked Meta campaign'),
        content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_unavailable != null)
                  Text(_unavailable!)
                else ...[
                  _caption(metaCampaignLinkBoundary),
                  _gap(),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: WfStyle.danger),
                    ),
                  if (_message != null)
                    Text(
                      _message!,
                      style: const TextStyle(color: WfStyle.cyan),
                    ),
                  if (d != null) ...[
                    _gap(),
                    Text(
                      d['campaign_name'],
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _gap(),
                    _saved(d),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => showDialog<void>(
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
                    _gap(),
                    if (d['configured'] != true)
                      _caption(
                        'Campaign lookup will be available after Meta platform setup.',
                      )
                    else if (d['account'] == null)
                      _caption(
                        'Connect Meta and select an ad account in Ads workspace.',
                      )
                    else
                      _caption(
                        'Selected account: ${d['account']['name']} · ${d['account']['id']} · ${d['account']['currency']} · ${d['account']['timezone']}',
                      ),
                    if (d['editable'] != true)
                      _caption(
                        'Archived plan · new associations are disabled. You can still read or clear the saved association.',
                      ),
                    _gap(),
                    DropdownButtonFormField<int>(
                      initialValue: _days,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Completed reporting days',
                      ),
                      items: [
                        for (final n in [7, 30, 90])
                          DropdownMenuItem(value: n, child: Text('$n days')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _generation++;
                                _days = v;
                                _choices = null;
                                _report = null;
                                _candidate = null;
                                _query = '';
                                _search.clear();
                                _page = 0;
                                _error = null;
                                _message = null;
                              });
                            },
                    ),
                    _gap(),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy || d['lookup_ready'] != true
                              ? null
                              : () => _run('campaigns'),
                          child: const Text('Load Meta campaigns'),
                        ),
                        FilledButton(
                          onPressed: _busy || d['report_ready'] != true
                              ? null
                              : () => _run('performance'),
                          child: const Text('Load linked performance'),
                        ),
                      ],
                    ),
                    if (_choices != null) _selection(),
                    if (_report != null) _results(_report!),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_unavailable == null)
            TextButton(
              onPressed: _busy ? null : () => _run('read'),
              child: const Text('Refresh association'),
            ),
          if (d != null)
            TextButton(
              onPressed: _busy || _candidate != null ? null : _copy,
              child: const Text('Copy association summary'),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close association'),
          ),
        ],
      ),
    );
  }
}
