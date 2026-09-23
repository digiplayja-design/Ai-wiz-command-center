import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const metaSetupChecks = <String, (String, String)>{
  'page_published': (
    'Landing page published',
    'Publish the funnel page before reviewing this setup.',
  ),
  'plan_reviewed': (
    'Campaign plan reviewed',
    'Complete the copy and audience brief, then review the plan against the published page.',
  ),
  'meta_configured': (
    'Meta platform setup available',
    'KORLIX Meta activation is still needed.',
  ),
  'meta_connected': (
    'Meta connection current',
    'Connect or reconnect Meta in the Ads workspace.',
  ),
  'account_selected': (
    'Ad account selected',
    'Select an ad account in the Meta connection card.',
  ),
  'account_active': (
    'Selected ad account active',
    'Refresh ad accounts and choose an active account.',
  ),
  'currency_supported': (
    'Account matches the USD plan',
    'This plan uses USD. Choose a USD ad account; no currency conversion is applied.',
  ),
  'page_selected': (
    'Facebook Page selected',
    'Refresh Facebook Pages and select the Page for this setup.',
  ),
};
bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a == b;
Map<String, dynamic> validateMetaPreparation(
  Map<String, dynamic> r,
  String funnel,
  String campaign,
) {
  bool text(dynamic v, int max) => v is String && v.length <= max;
  bool integer(dynamic v, int min, int max) => v is int && v >= min && v <= max;
  bool time(dynamic v) =>
      v == null || (v is String && DateTime.tryParse(v) != null);
  bool snapshot(dynamic v) {
    if (v is! Map ||
        v['campaign'] is! Map ||
        v['landing_page'] is! Map ||
        v['meta'] is! Map) {
      return false;
    }
    final c = v['campaign'], p = v['landing_page'], m = v['meta'];
    if (c['id'] != campaign ||
        !text(c['name'], 100) ||
        !text(c['headline'], 180) ||
        !text(c['body'], 2000) ||
        !text(c['cta'], 60) ||
        !text(c['audience'], 1000) ||
        !integer(c['daily_cents'], 100, 1000000) ||
        !integer(c['days'], 1, 90) ||
        c['currency'] != 'USD' ||
        c['planned_total_cents'] != c['daily_cents'] * c['days']) {
      return false;
    }
    if (!text(p['brand'], 1000) ||
        !text(p['headline'], 1000) ||
        !text(p['subheadline'], 4000) ||
        !text(p['cta'], 1000) ||
        !integer(p['version'], 0, 2147483647) ||
        !text(p['slug'], 60) ||
        !text(p['destination'], 2000)) {
      return false;
    }
    final url = Uri.tryParse(p['destination']);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.endsWith('/f/${p['slug']}') ||
        !_same(url.queryParameters, {
          'utm_source': 'facebook',
          'utm_medium': 'paid',
          'utm_campaign': 'k143_${campaign.replaceAll('-', '')}',
        }) ||
        url.queryParametersAll.values.any((x) => x.length != 1)) {
      return false;
    }
    if ((m['connection_version'] != null &&
            !integer(m['connection_version'], 1, 2147483647)) ||
        !time(m['accounts_refreshed_at']) ||
        !time(m['pages_refreshed_at'])) {
      return false;
    }
    final a = m['account'], page = m['page'];
    if (a != null &&
        (a is! Map ||
            a['id'] is! String ||
            !RegExp(r'^act_\d{1,40}$').hasMatch(a['id']) ||
            !text(a['name'], 200) ||
            !text(a['currency'], 8) ||
            !text(a['timezone'], 100) ||
            a['status'] is! int)) {
      return false;
    }
    if (page != null &&
        (page is! Map ||
            page['id'] is! String ||
            !RegExp(r'^\d{1,40}$').hasMatch(page['id']) ||
            !text(page['name'], 200) ||
            !text(page['category'], 200))) {
      return false;
    }
    return true;
  }

  bool selectedIdentity(dynamic s) {
    final m = s['meta'];
    return m['connection_version'] != null &&
        m['account'] != null &&
        m['account']['currency'] == 'USD' &&
        m['account']['status'] == 1 &&
        m['page'] != null;
  }

  final checks = r['checks'];
  var valid =
      r['source'] == 'meta_setup' &&
      r['funnel_id'] == funnel &&
      r['campaign_id'] == campaign &&
      integer(r['version'], 0, 2147483647) &&
      r['fingerprint'] is String &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(r['fingerprint']) &&
      r['ad_publishing_ready'] == false &&
      r['ready_for_review'] is bool &&
      r['review_current'] is bool &&
      time(r['reviewed_at']) &&
      checks is Map &&
      checks.length == metaSetupChecks.length &&
      metaSetupChecks.keys.every((k) => checks[k] is bool) &&
      snapshot(r['current_snapshot']);
  if (valid) {
    valid =
        r['ready_for_review'] == checks.values.every((v) => v == true) &&
        (r['ready_for_review'] != true ||
            selectedIdentity(r['current_snapshot'])) &&
        (r['reviewed_snapshot'] == null
            ? r['reviewed_at'] == null
            : snapshot(r['reviewed_snapshot']) &&
                  selectedIdentity(r['reviewed_snapshot']) &&
                  r['reviewed_at'] != null &&
                  r['version'] > 0) &&
        (r['review_current'] != true ||
            (r['ready_for_review'] == true &&
                r['reviewed_snapshot'] != null &&
                _same(r['current_snapshot'], r['reviewed_snapshot'])));
  }
  if (!valid) {
    throw const FunnelException(
      'The Meta setup review could not be read. Refresh it before continuing.',
    );
  }
  return r;
}

class FunnelMetaPreparation extends StatefulWidget {
  const FunnelMetaPreparation({
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
  State<FunnelMetaPreparation> createState() => _FunnelMetaPreparationState();
}

class _FunnelMetaPreparationState extends State<FunnelMetaPreparation> {
  Map<String, dynamic>? _data;
  bool _busy = false, _checked = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-setup';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _invalidate(String message) {
    if (!mounted) return;
    // Invalidate synchronously, including while the parent changes owner during
    // a build. The dialog lives in the navigator overlay, outside that subtree.
    _generation++;
    _data = null;
    _busy = false;
    _checked = false;
    _error = null;
    _message = null;
    _unavailable = message;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _deny() =>
      _invalidate('Sign in with Enterprise access to review Meta setup.');
  void _scopeChanged() => _invalidate(
    'The campaign workspace changed. Close this review and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaPreparation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.funnelId != widget.funnelId ||
        oldWidget.campaignId != widget.campaignId ||
        oldWidget.scope != widget.scope) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      oldWidget.scope?.removeListener(_scopeChanged);
      widget.client.addAccessDeniedListener(_deny);
      widget.scope?.addListener(_scopeChanged);
      _generation++;
      _data = null;
      _busy = false;
      _checked = false;
      _error = null;
      _message = null;
      _unavailable = null;
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

  void _apply(Map<String, dynamic> r, int g) {
    if (!_current(g)) return;
    final data = validateMetaPreparation(r, widget.funnelId, widget.campaignId);
    setState(() {
      _data = data;
      _checked = false;
    });
  }

  Future<void> _fetch(int g) async =>
      _apply(await widget.client.request('GET', _path), g);
  Future<void> _load() => _run((g) => _fetch(g));
  Future<void> _run(
    Future<void> Function(int) action, {
    bool recover = false,
  }) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _checked = false;
      _error = null;
      _message = null;
    });
    try {
      await action(g);
    } catch (e) {
      if (_current(g)) {
        setState(() => _data = null);
        if (recover && e is FunnelException && [400, 409].contains(e.status)) {
          try {
            await _fetch(g);
          } catch (_) {
            /* Show the original actionable error with no stale data. */
          }
        }
        if (_current(g)) {
          setState(
            () => _error = e is FunnelException
                ? e.message
                : 'Meta setup could not complete this request. Try again.',
          );
        }
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _save(String action) async {
    final r = _data;
    if (r == null) return;
    await _run((g) async {
      final result = await widget.client.request(
        'POST',
        '$_path/$action',
        body: {
          'version': r['version'],
          'confirmed': true,
          if (action == 'review') 'fingerprint': r['fingerprint'],
        },
      );
      _apply(result, g);
      if (_current(g)) {
        setState(
          () => _message = action == 'review'
              ? 'Meta setup review saved.'
              : 'Saved Meta setup review cleared.',
        );
      }
    }, recover: true);
  }

  String _money(dynamic cents) =>
      '\$${((cents as num) / 100).toStringAsFixed(2)}';
  Future<void> _copy() async {
    final r = _data;
    if (r == null || r['reviewed_snapshot'] == null) return;
    final s = r['reviewed_snapshot'],
        c = s['campaign'],
        m = s['meta'],
        p = s['landing_page'];
    await Clipboard.setData(
      ClipboardData(
        text:
            'KORLIX Meta setup review${r['review_current'] == true ? '' : ' — OUT OF DATE'}\nReviewed: ${r['reviewed_at']}\nCampaign: ${c['name']}\nHeadline: ${c['headline']}\nMessage: ${c['body']}\nCTA: ${c['cta']}\nAudience brief: ${c['audience']}\nPlanned budget: ${_money(c['daily_cents'])} USD/day × ${c['days']} days = ${_money(c['planned_total_cents'])} USD\nAd account: ${m['account']['name']} (${m['account']['id']})\nFacebook Page: ${m['page']['name']} (${m['page']['id']})\nDestination: ${p['destination']}\nSetup review only. Ad eligibility, creative, executable targeting and publishing require separate completion. No ad was created and no spending was authorized.',
      ),
    );
    if (mounted && _unavailable == null) {
      setState(() => _message = 'Saved review copied.');
    }
  }

  Widget _gap([double h = 12]) => SizedBox(height: h);
  Widget _caption(String text) =>
      Text(text, style: const TextStyle(color: WfStyle.muted, height: 1.5));
  Widget _snapshot(Map s) {
    final c = s['campaign'],
        p = s['landing_page'],
        m = s['meta'],
        a = m['account'],
        page = m['page'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          c['name'],
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        _gap(),
        Text(
          c['headline'],
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        _gap(8),
        Text(c['body'], style: const TextStyle(height: 1.5)),
        _gap(8),
        Text('CTA: ${c['cta']}'),
        _gap(),
        _caption('Audience brief: ${c['audience']}'),
        _gap(),
        Text(
          '${_money(c['daily_cents'])} USD/day × ${c['days']} days = ${_money(c['planned_total_cents'])} USD planned',
          style: const TextStyle(
            color: WfStyle.cyan,
            fontWeight: FontWeight.w600,
          ),
        ),
        _gap(8),
        _caption(
          'A planning amount. No platform budget is created or enforced by this review.',
        ),
        _gap(18),
        const Text(
          'Published landing page',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        _gap(8),
        Text('${p['brand']} · ${p['headline']}'),
        _gap(8),
        _caption('Published version ${p['version']}'),
        _gap(8),
        SelectableText(
          p['destination'],
          style: const TextStyle(color: WfStyle.cyan),
        ),
        _gap(18),
        const Text(
          'Meta account and Page',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        _gap(8),
        Text(
          a == null ? 'No ad account selected' : '${a['name']} · ${a['id']}',
        ),
        if (a != null) _caption('${a['currency']} · ${a['timezone']}'),
        _gap(8),
        Text(
          page == null
              ? 'No Facebook Page selected'
              : '${page['name']} · Page ${page['id']}',
        ),
        _gap(8),
        _caption(
          'Account and Page details come from your last Meta refresh. This review does not recheck permission with Meta.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _data;
    return AlertDialog(
      title: const Text('Meta setup review'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_unavailable != null) _caption(_unavailable!),
              if (_unavailable == null) ...[
                _caption(
                  'Review the campaign plan, landing page, ad account and Facebook Page together. Ad creation and spending remain unavailable.',
                ),
                _gap(),
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) ...[
                  _gap(),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      height: 1.5,
                    ),
                  ),
                ],
                if (_message != null) ...[
                  _gap(),
                  Text(
                    _message!,
                    style: const TextStyle(color: WfStyle.cyan, height: 1.5),
                  ),
                ],
                if (r != null) ...[
                  _gap(),
                  WfBadge(
                    r['review_current'] == true
                        ? 'SETUP REVIEWED'
                        : r['reviewed_snapshot'] != null
                        ? 'SETUP CHANGED · REVIEW AGAIN'
                        : 'SETUP REVIEW NEEDED',
                    color: r['review_current'] == true
                        ? WfStyle.cyan
                        : WfStyle.gold,
                  ),
                  _gap(),
                  for (final entry in metaSetupChecks.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            r['checks'][entry.key] == true
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                            color: r['checks'][entry.key] == true
                                ? WfStyle.cyan
                                : WfStyle.gold,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.value.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (r['checks'][entry.key] != true)
                                  _caption(entry.value.$2),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 28),
                  _snapshot(r['current_snapshot']),
                  _gap(18),
                  if (r['reviewed_at'] != null)
                    _caption(
                      'Saved review: ${DateTime.tryParse(r['reviewed_at'])?.toLocal().toString().split('.').first}',
                    ),
                  if (r['reviewed_snapshot'] != null &&
                      r['review_current'] != true)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Previously saved review'),
                      children: [_snapshot(r['reviewed_snapshot'])],
                    ),
                  if (r['review_current'] != true)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _checked,
                      onChanged: !_busy && r['ready_for_review'] == true
                          ? (v) => setState(() => _checked = v == true)
                          : null,
                      title: const Text(
                        'I reviewed this plan, destination, planned USD budget, ad account and Facebook Page.',
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close setup review'),
        ),
        if (_unavailable == null) ...[
          OutlinedButton(
            onPressed: _busy ? null : _load,
            child: const Text('Refresh setup'),
          ),
          if (r?['reviewed_snapshot'] != null) ...[
            TextButton(
              onPressed: _busy ? null : _copy,
              child: const Text('Copy saved review'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _save('clear'),
              child: const Text('Clear saved review'),
            ),
          ],
          FilledButton(
            onPressed:
                !_busy &&
                    _checked &&
                    r?['ready_for_review'] == true &&
                    r?['review_current'] != true
                ? () => _save('review')
                : null,
            child: const Text('Save Meta setup review'),
          ),
        ],
      ],
    );
  }
}
