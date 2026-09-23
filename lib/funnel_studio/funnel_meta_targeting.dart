import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

import 'funnel_meta_creative.dart';
import 'funnel_meta_preparation.dart';
import 'funnel_images.dart';
import 'funnel_meta_radius.dart';

const metaTargetingReviewConfirmation =
    'I reviewed the saved creative, image, destination, countries or radius areas, ages, ad categories and placement preference. This records my KORLIX preparation review; Meta eligibility and launch remain separate.';
const metaTargetingReviewChecks = {
  'saved_draft': 'Save the targeting draft.',
  'complete_choices':
      'Choose countries or supported radius areas, ad categories and a placement preference.',
  'current_context':
      'Compare the current campaign context and save targeting again.',
  'page_published': 'Publish the landing page.',
  'plan_reviewed': 'Review the campaign plan against the published page.',
  'creative_saved': 'Save a Meta creative draft.',
  'creative_complete':
      'Complete the creative text, image and image description.',
  'creative_current':
      'Compare the current campaign context and save the creative again.',
};
const metaPlacements = {
  'undecided': 'Choose later',
  'automatic': 'Automatic placements preference',
  'facebook_feed': 'Facebook Feed preference',
};
const metaAdCategories = {
  'UNDECIDED': 'Choose later',
  'NONE': 'No special category',
  'HOUSING': 'Housing',
  'EMPLOYMENT': 'Employment',
  'FINANCIAL_PRODUCTS_SERVICES': 'Financial products and services',
  'ISSUES_ELECTIONS_POLITICS': 'Social issues, elections or politics',
  'ONLINE_GAMBLING_AND_GAMING': 'Online gambling and gaming',
};
Map<String, dynamic> emptyMetaTargeting() => {
  'countries': <String>[],
  'age_min': 18,
  'age_max': 65,
  'placements': 'undecided',
  'categories': <String>['UNDECIDED'],
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
bool metaTargetingCatalogValid(dynamic c) {
  if (c is! Map ||
      c['version'] != 'korlix-meta-preparation-2026-09-23' ||
      c['scope'] != 'country_planning' ||
      c['countries'] is! List ||
      (c['countries'] as List).isEmpty ||
      (c['countries'] as List).length > 300) {
    return false;
  }
  final codes = <String>{};
  return (c['countries'] as List).every(
    (x) =>
        x is Map &&
        x.length == 2 &&
        x['code'] is String &&
        RegExp(r'^[A-Z]{2}$').hasMatch(x['code']) &&
        codes.add(x['code']) &&
        x['name'] is String &&
        (x['name'] as String).trim().isNotEmpty &&
        (x['name'] as String).length <= 100,
  );
}

bool metaTargetingValid(dynamic a, Map catalog) {
  if (a is! Map ||
      !a.keys.toSet().containsAll([
        'countries',
        'age_min',
        'age_max',
        'placements',
        'categories',
      ]) ||
      a.keys.any(
        (k) => ![
          'countries',
          'age_min',
          'age_max',
          'placements',
          'categories',
          'custom_locations',
        ].contains(k),
      ) ||
      a['countries'] is! List ||
      a['categories'] is! List ||
      a['age_min'] is! int ||
      a['age_max'] is! int ||
      a['age_min'] < 18 ||
      a['age_max'] > 65 ||
      a['age_min'] > a['age_max'] ||
      !metaPlacements.containsKey(a['placements'])) {
    return false;
  }
  if (a.containsKey('custom_locations') &&
      (!metaRadiiValid(a['custom_locations']) ||
          (a['countries'] as List).isNotEmpty)) {
    return false;
  }
  final c = a['countries'] as List,
      k = a['categories'] as List,
      codes = (catalog['countries'] as List).map((v) => v['code']).toSet();
  return c.length <= 20 &&
      c.toSet().length == c.length &&
      c.every((v) => v is String && codes.contains(v)) &&
      k.isNotEmpty &&
      k.length <= 5 &&
      k.toSet().length == k.length &&
      k.every(metaAdCategories.containsKey) &&
      (!k.any((v) => ['NONE', 'UNDECIDED'].contains(v)) || k.length == 1) &&
      (k.contains('NONE') || a['age_min'] == 18 && a['age_max'] == 65);
}

bool metaTargetingComplete(Map a) =>
    ((a['countries'] as List).isNotEmpty ||
        (metaRadiiValid(a['custom_locations']) &&
            (a['custom_locations'] as List).isNotEmpty &&
            (a['categories'] as List).contains('NONE'))) &&
    a['placements'] != 'undecided' &&
    !(a['categories'] as List).contains('UNDECIDED');
bool _labelsValid(dynamic labels, Map a) =>
    labels is Map &&
    labels.length == (a['countries'] as List).length &&
    (a['countries'] as List).every(
      (code) =>
          labels[code] is String &&
          (labels[code] as String).trim().isNotEmpty &&
          (labels[code] as String).length <= 100,
    );
Map<String, dynamic> _reviewCreative(Map d, Map snapshot) => {
  ...Map<String, dynamic>.from(d['creative']),
  'version': snapshot['version'],
  'assets': snapshot['assets'],
  'image': snapshot['image'],
  'saved_context': snapshot['context'],
  'updated_at': snapshot['saved_at'],
  'draft_current': false,
  'creative_complete': true,
};
Map<String, dynamic> validateMetaTargeting(
  Map<String, dynamic> r,
  String funnel,
  String campaign,
) {
  void bad() => throw const FunnelException(
    'The Meta preparation draft or review could not be verified. Reload it.',
    503,
  );
  bool integer(dynamic v, int min, int max) => v is int && v >= min && v <= max;
  bool hash(dynamic v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
  bool time(dynamic v) => v is String && DateTime.tryParse(v) != null;
  if (r['source'] != 'meta_targeting_draft' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      !integer(r['version'], 0, 2147483647) ||
      !hash(r['fingerprint']) ||
      !metaTargetingCatalogValid(r['catalog']) ||
      !metaTargetingValid(r['assets'], r['catalog']) ||
      (r.containsKey('radius_supported') && r['radius_supported'] is! bool) ||
      (r['assets'].containsKey('custom_locations') &&
          r['radius_supported'] != true) ||
      r['creative'] is! Map ||
      r['ad_publishing_ready'] != false ||
      r['draft_current'] is! bool ||
      r['editable'] is! bool ||
      r['draft_complete'] != metaTargetingComplete(r['assets'])) {
    bad();
  }
  final creative = validateMetaCreative(
        Map<String, dynamic>.from(r['creative']),
        funnel,
        campaign,
      ),
      setup = creative['setup'],
      version = r['version'];
  void contextValid(dynamic c) {
    if (c is! Map) bad();
    validateMetaPreparation(
      {
        ...Map<String, dynamic>.from(setup),
        'current_snapshot': c,
        'checks': {for (final k in metaSetupChecks.keys) k: false},
        'ready_for_review': false,
        'review_current': false,
        'reviewed_snapshot': null,
        'reviewed_at': null,
      },
      funnel,
      campaign,
    );
  }

  if (r['editable'] != creative['editable']) bad();
  if (version == 0) {
    if (r['saved_context'] != null ||
        r['saved_labels'] != null ||
        r['updated_at'] != null ||
        r['draft_current'] != false ||
        !_equalTargeting(r['assets'], emptyMetaTargeting())) {
      bad();
    }
  } else {
    contextValid(r['saved_context']);
    if (!_labelsValid(r['saved_labels'], r['assets']) ||
        !time(r['updated_at'])) {
      bad();
    }
    if (r['draft_current'] == true &&
        !_equalTargeting(r['saved_context'], setup['current_snapshot'])) {
      bad();
    }
  }
  final checks = r['review_checks'], review = r['reviewed_snapshot'];
  final expected = {
    'saved_draft': version > 0,
    'complete_choices': r['draft_complete'],
    'current_context': r['draft_current'],
    'page_published': setup['checks']['page_published'],
    'plan_reviewed': setup['checks']['plan_reviewed'],
    'creative_saved': creative['version'] > 0,
    'creative_complete': creative['creative_complete'],
    'creative_current': creative['draft_current'],
  };
  if (!integer(r['draft_revision'], version == 0 ? 0 : 1, version) ||
      !hash(r['review_fingerprint']) ||
      !_equalTargeting(checks, expected) ||
      r['review_ready'] != expected.values.every((v) => v == true) ||
      r['review_current'] is! bool) {
    bad();
  }
  if (review == null) {
    if (r['reviewed_at'] != null || r['review_current'] != false) bad();
  } else {
    if (review is! Map ||
        review.length != 7 ||
        !metaTargetingValid(review['assets'], r['catalog']) ||
        !metaTargetingComplete(review['assets']) ||
        !_labelsValid(review['labels'], review['assets']) ||
        !integer(review['draft_revision'], 1, r['draft_revision']) ||
        review['catalog_version'] != r['catalog']['version'] ||
        !time(review['saved_at']) ||
        !time(r['reviewed_at']) ||
        review['creative'] is! Map ||
        review['creative'].length != 5) {
      bad();
    }
    contextValid(review['context']);
    final rc = validateMetaCreative(
      _reviewCreative(r, review['creative']),
      funnel,
      campaign,
    );
    if (!integer(rc['version'], 1, creative['version']) ||
        !_equalTargeting(rc['saved_context'], review['context'])) {
      bad();
    }
    if (r['review_current'] == true &&
        (r['review_ready'] != true ||
            review['draft_revision'] != r['draft_revision'] ||
            review['saved_at'] != r['updated_at'] ||
            !_equalTargeting(review['assets'], r['assets']) ||
            !_equalTargeting(review['context'], r['saved_context']) ||
            !_equalTargeting(review['labels'], r['saved_labels']) ||
            review['creative']['version'] != creative['version'] ||
            review['creative']['saved_at'] != creative['updated_at'] ||
            !_equalTargeting(
              review['creative']['assets'],
              creative['assets'],
            ) ||
            !_equalTargeting(review['creative']['image'], creative['image']) ||
            !_equalTargeting(
              review['creative']['context'],
              creative['saved_context'],
            ))) {
      bad();
    }
  }
  return r;
}

String metaTargetingExport(Map d) {
  final a = d['assets'], c = d['saved_context'], labels = d['saved_labels'];
  return 'KORLIX Meta targeting draft — ${c['campaign']['name']}\n${d['draft_current'] == true ? 'SAVED DRAFT' : 'OUT OF DATE — compare with current context.'}\n${d['draft_complete'] == true ? 'Draft choices complete.' : 'INCOMPLETE draft choices.'}\nSaved: ${d['updated_at']}\n${metaRadiusSummary(a)}\nCountries: ${(a['countries'] as List).map((v) => '${labels[v]} ($v)').join(', ')}\nDraft ages: ${a['age_min']}–${a['age_max'] == 65 ? '65+' : a['age_max']} · all genders\nAd categories: ${(a['categories'] as List).map((v) => metaAdCategories[v]).join(', ')}\nPlacement preference: ${metaPlacements[a['placements']]}\nDestination at save: ${c['landing_page']['destination']}\nFacebook Page at save: ${c['meta']['page']?['name'] ?? 'Not selected'}\nCountry list is a planning reference. Account, category, country, age and placement eligibility need live Meta checks. Coordinate accuracy, location restrictions, delivery expansion and launch require checking. ${a.containsKey('custom_locations') && !(a['categories'] as List).contains('NONE') ? '$metaRadiusCategoryNotice\n' : ''}No ad or spending has been created.';
}

class FunnelMetaTargeting extends StatefulWidget {
  const FunnelMetaTargeting({
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
  State<FunnelMetaTargeting> createState() => _FunnelMetaTargetingState();
}

class _FunnelMetaTargetingState extends State<FunnelMetaTargeting> {
  Map<String, dynamic> _choices = emptyMetaTargeting();
  Map<String, dynamic>? _data;
  bool _busy = false, _dirty = false, _conflict = false, _reviewChecked = false;
  int _generation = 0, _areaModeSerial = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-targeting';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _empty() {
    _choices = emptyMetaTargeting();
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
  void didUpdateWidget(covariant FunnelMetaTargeting old) {
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
      data = validateMetaTargeting(r, widget.funnelId, widget.campaignId);
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
      _data != null && metaTargetingValid(_assets, _data!['catalog']);
  bool get _editable =>
      _data?['editable'] == true &&
      !_busy &&
      !_childOpen &&
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

  Map<String, dynamic> _reviewDraft(Map<String, dynamic> d, Map s) => {
    ...d,
    'assets': s['assets'],
    'saved_context': s['context'],
    'saved_labels': s['labels'],
    'updated_at': s['saved_at'],
    'draft_revision': s['draft_revision'],
    'draft_current': d['review_current'],
    'draft_complete': true,
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
      if (_current(g)) {
        setState(() => _message = 'Meta preparation review saved.');
      }
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
        title: const Text('Clear the Meta preparation review?'),
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
          () => _message =
              'Meta preparation review cleared. Your draft is unchanged.',
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
        'KORLIX OWNER META PREPARATION REVIEW — ${d['review_current'] == true ? 'CURRENT' : 'OUT OF DATE'}\nReviewed draft revision: ${snapshot['draft_revision']}\nReviewed at: ${d['reviewed_at']}\nReference catalog: ${snapshot['catalog_version']}\n${_export(_reviewDraft(d, snapshot))}\n\n${metaCreativeExport({..._reviewCreative(d, snapshot['creative']), 'draft_current': d['review_current']})}';
    await Clipboard.setData(ClipboardData(text: text));
    if (_current(g)) {
      setState(() => _message = 'Meta preparation review copied.');
    }
  }

  Widget _reviewPanel() {
    final d = _data!, snapshot = d['reviewed_snapshot'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Review creative and targeting'),
        WfBadge(
          _dirty
              ? 'SAVE CHANGES BEFORE REVIEW'
              : snapshot == null
              ? 'PREPARATION NOT REVIEWED'
              : d['review_current'] == true
              ? 'PREPARATION REVIEW CURRENT'
              : 'REVIEW OUT OF DATE',
        ),
        const SizedBox(height: 12),
        const Text(
          'Review the saved targeting choices and the creative shown above. This is your KORLIX preparation review. Meta account, Page, category, placement and country eligibility remain separate.',
        ),
        if (_dirty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Save or discard your targeting changes before reviewing.',
            ),
          ),
        for (final e in metaTargetingReviewChecks.entries)
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
                    SelectableText(
                      metaCreativeExport({
                        ..._reviewCreative(d, snapshot['creative']),
                        'draft_current': d['review_current'],
                      }),
                    ),
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
          title: const Text(metaTargetingReviewConfirmation),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: _canReview && _reviewChecked ? _review : null,
              child: const Text('Save Meta preparation review'),
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
              child: const Text('Clear Meta preparation review'),
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

  String _export(Map<String, dynamic> d) => metaTargetingExport(d);
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
      (_data!['catalog']['countries'] as List).firstWhere(
        (x) => x['code'] == code,
      )['name'];
  void _change(void Function() fn) => setState(() {
    fn();
    _dirty = true;
    _reviewChecked = false;
    _message = null;
  });
  Future<void> _switchAreaMode(String mode) async {
    if (!_editable || _data?['radius_supported'] != true) return;
    final radius = mode == 'radius';
    if (radius == _assets.containsKey('custom_locations')) return;
    final g = _generation;
    final populated = radius
        ? (_assets['countries'] as List).isNotEmpty
        : (_assets['custom_locations'] as List).isNotEmpty;
    if (populated) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change target area type?'),
          content: Text(
            radius
                ? 'This removes your whole-country targets from this draft. Add radius areas before saving.'
                : 'This removes your radius areas from this draft. Choose whole-country targets before saving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep current targets'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change target type'),
            ),
          ],
        ),
      );
      if (ok != true) {
        if (_current(g)) setState(() => _areaModeSerial++);
        return;
      }
    }
    if (!_current(g) || !_editable) return;
    _change(() {
      _choices['countries'] = <String>[];
      if (radius) {
        _choices['custom_locations'] = <Map<String, dynamic>>[];
      } else {
        _choices.remove('custom_locations');
      }
    });
  }

  Future<void> _choose(String group, String title) async {
    if (!_editable) return;
    final g = _generation;
    final rows = (_data!['catalog']['countries'] as List).cast<Map>();
    final blocked = <String>{..._assets[group]};
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _TargetingPicker(title: title, rows: rows, blocked: blocked),
    );
    if (choice == null || !_current(g) || !_editable) return;
    final list = _assets[group] as List;
    if (list.length >= 20 || blocked.contains(choice)) {
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
        onPressed: _editable && (_assets[group] as List).length < 20
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

  bool _childOpen = false;
  Future<void> _openCreative() async {
    if (_busy || _dirty || _conflict || _unavailable != null || _childOpen) {
      return;
    }
    final g = _generation;
    setState(() => _childOpen = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FunnelMetaCreative(
        client: widget.client,
        funnelId: widget.funnelId,
        campaignId: widget.campaignId,
        scope: widget.scope,
      ),
    );
    if (!mounted) return;
    setState(() => _childOpen = false);
    if (_current(g)) await _load();
  }

  void _category(String code, bool value) {
    _change(() {
      final a = List<String>.from(_assets['categories']);
      if (['NONE', 'UNDECIDED'].contains(code)) {
        _choices['categories'] = [code];
      } else {
        a.removeWhere((v) => ['NONE', 'UNDECIDED'].contains(v));
        if (value) {
          a.add(code);
        } else {
          a.remove(code);
        }
        _choices['categories'] = a.isEmpty ? ['UNDECIDED'] : a;
      }
      if (!(_choices['categories'] as List).contains('NONE')) {
        _choices['age_min'] = 18;
        _choices['age_max'] = 65;
      }
    });
  }

  Widget _age(String key, String label) => DropdownButtonFormField<int>(
    key: ValueKey('$key-${_assets[key]}'),
    initialValue: _assets[key],
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: List.generate(
      48,
      (i) => DropdownMenuItem(
        value: i + 18,
        child: Text(i + 18 == 65 ? '65+' : '${i + 18}'),
      ),
    ),
    onChanged: _editable && (_assets['categories'] as List).contains('NONE')
        ? (v) {
            if (v != null) _change(() => _choices[key] = v);
          }
        : null,
  );
  Widget _creativePanel() {
    final c = _data!['creative'], a = c['assets'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Saved creative for review'),
        WfBadge(
          c['version'] == 0
              ? 'CREATIVE NOT SAVED'
              : c['draft_current'] == true
              ? 'CREATIVE CONTEXT CURRENT'
              : 'CREATIVE OUT OF DATE',
        ),
        const SizedBox(height: 12),
        if (c['version'] > 0) ...[
          Text(a['primary_text']),
          const SizedBox(height: 8),
          Text(
            a['headline'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          if (a['description'] != '') Text(a['description']),
          Text('Button: ${metaCreativeCtas[a['cta']]}'),
          if (a['image_id'] != null) ...[
            FunnelPrivateImage(
              client: widget.client,
              id: a['image_id'],
              description: a['image_alt'],
              height: 200,
            ),
            Text('Image description: ${a['image_alt']}'),
          ],
          SelectableText(c['saved_context']['landing_page']['destination']),
        ],
        TextButton(
          onPressed: _busy || _dirty || _conflict || _childOpen
              ? null
              : _openCreative,
          child: const Text('Open creative draft'),
        ),
        if (_dirty)
          const Text(
            'Save your targeting changes before opening the creative editor.',
          ),
      ],
    );
  }

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
                    'Meta targeting and placement',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _busy || _childOpen ? null : _close,
                    child: const Text('Close'),
                  ),
                ],
              ),
              const Text(
                'Prepare your audience and placement preferences, then review them with the saved creative.',
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
                  Text(_message!, style: const TextStyle(color: WfStyle.cyan)),
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
                    const Text(
                      'The campaign, Page identity or landing page changed. Compare the current context before saving again.',
                    ),
                  if (_data!['editable'] != true)
                    const Text(
                      'This campaign is archived. Reopen it to edit this draft.',
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Current campaign context'),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_data!['creative']['setup']['current_snapshot']['campaign']['name']}\nAudience brief: ${_data!['creative']['setup']['current_snapshot']['campaign']['audience']}',
                        ),
                      ),
                      SelectableText(
                        _data!['creative']['setup']['current_snapshot']['landing_page']['destination'],
                      ),
                    ],
                  ),
                  if (_data!['radius_supported'] == true) ...[
                    _section('Target area type'),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'area-mode-${_assets.containsKey('custom_locations')}-$_areaModeSerial',
                      ),
                      initialValue: _assets.containsKey('custom_locations')
                          ? 'radius'
                          : 'countries',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Choose country or radius targeting',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'countries',
                          child: Text('Whole countries'),
                        ),
                        DropdownMenuItem(
                          value: 'radius',
                          child: Text('Radius areas'),
                        ),
                      ],
                      onChanged: _editable
                          ? (v) {
                              if (v != null) unawaited(_switchAreaMode(v));
                            }
                          : null,
                    ),
                  ],
                  if (_assets.containsKey('custom_locations')) ...[
                    _section('Radius targets'),
                    MetaRadiusFields(
                      areas: _assets['custom_locations'],
                      enabled: _editable,
                      onChange: (a, k, v) => _change(() => a[k] = v),
                      onRemove: (a) => _change(
                        () => (_choices['custom_locations'] as List).remove(a),
                      ),
                      onAdd: () => _change(
                        () => (_choices['custom_locations'] as List)
                            .add(<String, dynamic>{
                              'label': '',
                              'latitude_micro': null,
                              'longitude_micro': null,
                              'radius_meters': null,
                            }),
                      ),
                    ),
                  ] else ...[
                    _section('Target countries'),
                    const Text(
                      'Choose up to 20 countries or territories. This planning list does not confirm Meta ad availability. Empty targets do not mean worldwide. City and region lookup remain separate.',
                    ),
                    _selection('countries', 'Add target country'),
                  ],
                  _section('Ad categories'),
                  const Text(
                    'Choose every category that applies to your offer. Category eligibility and authorization are checked with Meta before launch.',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in ['UNDECIDED', 'NONE'])
                        ChoiceChip(
                          label: Text(metaAdCategories[key]!),
                          selected: (_assets['categories'] as List).contains(
                            key,
                          ),
                          onSelected: _editable
                              ? (v) => _category(key, true)
                              : null,
                        ),
                    ],
                  ),
                  for (final key in metaAdCategories.keys.where(
                    (k) => !['UNDECIDED', 'NONE'].contains(k),
                  ))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(metaAdCategories[key]!),
                      value: (_assets['categories'] as List).contains(key),
                      onChanged: _editable
                          ? (v) => _category(key, v == true)
                          : null,
                    ),
                  if (_assets.containsKey('custom_locations') &&
                      !(_assets['categories'] as List).contains('NONE'))
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        metaRadiusCategoryNotice,
                        style: TextStyle(color: WfStyle.gold),
                      ),
                    ),
                  _section('Draft age range'),
                  const Text(
                    'All genders. KORLIX uses a broad 18–65+ draft range for undecided or special categories. This is a planning default; final age restrictions depend on the offer, country and Meta rules.',
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, c) => c.maxWidth > 450
                        ? Row(
                            children: [
                              Expanded(child: _age('age_min', 'Minimum age')),
                              const SizedBox(width: 12),
                              Expanded(child: _age('age_max', 'Maximum age')),
                            ],
                          )
                        : Column(
                            children: [
                              _age('age_min', 'Minimum age'),
                              const SizedBox(height: 12),
                              _age('age_max', 'Maximum age'),
                            ],
                          ),
                  ),
                  if (_assets['age_min'] > _assets['age_max'])
                    const Text(
                      'Minimum age must not exceed maximum age.',
                      style: TextStyle(color: WfStyle.gold),
                    ),
                  _section('Placement preference'),
                  _choice('placements', 'Preferred placement', metaPlacements),
                  const SizedBox(height: 10),
                  const Text(
                    'Automatic is a preference for Meta-selected placements. Facebook Feed requests that feed only. Image formats, identity requirements, delivery expansion and availability are checked during live setup.',
                  ),
                  if (!metaTargetingComplete(_assets))
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'You can save an incomplete draft. Choose countries or supported radius areas, categories and a placement to complete these choices.',
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
                        child: const Text('Save Meta targeting'),
                      ),
                      OutlinedButton(
                        onPressed:
                            _busy ||
                                _dirty ||
                                _conflict ||
                                _childOpen ||
                                _data!['version'] == 0
                            ? null
                            : _copy,
                        child: const Text('Copy saved targeting'),
                      ),
                      TextButton(
                        onPressed: _busy || _childOpen ? null : _reload,
                        child: const Text('Reload saved draft'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preparation only. Meta location eligibility, delivery settings, budgets, tracking and launch remain separate. Saving creates no ad and authorizes no spending.',
                    style: TextStyle(color: WfStyle.muted),
                  ),
                  _creativePanel(),
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
