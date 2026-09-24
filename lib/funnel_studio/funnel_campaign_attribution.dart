import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const campaignAttributionBoundary =
    'Link-associated inquiries used a KORLIX-recognized campaign link when the form opened. A copied link can be shared anywhere. This does not prove an ad click, a unique person, a sale or a Google/Meta conversion. No inquiry data is sent to an ad platform.';
const _bad = FunnelException(
  'Campaign attribution could not be verified. Refresh it.',
  503,
);
bool _date(dynamic v) =>
    v is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
    DateTime.tryParse('${v}T00:00:00Z')?.toIso8601String().substring(0, 10) ==
        v;
bool _count(dynamic v) => v is int && v >= 0 && v <= 1000000000;
Map<String, dynamic> validateCampaignAttribution(
  Map<String, dynamic> d,
  String funnel,
  String campaign,
  int days,
) {
  if (d['source'] != 'campaign_link_attribution' ||
      d['funnel_id'] != funnel ||
      d['campaign_id'] != campaign ||
      d['name'] is! String ||
      (d['name'] as String).isEmpty ||
      (d['name'] as String).runes.length > 100 ||
      !['meta', 'google', 'other'].contains(d['platform']) ||
      !['draft', 'reviewed', 'archived'].contains(d['state']) ||
      !['draft', 'published', 'paused'].contains(d['page_state']) ||
      d['slug'] is! String ||
      !RegExp(r'^[a-z0-9][a-z0-9-]{2,59}$').hasMatch(d['slug']) ||
      ![7, 30, 90].contains(days) ||
      d['days'] != days ||
      !_date(d['from_day']) ||
      !_date(d['through_day']) ||
      d['timezone'] != 'UTC' ||
      d['includes_today'] != true ||
      d['provider_verified'] != false ||
      d['checked_at'] is! String ||
      DateTime.tryParse(
            d['checked_at'],
          )?.toUtc().toIso8601String().substring(0, 10) !=
          d['through_day'] ||
      d['rows'] is! List ||
      (d['rows'] as List).length != days ||
      d['totals'] is! Map) {
    throw _bad;
  }
  final start = DateTime.parse('${d['from_day']}T00:00:00Z');
  if (start.add(Duration(days: days - 1)).toIso8601String().substring(0, 10) !=
      d['through_day']) {
    throw _bad;
  }
  final totals = {
    'link_inquiries': 0,
    'tag_only_inquiries': 0,
    'tag_conflicts': 0,
  };
  for (var i = 0; i < days; i++) {
    final row = d['rows'][i];
    if (row is! Map ||
        row['day'] !=
            start.add(Duration(days: i)).toIso8601String().substring(0, 10) ||
        totals.keys.any((k) => !_count(row[k])) ||
        row['tag_conflicts'] > row['link_inquiries']) {
      throw _bad;
    }
    for (final k in totals.keys) {
      totals[k] = totals[k]! + (row[k] as int);
    }
  }
  if (totals.keys.any(
    (k) => !_count(d['totals'][k]) || d['totals'][k] != totals[k],
  )) {
    throw _bad;
  }
  final link = d['link'];
  if (link != null) {
    if (link is! Map ||
        link['url'] is! String ||
        link['created_at'] is! String ||
        DateTime.tryParse(link['created_at']) == null) {
      throw _bad;
    }
    final url = Uri.tryParse(link['url']);
    final source = d['platform'] == 'meta'
        ? 'facebook'
        : d['platform'] == 'google'
        ? 'google'
        : 'other';
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.fragment.isNotEmpty ||
        url.path != '/f/${d['slug']}' ||
        url.queryParametersAll.length != 4 ||
        url.queryParametersAll.values.any((v) => v.length != 1) ||
        url.queryParameters['utm_source'] != source ||
        url.queryParameters['utm_medium'] != 'paid' ||
        url.queryParameters['utm_campaign'] !=
            'k143_${campaign.replaceAll('-', '')}' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(url.queryParameters['kl'] ?? '')) {
      throw _bad;
    }
  }
  return d;
}

class FunnelCampaignAttribution extends StatefulWidget {
  const FunnelCampaignAttribution({
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
  State<FunnelCampaignAttribution> createState() =>
      _FunnelCampaignAttributionState();
}

class _FunnelCampaignAttributionState extends State<FunnelCampaignAttribution> {
  Map<String, dynamic>? _data;
  int _generation = 0, _days = 30;
  bool _busy = false;
  String? _error, _unavailable, _notice;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/attribution';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
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
    'Sign in with Enterprise access to view campaign attribution.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close this report and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelCampaignAttribution old) {
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
      _days = 30;
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

  Future<void> _request({bool create = false}) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation,
        client = widget.client,
        path = _path,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        days = _days;
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _notice = null;
    });
    try {
      final result = await client.request(
        create ? 'POST' : 'GET',
        create ? '$path/link' : '$path?days=$days',
        body: create ? {'days': days} : null,
      );
      if (!_current(g)) return;
      final d = validateCampaignAttribution(result, funnel, campaign, days);
      if (create && d['link'] == null) throw _bad;
      setState(() {
        _data = d;
        _notice = create
            ? 'Campaign link is ready to copy. Existing ads and their destinations were not changed.'
            : null;
      });
    } catch (e) {
      if (_current(g)) {
        setState(
          () => _error = e is FunnelException
              ? e.message
              : 'Attribution could not load. Refresh it.',
        );
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final d = _data, g = _generation;
    if (d == null ||
        d['link'] == null ||
        _busy ||
        _unavailable != null ||
        d['page_state'] != 'published') {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: d['link']['url']));
      if (_current(g)) {
        setState(() => _notice = 'Campaign attribution link copied.');
      }
    } catch (_) {
      if (_current(g)) {
        setState(
          () => _error =
              'Copy failed. Select the link text and copy it manually.',
        );
      }
    }
  }

  Widget _note(String s) =>
      Text(s, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  Widget _metric(String label, int value) => SizedBox(
    width: 210,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfStyle.surface,
        border: Border.all(color: WfStyle.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
          ),
          _note(label),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 850),
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
                      'Campaign inquiry attribution',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close attribution',
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
                      _note(campaignAttributionBoundary),
                      const SizedBox(height: 16),
                      if (_unavailable != null) Text(_unavailable!),
                      if (_unavailable == null) ...[
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            DropdownButton<int>(
                              value: _days,
                              items: [7, 30, 90]
                                  .map(
                                    (n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('Last $n UTC days'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (n) {
                                      if (n != null) {
                                        setState(() => _days = n);
                                        unawaited(_request());
                                      }
                                    },
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _request(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh attribution'),
                            ),
                          ],
                        ),
                        if (_busy)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(),
                          ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        if (_notice != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_notice!),
                          ),
                        if (d != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            d['name'],
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          _note(
                            '${d['from_day']} through ${d['through_day']} UTC · Includes today, which is incomplete.',
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _metric(
                                'Link-associated inquiries',
                                d['totals']['link_inquiries'],
                              ),
                              _metric(
                                'Tag-only inquiries',
                                d['totals']['tag_only_inquiries'],
                              ),
                              _metric(
                                'Link inquiries with different tags',
                                d['totals']['tag_conflicts'],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _note(
                            'Tag-only matches use visitor-editable tags and exclude inquiries associated with any recognized campaign link. Different-tag inquiries are already included in the link total. Counts are submissions, not unique people; removed inquiries disappear from this report.',
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Recognized campaign link',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _note(
                            'Use this link for future campaigns you share. Existing tracking links remain tag-only. Creating a link does not publish or edit an ad. Past inquiries are not backfilled. The association follows this link even if its URL tags are changed.',
                          ),
                          const SizedBox(height: 12),
                          if (d['link'] == null) ...[
                            if (d['state'] != 'archived' &&
                                d['page_state'] == 'published')
                              FilledButton(
                                onPressed: () => _request(create: true),
                                child: const Text('Create attribution link'),
                              )
                            else
                              _note(
                                'Publish the page and reopen the campaign before creating its attribution link.',
                              ),
                          ] else ...[
                            SelectableText(d['link']['url']),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: d['page_state'] == 'published'
                                  ? _copy
                                  : null,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy attribution link'),
                            ),
                            _note(
                              'The link stays associated with this campaign when its local plan is archived. Pausing the page prevents new inquiries.',
                            ),
                            if (d['page_state'] != 'published')
                              _note(
                                'This page is not published. Existing evidence remains available.',
                              ),
                          ],
                          const SizedBox(height: 22),
                          const Text(
                            'Daily inquiry evidence',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final row in d['rows'])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    row['day'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${row['link_inquiries']} link-associated',
                                  ),
                                  Text('${row['tag_only_inquiries']} tag-only'),
                                  if (row['tag_conflicts'] > 0)
                                    Text(
                                      '${row['tag_conflicts']} with different tags',
                                    ),
                                ],
                              ),
                            ),
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
