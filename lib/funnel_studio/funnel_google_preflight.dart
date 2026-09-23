import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_google_preparation.dart';
import 'funnel_google_creative.dart';
import 'funnel_google_keywords.dart';
import 'funnel_google_targeting.dart';
import 'funnel_google_radius.dart';

const googlePreflightChecks = <String, String>{
  'page_published': 'Landing page published',
  'plan_reviewed': 'Campaign plan reviewed',
  'setup_reviewed': 'Account setup reviewed',
  'copy_reviewed': 'Search-ad copy reviewed',
  'keywords_reviewed': 'Keywords reviewed',
  'targeting_reviewed': 'Targeting reviewed',
};
const googlePreflightBoundary =
    'Preparation only. This checklist does not verify live Google eligibility, create an ad, set a platform budget or authorize spending. Final account setup, conversion tracking, location eligibility and launch still require checking.';

bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a is List && b is List
    ? listEquals(a, b)
    : a == b;

Map<String, dynamic> validateGooglePreflight(
  Map<String, dynamic> r,
  String funnel,
  String campaign,
) {
  const error = FunnelException(
    'The preparation checklist could not be verified. Refresh it.',
    503,
  );
  if (r['source'] != 'google_preflight' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      r['checked_at'] is! String ||
      DateTime.tryParse(r['checked_at']) == null ||
      r['ad_publishing_ready'] != false ||
      r['preparation_complete'] is! bool ||
      [
        'setup',
        'creative',
        'keywords',
        'targeting',
      ].any((k) => r[k] is! Map<String, dynamic>)) {
    throw error;
  }
  final s = validateGooglePreparation(r['setup'], funnel, campaign);
  final a = validateGoogleCreative(r['creative'], funnel, campaign);
  final k = validateGoogleKeywords(r['keywords'], funnel, campaign);
  final t = validateGoogleTargeting(r['targeting'], funnel, campaign);
  final expected = <String, dynamic>{
    'page_published': s['checks']['page_published'],
    'plan_reviewed': s['checks']['plan_reviewed'],
    'setup_reviewed': s['review_current'],
    'copy_reviewed': a['review_current'],
    'keywords_reviewed': k['review_current'],
    'targeting_reviewed': t['review_current'],
  };
  final context = a['context'] as Map,
      plan = s['current_snapshot']['campaign'],
      page = s['current_snapshot']['landing_page'];
  if (!_same(r['checks'], expected) ||
      r['preparation_complete'] != expected.values.every((v) => v == true) ||
      !_same(context, k['context']) ||
      !_same(context, t['context']) ||
      context['campaign_name'] != plan['name'] ||
      context['page_version'] != page['version'] ||
      context['brand'] != page['brand'] ||
      context['destination'] != page['destination'] ||
      [
        'headline',
        'body',
        'cta',
        'audience',
        'daily_cents',
        'days',
      ].any((key) => context[key] != plan[key]) ||
      expected['page_published'] != (context['page_state'] == 'published') ||
      [a, k, t].any(
        (d) =>
            d['review_checks']['page_published'] !=
                expected['page_published'] ||
            d['review_checks']['plan_reviewed'] != expected['plan_reviewed'],
      )) {
    throw error;
  }
  return r;
}

String googlePreparationStatus(Map d) => d['review_current'] == true
    ? 'CURRENT'
    : d['reviewed_snapshot'] == null
    ? 'NOT REVIEWED'
    : 'OUT OF DATE';
String _money(num n) => '\$${(n / 100).toStringAsFixed(2)}';
String googlePreparationSummary(Map<String, dynamic> d) {
  final s = d['setup']['current_snapshot'],
      p = s['campaign'],
      page = s['landing_page'],
      identity = s['google_ads'];
  final out = StringBuffer(
    'KORLIX GOOGLE PREPARATION SUMMARY\nChecked: ${d['checked_at']}\n',
  );
  out.writeln(
    d['preparation_complete'] == true
        ? 'ALL PREPARATION REVIEWS CURRENT AT CHECK TIME'
        : 'PREPARATION INCOMPLETE AT CHECK TIME',
  );
  out.writeln(
    'Campaign: ${p['name']}\nPlanned budget: ${_money(p['daily_cents'])} USD/day for ${p['days']} days; ${_money(p['planned_total_cents'])} USD total.\nAudience: ${p['audience']}\nDestination: ${page['destination']}\nPublished page version: ${page['version']}',
  );
  for (final e in googlePreflightChecks.entries) {
    out.writeln(
      '${e.value}: ${d['checks'][e.key] == true ? 'CURRENT' : 'NEEDS ATTENTION'}',
    );
  }
  final account = identity['account'];
  out.writeln(
    '\nAccount setup: ${googlePreparationStatus(d['setup'])}\nSelected account (cached): ${account == null ? '(none)' : '${account['name']} (${account['id']})'}\nAccount cache refreshed: ${identity['accounts_refreshed_at'] ?? '(never)'}\nSetup reviewed: ${d['setup']['reviewed_at'] ?? '(never)'}',
  );
  for (final entry in [
    ('creative', 'Search-ad copy'),
    ('keywords', 'Keywords'),
    ('targeting', 'Targeting'),
  ]) {
    final draft = d[entry.$1];
    out.writeln('\n${entry.$2}: ${googlePreparationStatus(draft)}');
    if (draft['version'] == 0) {
      out.writeln('No saved draft.');
      continue;
    }
    final a = draft['assets'], c = draft['saved_context'];
    out.writeln(
      'Saved draft revision: ${draft['draft_revision']}\nSaved: ${draft['updated_at']}\nSaved context: ${draft['draft_current'] == true ? 'CURRENT' : 'OUT OF DATE'}\nCampaign at save: ${c['campaign_name']}\nDestination at save: ${c['destination']}\nReviewed: ${draft['reviewed_at'] ?? '(never)'}',
    );
    if (entry.$1 == 'creative') {
      out.writeln(
        'Headlines:\n${(a['headlines'] as List).join('\n')}\nDescriptions:\n${(a['descriptions'] as List).join('\n')}\nDisplay paths: ${a['path1']} / ${a['path2']}',
      );
    } else if (entry.$1 == 'keywords') {
      for (final e in googleKeywordLabels.entries) {
        out.writeln(
          '${e.value}:\n${(a[e.key] as List).isEmpty ? '(none)' : (a[e.key] as List).join('\n')}',
        );
      }
    } else {
      final labels = draft['saved_labels'];
      String names(String key) => (a[key] as List).isEmpty
          ? '(none selected)'
          : (a[key] as List)
                .map(
                  (code) =>
                      labels[key == 'content_languages'
                          ? key
                          : 'countries'][code],
                )
                .join(', ');
      out.writeln(
        '${googleRadiusSummary(a)}\nTarget countries: ${names('countries')}\nExcluded countries: ${names('excluded_countries')}\nContent languages (planning only): ${names('content_languages')}\nLocation reach: ${googleLocationModes[a['location_mode']]}\nPlanned bidding: ${googleBiddingPlans[a['bidding']]}',
      );
    }
  }
  out.writeln(
    '\nDraft details above are the saved drafts at check time. A prior review may cover an earlier revision; open the individual review record for its exact contents.\n$googlePreflightBoundary',
  );
  return out.toString();
}

class FunnelGooglePreflight extends StatefulWidget {
  const FunnelGooglePreflight({
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
  State<FunnelGooglePreflight> createState() => _FunnelGooglePreflightState();
}

class _FunnelGooglePreflightState extends State<FunnelGooglePreflight> {
  Map<String, dynamic>? _data;
  bool _busy = false, _childOpen = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  bool _current(int g) => mounted && g == _generation && _unavailable == null;
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
    _childOpen = false;
    _error = null;
    _message = null;
    _unavailable = message;
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
    'Sign in with Enterprise access to view this preparation checklist.',
  );
  void _scopeChanged() => _invalidate(
    'Your workspace changed. Close this checklist and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGooglePreflight old) {
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
        old.funnelId != widget.funnelId ||
        old.campaignId != widget.campaignId ||
        old.scope != widget.scope) {
      _generation++;
      _unavailable = null;
      _data = null;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.client.removeAccessDeniedListener(_deny);
    widget.scope?.removeListener(_scopeChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (_unavailable != null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _childOpen = false;
      _data = null;
      _error = null;
      _message = null;
    });
    try {
      final r = await widget.client.request(
        'GET',
        '/${widget.funnelId}/campaigns/${widget.campaignId}/google-preflight',
      );
      if (!_current(g)) return;
      final d = validateGooglePreflight(r, widget.funnelId, widget.campaignId);
      setState(() => _data = d);
    } catch (e) {
      if (!_current(g)) return;
      if (e is FunnelException && [401, 403].contains(e.status)) {
        _deny();
      } else if (e is FunnelException && e.status == 404) {
        _invalidate(
          'This campaign is no longer available. Close this checklist.',
        );
      } else {
        setState(
          () => _error = e is FunnelException
              ? e.message
              : 'The preparation checklist is unavailable. Refresh it.',
        );
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _open(String key) async {
    if (_busy || _unavailable != null || _data == null) return;
    final g = _generation,
        client = widget.client,
        funnel = widget.funnelId,
        campaign = widget.campaignId,
        scope = widget.scope;
    setState(() {
      _busy = true;
      _childOpen = true;
      _message = null;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => switch (key) {
        'setup' => FunnelGooglePreparation(
          client: client,
          funnelId: funnel,
          campaignId: campaign,
          scope: scope,
        ),
        'creative' => FunnelGoogleCreative(
          client: client,
          funnelId: funnel,
          campaignId: campaign,
          scope: scope,
        ),
        'keywords' => FunnelGoogleKeywords(
          client: client,
          funnelId: funnel,
          campaignId: campaign,
          scope: scope,
        ),
        _ => FunnelGoogleTargeting(
          client: client,
          funnelId: funnel,
          campaignId: campaign,
          scope: scope,
        ),
      },
    );
    if (_current(g)) await _load();
  }

  Future<void> _copy() async {
    if (_busy || _unavailable != null || _data == null) return;
    final g = _generation;
    try {
      await Clipboard.setData(
        ClipboardData(text: googlePreparationSummary(_data!)),
      );
      if (_current(g)) setState(() => _message = 'Preparation summary copied.');
    } catch (_) {
      if (_current(g)) {
        setState(() => _error = 'The summary could not be copied. Try again.');
      }
    }
  }

  Widget _component(
    String key,
    String title,
    String button,
    Map<String, String> reasons,
  ) {
    final d = _data![key],
        checks = d[key == 'setup' ? 'checks' : 'review_checks'];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WfStyle.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WfStyle.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          WfBadge(googlePreparationStatus(d)),
          if (d['reviewed_at'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Reviewed: ${d['reviewed_at']}'),
            ),
          if (key != 'setup')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                d['version'] == 0
                    ? 'No saved draft yet.'
                    : 'Saved draft ${d['draft_revision']} · ${d['updated_at']}',
              ),
            ),
          for (final e in reasons.entries)
            if (checks[e.key] != true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  e.value,
                  style: const TextStyle(color: WfStyle.gold),
                ),
              ),
          if (d['review_current'] != true &&
              checks.values.every((v) => v == true))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Open this review and confirm the current saved details.',
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _open(key),
            child: Text(button),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 20,
                runSpacing: 8,
                children: [
                  const Text(
                    'Google preparation checklist',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                googlePreflightBoundary,
                style: TextStyle(color: WfStyle.muted, height: 1.5),
              ),
              if (_busy && !_childOpen)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
              if (_unavailable != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_unavailable!),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: WfStyle.gold),
                  ),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _message!,
                    style: const TextStyle(color: WfStyle.cyan),
                  ),
                ),
              if (d != null) ...[
                const SizedBox(height: 16),
                Text(
                  d['setup']['current_snapshot']['campaign']['name'],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                WfBadge(
                  d['preparation_complete'] == true
                      ? 'PREPARATION REVIEWS CURRENT'
                      : 'PREPARATION NEEDS ATTENTION',
                ),
                const SizedBox(height: 10),
                Text(
                  '${(d['checks'] as Map).values.where((v) => v == true).length} of 6 preparation checks current',
                ),
                Text('Checked: ${d['checked_at']}'),
                const SizedBox(height: 12),
                const Text(
                  'Account details come from the saved account cache. Refresh the checklist after making changes elsewhere.',
                ),
                const SizedBox(height: 12),
                for (final key in ['page_published', 'plan_reviewed'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${googlePreflightChecks[key]}: ${d['checks'][key] == true ? 'CURRENT' : 'NEEDS ATTENTION'}',
                    ),
                  ),
                if (d['checks']['page_published'] != true ||
                    d['checks']['plan_reviewed'] != true)
                  const Text(
                    'Close this checklist to publish the landing page or review the campaign plan.',
                  ),
                _component('setup', 'Account setup', 'Open setup review', {
                  for (final e in googleSetupChecks.entries) e.key: e.value.$2,
                }),
                _component(
                  'creative',
                  'Search-ad copy',
                  'Open copy review',
                  googleCopyReviewChecks,
                ),
                _component(
                  'keywords',
                  'Keywords',
                  'Open keyword review',
                  googleKeywordReviewChecks,
                ),
                _component(
                  'targeting',
                  'Targeting',
                  'Open targeting review',
                  googleTargetingReviewChecks,
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Preparation summary'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(googlePreparationSummary(d)),
                    ),
                  ],
                ),
              ],
              if (_unavailable == null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Refresh checklist'),
                      ),
                      OutlinedButton(
                        onPressed: _busy || d == null ? null : _copy,
                        child: const Text('Copy preparation summary'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
