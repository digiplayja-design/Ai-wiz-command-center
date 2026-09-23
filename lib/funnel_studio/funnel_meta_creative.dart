import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';
import 'funnel_images.dart';
import 'funnel_meta_preparation.dart';

const metaCreativeCtas = {
  'LEARN_MORE': 'Learn more',
  'CONTACT_US': 'Contact us',
  'SIGN_UP': 'Sign up',
  'SHOP_NOW': 'Shop now',
  'GET_QUOTE': 'Get quote',
};
const metaCreativeLimits = {
  'primary_text': 1000,
  'headline': 100,
  'description': 200,
  'image_alt': 180,
};
bool _uuid(dynamic v) =>
    v is String &&
    RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(v);
bool _hash(dynamic v) => v is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
bool _integer(dynamic v, int max) => v is int && v >= 0 && v <= max;
String? metaCreativeTextError(String s, int limit) {
  if (s != s.trim() ||
      RegExp(
        r'[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u200b-\u200f\u2028-\u202e\u2060-\u206f\ufeff\ud800-\udfff]',
        unicode: true,
      ).hasMatch(s)) {
    return 'Use plain text without line breaks or hidden characters.';
  }
  if (s.runes.length > limit) return 'Use up to $limit characters.';
  return null;
}

bool _assetsValid(dynamic a) =>
    a is Map &&
    a.length == 6 &&
    metaCreativeLimits.entries.every(
      (e) =>
          a[e.key] is String &&
          metaCreativeTextError(a[e.key], e.value) == null,
    ) &&
    metaCreativeCtas.containsKey(a['cta']) &&
    (a['image_id'] == null ? a['image_alt'] == '' : _uuid(a['image_id']));
bool _same(dynamic a, dynamic b) => a is Map && b is Map
    ? a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]))
    : a == b;
bool _imageValid(dynamic v, {bool saved = false}) =>
    v is Map &&
    _uuid(v['id']) &&
    v['label'] is String &&
    (v['label'] as String).isNotEmpty &&
    (v['label'] as String).length <= 100 &&
    _integer(v['width'], 1600) &&
    v['width'] > 0 &&
    _integer(v['height'], 1600) &&
    v['height'] > 0 &&
    (!saved || _hash(v['sha256']));
Map<String, dynamic> validateMetaCreative(
  Map<String, dynamic> r,
  String funnel,
  String campaign,
) {
  void bad() => throw const FunnelException(
    'The Meta ad draft could not be verified. Reload it.',
    503,
  );
  if (r['source'] != 'meta_ad_draft' ||
      r['funnel_id'] != funnel ||
      r['campaign_id'] != campaign ||
      !_integer(r['version'], 2147483647) ||
      !_hash(r['fingerprint']) ||
      r['setup'] is! Map ||
      !_assetsValid(r['assets']) ||
      r['editable'] is! bool ||
      r['draft_current'] is! bool ||
      r['creative_complete'] is! bool ||
      r['ad_publishing_ready'] != false) {
    bad();
  }
  final setup = validateMetaPreparation(
        Map<String, dynamic>.from(r['setup']),
        funnel,
        campaign,
      ),
      a = r['assets'];
  if (r['fingerprint'] != setup['fingerprint'] ||
      (a['image_id'] == null
          ? r['image'] != null
          : !_imageValid(r['image'], saved: true) ||
                r['image']['id'] != a['image_id'])) {
    bad();
  }
  if (r['creative_complete'] !=
      (a['primary_text'] != '' &&
          a['headline'] != '' &&
          a['image_id'] != null &&
          a['image_alt'] != '')) {
    bad();
  }
  if (r['version'] == 0) {
    if (r['saved_context'] != null ||
        r['updated_at'] != null ||
        r['draft_current'] != false ||
        a['primary_text'] != '' ||
        a['headline'] != '' ||
        a['description'] != '' ||
        a['cta'] != 'LEARN_MORE' ||
        a['image_id'] != null) {
      bad();
    }
  } else {
    if (r['updated_at'] is! String ||
        DateTime.tryParse(r['updated_at']) == null ||
        r['saved_context'] is! Map) {
      bad();
    }
    validateMetaPreparation(
      {
        ...setup,
        'current_snapshot': r['saved_context'],
        'checks': {for (final k in metaSetupChecks.keys) k: false},
        'ready_for_review': false,
        'review_current': false,
        'reviewed_snapshot': null,
        'reviewed_at': null,
      },
      funnel,
      campaign,
    );
    if (r['draft_current'] == true &&
        !_same(r['saved_context'], setup['current_snapshot'])) {
      bad();
    }
  }
  return r;
}

String metaCreativeExport(Map<String, dynamic> data) {
  final a = data['assets'],
      s = data['saved_context'],
      m = s['meta'],
      image = data['image'];
  return 'KORLIX Meta ad draft — ${s['campaign']['name']}\n${data['draft_current'] == true ? 'SAVED DRAFT' : 'OUT OF DATE — compare with the current campaign, Page and destination.'}\n${data['creative_complete'] == true ? 'Text and image preparation complete.' : 'INCOMPLETE — add primary text, a headline, an image and its description.'}\nSaved: ${data['updated_at']}\nFacebook Page at save: ${m['page']?['name'] ?? 'Not selected'} (${m['page']?['id'] ?? 'none'})\nAd account at save: ${m['account']?['name'] ?? 'Not selected'} (${m['account']?['id'] ?? 'none'})\nDestination at save: ${s['landing_page']['destination']}\nPrimary text: ${a['primary_text']}\nHeadline: ${a['headline']}\nDescription: ${a['description']}\nButton preference: ${metaCreativeCtas[a['cta']]} (${a['cta']})\nImage: ${image == null ? 'Not selected' : '${image['label']} — ${image['width']} × ${image['height']} — private KORLIX asset ${image['id']}'}\nImage description: ${a['image_alt']}\nDraft preparation only. Placement, image upload, button eligibility, Meta policy review and launch remain separate. No ad or spending has been created.';
}

class FunnelMetaCreative extends StatefulWidget {
  const FunnelMetaCreative({
    super.key,
    required this.client,
    required this.funnelId,
    required this.campaignId,
    this.scope,
    this.picker = pickFunnelImage,
  });
  final FunnelClient client;
  final String funnelId, campaignId;
  final ValueListenable<int>? scope;
  final Future<FunnelPickedImage?> Function() picker;
  @override
  State<FunnelMetaCreative> createState() => _FunnelMetaCreativeState();
}

class _FunnelMetaCreativeState extends State<FunnelMetaCreative> {
  final _primary = TextEditingController(),
      _headline = TextEditingController(),
      _description = TextEditingController(),
      _alt = TextEditingController();
  List<TextEditingController> get _all => [
    _primary,
    _headline,
    _description,
    _alt,
  ];
  Map<String, dynamic>? _data, _selectedImage;
  List<Map<String, dynamic>>? _images;
  bool _busy = false, _dirty = false, _conflict = false;
  int _generation = 0;
  String? _error, _unavailable, _message, _imageId;
  String _cta = 'LEARN_MORE';
  String get _path =>
      '/${widget.funnelId}/campaigns/${widget.campaignId}/meta-creative';
  bool _current(int g) => mounted && _unavailable == null && g == _generation;
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
    _imageId = null;
    _selectedImage = null;
    _images = null;
    _cta = "LEARN_MORE";
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
      _invalidate('Sign in with Enterprise access to edit Meta ad drafts.');
  void _scopeChanged() => _invalidate(
    'The campaign workspace changed. Close this draft and open it again.',
  );
  @override
  void didUpdateWidget(covariant FunnelMetaCreative old) {
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
    late Map<String, dynamic> d;
    try {
      d = validateMetaCreative(r, widget.funnelId, widget.campaignId);
    } catch (_) {
      setState(_empty);
      rethrow;
    }
    setState(() {
      _empty();
      _data = d;
      final a = d['assets'];
      _primary.text = a['primary_text'];
      _headline.text = a['headline'];
      _description.text = a['description'];
      _alt.text = a['image_alt'];
      _cta = a['cta'];
      _imageId = a['image_id'];
      _selectedImage = d['image'] == null
          ? null
          : Map<String, dynamic>.from(d['image']);
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
                : 'The Meta draft could not be updated. Try again.';
            if (e is FunnelException && e.status == 409) _conflict = true;
          }
        });
      }
    } finally {
      if (mounted && g == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _load() =>
      _run((g) async => _apply(await widget.client.request('GET', _path), g));
  Map<String, dynamic> get _assets => {
    'primary_text': _primary.text.trim(),
    'headline': _headline.text.trim(),
    'description': _description.text.trim(),
    'cta': _cta,
    'image_id': _imageId,
    'image_alt': _alt.text.trim(),
  };
  bool get _editable =>
      _data?['editable'] == true &&
      !_busy &&
      !_conflict &&
      _unavailable == null;
  void _changed([String? value]) => setState(() {
    _dirty = true;
    _message = null;
  });
  Future<void> _save() async {
    if (!_editable || !_assetsValid(_assets)) return;
    final body = {
      'version': _data!['version'],
      'fingerprint': _data!['fingerprint'],
      'assets': _assets,
    };
    await _run((g) async {
      _apply(await widget.client.request('POST', '$_path/save', body: body), g);
      if (_current(g)) setState(() => _message = 'Meta ad draft saved.');
    });
  }

  Future<void> _chooseImages() async {
    if (!_editable) return;
    await _run((g) async {
      final r = await widget.client.request('GET', '/images');
      if (!_current(g)) return;
      if (r['images'] is! List ||
          (r['images'] as List).length > 50 ||
          (r['images'] as List).any((v) => !_imageValid(v))) {
        throw const FunnelException(
          'The image library could not be read. Reload it.',
          503,
        );
      }
      setState(
        () => _images = (r['images'] as List)
            .map((v) => Map<String, dynamic>.from(v))
            .toList(),
      );
    });
  }

  void _select(Map<String, dynamic> image) {
    if (!_editable) return;
    setState(() {
      _imageId = image['id'];
      _selectedImage = image;
      _alt.text = image['label'].toString().replaceFirst(
        RegExp(r'\.[^.]+$'),
        '',
      );
      _images = null;
      _dirty = true;
      _message = null;
    });
  }

  Future<void> _upload() async {
    if (!_editable) return;
    await _run((g) async {
      final picked = await widget.picker();
      if (picked == null || !_current(g)) return;
      final r = await widget.client.uploadImage(picked.name, picked.bytes);
      if (!_current(g)) return;
      if (!_imageValid(r['image'])) {
        throw const FunnelException(
          'The uploaded image could not be verified. Reload your image library.',
          503,
        );
      }
      setState(() {
        final image = Map<String, dynamic>.from(r['image']);
        _imageId = image['id'];
        _selectedImage = image;
        _alt.text = image['label'].toString().replaceFirst(
          RegExp(r'\.[^.]+$'),
          '',
        );
        _images = null;
        _dirty = true;
      });
    });
  }

  Future<bool> _discard(String title) async {
    if (!_dirty) return true;
    final g = _generation;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Your unsaved text and image selection will be discarded.',
        ),
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
    if (await _discard('Reload the saved draft?')) await _load();
  }

  Future<void> _copy() async {
    if (_busy ||
        _dirty ||
        _conflict ||
        _unavailable != null ||
        _data == null ||
        _data!['version'] == 0) {
      return;
    }
    final g = _generation;
    await Clipboard.setData(ClipboardData(text: metaCreativeExport(_data!)));
    if (_current(g)) setState(() => _message = 'Saved Meta draft copied.');
  }

  Widget _field(TextEditingController c, String label, int limit) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: c,
      enabled: _editable,
      maxLines: null,
      minLines: 1,
      onChanged: _changed,
      decoration: InputDecoration(
        labelText: label,
        counterText:
            '${c.text.trim().runes.length}/$limit preparation characters',
        errorText: metaCreativeTextError(c.text.trim(), limit),
      ),
    ),
  );
  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(
      label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
  Widget _preview() {
    final s = _data!['setup']['current_snapshot'], a = _assets;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s['meta']['page']?['name'] ?? 'Facebook Page not selected',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Draft preview · actual placements may differ',
              style: TextStyle(color: WfStyle.muted),
            ),
            const SizedBox(height: 16),
            Text(
              a['primary_text'] == '' ? 'Your primary text' : a['primary_text'],
            ),
            const SizedBox(height: 14),
            if (_imageId != null)
              FunnelPrivateImage(
                key: ValueKey(
                  '${widget.funnelId}:${widget.campaignId}:$_imageId',
                ),
                client: widget.client,
                id: _imageId!,
                description: a['image_alt'],
                height: 240,
              )
            else
              const SizedBox(
                height: 130,
                child: Center(
                  child: Icon(Icons.add_photo_alternate_outlined, size: 44),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              a['headline'] == '' ? 'Your headline' : a['headline'],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (a['description'] != '') Text(a['description']),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(Uri.parse(s['landing_page']['destination']).host),
                Chip(label: Text(metaCreativeCtas[_cta]!)),
              ],
            ),
          ],
        ),
      ),
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
                spacing: 24,
                runSpacing: 8,
                children: [
                  const Text(
                    'Meta ad creative',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _close,
                    child: const Text('Close'),
                  ),
                ],
              ),
              const Text(
                'Prepare a single-image ad draft with its text, button preference and landing page.',
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
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: WfStyle.gold),
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!),
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
                        : 'DRAFT OUT OF DATE',
                  ),
                  if (_data!['draft_current'] == false && _data!['version'] > 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'The campaign, Page identity or landing page changed. Compare the saved context below, then save the draft against the current setup.',
                      ),
                    ),
                  if (_data!['editable'] == false)
                    const Text(
                      'This campaign is archived. Reopen it to edit the draft.',
                    ),
                  _section('Ad text'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'These are KORLIX preparation limits. Text display and button availability depend on the eventual Meta placement and objective.',
                    ),
                  ),
                  _field(_primary, 'Primary text', 1000),
                  _field(_headline, 'Headline', 100),
                  _field(_description, 'Description (optional)', 200),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_cta),
                    initialValue: _cta,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Button preference',
                    ),
                    items: metaCreativeCtas.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: _editable
                        ? (v) {
                            if (v != null) {
                              setState(() => _cta = v);
                              _changed();
                            }
                          }
                        : null,
                  ),
                  _section('Image'),
                  const Text(
                    'Choose a private KORLIX image. The optimized preview stays in your library; Meta upload and placement checks happen at launch preparation.',
                  ),
                  const SizedBox(height: 12),
                  if (_selectedImage != null)
                    Text(
                      '${_selectedImage!['label']} · ${_selectedImage!['width']} × ${_selectedImage!['height']}',
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _editable ? _chooseImages : null,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose image'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _editable ? _upload : null,
                        icon: const Icon(Icons.upload),
                        label: const Text('Upload image'),
                      ),
                      if (_imageId != null)
                        TextButton(
                          onPressed: _editable
                              ? () {
                                  setState(() {
                                    _imageId = null;
                                    _selectedImage = null;
                                    _alt.clear();
                                    _dirty = true;
                                  });
                                }
                              : null,
                          child: const Text('Remove image'),
                        ),
                    ],
                  ),
                  if (_images != null) ...[
                    if (_images!.isEmpty)
                      const Text(
                        'Your image library is empty. Upload an image to begin.',
                      ),
                    for (final image in _images!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(image['label']),
                        subtitle: Text(
                          '${image['width']} × ${image['height']}',
                        ),
                        trailing: OutlinedButton(
                          onPressed: _editable ? () => _select(image) : null,
                          child: const Text('Use image'),
                        ),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _images = null),
                      child: const Text('Hide image library'),
                    ),
                  ],
                  if (_imageId != null) _field(_alt, 'Image description', 180),
                  _section('Preview'),
                  _preview(),
                  _section('Current destination'),
                  SelectableText(
                    _data!['setup']['current_snapshot']['landing_page']['destination'],
                  ),
                  if (_data!['saved_context'] != null)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Context when last saved'),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Campaign: ${_data!['saved_context']['campaign']['name']}',
                              ),
                              Text(
                                'Facebook Page: ${_data!['saved_context']['meta']['page']?['name'] ?? 'Not selected'}',
                              ),
                              Text(
                                'Ad account: ${_data!['saved_context']['meta']['account']?['name'] ?? 'Not selected'}',
                              ),
                              SelectableText(
                                _data!['saved_context']['landing_page']['destination'],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'A complete draft needs primary text, a headline, an image and its description. Saving stores it privately. Meta approval, image upload, targeting, placement and launch remain separate.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _editable && _assetsValid(_assets)
                            ? _save
                            : null,
                        child: const Text('Save Meta draft'),
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
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: Text(
                    _conflict ? 'Reload after conflict' : 'Reload saved draft',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
