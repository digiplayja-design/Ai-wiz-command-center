import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' as ip;
import 'babyblend_client.dart';
import 'babyblend_saver.dart';

const _ink = Color(0xFF152D46),
    _teal = Color(0xFF087E91),
    _muted = Color(0xFF64748B),
    _line = Color(0xFFE3EAF2);
const _ages = {'baby': 'Baby', 'toddler': 'Toddler', 'child': 'Child'};
const _styles = {
  'natural': 'Natural photo',
  'studio': 'Studio',
  'artistic': 'Artistic',
};
List<Map<String, dynamic>> _rows(dynamic v) => v is List
    ? v.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
    : [];

class BabyBlendScreen extends StatefulWidget {
  const BabyBlendScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.pickPhoto,
    this.saveFile,
  });
  final BabyBlendClient client;
  final Future<bool> Function() ensureConsent;
  final Future<BabyBlendPhoto?> Function(bool camera)? pickPhoto;
  final Future<void> Function(Uint8List bytes, String name, String mime)?
  saveFile;
  @override
  State<BabyBlendScreen> createState() => _BabyBlendScreenState();
}

class _BabyBlendScreenState extends State<BabyBlendScreen> {
  List<Map<String, dynamic>> _assets = [];
  List<String?> _selected = [null, null];
  Map<String, dynamic>? _job;
  String _age = 'baby', _style = 'natural';
  String? _portrait, _error, _requestKey;
  bool _loading = true,
      _busy = false,
      _refreshing = false,
      _locked = false,
      _permission = false,
      _dialogOpen = false;
  int _tab = 0;
  Timer? _timer;
  bool get _running => _job?['state'] == 'running';
  bool get _working => _busy || _running || _refreshing;
  List<Map<String, dynamic>> get _sources =>
      _assets.where((a) => a['kind'] == 'source').toList();
  List<Map<String, dynamic>> get _portraits =>
      _assets.where((a) => a['kind'] == 'portrait').toList();
  Map<String, dynamic>? _asset(String? id) =>
      _assets.where((a) => a['id'] == id && a['state'] == 'ready').firstOrNull;
  String? get _disabledReason {
    if (_running) {
      return 'KORLIX is creating your portrait. You can leave and return.';
    }
    if (_asset(_selected[0]) == null) {
      return 'Add a clear adult photo for Person 1.';
    }
    if (_asset(_selected[1]) == null) {
      return 'Add a different adult photo for Person 2.';
    }
    if (_selected[0] == _selected[1]) {
      return 'Choose a different photo for each person.';
    }
    if (!_permission) {
      return 'Confirm permission to use both adult photos below.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_load(restore: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _timer?.cancel();
    if (_dialogOpen) Navigator.of(context).pop();
    setState(() {
      _locked = true;
      _assets = [];
      _selected = [null, null];
      _job = null;
      _portrait = _error = _requestKey = null;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  void _message(String s) {
    if (mounted && !_locked) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s)));
    }
  }

  void _changed() {
    _portrait = null;
    _requestKey = null;
    _error = null;
    if (!_running) _job = null;
  }

  Future<void> _load({bool restore = false}) async {
    if (_locked || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final r = await widget.client.load();
      if (!mounted || _locked) return;
      final jobs = _rows(r['jobs']);
      setState(() {
        _assets = _rows(r['assets']);
        _loading = false;
        _error = null;
        final running = jobs.where((j) => j['state'] == 'running').firstOrNull;
        if (running != null) {
          _job = running;
          _selected = List<String?>.from(running['photoIds']);
          _age = running['age'];
          _style = running['style'];
          _portrait = null;
        } else if (_job != null) {
          _job = jobs.where((j) => j['id'] == _job!['id']).firstOrNull ?? _job;
          if (_job?['state'] == 'completed') {
            _portrait = _asset(_job!['id'])?['id'];
          }
          if (_job?['state'] == 'failed') _error = _job!['error']?.toString();
        }
        if (restore && running == null) {
          final last = jobs
              .where(
                (j) => j['state'] == 'completed' && _asset(j['id']) != null,
              )
              .firstOrNull;
          if (last != null) {
            _job = last;
            _selected = List<String?>.from(last['photoIds']);
            _age = last['age'];
            _style = last['style'];
            _portrait = last['id'];
          } else {
            final ready = _sources.where((a) => a['state'] == 'ready').toList();
            for (var i = 0; i < 2 && i < ready.length; i++) {
              _selected[i] = ready[i]['id'];
            }
          }
        }
        for (var i = 0; i < 2; i++) {
          if (_asset(_selected[i]) == null) _selected[i] = null;
        }
      });
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (mounted && !_locked && _running) {
      _timer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    if (_locked || !_running) return;
    final id = _job!['id'] as String;
    try {
      final r = await widget.client.job(id);
      if (!mounted || _locked || _job?['id'] != id) return;
      setState(() {
        _job = Map<String, dynamic>.from(r['job']);
        _error = null;
        if (r['asset'] is Map) {
          final a = Map<String, dynamic>.from(r['asset']);
          _assets.removeWhere((x) => x['id'] == a['id']);
          _assets.insert(0, a);
          _portrait = a['id'];
        }
        if (!_running) {
          _requestKey = null;
          if (_job?['state'] == 'failed') {
            _error =
                _job!['error']?.toString() ??
                'This portrait could not finish. No credit was charged.';
          }
        }
      });
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      _schedule();
    }
  }

  Future<void> _start() async {
    if (_working || _locked || _disabledReason != null) return;
    setState(() => _busy = true);
    try {
      if (!await widget.ensureConsent() || !mounted || _locked) return;
      final key = _requestKey ??= babyBlendRequestKey();
      final j = await widget.client.start(
        key: key,
        photoIds: _selected.cast<String>(),
        age: _age,
        style: _style,
      );
      if (!mounted || _locked) return;
      setState(() {
        _job = j;
        _portrait = null;
        _error = null;
      });
      if (j['state'] == 'running') {
        _schedule();
      } else {
        _requestKey = null;
        await _load();
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<BabyBlendPhoto?> _pick(bool camera) async {
    if (widget.pickPhoto != null) return widget.pickPhoto!(camera);
    if (camera) {
      final f = await ip.ImagePicker().pickImage(
        source: ip.ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 94,
      );
      if (f == null) return null;
      if (await f.length() > 15 * 1024 * 1024) {
        throw const BabyBlendException('Choose a photo under 15 MB.');
      }
      return BabyBlendPhoto(f.name, await f.readAsBytes());
    }
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: false,
      withReadStream: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    if (f.size > 15 * 1024 * 1024) {
      throw const BabyBlendException('Choose a photo under 15 MB.');
    }
    if (f.bytes != null) return BabyBlendPhoto(f.name, f.bytes!);
    if (f.readStream == null) {
      throw const BabyBlendException('Please choose this photo again.');
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in f.readStream!) {
      if (b.length + chunk.length > 15 * 1024 * 1024) {
        throw const BabyBlendException('Choose a photo under 15 MB.');
      }
      b.add(chunk);
    }
    return BabyBlendPhoto(f.name, b.takeBytes());
  }

  Future<void> _choose(int index) async {
    if (_working || _locked) return;
    _dialogOpen = true;
    try {
      final id = await showDialog<String>(
        context: context,
        builder: (c) => _PhotoDialog(
          index: index,
          existing: _sources
              .where(
                (a) => a['state'] == 'ready' && a['id'] != _selected[1 - index],
              )
              .toList(),
          pick: _pick,
          upload: widget.client.upload,
          isLocked: () => _locked,
        ),
      );
      if (id != null && mounted && !_locked) {
        await _load();
        if (!mounted || _locked) return;
        setState(() {
          _selected[index] = id;
          _changed();
        });
      }
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _remove(Map<String, dynamic> a) async {
    if (_working || _locked) return;
    _dialogOpen = true;
    bool confirmed = false;
    try {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Remove this photo?'),
              content: Text(
                a['kind'] == 'source'
                    ? 'This removes this saved reference. Existing portraits remain available.'
                    : 'This permanently removes this portrait from your private gallery. Downloaded copies remain on your device.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Remove'),
                ),
              ],
            ),
          ) ??
          false;
    } finally {
      _dialogOpen = false;
    }
    if (!confirmed || !mounted || _locked) return;
    setState(() => _busy = true);
    try {
      await widget.client.remove(a['id']);
      if (!mounted || _locked) return;
      setState(() {
        _assets.removeWhere((x) => x['id'] == a['id']);
        for (var i = 0; i < 2; i++) {
          if (_selected[i] == a['id']) _selected[i] = null;
        }
        if (_portrait == a['id']) _portrait = null;
        _requestKey = null;
        _error = null;
      });
      _message('Photo removed.');
    } catch (e) {
      await _load();
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String id) async {
    if (_busy || _locked) return;
    setState(() => _busy = true);
    try {
      final b = await widget.client.imageBytes(id);
      if (!mounted || _locked) return;
      await (widget.saveFile ?? saveBabyBlendFile)(
        b,
        'KORLIX-BabyBlend-$id.png',
        'image/png',
      );
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photo(Map<String, dynamic>? a, {bool full = false}) {
    final url = a?[full ? 'imageUrl' : 'thumbnailUrl'];
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: url is String && url.isNotEmpty
          ? Image.network(
              url,
              fit: full ? BoxFit.contain : BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, e, s) => const Center(
                child: Icon(Icons.image_outlined, color: _muted, size: 42),
              ),
            )
          : const Center(
              child: Icon(Icons.add_a_photo_outlined, size: 38, color: _teal),
            ),
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(24),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x080D3150),
          blurRadius: 28,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _title(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: _ink,
    ),
  );
  Widget _badge(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F8FA),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: _teal),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _teal,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _reference(int index) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Person ${index + 1}',
          style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 10),
        AspectRatio(
          aspectRatio: .92,
          child: Material(
            color: const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: ValueKey('photo-${index + 1}'),
              onTap: _working ? null : () => _choose(index),
              borderRadius: BorderRadius.circular(18),
              child: _photo(_asset(_selected[index])),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _working ? null : () => _choose(index),
          icon: Icon(
            _asset(_selected[index]) == null ? Icons.add : Icons.swap_horiz,
            size: 17,
          ),
          label: Text(
            _asset(_selected[index]) == null ? 'Add photo' : 'Replace',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
  Widget _choices(
    Map<String, String> choices,
    String value,
    void Function(String) select,
  ) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: choices.entries
        .map(
          (e) => ChoiceChip(
            label: Text(e.value),
            selected: value == e.key,
            onSelected: _working
                ? null
                : (_) => setState(() {
                    select(e.key);
                    _changed();
                  }),
            selectedColor: const Color(0xFFE0F5F7),
            backgroundColor: Colors.white,
            side: BorderSide(color: value == e.key ? _teal : _line),
            labelStyle: TextStyle(
              color: value == e.key ? _teal : _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
        .toList(),
  );
  Widget _controls() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Start with two photos'),
        const SizedBox(height: 7),
        const Text(
          'One clear, front-facing adult in each photo.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _reference(0),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9),
              child: Icon(Icons.add_rounded, color: _teal, size: 22),
            ),
            _reference(1),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Imagine an age',
          style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 9),
        _choices(_ages, _age, (v) => _age = v),
        const SizedBox(height: 20),
        const Text(
          'Choose a look',
          style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 9),
        _choices(_styles, _style, (v) => _style = v),
        const SizedBox(height: 16),
        CheckboxListTile(
          key: const ValueKey('photo-permission'),
          value: _permission,
          onChanged: _working
              ? null
              : (v) => setState(() => _permission = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: _teal,
          title: const Text(
            'Both people are adults and I have permission to use these photos.',
            style: TextStyle(fontSize: 13, color: _muted),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('create-babyblend'),
            onPressed: _working || _disabledReason != null ? null : _start,
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              padding: const EdgeInsets.symmetric(vertical: 19),
            ),
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 20),
            label: Text(
              _running ? 'Creating your portrait…' : 'Create BabyBlend',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_disabledReason != null)
          Text(
            _disabledReason!,
            key: const ValueKey('disabled-reason'),
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        const SizedBox(height: 7),
        const Text(
          '1 credit per completed portrait · Ultra Premium & Enterprise',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );
  Widget _result() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _title(
                _portrait != null
                    ? 'Your little possibility'
                    : 'A little possibility awaits',
              ),
            ),
            _badge('Private', Icons.lock_outline),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          height: _portrait != null ? 480 : null,
          constraints: const BoxConstraints(minHeight: 480),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF2EFFF), Color(0xFFFFF4EE), Color(0xFFECFAFC)],
            ),
          ),
          child: _portrait != null
              ? _photo(_asset(_portrait), full: true)
              : Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_running)
                        const CircularProgressIndicator(color: _teal)
                      else
                        const Icon(
                          Icons.favorite_border_rounded,
                          size: 58,
                          color: _teal,
                        ),
                      const SizedBox(height: 22),
                      Text(
                        _running
                            ? 'KORLIX is imagining…'
                            : 'Two faces. Endless wonder.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _running
                            ? 'Your photos are becoming a unique fictional portrait. It can take a few minutes. Your progress is saved.'
                            : 'Add two adult photos and discover a playful portrait inspired by both.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _muted, height: 1.6),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 16),
        if (_portrait != null) ...[
          Text(
            '${_ages[_asset(_portrait)?['details']?['age']] ?? 'Portrait'} · ${_styles[_asset(_portrait)?['details']?['style']] ?? 'AI imagining'}',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _save(_portrait!),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Save portrait'),
              ),
              OutlinedButton.icon(
                onPressed: _working || _disabledReason != null ? null : _start,
                icon: const Icon(Icons.refresh),
                label: const Text('Try another look'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'For creative fun. Not a genetic prediction.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
  Widget _gallery() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('My portraits'),
      const SizedBox(height: 7),
      const Text(
        'Your private collection of little possibilities.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 18),
      if (_portraits.isEmpty)
        _card(
          child: const Padding(
            padding: EdgeInsets.all(28),
            child: Text(
              'Your first portrait will appear here. Create a BabyBlend to get started.',
              style: TextStyle(color: _muted),
            ),
          ),
        ),
      LayoutBuilder(
        builder: (c, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 650
              ? 3
              : 2;
          final w = (constraints.maxWidth - (columns - 1) * 14) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 16,
            children: _portraits
                .map(
                  (a) => SizedBox(
                    width: w,
                    child: _card(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 2 / 3,
                            child: InkWell(
                              onTap: a['state'] != 'ready' || _running
                                  ? null
                                  : () => setState(() {
                                      _portrait = a['id'];
                                      final details = a['details'];
                                      _selected =
                                          List<String?>.from(
                                                details['photoIds'],
                                              )
                                              .map(
                                                (id) => _asset(id) == null
                                                    ? null
                                                    : id,
                                              )
                                              .toList();
                                      _age = details['age'];
                                      _style = details['style'];
                                      _job = null;
                                      _requestKey = null;
                                      _permission = false;
                                      _tab = 0;
                                    }),
                              child: a['state'] == 'ready'
                                  ? _photo(a)
                                  : const Center(
                                      child: Text(
                                        'Incomplete portrait',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${_ages[a['details']?['age']] ?? 'Portrait'} · ${_styles[a['details']?['style']] ?? 'AI imagining'}',
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: 'Save portrait',
                                onPressed: a['state'] == 'ready' && !_busy
                                    ? () => _save(a['id'])
                                    : null,
                                icon: const Icon(Icons.download_outlined),
                              ),
                              IconButton(
                                tooltip: 'Remove portrait',
                                onPressed: _working ? null : () => _remove(a),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 32),
      _title('Saved reference photos'),
      const SizedBox(height: 7),
      const Text(
        'Manage the photos you can use in another blend. Up to 10 references and 50 portraits.',
        style: TextStyle(color: _muted),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _sources
            .map(
              (a) => SizedBox(
                width: 130,
                child: _card(
                  padding: const EdgeInsets.all(9),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 125,
                        child: a['state'] == 'ready'
                            ? _photo(a)
                            : const Center(
                                child: Text(
                                  'Incomplete upload',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                      ),
                      IconButton(
                        tooltip: 'Remove reference photo',
                        onPressed: _working ? null : () => _remove(a),
                        icon: const Icon(Icons.delete_outline, color: _muted),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 24),
      const Text(
        'Photos are stored in your account gallery. When you create a portrait, both references are sent to OpenAI with your permission. Downloaded or shared copies are separate; removing a gallery item does not recall those copies or earlier provider processing.',
        style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: _teal),
      scaffoldBackgroundColor: Colors.white,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    ),
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Row(
          children: [
            Image.asset(
              'assets/branding/korlix_mini_mark.png',
              width: 29,
              height: 29,
            ),
            const SizedBox(width: 10),
            const Flexible(
              child: Text(
                'KORLIX BabyBlend',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh BabyBlend',
            onPressed: _busy || _refreshing || _locked ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _locked
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your session changed. Close this screen, sign in and reopen BabyBlend.',
                ),
              ),
            )
          : _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFAFCFF), Colors.white, Color(0xFFF7F4FF)],
                ),
              ),
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Padding(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 18 : 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _badge(
                                'A little imagination, by KORLIX',
                                Icons.auto_awesome_outlined,
                              ),
                              _badge('Private by default', Icons.lock_outline),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'BabyBlend',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.5,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Two faces. A little imagination.',
                            style: TextStyle(fontSize: 20, color: _muted),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 10,
                            children: [
                              ChoiceChip(
                                label: const Text('Create'),
                                selected: _tab == 0,
                                onSelected: (_) => setState(() => _tab = 0),
                              ),
                              ChoiceChip(
                                label: Text(
                                  'My portraits (${_portraits.where((a) => a['state'] == 'ready').length})',
                                ),
                                selected: _tab == 1,
                                onSelected: (_) => setState(() => _tab = 1),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          if (_error != null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF0E9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFF8A3E19),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_tab == 1)
                            _gallery()
                          else
                            LayoutBuilder(
                              builder: (c, s) => s.maxWidth >= 840
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(flex: 5, child: _controls()),
                                        const SizedBox(width: 24),
                                        Expanded(flex: 6, child: _result()),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _controls(),
                                        const SizedBox(height: 22),
                                        _result(),
                                      ],
                                    ),
                            ),
                          const SizedBox(height: 26),
                          const Center(
                            child: Text(
                              'AI imagining · Every blend is unique',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

class _PhotoDialog extends StatefulWidget {
  const _PhotoDialog({
    required this.index,
    required this.existing,
    required this.pick,
    required this.upload,
    required this.isLocked,
  });
  final int index;
  final List<Map<String, dynamic>> existing;
  final Future<BabyBlendPhoto?> Function(bool) pick;
  final Future<Map<String, dynamic>> Function(BabyBlendPhoto, String) upload;
  final bool Function() isLocked;
  @override
  State<_PhotoDialog> createState() => _PhotoDialogState();
}

class _PhotoDialogState extends State<_PhotoDialog> {
  BabyBlendPhoto? _photo;
  String? _key, _error;
  bool _busy = false;
  Future<void> _pick(bool camera) async {
    if (_busy || widget.isLocked()) return;
    setState(() => _busy = true);
    try {
      final p = await widget.pick(camera);
      if (!mounted || widget.isLocked()) return;
      if (p != null) {
        if (p.bytes.isEmpty || p.bytes.length > 15 * 1024 * 1024) {
          throw const BabyBlendException('Choose a photo under 15 MB.');
        }
        setState(() {
          _photo = p;
          _key = babyBlendRequestKey();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !widget.isLocked()) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_photo == null || _busy || widget.isLocked()) return;
    setState(() => _busy = true);
    try {
      final a = await widget.upload(_photo!, _key!);
      if (mounted && !widget.isLocked()) Navigator.pop(context, a['id']);
    } catch (e) {
      if (mounted && !widget.isLocked()) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text('Person ${widget.index + 1} photo'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a clear photo of one adult. JPG, PNG or WEBP · Up to 15 MB.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Camera'),
                  ),
                ],
              ),
              if (_photo != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    _photo!.bytes,
                    height: 220,
                    fit: BoxFit.contain,
                    errorBuilder: (_, e, s) => const Text(
                      'Preview unavailable. Choose a supported photo.',
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
              ],
              if (widget.existing.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Or use a saved reference'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.existing
                      .map(
                        (a) => InkWell(
                          onTap: _busy
                              ? null
                              : () => Navigator.pop(context, a['id']),
                          child: SizedBox(
                            width: 76,
                            height: 90,
                            child: Image.network(
                              a['thumbnailUrl'] ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (_, e, s) =>
                                  const Icon(Icons.person_outline),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _photo == null ? null : _upload,
          child: Text(_busy ? 'Saving…' : 'Use this photo'),
        ),
      ],
    ),
  );
}
