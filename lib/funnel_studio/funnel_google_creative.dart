import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

int googleDraftUnits(String value) =>
    value.runes.fold(0, (n, c) => n + (c > 127 ? 2 : 1));
String? googleDraftTextError(String value, int limit, {bool path = false}) {
  if (value != value.trim() ||
      RegExp(
        r'[\x00-\x1f\x7f-\x9f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff{}]',
      ).hasMatch(value)) {
    return 'Use plain text without braces or hidden control characters.';
  }
  if (googleDraftUnits(value) > limit) {
    return 'Use $limit draft characters or fewer.';
  }
  if (path && RegExp(r'[\s/\\?#]').hasMatch(value)) {
    return 'Use a path without spaces, slashes or URL punctuation.';
  }
  return null;
}

bool _assetsValid(dynamic a) {
  if (a is! Map || a.length != 4) return false;
  for (final (key, max, limit) in [
    ('headlines', 15, 30),
    ('descriptions', 4, 90),
  ]) {
    final values = a[key];
    if (values is! List ||
        values.length > max ||
        values.any(
          (v) =>
              v is! String ||
              v.isEmpty ||
              googleDraftTextError(v, limit) != null,
        )) {
      return false;
    }
    if (values.map((v) => (v as String).toLowerCase()).toSet().length !=
        values.length) {
      return false;
    }
  }
  return a['path1'] is String &&
      a['path2'] is String &&
      googleDraftTextError(a['path1'], 15, path: true) == null &&
      googleDraftTextError(a['path2'], 15, path: true) == null &&
      (a['path1'] != '' || a['path2'] == '');
}

Map<String, dynamic> validateGoogleCreative(
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
  if (r['source'] != 'google_search_draft' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      !integer(version, 0, 2147483647) ||
      r['fingerprint'] is! String ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(r['fingerprint']) ||
      !_assetsValid(r['assets']) ||
      !contextValid(r['context']) ||
      r['ad_publishing_ready'] != false ||
      r['draft_current'] is! bool ||
      r['editable'] != (r['context']?['campaign_state'] != 'archived') ||
      r['text_complete'] !=
          ((r['assets']['headlines'] as List).length >= 3 &&
              (r['assets']['descriptions'] as List).length >= 2) ||
      (version == 0
          ? r['saved_context'] != null ||
                r['updated_at'] != null ||
                r['draft_current'] != false ||
                (r['assets']['headlines'] as List).isNotEmpty ||
                (r['assets']['descriptions'] as List).isNotEmpty ||
                r['assets']['path1'] != '' ||
                r['assets']['path2'] != ''
          : !contextValid(r['saved_context']) ||
                r['updated_at'] is! String ||
                DateTime.tryParse(r['updated_at']) == null)) {
    throw const FunnelException(
      'The search-ad draft could not be verified. Reload it.',
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
  return r;
}

class FunnelGoogleCreative extends StatefulWidget {
  const FunnelGoogleCreative({
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
  State<FunnelGoogleCreative> createState() => _FunnelGoogleCreativeState();
}

class _FunnelGoogleCreativeState extends State<FunnelGoogleCreative> {
  final _headlines = List.generate(15, (_) => TextEditingController());
  final _descriptions = List.generate(4, (_) => TextEditingController());
  final _path1 = TextEditingController(), _path2 = TextEditingController();
  Map<String, dynamic>? _data;
  bool _busy = false, _dirty = false, _conflict = false;
  int _generation = 0, _headlineCount = 3, _descriptionCount = 2;
  String? _error, _unavailable, _message;
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/google-creative';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
  List<TextEditingController> get _all => [
    ..._headlines,
    ..._descriptions,
    _path1,
    _path2,
  ];
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
    _message = null;
    _error = null;
    _headlineCount = 3;
    _descriptionCount = 2;
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
      _invalidate('Sign in with Enterprise access to edit search-ad drafts.');
  void _scopeChanged() => _invalidate(
    'The campaign workspace changed. Close this draft and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelGoogleCreative old) {
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
      data = validateGoogleCreative(r, widget.funnelId, widget.campaignId);
    } catch (_) {
      setState(() => _data = null);
      rethrow;
    }
    final a = data['assets'];
    setState(() {
      _empty();
      _data = data;
      for (var i = 0; i < a['headlines'].length; i++) {
        _headlines[i].text = a['headlines'][i];
      }
      for (var i = 0; i < a['descriptions'].length; i++) {
        _descriptions[i].text = a['descriptions'][i];
      }
      _path1.text = a['path1'];
      _path2.text = a['path2'];
      _headlineCount = (a['headlines'].length as int).clamp(3, 15);
      _descriptionCount = (a['descriptions'].length as int).clamp(2, 4);
    });
  }

  Future<void> _run(Future<void> Function(int) fn) async {
    if (_busy || _unavailable != null) return;
    final g = ++_generation;
    setState(() {
      _busy = true;
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
            _unavailable =
                'This campaign is no longer available. Close this draft.';
          } else {
            _error = e is FunnelException
                ? e.message
                : 'The search-ad draft could not be saved. Try again.';
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
    'headlines': _headlines
        .take(_headlineCount)
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    'descriptions': _descriptions
        .take(_descriptionCount)
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
    'path1': _path1.text.trim(),
    'path2': _path2.text.trim(),
  };
  bool get _valid => _assetsValid(_assets);
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
      if (_current(g)) setState(() => _message = 'Search-ad draft saved.');
    });
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
    final a = data['assets'], c = data['saved_context'];
    return 'KORLIX Google search-ad draft — ${c['campaign_name']}\n${data['draft_current'] == true ? 'SAVED DRAFT' : 'OUT OF DATE — compare with the current campaign and landing page.'}\n${data['text_complete'] == true ? 'Minimum text counts complete.' : 'INCOMPLETE — add at least 3 headlines and 2 descriptions.'}\nSaved: ${data['updated_at']}\nDestination at save: ${c['destination']}\nDisplay paths: ${a['path1']} / ${a['path2']}\nHeadlines:\n${(a['headlines'] as List).asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\nDescriptions:\n${(a['descriptions'] as List).asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\nDraft only. Google policy approval, keywords, targeting, pinning, final preview and launch are separate. No ad or spending has been created.';
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
    _message = null;
  });
  Widget _field(
    TextEditingController c,
    String label,
    int limit, {
    bool path = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      enabled: _editable,
      maxLines: path ? 1 : null,
      minLines: 1,
      maxLength: limit * 2,
      maxLengthEnforcement: MaxLengthEnforcement.none,
      onChanged: _changed,
      decoration: InputDecoration(
        labelText: label,
        counterText:
            '${googleDraftUnits(c.text.trim())}/$limit draft characters',
        errorText: googleDraftTextError(c.text.trim(), limit, path: path),
      ),
    ),
  );
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final a = _assets;
    final headlines = a['headlines'] as List,
        descriptions = a['descriptions'] as List;
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
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Google search-ad draft',
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
                  'Prepare headlines and descriptions for a responsive search ad. Saving keeps your text in KORLIX.',
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
                        WfBadge(
                          headlines.length >= 3 &&
                                  descriptions.length >= 2 &&
                                  _valid
                              ? 'TEXT COUNTS COMPLETE'
                              : 'TEXT INCOMPLETE',
                        ),
                      ],
                    ),
                    if (_data!['version'] > 0 &&
                        _data!['draft_current'] != true)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'The campaign or published page changed since this draft was saved. Compare your text with the current context before saving again.',
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
                            '${_data!['context']['campaign_name']}\n${_data!['context']['headline']}\n${_data!['context']['body']}\nAudience: ${_data!['context']['audience']}\nPage: ${_data!['context']['page_state']}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(_data!['context']['destination']),
                      ],
                    ),
                    const Text(
                      'English letters, numbers, spaces and basic punctuation count as 1; other characters count as 2. Confirm the final count in Google Ads.',
                      style: TextStyle(color: WfStyle.muted),
                    ),
                    _section('Headlines · ${headlines.length}/15'),
                    const Text(
                      'Use at least 3 different headlines, up to 30 draft characters each.',
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _headlineCount; i++)
                      _field(_headlines[i], 'Headline ${i + 1}', 30),
                    if (_headlineCount < 15)
                      OutlinedButton.icon(
                        onPressed: _editable
                            ? () => setState(() => _headlineCount++)
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add headline'),
                      ),
                    _section('Descriptions · ${descriptions.length}/4'),
                    const Text(
                      'Use at least 2 different descriptions, up to 90 draft characters each.',
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _descriptionCount; i++)
                      _field(_descriptions[i], 'Description ${i + 1}', 90),
                    if (_descriptionCount < 4)
                      OutlinedButton.icon(
                        onPressed: _editable
                            ? () => setState(() => _descriptionCount++)
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Add description'),
                      ),
                    _section('Display paths · optional'),
                    const Text(
                      'These labels describe your offer. They do not change the landing-page link.',
                    ),
                    const SizedBox(height: 12),
                    _field(_path1, 'Display path 1', 15, path: true),
                    _field(_path2, 'Display path 2', 15, path: true),
                    if (!_valid)
                      const Text(
                        'Check text lengths, duplicate headlines or descriptions, and display paths before saving.',
                        style: TextStyle(color: WfStyle.gold),
                      ),
                    _section('Illustrative preview'),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sponsored · draft',
                            style: TextStyle(color: Colors.black54),
                          ),
                          Text(
                            '${Uri.parse(_data!['context']['destination']).host}${a['path1'] == '' ? '' : ' / ${a['path1']}'}${a['path2'] == '' ? '' : ' / ${a['path2']}'}',
                            style: const TextStyle(color: Colors.black87),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            headlines.isEmpty
                                ? 'Your headlines'
                                : headlines.take(3).join(' | '),
                            style: const TextStyle(
                              color: Color(0xFF1A0DAB),
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            descriptions.isEmpty
                                ? 'Your descriptions'
                                : descriptions.take(2).join(' '),
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'One possible combination. Google can reorder, shorten or omit text. Policy review, keywords, targeting, pinning and launch are separate.',
                        style: TextStyle(color: WfStyle.muted),
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: _editable && _valid ? _save : null,
                          child: const Text('Save search-ad draft'),
                        ),
                        OutlinedButton(
                          onPressed:
                              _busy ||
                                  _dirty ||
                                  _conflict ||
                                  _data!['version'] == 0
                              ? null
                              : _copy,
                          child: const Text('Copy saved draft'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _reload,
                          child: const Text('Reload saved draft'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'You can save incomplete text. Saving does not create an ad or authorize spending.',
                      style: TextStyle(color: WfStyle.muted),
                    ),
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
