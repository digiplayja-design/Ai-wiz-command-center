import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const googleTargetingReviewConfirmation =
    'I reviewed the target countries, exclusions, location reach, content languages and bidding preference against the published landing page. This is my KORLIX review only; provider eligibility, final setup and launch still require checking.';
const googleTargetingReviewChecks = <String, String>{
  'saved_draft': 'Save the draft first.',
  'complete_choices':
      'Choose target countries, content languages, location reach and bidding.',
  'current_context':
      'Check the current campaign context and save the draft again.',
  'page_published': 'Publish the landing page.',
  'plan_reviewed': 'Review the campaign plan against the published page.',
};
bool _equalTargeting(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equalTargeting(a[k], b[k]))
    : a is List && b is List
    ? a.length == b.length &&
          List.generate(
            a.length,
            (i) => i,
          ).every((i) => _equalTargeting(a[i], b[i]))
    : a == b;

const googleLocationModes = <String, String>{
  'undecided': 'Choose later',
  'presence': 'People in or regularly in these countries',
  'presence_or_interest': 'People in or interested in these countries',
};
const googleBiddingPlans = <String, String>{
  'undecided': 'Choose later',
  'maximize_clicks': 'Maximize clicks',
  'maximize_conversions': 'Maximize conversions',
};
Map<String, dynamic> emptyGoogleTargeting() => {
  'countries': <String>[],
  'excluded_countries': <String>[],
  'content_languages': <String>[],
  'location_mode': 'undecided',
  'bidding': 'undecided',
};
bool googleTargetingCatalogValid(dynamic c) {
  if (c is! Map ||
      c['version'] != 'google-reference-2026-09-23' ||
      c['geo_date'] != '2026-08-12' ||
      c['language_mode'] != 'content_planning' ||
      c['location_scope'] != 'countries') {
    return false;
  }
  for (final k in ['countries', 'languages']) {
    final rows = c[k];
    if (rows is! List || rows.isEmpty || rows.length > 300) return false;
    final codes = <String>{}, ids = <String>{};
    for (final x in rows) {
      if (x is! Map ||
          x.length != 3 ||
          x['name'] is! String ||
          (x['name'] as String).trim().isEmpty ||
          (x['name'] as String).length > 100 ||
          x['code'] is! String ||
          !RegExp(
            k == 'countries' ? r'^[A-Z]{2}$' : r'^[a-z]{2,3}(?:_[A-Z]{2})?$',
          ).hasMatch(x['code']) ||
          x['id'] is! String ||
          !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(x['id']) ||
          !codes.add(x['code']) ||
          !ids.add(x['id'])) {
        return false;
      }
    }
  }
  return true;
}

bool googleTargetingValid(dynamic a, Map catalog) {
  if (a is! Map ||
      a.length != 5 ||
      !googleLocationModes.containsKey(a['location_mode']) ||
      !googleBiddingPlans.containsKey(a['bidding'])) {
    return false;
  }
  for (final k in ['countries', 'excluded_countries', 'content_languages']) {
    final values = a[k],
        options =
            (catalog[k == 'content_languages' ? 'languages' : 'countries']
                    as List)
                .map((x) => x['code'])
                .toSet();
    if (values is! List ||
        values.length > (k == 'content_languages' ? 10 : 20) ||
        values.any((v) => v is! String || !options.contains(v)) ||
        values.toSet().length != values.length) {
      return false;
    }
  }
  return !(a['countries'] as List).any(
    (v) => (a['excluded_countries'] as List).contains(v),
  );
}

bool googleTargetingComplete(Map a) =>
    (a['countries'] as List).isNotEmpty &&
    (a['content_languages'] as List).isNotEmpty &&
    a['location_mode'] != 'undecided' &&
    a['bidding'] != 'undecided';
bool _labelsValid(dynamic labels, Map a) {
  if (labels is! Map || labels.length != 2) return false;
  for (final k in ['countries', 'content_languages']) {
    final selected = k == 'countries'
        ? [...a['countries'], ...a['excluded_countries']]
        : a[k] as List;
    final names = labels[k];
    if (names is! Map ||
        names.length != selected.length ||
        selected.any(
          (code) =>
              names[code] is! String ||
              (names[code] as String).trim().isEmpty ||
              (names[code] as String).length > 100,
        )) {
      return false;
    }
  }
  return true;
}

Map<String, dynamic> validateGoogleTargeting(
  Map<String, dynamic> r,
  String funnel,
  String campaign,
) {
  bool integer(dynamic v, int min, int max) => v is int && v >= min && v <= max;
  bool text(dynamic v, int max) => v is String && v.length <= max;
  bool contextValid(dynamic c) {
    if (c is! Map ||
        !text(c['campaign_name'], 100) ||
        !text(c['headline'], 180) ||
        !text(c['body'], 2000) ||
        !text(c['cta'], 60) ||
        !text(c['audience'], 1000) ||
        !text(c['brand'], 1000) ||
        !integer(c['daily_cents'], 100, 1000000) ||
        !integer(c['days'], 1, 90) ||
        !integer(c['page_version'], 0, 2147483647) ||
        !['draft', 'reviewed', 'archived'].contains(c['campaign_state']) ||
        !['draft', 'published', 'paused'].contains(c['page_state']) ||
        !text(c['destination'], 2000)) {
      return false;
    }
    final u = Uri.tryParse(c['destination']);
    return u != null &&
        u.scheme == 'https' &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty &&
        !u.hasFragment &&
        RegExp(r'/f/[a-z0-9-]+$').hasMatch(u.path) &&
        u.queryParameters.length == 3 &&
        u.queryParameters['utm_source'] == 'google' &&
        u.queryParameters['utm_medium'] == 'paid' &&
        u.queryParameters['utm_campaign'] ==
            'k143_${campaign.replaceAll('-', '')}' &&
        u.queryParametersAll.values.every((v) => v.length == 1);
  }

  final version = r['version'];
  if (r['source'] != 'google_targeting_draft' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      !integer(version, 0, 2147483647) ||
      r['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['fingerprint']) ||
      !googleTargetingCatalogValid(r['catalog']) ||
      !googleTargetingValid(r['assets'], r['catalog']) ||
      !contextValid(r['context']) ||
      r['ad_publishing_ready'] != false ||
      r['draft_current'] is! bool ||
      r['editable'] != (r['context']?['campaign_state'] != 'archived') ||
      r['draft_complete'] != googleTargetingComplete(r['assets']) ||
      (version == 0
          ? r['saved_context'] != null ||
                r['updated_at'] != null ||
                r['draft_current'] != false ||
                r['saved_labels'] != null ||
                (r['assets']['countries'] as List).isNotEmpty ||
                (r['assets']['excluded_countries'] as List).isNotEmpty ||
                (r['assets']['content_languages'] as List).isNotEmpty ||
                r['assets']['location_mode'] != 'undecided' ||
                r['assets']['bidding'] != 'undecided'
          : !_labelsValid(r['saved_labels'], r['assets']) ||
                !contextValid(r['saved_context']) ||
                r['updated_at'] is! String ||
                DateTime.tryParse(r['updated_at']) == null)) {
    throw const FunnelException(
      'The targeting draft could not be verified. Reload it.',
      503,
    );
  }
  if (r['draft_current'] == true &&
      jsonEncode(r['context']) != jsonEncode(r['saved_context'])) {
    // Compare maps independent of JSON key ordering.
    final a = r['context'] as Map, b = r['saved_context'] as Map;
    if (a.length != b.length || a.keys.any((k) => a[k] != b[k])) {
      throw const FunnelException(
        'The saved draft context could not be verified.',
        503,
      );
    }
  }
  final checks = r['review_checks'], review = r['reviewed_snapshot'];
  bool validReview(dynamic v) =>
      v is Map &&
      v.length == 6 &&
      googleTargetingValid(v['assets'], r['catalog']) &&
      contextValid(v['context']) &&
      integer(v['draft_revision'], 1, r['draft_revision']) &&
      googleTargetingComplete(v['assets']) &&
      _labelsValid(v['labels'], v['assets']) &&
      v['catalog_version'] is String &&
      RegExp(
        r'^google-reference-[0-9]{4}-[0-9]{2}-[0-9]{2}$',
      ).hasMatch(v['catalog_version']) &&
      v['saved_at'] is String &&
      DateTime.tryParse(v['saved_at']) != null;
  if (!integer(r['draft_revision'], version == 0 ? 0 : 1, version) ||
      r['review_fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['review_fingerprint']) ||
      checks is! Map ||
      checks.length != googleTargetingReviewChecks.length ||
      googleTargetingReviewChecks.keys.any((k) => checks[k] is! bool) ||
      r['review_ready'] is! bool ||
      r['review_ready'] != checks.values.every((v) => v == true) ||
      checks['saved_draft'] != (version > 0) ||
      checks['complete_choices'] != r['draft_complete'] ||
      checks['current_context'] != r['draft_current'] ||
      checks['page_published'] != (r['context']['page_state'] == 'published') ||
      (checks['plan_reviewed'] == true &&
          r['context']['campaign_state'] != 'reviewed') ||
      r['review_current'] is! bool ||
      (review == null
          ? r['reviewed_at'] != null || r['review_current'] != false
          : !validReview(review) ||
                r['reviewed_at'] is! String ||
                DateTime.tryParse(r['reviewed_at']) == null) ||
      (r['review_current'] == true &&
          (r['review_ready'] != true ||
              review == null ||
              review['draft_revision'] != r['draft_revision'] ||
              review['saved_at'] != r['updated_at'] ||
              !_equalTargeting(review['assets'], r['assets']) ||
              !_equalTargeting(review['context'], r['saved_context']) ||
              !_equalTargeting(review['labels'], r['saved_labels']) ||
              review['catalog_version'] != r['catalog']['version']))) {
    throw const FunnelException(
      'The targeting review could not be verified. Reload the draft.',
      503,
    );
  }
  return r;
}

class FunnelGoogleTargeting extends StatefulWidget {
  const FunnelGoogleTargeting({
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
  State<FunnelGoogleTargeting> createState() => _FunnelGoogleTargetingState();
}

class _FunnelGoogleTargetingState extends State<FunnelGoogleTargeting> {
  Map<String, dynamic> _choices = emptyGoogleTargeting();
  Map<String, dynamic>? _data;
  bool _busy = false, _dirty = false, _conflict = false, _reviewChecked = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-targeting';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _empty() {
    _choices = emptyGoogleTargeting();
    _data = null;
    _dirty = false;
    _conflict = false;
    _reviewChecked = false;
    _message = null;
    _error = null;
  }

  void _invalidate(String message) {
    if (!mounted) return;
    final g = ++_generation;
    _empty();
    _busy = false;
    _unavailable = message;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && g == _generation) {
          setState(() {});
        }
      });
    } else {
      setState(() {});
    }
  }

  void _deny() =>
      _invalidate('Sign in with Enterprise access to edit targeting drafts.');
  void _scopeChanged() => _invalidate(
    'The campaign workspace changed. Close this draft and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleTargeting old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client ||
        old.funnelId != widget.funnelId ||
        old.campaignId != widget.campaignId ||
        old.scope != widget.scope) {
      old.client.removeAccessDeniedListener(_deny);
      old.scope?.removeListener(_scopeChanged);
      widget.client.addAccessDeniedListener(_deny);
      widget.scope?.addListener(_scopeChanged);
      _generation++;
      _empty();
      _busy = false;
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
    late Map<String, dynamic> data;
    try {
      data = validateGoogleTargeting(r, widget.funnelId, widget.campaignId);
    } catch (_) {
      setState(() => _data = null);
      rethrow;
    }
    final a = data['assets'];
    setState(() {
      _empty();
      _data = data;
      _choices = Map<String, dynamic>.from(jsonDecode(jsonEncode(a)));
    });
  }

  Future<void> _run(Future<void> Function(int) fn) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
      _reviewChecked = false;
      _error = null;
      _message = null;
    });
    try {
      await fn(g);
    } catch (e) {
      if (_current(g)) {
        setState(() {
          if (e is FunnelException && [401, 403, 404].contains(e.status)) {
            _empty();
            _busy = false;
            _unavailable =
                'This campaign is no longer available. Close this draft.';
          } else {
            _error = e is FunnelException
                ? e.message
                : 'The targeting draft could not be saved. Try again.';
            if (e is FunnelException && e.status == 409) {
              _conflict = true;
            }
          }
        });
      }
    } finally {
      if (_current(g)) setState(() => _busy = false);
    }
  }

  Future<void> _load() =>
      _run((g) async => _apply(await widget.client.request('GET', _path), g));
  Map<String, dynamic> get _assets => _choices;
  bool get _valid =>
      _data != null && googleTargetingValid(_assets, _data!['catalog']);
  bool get _editable =>
      _data?['editable'] == true &&
      !_busy &&
      !_conflict &&
      _unavailable == null;
  Future<void> _save() async {
    if (!_editable || !_valid) return;
    final body = {
      'version': _data!['version'],
      'fingerprint': _data!['fingerprint'],
      'assets': _assets,
    };
    await _run((g) async {
      _apply(await widget.client.request('POST', '$_path/save', body: body), g);
      if (_current(g)) setState(() => _message = 'Targeting draft saved.');
    });
  }

  Map<String, dynamic> _reviewDraft(Map<String, dynamic> d, Map snapshot) => {
    ...d,
    'assets': snapshot['assets'],
    'saved_context': snapshot['context'],
    'saved_labels': snapshot['labels'],
    'updated_at': snapshot['saved_at'],
    'draft_revision': snapshot['draft_revision'],
    'draft_current': d['review_current'],
    'draft_complete': googleTargetingComplete(snapshot['assets']),
  };

  bool get _canReview => _editable && !_dirty && _data?['review_ready'] == true;
  Future<void> _review() async {
    if (!_canReview || !_reviewChecked) return;
    final body = {
      'version': _data!['version'],
      'review_fingerprint': _data!['review_fingerprint'],
      'confirmed': true,
    };
    await _run((g) async {
      _apply(
        await widget.client.request('POST', '$_path/review', body: body),
        g,
      );
      if (_current(g)) setState(() => _message = 'Targeting review saved.');
    });
  }

  Future<void> _clearReview() async {
    if (_busy ||
        _dirty ||
        _conflict ||
        _unavailable != null ||
        _data?['reviewed_snapshot'] == null) {
      return;
    }
    final g = _generation, version = _data!['version'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the targeting review?'),
        content: const Text(
          'Your saved draft stays available. Only its saved review will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep review'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear review'),
          ),
        ],
      ),
    );
    if (ok != true || !_current(g) || _dirty || _busy || _conflict) return;
    await _run((generation) async {
      _apply(
        await widget.client.request(
          'POST',
          '$_path/clear-review',
          body: {'version': version, 'confirmed': true},
        ),
        generation,
      );
      if (_current(generation)) {
        setState(
          () => _message = 'Targeting review cleared. Your draft is unchanged.',
        );
      }
    });
  }

  Future<void> _copyReview() async {
    if (_busy ||
        _dirty ||
        _conflict ||
        _unavailable != null ||
        _data?['reviewed_snapshot'] == null) {
      return;
    }
    final g = _generation, d = _data!, snapshot = d['reviewed_snapshot'];
    final text =
        'KORLIX OWNER TARGETING REVIEW — ${d['review_current'] == true ? 'CURRENT' : 'OUT OF DATE'}\nReviewed draft revision: ${snapshot['draft_revision']}\nReviewed at: ${d['reviewed_at']}\nReference catalog: ${snapshot['catalog_version']}\n${_export(_reviewDraft(d, snapshot))}';
    await Clipboard.setData(ClipboardData(text: text));
    if (_current(g)) {
      setState(() => _message = 'Targeting review record copied.');
    }
  }

  Widget _reviewPanel() {
    final d = _data!, snapshot = d['reviewed_snapshot'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Review saved targeting'),
        WfBadge(
          _dirty
              ? 'SAVE CHANGES BEFORE REVIEW'
              : snapshot == null
              ? 'TARGETING NOT REVIEWED'
              : d['review_current'] == true
              ? 'TARGETING REVIEW CURRENT'
              : 'TARGETING REVIEW OUT OF DATE',
        ),
        const SizedBox(height: 12),
        const Text(
          'Review the saved countries, exclusions, location reach, content languages and bidding preference against the published page. This records your review in KORLIX. Google eligibility, final account setup, local areas and launch remain separate.',
        ),
        if (_dirty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Save or discard your targeting changes before reviewing.',
            ),
          ),
        for (final e in googleTargetingReviewChecks.entries)
          if (d['review_checks'][e.key] != true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(e.value, style: const TextStyle(color: WfStyle.gold)),
            ),
        if (snapshot != null) ...[
          const SizedBox(height: 12),
          Text(
            'Reviewed draft ${snapshot['draft_revision']} · ${d['reviewed_at']}',
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Saved review record'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(_export(_reviewDraft(d, snapshot))),
                    Text('Saved: ${snapshot['saved_at']}'),
                    SelectableText(snapshot['context']['destination']),
                  ],
                ),
              ),
            ],
          ),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _reviewChecked,
          onChanged: _canReview
              ? (v) => setState(() => _reviewChecked = v == true)
              : null,
          title: const Text(googleTargetingReviewConfirmation),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: _canReview && _reviewChecked ? _review : null,
              child: const Text('Save targeting review'),
            ),
            OutlinedButton(
              onPressed: _busy || _dirty || _conflict || snapshot == null
                  ? null
                  : _copyReview,
              child: const Text('Copy review record'),
            ),
            TextButton(
              onPressed: _busy || _dirty || _conflict || snapshot == null
                  ? null
                  : _clearReview,
              child: const Text('Clear targeting review'),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _discard(String title) async {
    if (!_dirty) return true;
    final g = _generation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text('Your unsaved choices will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    return ok == true && _current(g);
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_unavailable != null || await _discard('Close this draft?')) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _reload() async {
    if (await _discard('Reload the saved draft?')) {
      await _load();
    }
  }

  String _export(Map<String, dynamic> d) {
    final a = d['assets'] as Map,
        c = d['saved_context'],
        labels = d['saved_labels'];
    String names(String k) => (a[k] as List).isEmpty
        ? '(none selected)'
        : (a[k] as List)
              .map(
                (code) =>
                    labels[k == 'content_languages'
                        ? 'content_languages'
                        : 'countries'][code],
              )
              .join(', ');
    return 'KORLIX Google targeting draft — ${c['campaign_name']}\n${d['draft_current'] == true ? 'SAVED DRAFT' : 'OUT OF DATE — compare with the current campaign and published page.'}\n${d['draft_complete'] == true ? 'Draft choices filled; final review required.' : 'INCOMPLETE — finish your draft choices.'}\nDraft revision: ${d['draft_revision']}\nSaved: ${d['updated_at']}\nDestination at save: ${c['destination']}\nAudience at save: ${c['audience']}\nTarget countries: ${names('countries')}\nExcluded countries: ${names('excluded_countries')}\nLocation reach: ${googleLocationModes[a['location_mode']]}\nExclusions: people in excluded countries.\nAd and landing-page languages (planning only): ${names('content_languages')}\nPlanned bidding: ${googleBiddingPlans[a['bidding']]}\nEmpty targets do not mean worldwide targeting. Country availability, local areas, account settings, conversion tracking and bid limits require final setup. Search language matching is based on ad content as Google rolls out its September 2026 change. No ad or spending has been created.';
  }

  Future<void> _copy() async {
    if (_busy ||
        _unavailable != null ||
        _data == null ||
        _data!['version'] == 0 ||
        _dirty ||
        _conflict) {
      return;
    }
    final g = _generation;
    await Clipboard.setData(ClipboardData(text: _export(_data!)));
    if (_current(g)) setState(() => _message = 'Saved draft copied.');
  }

  String _name(String group, String code) =>
      (_data!['catalog'][group == 'content_languages'
                  ? 'languages'
                  : 'countries']
              as List)
          .firstWhere((x) => x['code'] == code)['name'];
  void _change(void Function() fn) => setState(() {
    fn();
    _dirty = true;
    _reviewChecked = false;
    _message = null;
  });
  Future<void> _choose(String group, String title) async {
    if (!_editable) return;
    final g = _generation;
    final rows =
        (_data!['catalog'][group == 'content_languages'
                    ? 'languages'
                    : 'countries']
                as List)
            .cast<Map>();
    final blocked = <String>{
      ..._assets[group],
      if (group == 'countries') ..._assets['excluded_countries'],
      if (group == 'excluded_countries') ..._assets['countries'],
    };
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _TargetingPicker(title: title, rows: rows, blocked: blocked),
    );
    if (choice == null || !_current(g) || !_editable) return;
    final list = _assets[group] as List;
    if (list.length >= (group == 'content_languages' ? 10 : 20) ||
        blocked.contains(choice)) {
      return;
    }
    _change(() => _choices[group] = [...list, choice]);
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
    ),
  );
  Widget _selection(String group, String addLabel) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final code in _assets[group])
        Row(
          children: [
            Expanded(child: Text(_name(group, code))),
            IconButton(
              tooltip: 'Remove ${_name(group, code)}',
              onPressed: _editable
                  ? () => _change(
                      () => _choices[group] = [
                        ...(_assets[group] as List).where((v) => v != code),
                      ],
                    )
                  : null,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      OutlinedButton.icon(
        onPressed:
            _editable &&
                (_assets[group] as List).length <
                    (group == 'content_languages' ? 10 : 20)
            ? () => _choose(group, addLabel)
            : null,
        icon: const Icon(Icons.add),
        label: Text(addLabel),
      ),
    ],
  );
  Widget _choice(String key, String label, Map<String, String> options) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$key-${_assets[key]}'),
        initialValue: _assets[key],
        isExpanded: true,
        itemHeight: null,
        decoration: InputDecoration(labelText: label),
        selectedItemBuilder: (context) => options.values
            .map((v) => Text(v, maxLines: 1, overflow: TextOverflow.ellipsis))
            .toList(),
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, softWrap: true),
              ),
            )
            .toList(),
        onChanged: _editable
            ? (v) {
                if (v != null) _change(() => _choices[key] = v);
              }
            : null,
      );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 950),
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
                    'Google targeting draft',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _close,
                    child: const Text('Close'),
                  ),
                ],
              ),
              const Text(
                'Plan country reach, content languages and bidding for this Search campaign.',
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_unavailable != null)
                Text(_unavailable!)
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: WfStyle.gold),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _message!,
                      style: const TextStyle(color: WfStyle.cyan),
                    ),
                  ),
                if (_data != null) ...[
                  const SizedBox(height: 16),
                  WfBadge(
                    _dirty
                        ? 'UNSAVED CHANGES'
                        : _data!['version'] == 0
                        ? 'NEW DRAFT'
                        : _data!['draft_current'] == true
                        ? 'SAVED DRAFT'
                        : 'OUT OF DATE',
                  ),
                  if (_data!['version'] > 0 && _data!['draft_current'] != true)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'The campaign or published page changed. Compare these choices with the current context before saving again.',
                      ),
                    ),
                  if (_data!['editable'] != true)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'This campaign is archived. Reopen it to edit this draft.',
                      ),
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Current campaign context'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_data!['context']['campaign_name']}\n${_data!['context']['headline']}\nAudience: ${_data!['context']['audience']}\nPage: ${_data!['context']['page_state']}',
                        ),
                      ),
                      SelectableText(_data!['context']['destination']),
                    ],
                  ),
                  _section('Target countries'),
                  const Text(
                    'Choose up to 20 countries from Google’s reference list. Empty targets do not mean worldwide targeting. Cities, regions and radius targeting need separate setup.',
                  ),
                  _selection('countries', 'Add target country'),
                  _section('Excluded countries · optional'),
                  const Text(
                    'Choose up to 20 different exclusions. A country cannot be both targeted and excluded. Exclusions apply to people in those countries.',
                  ),
                  _selection('excluded_countries', 'Add excluded country'),
                  _section('Location reach'),
                  _choice(
                    'location_mode',
                    'Who should see the ads?',
                    googleLocationModes,
                  ),
                  const SizedBox(height: 10),
                  Text(googleLocationModes[_assets['location_mode']]!),
                  const Text(
                    'Presence uses people in or regularly in your chosen countries. Presence or interest can also reach people elsewhere who show interest. Google uses location signals; exact location is not guaranteed.',
                    style: TextStyle(color: WfStyle.muted),
                  ),
                  _section('Ad and landing-page languages'),
                  const Text(
                    'Choose up to 10 languages for your content plan. Starting September 2026, Google is removing Search campaign language targeting and matching from ad content. These choices document the languages you intend to write; they do not restrict who sees an ad.',
                  ),
                  _selection('content_languages', 'Add content language'),
                  _section('Planned bidding strategy'),
                  _choice('bidding', 'Bidding preference', googleBiddingPlans),
                  const SizedBox(height: 10),
                  if (_assets['bidding'] == 'maximize_clicks')
                    const Text(
                      'Maximize clicks aims for more clicks within the budget. Decide any CPC bid limit during final setup.',
                    ),
                  if (_assets['bidding'] == 'maximize_conversions')
                    const Text(
                      'Maximize conversions aims to spend the budget for more conversions. Conversion tracking and goals must be set up and checked before use.',
                    ),
                  if (!googleTargetingComplete(_assets))
                    const Padding(
                      padding: EdgeInsets.only(top: 14),
                      child: Text(
                        'You can save an incomplete draft. Choose a target country, content language, location reach and bidding preference to finish these draft choices.',
                        style: TextStyle(color: WfStyle.gold),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _editable && _valid ? _save : null,
                        child: const Text('Save targeting draft'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _busy ||
                                _dirty ||
                                _conflict ||
                                _data!['version'] == 0
                            ? null
                            : _copy,
                        child: const Text('Copy saved targeting'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _reload,
                        child: const Text('Reload saved draft'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Draft preparation only. Country options use Google reference data from August 2026. Account eligibility, country availability, local areas, bid limits and final review still need checking. Saving creates no ad and authorizes no spending.',
                    style: TextStyle(color: WfStyle.muted),
                  ),
                  _reviewPanel(),
                ] else if (!_busy)
                  TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _TargetingPicker extends StatefulWidget {
  const _TargetingPicker({
    required this.title,
    required this.rows,
    required this.blocked,
  });
  final String title;
  final List<Map> rows;
  final Set<dynamic> blocked;
  @override
  State<_TargetingPicker> createState() => _TargetingPickerState();
}

class _TargetingPickerState extends State<_TargetingPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows
        .where(
          (r) =>
              !widget.blocked.contains(r['code']) &&
              ('${r['name']} ${r['code']}').toLowerCase().contains(
                _query.toLowerCase().trim(),
              ),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(labelText: 'Search choices'),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: rows.isEmpty
                  ? const Text('No matching choices.')
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(rows[i]['name']),
                        onTap: () => Navigator.pop(context, rows[i]['code']),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
