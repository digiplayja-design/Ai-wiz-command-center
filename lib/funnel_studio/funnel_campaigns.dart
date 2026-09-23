import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_meta.dart';
import 'funnel_google_ads.dart';

String campaignMoney(num cents) => '\$${(cents / 100).toStringAsFixed(2)}';
String campaignChannel(String value) => switch (value) {
  'meta' => 'Meta',
  'google' => 'Google',
  _ => 'Other',
};
int campaignTotal(Map c, String key) => (c['reports'] as List? ?? []).fold<int>(
  0,
  (n, r) => n + ((r[key] as num?)?.toInt() ?? 0),
);
Widget campaignCard(Widget child) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(22),
  decoration: BoxDecoration(
    color: WfStyle.surface,
    border: Border.all(color: WfStyle.line),
    borderRadius: BorderRadius.circular(20),
  ),
  child: child,
);
Widget campaignSpace([double height = 14]) => SizedBox(height: height);
Widget campaignCaption(String text) =>
    Text(text, style: const TextStyle(color: WfStyle.muted, height: 1.5));
Widget campaignPreview(Map c) => Container(
  padding: const EdgeInsets.all(22),
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      colors: [Color(0xFF163442), WfStyle.surface],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: WfStyle.cyan.withValues(alpha: .3)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const WfBadge('COPY PREVIEW'),
      campaignSpace(),
      Text(
        '${c['headline'] ?? ''}',
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      campaignSpace(),
      Text('${c['body'] ?? ''}', style: const TextStyle(height: 1.6)),
      campaignSpace(),
      Text(
        '${c['cta'] ?? ''}',
        style: const TextStyle(
          color: WfStyle.cyan,
          fontWeight: FontWeight.bold,
        ),
      ),
      campaignSpace(8),
      campaignCaption(
        'Text concept · final ad formatting and creative are set in the ad platform.',
      ),
    ],
  ),
);

class FunnelCampaigns extends StatefulWidget {
  const FunnelCampaigns({
    super.key,
    required this.client,
    required this.funnelId,
  });
  final FunnelClient client;
  final String funnelId;
  @override
  State<FunnelCampaigns> createState() => _FunnelCampaignsState();
}

class _FunnelCampaignsState extends State<FunnelCampaigns> {
  List<Map<String, dynamic>> _items = [];
  bool _busy = false, _ai = false;
  String? _error;
  String _search = '', _channel = 'all', _state = 'all';
  String get _path => '/${widget.funnelId}/campaigns';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fetch() async {
    final r = await widget.client.request('GET', _path);
    if (!mounted) return;
    setState(() {
      _items = (r['campaigns'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _ai = r['ai_ready'] == true;
    });
  }

  Future<void> _load() => _run(_fetch);
  Future<void> _edit([Map<String, dynamic>? c]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CampaignEditor(
        client: widget.client,
        path: _path,
        campaign: c,
        aiReady: _ai,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
    }
  }

  Future<void> _action(Map c, String action, {bool confirmed = false}) =>
      _run(() async {
        await widget.client.request(
          'POST',
          '$_path/$action',
          body: {
            'campaign_id': c['id'],
            'version': c['version'],
            'confirmed': confirmed,
          },
        );
        await _fetch();
      });
  Future<void> _review(Map c) async {
    var checked = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, change) => AlertDialog(
          title: const Text('Review campaign plan'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${c['name']} · ${campaignChannel('${c['platform']}')}'),
                  campaignSpace(),
                  Text(
                    '${campaignMoney(c['daily_cents'])} / day × ${c['days']} days = ${campaignMoney(c['planned_total_cents'])} USD planned',
                  ),
                  campaignSpace(),
                  campaignPreview(c),
                  campaignSpace(),
                  Text('Audience brief: ${c['audience']}'),
                  campaignSpace(),
                  SelectableText('${c['tracking_url']}'),
                  campaignSpace(),
                  campaignCaption(
                    'Review records this plan and the current published page. It does not publish an ad, authorize spending, or enforce a platform budget.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    onChanged: (v) => change(() => checked = v == true),
                    title: const Text(
                      'I reviewed the offer, copy, audience, and planned budget.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Mark plan reviewed'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) await _action(c, 'review', confirmed: true);
  }

  Future<void> _archive(Map c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this plan?'),
        content: const Text(
          'The plan and its reporting history remain available. Archiving here does not pause any ads you created in Meta or Google.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep plan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive plan'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _action(c, 'archive', confirmed: true);
  }

  Future<void> _reports(Map<String, dynamic> c) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CampaignReports(client: widget.client, path: _path, campaign: c),
    );
    if (mounted) await _load();
  }

  String _brief(Map c) =>
      'KORLIX campaign plan — ${c['name']}\nChannel: ${campaignChannel('${c['platform']}')}\nPlanned budget: ${campaignMoney(c['daily_cents'])} USD/day for ${c['days']} days; ${campaignMoney(c['planned_total_cents'])} USD total.\nAudience: ${c['audience']}\nHeadline: ${c['headline']}\nMessage: ${c['body']}\nCTA: ${c['cta']}\nDestination: ${c['tracking_url']}\nPlan only. Review and launch separately in your ad platform.';
  @override
  Widget build(BuildContext context) {
    final shown = _items
        .where(
          (c) =>
              '${c['name']}'.toLowerCase().contains(_search.toLowerCase()) &&
              (_channel == 'all' || c['platform'] == _channel) &&
              (_state == 'all' || c['state'] == _state),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        campaignCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WfBadge(
                'ENTERPRISE · CAMPAIGN WORKSPACE',
                color: WfStyle.violet,
              ),
              campaignSpace(),
              const Text(
                'From offer to opportunity.',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              campaignSpace(8),
              campaignCaption(
                'Shape your campaign with NOVA. Plan the budget, prepare the copy, and connect each inquiry to its source.',
              ),
              campaignSpace(),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('New campaign plan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh campaigns'),
                  ),
                ],
              ),
              campaignSpace(),
              campaignCaption(
                'Connect a Meta or Google Ads account below when available. Launch and manage ads in your ad platform using the campaign link. Budgets here are plans; results are entered manually.',
              ),
            ],
          ),
        ),
        campaignSpace(20),
        FunnelMetaConnection(client: widget.client),
        campaignSpace(20),
        FunnelGoogleAdsConnection(client: widget.client),
        campaignSpace(20),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(_error!, style: const TextStyle(color: WfStyle.danger)),
          ),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _stat('${_items.length}', 'Saved plans'),
            _stat(
              '${_items.fold<int>(0, (n, c) => n + ((c['tagged_leads'] as num?)?.toInt() ?? 0))}',
              'Tagged inquiries · all time',
            ),
            _stat(
              campaignMoney(
                _items.fold<int>(
                  0,
                  (n, c) => n + campaignTotal(c, 'spend_cents'),
                ),
              ),
              'Recorded spend · USD · manual',
            ),
          ],
        ),
        campaignSpace(20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search campaign plans',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                initialValue: _channel,
                decoration: const InputDecoration(labelText: 'Channel'),
                items: ['all', 'meta', 'google', 'other']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(
                          v == 'all' ? 'All channels' : campaignChannel(v),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _channel = v!),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                initialValue: _state,
                decoration: const InputDecoration(labelText: 'Plan status'),
                items: ['all', 'draft', 'reviewed', 'archived']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text(v == 'all' ? 'All statuses' : v),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _state = v!),
              ),
            ),
          ],
        ),
        campaignSpace(20),
        if (!_busy && shown.isEmpty)
          campaignCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  size: 38,
                  color: WfStyle.cyan,
                ),
                campaignSpace(),
                Text(
                  _items.isEmpty
                      ? 'Your next audience starts with a plan.'
                      : 'No plans match these filters.',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                campaignSpace(8),
                campaignCaption(
                  'Create a campaign for this funnel, prepare its copy, and use its unique link when launching externally.',
                ),
              ],
            ),
          ),
        for (final c in shown)
          Padding(padding: const EdgeInsets.only(bottom: 18), child: _plan(c)),
      ],
    );
  }

  Widget _stat(String value, String label) => SizedBox(
    width: 240,
    child: campaignCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          campaignSpace(6),
          campaignCaption(label),
        ],
      ),
    ),
  );
  Widget _plan(Map<String, dynamic> c) {
    final archived = c['state'] == 'archived',
        current = c['review_current'] == true;
    return campaignCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              WfBadge(
                campaignChannel('${c['platform']}'),
                color: WfStyle.violet,
              ),
              WfBadge(
                archived
                    ? 'ARCHIVED PLAN'
                    : current
                    ? 'REVIEWED PLAN'
                    : c['state'] == 'reviewed'
                    ? 'PAGE CHANGED · REVIEW AGAIN'
                    : 'DRAFT PLAN',
                color: current ? WfStyle.cyan : WfStyle.gold,
              ),
            ],
          ),
          campaignSpace(),
          Text(
            '${c['name']}',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          campaignSpace(8),
          Text('${c['headline']}', style: const TextStyle(fontSize: 16)),
          campaignSpace(),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              Text(
                '${campaignMoney(c['daily_cents'])}/day · ${c['days']} days planned',
              ),
              Text(
                '${campaignMoney(c['planned_total_cents'])} USD planned total',
              ),
              Text('${c['tagged_leads'] ?? 0} tagged inquiries'),
            ],
          ),
          campaignSpace(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!archived)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _edit(c),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit plan'),
                ),
              if (!archived)
                FilledButton(
                  onPressed: _busy || c['page_state'] != 'published'
                      ? null
                      : () => _review(c),
                  child: const Text('Review plan'),
                ),
              OutlinedButton(
                onPressed: _busy ? null : () => _reports(c),
                child: const Text('Results & reporting'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _copy('${c['tracking_url']}'),
                child: const Text('Copy tracking link'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _copy(_brief(c)),
                child: const Text('Copy campaign brief'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => archived ? _action(c, 'reopen') : _archive(c),
                child: Text(archived ? 'Reopen plan' : 'Archive'),
              ),
            ],
          ),
          if (c['page_state'] != 'published') ...[
            campaignSpace(8),
            campaignCaption(
              'Publish this funnel page before reviewing or sharing your campaign destination.',
            ),
          ],
        ],
      ),
    );
  }
}

class CampaignEditor extends StatefulWidget {
  const CampaignEditor({
    super.key,
    required this.client,
    required this.path,
    this.campaign,
    required this.aiReady,
  });
  final FunnelClient client;
  final String path;
  final Map<String, dynamic>? campaign;
  final bool aiReady;
  @override
  State<CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends State<CampaignEditor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;
  String _platform = 'meta';
  TextEditingController get _brief => _controllers['brief']!;
  @override
  void initState() {
    super.initState();
    final c = widget.campaign;
    _platform = c?['platform'] ?? 'meta';
    for (final key in [
      'name',
      'headline',
      'body',
      'cta',
      'audience',
      'brief',
      'daily',
      'days',
    ]) {
      _controllers[key] = TextEditingController(
        text: key == 'daily'
            ? ((c?['daily_cents'] ?? 2500) / 100).toStringAsFixed(2)
            : key == 'days'
            ? '${c?['days'] ?? 14}'
            : '${c?[key] ?? ''}',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _copy => {
    for (final k in ['headline', 'body', 'cta', 'audience'])
      k: _controllers[k]!.text.trim(),
  };
  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(() async {
    if (_brief.text.trim().isEmpty) {
      throw const FunnelException(
        'Describe the offer and facts NOVA should use.',
      );
    }
    final r = await widget.client.request(
      'POST',
      '${widget.path}/generate',
      body: {'brief': _brief.text.trim()},
    );
    if (!mounted) return;
    setState(() {
      for (final key in ['headline', 'body', 'cta', 'audience']) {
        _controllers[key]!.text = '${r['copy'][key] ?? ''}';
      }
    });
  });
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      final c = widget.campaign;
      await widget.client.request(
        'POST',
        '${widget.path}/${c == null ? 'create' : 'save'}',
        body: {
          'name': _controllers['name']!.text.trim(),
          'platform': _platform,
          ..._copy,
          'daily_cents': (double.parse(_controllers['daily']!.text) * 100)
              .round(),
          'days': int.parse(_controllers['days']!.text),
          if (c != null) ...{'campaign_id': c['id'], 'version': c['version']},
        },
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  Widget _field(
    String key,
    String label,
    int max, {
    int lines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _controllers[key],
      enabled: !_busy,
      maxLength: max,
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      validator: (v) =>
          required && (v?.trim().isEmpty ?? true) ? 'Required' : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final daily = double.tryParse(_controllers['daily']!.text) ?? 0,
        days = int.tryParse(_controllers['days']!.text) ?? 0;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          widget.campaign == null
              ? 'Build a campaign plan'
              : 'Edit campaign plan',
        ),
        content: SizedBox(
          width: 920,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  campaignCaption(
                    'Create an ad-ready brief for this funnel. All amounts are USD. Saving an edit resets the plan review.',
                  ),
                  campaignSpace(),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: WfStyle.danger),
                    ),
                  _field('name', 'Campaign name', 100, required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _platform,
                    decoration: const InputDecoration(
                      labelText: 'Campaign channel',
                    ),
                    items: ['meta', 'google', 'other']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(campaignChannel(v)),
                          ),
                        )
                        .toList(),
                    onChanged: _busy || widget.campaign != null
                        ? null
                        : (v) => setState(() => _platform = v!),
                  ),
                  campaignSpace(),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: 210,
                        child: TextFormField(
                          controller: _controllers['daily'],
                          enabled: !_busy,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Planned daily budget · USD',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            return n == null ||
                                    !n.isFinite ||
                                    n < 1 ||
                                    n > 10000 ||
                                    !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v!)
                                ? 'Use 1–10,000 USD, up to 2 decimals.'
                                : null;
                          },
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: TextFormField(
                          controller: _controllers['days'],
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duration · days',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 90
                                ? 'Use 1–90 days.'
                                : null;
                          },
                        ),
                      ),
                    ],
                  ),
                  campaignSpace(),
                  Text(
                    'Planned total: ${daily.isFinite ? campaignMoney(daily * days * 100) : '—'} USD',
                    style: const TextStyle(
                      color: WfStyle.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  campaignSpace(),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Draft with NOVA'),
                    subtitle: const Text(
                      'Uses the shared 10 daily NOVA draft attempts',
                    ),
                    children: [
                      _field(
                        'brief',
                        'Offer, audience, and verified facts',
                        2400,
                        lines: 3,
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || !widget.aiReady ? null : _generate,
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Generate ad copy'),
                      ),
                      campaignSpace(),
                      campaignCaption(
                        'Replaces the unsaved copy fields below. Review AI-generated text before using it.',
                      ),
                    ],
                  ),
                  campaignSpace(),
                  _field('audience', 'Audience brief', 1000, lines: 2),
                  _field('headline', 'Headline', 180),
                  _field('body', 'Primary message', 2000, lines: 4),
                  _field('cta', 'Call to action', 60),
                  campaignPreview(_copy),
                  if (_busy) ...[
                    campaignSpace(),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save campaign plan'),
          ),
        ],
      ),
    );
  }
}

class CampaignReports extends StatefulWidget {
  const CampaignReports({
    super.key,
    required this.client,
    required this.path,
    required this.campaign,
  });
  final FunnelClient client;
  final String path;
  final Map<String, dynamic> campaign;
  @override
  State<CampaignReports> createState() => _CampaignReportsState();
}

class _CampaignReportsState extends State<CampaignReports> {
  late Map<String, dynamic> _c;
  final _form = GlobalKey<FormState>();
  final _spend = TextEditingController(text: '0.00'),
      _clicks = TextEditingController(text: '0'),
      _impressions = TextEditingController(text: '0'),
      _note = TextEditingController();
  String _day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  String? _error;
  bool _busy = false;
  List get _rows => _c['reports'] as List? ?? [];
  @override
  void initState() {
    super.initState();
    _c = Map.from(widget.campaign);
    _takeDay(_day);
  }

  @override
  void dispose() {
    _spend.dispose();
    _clicks.dispose();
    _impressions.dispose();
    _note.dispose();
    super.dispose();
  }

  void _takeDay(String day) {
    final r = _rows.where((r) => r['day'] == day).firstOrNull;
    _day = day;
    _spend.text = ((r?['spend_cents'] ?? 0) / 100).toStringAsFixed(2);
    _clicks.text = '${r?['clicks'] ?? 0}';
    _impressions.text = '${r?['impressions'] ?? 0}';
    _note.text = '${r?['note'] ?? ''}';
  }

  Future<void> _date() async {
    final now = DateTime.now().toUtc();
    final earliest = now.subtract(const Duration(days: 730));
    final selected = DateTime.parse(_day);
    final d = await showDatePicker(
      context: context,
      initialDate: selected.isBefore(earliest)
          ? earliest
          : selected.isAfter(now)
          ? now
          : selected,
      firstDate: earliest,
      lastDate: now,
    );
    if (d != null && mounted) {
      setState(
        () => _takeDay(
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        ),
      );
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (_busy || !remove && !_form.currentState!.validate()) return;
    if (remove) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove this reporting day?'),
          content: Text(
            'Remove manual results for $_day UTC. Captured inquiries remain unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep results'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove day'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'POST',
        '${widget.path}/${remove ? 'removeReport' : 'report'}',
        body: {
          'campaign_id': _c['id'],
          'version': _c['version'],
          'day': _day,
          if (remove) 'confirmed': true,
          if (!remove) ...{
            'spend_cents': (double.parse(_spend.text) * 100).round(),
            'clicks': int.parse(_clicks.text),
            'impressions': int.parse(_impressions.text),
            'note': _note.text.trim(),
          },
        },
      );
      final out = await widget.client.request('GET', widget.path);
      if (mounted) {
        setState(() {
          _c = Map<String, dynamic>.from(
            (out['campaigns'] as List).firstWhere((r) => r['id'] == _c['id'])
                as Map,
          );
          _takeDay(_day);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _number(
    TextEditingController c,
    String label,
    int max, {
    bool money = false,
  }) => SizedBox(
    width: 190,
    child: TextFormField(
      controller: c,
      enabled: !_busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final n = double.tryParse(v ?? '');
        return n == null ||
                !n.isFinite ||
                n < 0 ||
                n > max ||
                !(money ? RegExp(r'^\d+(\.\d{1,2})?$') : RegExp(r'^\d+$'))
                    .hasMatch(v!)
            ? 'Enter a valid nonnegative total.'
            : null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final spend = campaignTotal(_c, 'spend_cents'),
        clicks = campaignTotal(_c, 'clicks'),
        impressions = campaignTotal(_c, 'impressions'),
        covered = (_c['covered_leads'] as num?)?.toInt() ?? 0,
        archived = _c['state'] == 'archived';
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Campaign results'),
        content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_c['name']}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                campaignSpace(),
                const WfBadge('MANUALLY RECORDED · USD'),
                campaignSpace(),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    Text('${campaignMoney(spend)} recorded spend'),
                    Text('$clicks clicks · $impressions impressions'),
                    Text(
                      '${_c['tagged_leads'] ?? 0} tagged inquiries · all time',
                    ),
                    Text('${_rows.length} reported UTC days'),
                  ],
                ),
                campaignSpace(),
                Text(
                  'Cost per click: ${clicks > 0 ? campaignMoney(spend / clicks) : '—'} · Cost per tagged inquiry: ${covered > 0 ? campaignMoney(spend / covered) : '—'}',
                ),
                campaignSpace(8),
                campaignCaption(
                  'Cost per inquiry uses only the $covered matching submissions on dates with a manual report. Tags are visitor-supplied; this is not verified ad attribution. Missing dates are excluded. No revenue or ROAS is inferred.',
                ),
                campaignSpace(20),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: WfStyle.danger)),
                if (!archived)
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enter or correct daily totals',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        campaignSpace(8),
                        campaignCaption(
                          'Copy totals from your ad platform for this campaign and UTC date. Saving replaces the existing totals for this date.',
                        ),
                        TextButton.icon(
                          onPressed: _busy ? null : _date,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Reporting date: $_day UTC'),
                        ),
                        campaignSpace(8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _number(
                              _spend,
                              'Spend · USD',
                              1000000,
                              money: true,
                            ),
                            _number(_clicks, 'Clicks', 100000000),
                            _number(_impressions, 'Impressions', 1000000000),
                          ],
                        ),
                        campaignSpace(),
                        TextFormField(
                          controller: _note,
                          enabled: !_busy,
                          maxLength: 400,
                          decoration: const InputDecoration(
                            labelText: 'Source note · optional',
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton(
                              onPressed: _busy ? null : () => _save(),
                              child: const Text('Save daily results'),
                            ),
                            if (_rows.any((r) => r['day'] == _day))
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _save(remove: true),
                                child: const Text('Remove this day'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                campaignSpace(20),
                const Text(
                  'Reporting history · latest 30 days entered',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                campaignSpace(),
                if (_rows.isEmpty)
                  campaignCaption('No platform results entered yet.'),
                for (final r in _rows.take(30))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${r['day']} UTC · ${campaignMoney(r['spend_cents'])}',
                    ),
                    subtitle: Text(
                      '${r['clicks']} clicks · ${r['impressions']} impressions${r['note'] == '' ? '' : '\n${r['note']}'}',
                    ),
                    trailing: archived ? null : const Icon(Icons.edit_outlined),
                    onTap: archived || _busy
                        ? null
                        : () => setState(() => _takeDay('${r['day']}')),
                  ),
                if (_rows.length > 30)
                  campaignCaption(
                    'Choose an earlier reporting date above to view or correct its totals.',
                  ),
                if (_busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close reporting'),
          ),
        ],
      ),
    );
  }
}
