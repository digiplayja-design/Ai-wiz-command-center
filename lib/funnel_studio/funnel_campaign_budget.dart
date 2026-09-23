import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const campaignBudgetBoundary =
    'Tracking only. Uses manually recorded USD results and the current campaign plan. This date does not schedule ads, enforce a spending cap or pause a campaign.';
String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
bool _int(dynamic n, int low, int high) => n is int && n >= low && n <= high;
bool _date(dynamic s) =>
    s is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
    DateTime.tryParse('${s}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        s;
bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a is List && b is List
    ? a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]))
    : a == b;

Map<String, dynamic> validateCampaignBudget(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
) {
  const error = FunnelException(
    'Budget tracking data could not be verified. Refresh it.',
    503,
  );
  if (d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['name'] is! String ||
      (d['name'] as String).trim().isEmpty ||
      (d['name'] as String).runes.length > 100 ||
      !['draft', 'reviewed', 'archived'].contains(d['state']) ||
      !_int(d['version'], 0, 2147483647) ||
      !_int(d['campaign_version'], 1, 2147483647) ||
      !_int(d['daily_cents'], 100, 1000000) ||
      !_int(d['days'], 1, 90) ||
      d['currency'] != 'USD' ||
      d['reporting_source'] != 'manual' ||
      d['budget_enforced'] != false ||
      d['ad_publishing_ready'] != false ||
      !_date(d['as_of_date']) ||
      d['checked_at'] is! String ||
      DateTime.tryParse(
            d['checked_at'],
          )?.toUtc().toIso8601String().substring(0, 10) !=
          d['as_of_date'] ||
      d['reports'] is! List ||
      (d['reports'] as List).length > 731 ||
      (d['version'] == 0
          ? d['updated_at'] != null || d['start_date'] != null
          : d['updated_at'] is! String ||
                DateTime.tryParse(d['updated_at']) == null)) {
    throw error;
  }
  final reports = <String, int>{};
  for (final r in d['reports']) {
    if (r is! Map ||
        !_date(r['day']) ||
        (r['day'] as String).compareTo(d['as_of_date']) > 0 ||
        !_int(r['spend_cents'], 0, 100000000) ||
        reports.containsKey(r['day'])) {
      throw error;
    }
    reports[r['day']] = r['spend_cents'];
  }
  if (d['start_date'] == null) {
    if (d['pacing'] != null) throw error;
    return d;
  }
  if (!_date(d['start_date'])) throw error;
  final start = DateTime.parse('${d['start_date']}T00:00:00Z');
  final rows = <Map<String, dynamic>>[], missing = <String>[];
  var recorded = 0,
      completedSpend = 0,
      completed = 0,
      reportedCompleted = 0,
      reported = 0;
  for (var i = 0; i < d['days']; i++) {
    final day = start.add(Duration(days: i)).toIso8601String().substring(0, 10),
        spend = reports[day];
    final relation = day.compareTo(d['as_of_date']);
    final status = relation > 0
        ? 'future'
        : relation == 0
        ? 'today'
        : spend == null
        ? 'missing'
        : 'recorded';
    if (spend != null) {
      recorded += spend;
      reported++;
    }
    if (relation < 0) {
      completed++;
      if (spend == null) {
        missing.add(day);
      } else {
        completedSpend += spend;
        reportedCompleted++;
      }
    }
    rows.add({'day': day, 'spend_cents': spend, 'status': status});
  }
  final end = rows.last['day'] as String,
      total = (d['daily_cents'] as int) * (d['days'] as int);
  final expected = {
    'end_date': end,
    'phase': (d['as_of_date'] as String).compareTo(d['start_date']) < 0
        ? 'upcoming'
        : (d['as_of_date'] as String).compareTo(end) > 0
        ? 'finished'
        : 'active',
    'planned_total_cents': total,
    'recorded_spend_cents': recorded,
    'balance_cents': total - recorded,
    'completed_days': completed,
    'reported_days': reported,
    'reported_completed_days': reportedCompleted,
    'completed_spend_cents': completedSpend,
    'reported_days_plan_cents': reportedCompleted * (d['daily_cents'] as int),
    'reported_days_variance_cents':
        completedSpend - reportedCompleted * (d['daily_cents'] as int),
    'missing_dates': missing,
    'excluded_report_days': reports.length - reported,
    'rows': rows,
  };
  if (!_same(d['pacing'], expected)) throw error;
  return d;
}

String campaignBudgetSummary(Map<String, dynamic> d) {
  final out = StringBuffer(
    'KORLIX CAMPAIGN BUDGET PACING\nCampaign: ${d['name']}\nChecked: ${d['checked_at']}\n',
  );
  out.writeln(
    'Current plan: ${_money(d['daily_cents'])} USD/day for ${d['days']} days.',
  );
  final p = d['pacing'];
  if (p == null) {
    out.writeln('No saved reporting window.');
  } else {
    out.writeln(
      'Reporting window: ${d['start_date']} through ${p['end_date']} UTC (${p['phase']}).',
    );
    out.writeln('Planned total: ${_money(p['planned_total_cents'])} USD');
    out.writeln(
      'Recorded spend: ${p['reported_days'] == 0 ? '(no reported days)' : '${_money(p['recorded_spend_cents'])} USD'}',
    );
    out.writeln(
      'Completed-day coverage: ${p['reported_completed_days']}/${p['completed_days']}. Missing dates: ${(p['missing_dates'] as List).isEmpty ? '(none)' : (p['missing_dates'] as List).join(', ')}',
    );
    out.writeln(
      'Plan minus recorded spend: ${_money(p['balance_cents'])} USD. Unreported spend is unknown; this is not confirmed money available to spend.',
    );
    if (p['reported_completed_days'] > 0) {
      out.writeln(
        'Completed reported days: ${_money(p['completed_spend_cents'])} USD recorded against ${_money(p['reported_days_plan_cents'])} USD planned.',
      );
    }
    out.writeln(
      'Reports outside this window: ${p['excluded_report_days']} (excluded). Today is partial and excluded from completed-day comparisons.',
    );
    for (final r in p['rows']) {
      out.writeln(
        '${r['day']} UTC | ${r['status']} | ${r['spend_cents'] == null ? 'no entry' : '${_money(r['spend_cents'])} USD'}',
      );
    }
  }
  out.writeln(campaignBudgetBoundary);
  return out.toString();
}

class FunnelCampaignBudget extends StatefulWidget {
  const FunnelCampaignBudget({
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
  State<FunnelCampaignBudget> createState() => _FunnelCampaignBudgetState();
}

class _FunnelCampaignBudgetState extends State<FunnelCampaignBudget> {
  Map<String, dynamic>? _data;
  final _start = TextEditingController();
  int _generation = 0;
  bool _busy = false;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/budget';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  bool get _dirty =>
      _data != null && _start.text != (_data!['start_date'] ?? '');
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _invalidate(String message) {
    if (!mounted) return;
    final g = ++_generation;
    _data = null;
    _busy = false;
    _error = null;
    _message = null;
    _unavailable = message;
    // Do not notify a TextField during its parent's build.
    void redraw() {
      if (mounted && g == _generation) setState(() => _start.clear());
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => redraw());
    } else {
      redraw();
    }
  }

  void _deny() => _invalidate(
    'Sign in with Enterprise access to view this budget tracker.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close this tracker and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelCampaignBudget old) {
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
      _busy = false;
      _unavailable = null;
      _start.clear();
      unawaited(_load());
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

  Future<bool> _confirm(String title, String detail, String action) async {
    final g = _generation;
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer == true && _current(g);
  }

  Future<void> _request(String action, [Map<String, dynamic>? body]) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _data = null;
    });
    try {
      final result = await client.request(
        action == 'read' ? 'GET' : 'POST',
        action == 'read' ? path : '$path/$action',
        body: body,
      );
      if (!_current(g)) return;
      final data = validateCampaignBudget(result, funnel, campaign);
      setState(() {
        _data = data;
        _start.text = data['start_date'] ?? '';
        _message = action == 'save'
            ? 'Reporting window saved.'
            : action == 'clear'
            ? 'Reporting window cleared. Daily results are retained.'
            : null;
      });
    } catch (e) {
      if (_current(g)) {
        setState(() {
          _error = e is FunnelException
              ? e.message
              : 'The budget tracker could not load. Refresh it.';
          _start.clear();
        });
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (_dirty &&
        !await _confirm(
          'Discard this date change?',
          'Refresh loads the saved reporting window.',
          'Discard and refresh',
        )) {
      return;
    }
    await _request('read');
  }

  Future<void> _save() async {
    final d = _data;
    if (d == null || _busy || d['state'] == 'archived') return;
    final day = _start.text;
    final today = DateTime.parse('${d['as_of_date']}T00:00:00Z');
    if (!_date(day) ||
        DateTime.parse(
          '${day}T00:00:00Z',
        ).isBefore(today.subtract(const Duration(days: 730))) ||
        DateTime.parse(
          '${day}T00:00:00Z',
        ).isAfter(today.add(const Duration(days: 365)))) {
      setState(
        () =>
            _error = 'Enter YYYY-MM-DD within the past two years or next year.',
      );
      return;
    }
    await _request('save', {
      'version': d['version'],
      'campaign_version': d['campaign_version'],
      'start_date': day,
    });
  }

  Future<void> _clear() async {
    final d = _data;
    if (d == null || _busy || d['state'] == 'archived') return;
    if (!await _confirm(
      'Clear the reporting window?',
      'Daily results and your campaign plan are retained.',
      'Clear window',
    )) {
      return;
    }
    await _request('clear', {
      'version': d['version'],
      'campaign_version': d['campaign_version'],
      'confirmed': true,
    });
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_dirty &&
        !await _confirm(
          'Discard this date change?',
          'Your saved window remains unchanged.',
          'Discard date',
        )) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _copy() async {
    final d = _data, g = _generation;
    if (d == null || _dirty || _busy || _unavailable != null) return;
    try {
      await Clipboard.setData(ClipboardData(text: campaignBudgetSummary(d)));
      if (_current(g)) {
        setState(() => _message = 'Saved budget summary copied.');
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
  Widget _pacing(Map p) {
    final missing = p['missing_dates'] as List,
        variance = p['reported_days_variance_cents'] as int;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WfBadge('${p['phase']}'.toUpperCase()),
            const WfBadge('MANUAL RESULTS'),
            const WfBadge('USD'),
          ],
        ),
        _gap(),
        Text(
          '${_data!['start_date']} through ${p['end_date']} UTC',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _gap(),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            Text('${_money(p['planned_total_cents'])} planned total'),
            Text(
              p['reported_days'] == 0
                  ? 'No spend entries in this window'
                  : '${_money(p['recorded_spend_cents'])} recorded spend',
            ),
            Text(
              '${p['reported_completed_days']}/${p['completed_days']} completed days reported',
            ),
          ],
        ),
        _gap(),
        if (p['balance_cents'] < 0)
          Text(
            'Recorded spend exceeds the total plan by ${_money(-(p['balance_cents'] as int))}.',
            style: const TextStyle(
              color: WfStyle.danger,
              fontWeight: FontWeight.bold,
            ),
          )
        else
          Text('${_money(p['balance_cents'])} plan minus recorded spend'),
        _caption(
          'Unreported spend is unknown. This balance is not confirmed money available to spend.',
        ),
        if (missing.isNotEmpty) ...[
          _gap(),
          Text(
            '${missing.length} completed days have no report.',
            style: const TextStyle(
              color: WfStyle.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
          _caption(
            'Missing dates are not counted as zero spend. Enter them in Results & reporting.',
          ),
        ],
        _gap(),
        if (p['reported_completed_days'] == 0)
          _caption('No completed reported days to compare yet.')
        else
          Text(
            'For ${p['reported_completed_days']} completed reported days: ${_money(p['completed_spend_cents'])} recorded versus ${_money(p['reported_days_plan_cents'])} planned. ${variance == 0 ? 'Matches the daily plan.' : '${_money(variance.abs())} ${variance > 0 ? 'above' : 'below'} the plan for those days.'}',
          ),
        _caption(
          'Today is partial and excluded from completed-day comparisons. ${p['excluded_report_days']} reports outside this window are excluded.',
        ),
        _gap(),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Daily coverage'),
          children: [
            for (final r in p['rows'])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${r['day']} UTC'),
                subtitle: Text(
                  '${r['spend_cents'] == null ? 'No entry' : '${_money(r['spend_cents'])} recorded'} · ${switch (r['status']) {
                    'today' => 'Today · partial',
                    'future' => 'Upcoming day',
                    'missing' => 'Missing report',
                    _ => 'Completed report',
                  }}',
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data, archived = d?['state'] == 'archived';
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) unawaited(_close());
      },
      child: AlertDialog(
        title: const Text('Campaign budget pacing'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_unavailable != null)
                  Text(_unavailable!)
                else ...[
                  _caption(campaignBudgetBoundary),
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
                      d['name'],
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _gap(),
                    Text(
                      '${_money(d['daily_cents'])}/day · ${d['days']} days in the current plan',
                    ),
                    _caption(
                      'Changing the campaign budget or duration updates this comparison. Edit those values in Edit plan.',
                    ),
                    _gap(),
                    if (!archived) ...[
                      TextField(
                        controller: _start,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {
                          _message = null;
                          _error = null;
                        }),
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Reporting start date · UTC',
                          hintText: 'YYYY-MM-DD',
                        ),
                      ),
                      _gap(),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _busy || !_dirty ? null : _save,
                            child: const Text('Save reporting window'),
                          ),
                          if (d['start_date'] != null)
                            TextButton(
                              onPressed: _busy ? null : _clear,
                              child: const Text('Clear reporting window'),
                            ),
                        ],
                      ),
                    ] else
                      _caption(
                        'Archived campaign · reporting window is read-only.',
                      ),
                    _gap(),
                    if (_dirty)
                      _caption(
                        'Unsaved date change. Save it to update the comparison.',
                      )
                    else if (d['pacing'] == null)
                      _caption(
                        'Save a start date to compare daily results with this campaign plan.',
                      )
                    else
                      _pacing(d['pacing']),
                    _gap(),
                    _caption(
                      'Checked ${d['checked_at']}. Refresh after changing daily results or the campaign plan.',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_unavailable == null)
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh tracker'),
            ),
          if (d != null)
            TextButton(
              onPressed: _busy || _dirty ? null : _copy,
              child: const Text('Copy saved summary'),
            ),
          TextButton(
            onPressed: _busy ? null : _close,
            child: const Text('Close tracker'),
          ),
        ],
      ),
    );
  }
}
