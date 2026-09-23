import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

const googleKeywordReviewConfirmation =
    'I reviewed all positive and negative keywords, their match types and any overlap warnings against the published landing page.';
const googleKeywordReviewChecks = <String, String>{
  'saved_draft': 'Save the draft first.',
  'positive_keywords': 'Add at least one positive keyword.',
  'current_context':
      'Check the current campaign context and save the draft again.',
  'page_published': 'Publish the landing page.',
  'plan_reviewed': 'Review the campaign plan against the published page.',
};
bool _equalKeywords(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equalKeywords(a[k], b[k]))
    : a is List && b is List
    ? a.length == b.length &&
          List.generate(
            a.length,
            (i) => i,
          ).every((i) => _equalKeywords(a[i], b[i]))
    : a == b;

const googleKeywordLabels = <String, String>{
  'exact': 'Exact match',
  'phrase': 'Phrase match',
  'broad': 'Broad match',
  'negative_exact': 'Negative exact match',
  'negative_phrase': 'Negative phrase match',
  'negative_broad': 'Negative broad match',
};
String? googleKeywordError(String s) {
  if (s.isEmpty ||
      s != s.trim() ||
      s.runes.length > 80 ||
      s.split(' ').length > 10 ||
      s.contains('  ') ||
      RegExp(
        r'[\x00-\x1f\x7f-\x9f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff!@%^=;<>?,{}\[\]"\\+*/:|()#$]',
      ).hasMatch(s) ||
      RegExp(r'[^\S ]').hasMatch(s)) {
    return 'Use plain text, up to 80 characters and 10 words. Leave out brackets, quotes and operators.';
  }
  return null;
}

bool googleKeywordsValid(dynamic a) {
  if (a is! Map || a.length != 6) return false;
  var positive = 0, negative = 0;
  for (final k in googleKeywordLabels.keys) {
    final values = a[k];
    if (values is! List ||
        values.length > 50 ||
        values.any((v) => v is! String || googleKeywordError(v) != null)) {
      return false;
    }
    if (values.map((v) => (v as String).toLowerCase()).toSet().length !=
        values.length) {
      return false;
    }
    if (k.startsWith('negative_')) {
      negative += values.length;
    } else {
      positive += values.length;
    }
  }
  return positive <= 50 && negative <= 50;
}

int _keywordCount(Map a, bool negative) => googleKeywordLabels.keys
    .where((k) => k.startsWith('negative_') == negative)
    .fold(0, (n, k) => n + (a[k] as List).length);
bool _emptyKeywords(Map a) =>
    googleKeywordLabels.keys.every((k) => (a[k] as List).isEmpty);

Map<String, dynamic> validateGoogleKeywords(
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
  if (r['source'] != 'google_keyword_draft' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      !integer(version, 0, 2147483647) ||
      r['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['fingerprint']) ||
      !googleKeywordsValid(r['assets']) ||
      !contextValid(r['context']) ||
      r['ad_publishing_ready'] != false ||
      r['draft_current'] is! bool ||
      r['editable'] != (r['context']?['campaign_state'] != 'archived') ||
      r['keyword_count'] != _keywordCount(r['assets'], false) ||
      r['negative_count'] != _keywordCount(r['assets'], true) ||
      (version == 0
          ? r['saved_context'] != null ||
                r['updated_at'] != null ||
                r['draft_current'] != false ||
                !_emptyKeywords(r['assets'])
          : !contextValid(r['saved_context']) ||
                r['updated_at'] is! String ||
                DateTime.tryParse(r['updated_at']) == null)) {
    throw const FunnelException(
      'The keyword draft could not be verified. Reload it.',
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
      v.length == 4 &&
      googleKeywordsValid(v['assets']) &&
      contextValid(v['context']) &&
      integer(v['draft_revision'], 1, r['draft_revision']) &&
      _keywordCount(v['assets'], false) > 0 &&
      v['saved_at'] is String &&
      DateTime.tryParse(v['saved_at']) != null;
  if (!integer(r['draft_revision'], version == 0 ? 0 : 1, version) ||
      r['review_fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['review_fingerprint']) ||
      checks is! Map ||
      checks.length != googleKeywordReviewChecks.length ||
      googleKeywordReviewChecks.keys.any((k) => checks[k] is! bool) ||
      r['review_ready'] is! bool ||
      r['review_ready'] != checks.values.every((v) => v == true) ||
      checks['saved_draft'] != (version > 0) ||
      checks['positive_keywords'] != (r['keyword_count'] > 0) ||
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
              !_equalKeywords(review['assets'], r['assets']) ||
              !_equalKeywords(review['context'], r['saved_context'])))) {
    throw const FunnelException(
      'The keyword review could not be verified. Reload the draft.',
      503,
    );
  }
  return r;
}

class FunnelGoogleKeywords extends StatefulWidget {
  const FunnelGoogleKeywords({
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
  State<FunnelGoogleKeywords> createState() => _FunnelGoogleKeywordsState();
}

class _FunnelGoogleKeywordsState extends State<FunnelGoogleKeywords> {
  final _fields = {
    for (final k in googleKeywordLabels.keys) k: TextEditingController(),
  };
  Map<String, dynamic>? _data;
  bool _busy = false, _dirty = false, _conflict = false, _reviewChecked = false;
  int _generation = 0;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-keywords';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  List<TextEditingController> get _all => _fields.values.toList();
  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    widget.scope?.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _empty({bool clearFields = true}) {
    if (clearFields) {
      for (final c in _all) {
        c.clear();
      }
    }
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
    final building =
        SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    _empty(clearFields: !building);
    _busy = false;
    _unavailable = message;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && g == _generation) {
          setState(() {
            for (final c in _all) {
              c.clear();
            }
          });
        }
      });
    } else {
      setState(() {});
    }
  }

  void _deny() =>
      _invalidate('Sign in with Enterprise access to edit keyword drafts.');
  void _scopeChanged() => _invalidate(
    'The campaign workspace changed. Close this draft and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleKeywords old) {
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
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(Map<String, dynamic> r, int g) {
    if (!_current(g)) return;
    late Map<String, dynamic> data;
    try {
      data = validateGoogleKeywords(r, widget.funnelId, widget.campaignId);
    } catch (_) {
      setState(() => _data = null);
      rethrow;
    }
    final a = data['assets'];
    setState(() {
      _empty();
      _data = data;
      for (final k in googleKeywordLabels.keys) {
        _fields[k]!.text = (a[k] as List).join('\n');
      }
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
                : 'The keyword draft could not be saved. Try again.';
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
  Map<String, dynamic> get _assets => {
    for (final k in googleKeywordLabels.keys)
      k: _fields[k]!.text
          .split('\n')
          .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
          .where((s) => s.isNotEmpty)
          .toList(),
  };
  bool get _valid => googleKeywordsValid(_assets);
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
      if (_current(g)) setState(() => _message = 'Keyword draft saved.');
    });
  }

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
      if (_current(g)) setState(() => _message = 'Keyword review saved.');
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
        title: const Text('Clear the keyword review?'),
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
          () => _message = 'Keyword review cleared. Your draft is unchanged.',
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
        'KORLIX OWNER KEYWORD REVIEW — ${d['review_current'] == true ? 'CURRENT' : 'OUT OF DATE'}\nReviewed draft revision: ${snapshot['draft_revision']}\nReviewed at: ${d['reviewed_at']}\n${_export({...d, 'assets': snapshot['assets'], 'saved_context': snapshot['context'], 'updated_at': snapshot['saved_at'], 'draft_revision': snapshot['draft_revision'], 'draft_current': d['review_current'], 'keyword_count': _keywordCount(snapshot['assets'], false), 'negative_count': _keywordCount(snapshot['assets'], true)})}';
    await Clipboard.setData(ClipboardData(text: text));
    if (_current(g)) setState(() => _message = 'Keyword review record copied.');
  }

  Widget _reviewPanel() {
    final d = _data!, snapshot = d['reviewed_snapshot'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('Review saved keywords'),
        WfBadge(
          _dirty
              ? 'SAVE CHANGES BEFORE REVIEW'
              : snapshot == null
              ? 'KEYWORDS NOT REVIEWED'
              : d['review_current'] == true
              ? 'KEYWORD REVIEW CURRENT'
              : 'KEYWORD REVIEW OUT OF DATE',
        ),
        const SizedBox(height: 12),
        const Text(
          'Review all saved keywords, exclusions, match types and overlaps against the published page. This records your keyword review in KORLIX; targeting setup, Google approval and launch remain separate.',
        ),
        if (_dirty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Save or discard your keyword changes before reviewing.',
            ),
          ),
        for (final e in googleKeywordReviewChecks.entries)
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
                    for (final e in googleKeywordLabels.entries)
                      Text(
                        '${e.value}: ${(snapshot['assets'][e.key] as List).isEmpty ? '(none)' : (snapshot['assets'][e.key] as List).join(', ')}',
                      ),
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
          title: const Text(googleKeywordReviewConfirmation),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton(
              onPressed: _canReview && _reviewChecked ? _review : null,
              child: const Text('Save keyword review'),
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
              child: const Text('Clear keyword review'),
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
        content: const Text('Your unsaved text will be discarded.'),
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

  String _export(Map<String, dynamic> data) {
    final a = data['assets'] as Map, c = data['saved_context'];
    return 'KORLIX Google keyword draft — ${c['campaign_name']}\n${data['draft_current'] == true ? 'SAVED DRAFT' : 'OUT OF DATE — compare with the current campaign and published page.'}\n${data['keyword_count'] == 0 ? 'INCOMPLETE — no positive keywords.' : '${data['keyword_count']} positive / ${data['negative_count']} negative keywords.'}\nDraft revision: ${data['draft_revision']}\nSaved: ${data['updated_at']}\nDestination at save: ${c['destination']}\nAudience at save: ${c['audience']}\n${googleKeywordLabels.entries.map((e) => '${e.value}:\n${(a[e.key] as List).isEmpty ? '(none)' : (a[e.key] as List).join('\n')}').join('\n\n')}\nDraft only. Check keyword overlaps and Google eligibility. Locations, languages, bidding, final targeting review and launch are separate. No ad or spending has been created.';
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

  void _changed(String value) => setState(() {
    _dirty = true;
    _reviewChecked = false;
    _message = null;
  });
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
    ),
  );
  Widget _field(String key, Map a) {
    final values = a[key] as List;
    final invalid =
        values.any((v) => googleKeywordError(v) != null) ||
        values.map((v) => (v as String).toLowerCase()).toSet().length !=
            values.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        key: ValueKey('keywords-$key'),
        controller: _fields[key],
        enabled: _editable,
        minLines: 2,
        maxLines: 6,
        onChanged: _changed,
        decoration: InputDecoration(
          labelText: googleKeywordLabels[key],
          hintText: 'One keyword per line',
          counterText: '${values.length} keywords',
          errorMaxLines: 4,
          errorText: invalid
              ? 'Check duplicates within this list, text limits and match-type punctuation.'
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _assets,
        positive = _keywordCount(_assets, false),
        negative = _keywordCount(_assets, true);
    final included = googleKeywordLabels.keys
        .where((k) => !k.startsWith('negative_'))
        .expand((k) => a[k] as List)
        .map((v) => (v as String).toLowerCase())
        .toSet();
    final overlaps = googleKeywordLabels.keys
        .where((k) => k.startsWith('negative_'))
        .expand((k) => a[k] as List)
        .map((v) => (v as String).toLowerCase())
        .where(included.contains)
        .toSet();
    return PopScope(
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
                      'Google keyword draft',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _close,
                      child: const Text('Close'),
                    ),
                  ],
                ),
                const Text(
                  'Prepare search terms and exclusions for this campaign. Saving keeps your keyword plan in KORLIX.',
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        WfBadge(
                          _dirty
                              ? 'UNSAVED CHANGES'
                              : _data!['version'] == 0
                              ? 'NEW DRAFT'
                              : _data!['draft_current'] == true
                              ? 'SAVED DRAFT'
                              : 'OUT OF DATE',
                        ),
                        WfBadge('$positive positive / $negative negative'),
                      ],
                    ),
                    if (_data!['version'] > 0 &&
                        _data!['draft_current'] != true)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'The campaign or published page changed. Compare these keywords with the current context before saving again.',
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
                    const Text(
                      'One keyword per line. Use up to 50 positive and 50 negative keywords, each up to 80 characters and 10 words. Enter plain text without match-type brackets or quotes. These are KORLIX draft limits; Google eligibility is checked separately.',
                      style: TextStyle(color: WfStyle.muted),
                    ),
                    _section('Positive keywords'),
                    const Text(
                      'Exact: same meaning or intent. Phrase: includes the keyword meaning. Broad: related searches, which can reach further. Check bidding and reach before choosing broad match.',
                    ),
                    const SizedBox(height: 14),
                    for (final k in ['exact', 'phrase', 'broad']) _field(k, a),
                    _section('Negative keywords · optional'),
                    const Text(
                      'Negative matching differs from positive matching. Exact excludes the term alone; phrase excludes those words in that order; broad excludes searches containing all those words. Check synonyms and singular/plural forms separately.',
                    ),
                    const SizedBox(height: 14),
                    for (final k in [
                      'negative_exact',
                      'negative_phrase',
                      'negative_broad',
                    ])
                      _field(k, a),
                    if (overlaps.isNotEmpty)
                      Text(
                        'Same text appears in positive and negative lists: ${overlaps.join(', ')}. Review these exclusions. This check does not detect every match overlap.',
                        style: const TextStyle(color: WfStyle.gold),
                      ),
                    if (positive == 0)
                      const Text(
                        'No positive keywords yet. You can save an incomplete draft.',
                        style: TextStyle(color: WfStyle.gold),
                      ),
                    if (!_valid)
                      const Text(
                        'Check keyword limits, duplicates within each list and text before saving.',
                        style: TextStyle(color: WfStyle.gold),
                      ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: _editable && _valid ? _save : null,
                          child: const Text('Save keyword draft'),
                        ),
                        OutlinedButton(
                          onPressed:
                              _busy ||
                                  _dirty ||
                                  _conflict ||
                                  _data!['version'] == 0
                              ? null
                              : _copy,
                          child: const Text('Copy saved keywords'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _reload,
                          child: const Text('Reload saved draft'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Draft preparation only. Saving does not create an ad or authorize spending. Locations, languages, bidding and final targeting review remain separate.',
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
}
