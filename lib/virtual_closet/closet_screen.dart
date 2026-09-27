import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;
import '../improve_picture/picture_studio_client.dart';
import '../korlix_image_saver.dart';
import 'closet_client.dart';

const _navy = Color(0xFF082C41),
    _cyan = Color(0xFF007BA8),
    _line = Color(0xFFDCE7EC),
    _muted = Color(0xFF526C7C);
const _categories = {
  'tops': 'Tops',
  'bottoms': 'Bottoms',
  'dresses': 'Dresses',
  'outerwear': 'Outerwear',
  'shoes': 'Shoes',
  'accessories': 'Accessories',
};

class VirtualClosetScreen extends StatefulWidget {
  const VirtualClosetScreen({
    super.key,
    required this.client,
    required this.ensureConsent,
    this.disposeClient = true,
    this.pickFile,
    this.saveImage,
  });
  final ClosetClient client;
  final Future<bool> Function() ensureConsent;
  final bool disposeClient;
  final Future<PlatformFile?> Function()? pickFile;
  final Future<void> Function(Uint8List, String)? saveImage;
  @override
  State<VirtualClosetScreen> createState() => _VirtualClosetScreenState();
}

class _VirtualClosetScreenState extends State<VirtualClosetScreen> {
  final _search = TextEditingController(), _occasion = TextEditingController();
  List<ClosetAsset> _assets = [];
  final Set<String> _selected = {};
  String? _photoId, _lookId, _lookSourceId, _error, _notice;
  String
  _filter = 'all',
  _nova =
      'Tell me the occasion, mood, or dress code. I’ll suggest an outfit from your closet.';
  bool _loading = true,
      _busy = false,
      _locked = false,
      _before = false,
      _polling = false,
      _refreshing = false;
  int _tab = 0;
  ClosetJob? _job;
  Timer? _pollTimer, _refreshTimer;
  Future<void> Function()? _retryUpload;
  String? _pendingKey, _pendingSignature;
  bool get _working => _busy || (_job?.running ?? false);
  bool get _photoReady =>
      _asset(_photoId)?.kind == 'photo' && (_asset(_photoId)?.ready ?? false);
  List<ClosetAsset> get _outfit => _assets
      .where((a) => a.kind == 'garment' && a.ready && _selected.contains(a.id))
      .toList();
  bool get _canTryOn =>
      !_locked &&
      !_loading &&
      !_working &&
      _photoReady &&
      _outfit.isNotEmpty &&
      _outfit.length <= 4 &&
      _outfit.length == _selected.length;
  String get _tryOnStatus {
    if (_job?.running ?? false) {
      return 'KORLIX is working on your current request.';
    }
    if (_busy) return 'Finishing your current action…';
    if (!_photoReady && _outfit.isEmpty) {
      return 'Add your photo and choose at least one clothing item.';
    }
    if (!_photoReady) return 'Add a photo of yourself to continue.';
    if (_outfit.isEmpty) {
      return 'Choose at least one clothing item from My wardrobe.';
    }
    if (!_canTryOn) return 'Refresh your closet to check the selected items.';
    return 'Ready to try on';
  }

  List<ClosetAsset> get _garments =>
      _assets.where((a) => a.kind == 'garment').toList();
  List<ClosetAsset> get _photos =>
      _assets.where((a) => a.kind == 'photo' && a.ready).toList();
  List<ClosetAsset> get _looks =>
      _assets.where((a) => a.kind == 'look').toList();
  ClosetAsset? _asset(String? id) {
    for (final a in _assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.client.onAccessDenied = _lock;
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 8),
      (_) => unawaited(_refresh(quiet: true)),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    _search.dispose();
    _occasion.dispose();
    widget.client.onAccessDenied = null;
    if (widget.disposeClient) widget.client.dispose();
    super.dispose();
  }

  void _lock() {
    if (!mounted) return;
    _pollTimer?.cancel();
    _refreshTimer?.cancel();
    setState(() {
      _locked = true;
      _assets = [];
      _selected.clear();
      _photoId = null;
      _lookId = null;
      _lookSourceId = null;
      _job = null;
      _retryUpload = null;
      _occasion.clear();
      _search.clear();
      _nova = '';
      _error = null;
    });
  }

  Future<void> _refresh({bool quiet = false}) async {
    if (_locked || _refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await widget.client.load();
      if (!mounted || _locked) return;
      setState(() {
        _assets = snapshot.assets;
        _loading = false;
        _selected.removeWhere(
          (id) => !_assets.any((a) => a.id == id && a.ready),
        );
        if (!_photoReady) _photoId = _photos.firstOrNull?.id;
        if (!quiet) _error = null;
        final running = snapshot.jobs.where((j) => j.running).firstOrNull;
        if (running != null) {
          _job = running;
          _photoId = running.photoId ?? _photoId;
          if (running.kind == 'tryon') {
            _selected
              ..clear()
              ..addAll(running.garmentIds);
          }
        } else if (_job == null && snapshot.jobs.isNotEmpty) {
          final latest = snapshot.jobs.first;
          if (latest.state == 'completed') {
            _showResult(latest);
          } else if (latest.state == 'failed') {
            _notice = latest.error;
          }
        }
      });
      if (_job?.running ?? false) _schedulePoll();
    } catch (e) {
      if (mounted && !_locked) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _showResult(ClosetJob job) {
    if (job.kind == 'tryon') {
      _lookId = job.result['asset_id'] as String?;
      _lookSourceId = _asset(job.photoId)?.id;
      _photoId = _lookSourceId ?? _photoId;
      _before = false;
      _notice = 'Your preview is saved in Saved Looks.';
    } else {
      _nova = job.result['message']?.toString() ?? 'Your suggestion is ready.';
      _selected
        ..clear()
        ..addAll(
          List<String>.from(
            job.result['garmentIds'] as List? ?? [],
          ).where((id) => _assets.any((a) => a.id == id && a.ready)),
        );
      _lookId = null;
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (mounted && !_locked && (_job?.running ?? false)) {
      _pollTimer = Timer(const Duration(seconds: 3), () => unawaited(_poll()));
    }
  }

  Future<void> _poll() async {
    if (_polling || _locked || !(_job?.running ?? false)) return;
    _polling = true;
    try {
      final job = await widget.client.job(_job!.id);
      if (!mounted || _locked) return;
      if (!job.running) {
        final snapshot = await widget.client.load();
        if (!mounted || _locked) return;
        setState(() {
          _assets = snapshot.assets;
          _job = job;
          _pendingKey = null;
          _pendingSignature = null;
          _error = job.state == 'failed' ? job.error : null;
          if (job.state == 'completed') _showResult(job);
        });
      } else {
        setState(() {
          _job = job;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !_locked) {
        setState(
          () => _error =
              '${e.toString()} Your session remains saved; refresh to check it.',
        );
      }
    } finally {
      _polling = false;
      _schedulePoll();
    }
  }

  Future<PlatformFile?> _pick({bool camera = false}) async {
    if (widget.pickFile != null) return widget.pickFile!();
    if (camera) {
      final x = await ip.ImagePicker().pickImage(source: ip.ImageSource.camera);
      if (x == null) return null;
      final b = await x.readAsBytes();
      return PlatformFile(name: x.name, size: b.length, bytes: b);
    }
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    return r?.files.firstOrNull;
  }

  Future<void> _add(String kind, {bool camera = false}) async {
    if (_working || _locked) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final file = await _pick(camera: camera);
      if (file == null || !mounted || _locked) return;
      final problem = pictureFileError(file);
      if (problem != null) throw ClosetException(problem);
      String name = 'My photo', category = 'photo';
      if (kind == 'garment') {
        final value = await showDialog<(String, String)>(
          context: context,
          builder: (_) => _GarmentDetails(
            initialName: file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          ),
        );
        if (value == null || !mounted || _locked) return;
        name = value.$1;
        category = value.$2;
      }
      final key = closetRequestKey();
      Future<void> send() async {
        if (!mounted || _locked) return;
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          final a = await widget.client.upload(
            file: file,
            key: key,
            kind: kind,
            name: name,
            category: category,
          );
          if (!mounted || _locked) return;
          setState(() {
            _assets.removeWhere((x) => x.id == a.id);
            _assets.insert(0, a);
            if (kind == 'photo') {
              _photoId = a.id;
              _lookId = null;
              _lookSourceId = null;
              _before = false;
              _tab = 1;
            } else if (a.ready) {
              if (_selected.length < 4) _selected.add(a.id);
              _lookId = null;
              _before = false;
              _filter = 'all';
              _search.clear();
            }
            _retryUpload = null;
            _notice = kind == 'garment' && a.ready
                ? _selected.contains(a.id)
                      ? '${a.name} saved and selected for try-on.'
                      : '${a.name} saved. Four items are already selected; unselect one to include it.'
                : '${a.name} saved to your private closet.';
          });
        } catch (e) {
          if (mounted && !_locked) {
            setState(() {
              _error = e.toString();
              _retryUpload = send;
            });
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }

      await send();
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ClosetAsset a) async {
    if (_working || _locked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${a.name}?'),
        content: const Text(
          'This removes the image from your closet. Existing saved looks stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _locked) return;
    setState(() => _busy = true);
    try {
      await widget.client.remove(a.id);
      if (!mounted || _locked) return;
      setState(() {
        _assets.removeWhere((x) => x.id == a.id);
        _selected.remove(a.id);
        if (_photoId == a.id) _photoId = _photos.firstOrNull?.id;
        if (_lookSourceId == a.id) {
          _lookSourceId = null;
          _before = false;
        }
        if (_lookId == a.id) _lookId = null;
        _error = null;
      });
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(String kind) async {
    if (_working || _locked) return;
    if (kind == 'tryon' && !_canTryOn) {
      setState(
        () =>
            _error = 'Upload your photo and select one to four wardrobe items.',
      );
      return;
    }
    if (kind == 'style' &&
        (_occasion.text.trim().isEmpty || !_garments.any((a) => a.ready))) {
      setState(
        () => _error = 'Add a wardrobe item and tell KORLIX the occasion first.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (!await widget.ensureConsent() || !mounted || _locked) return;
      final signature =
          '$kind|$_photoId|${(_selected.toList()..sort()).join(',')}|${_occasion.text.trim()}';
      if (_pendingSignature != signature) {
        _pendingSignature = signature;
        _pendingKey = closetRequestKey();
      }
      final j = await widget.client.start(
        key: _pendingKey!,
        kind: kind,
        prompt: _occasion.text.trim(),
        photoId: _photoId,
        garmentIds: _selected.toList(),
      );
      if (!mounted || _locked) return;
      setState(() => _job = j);
      if (j.running) {
        _schedulePoll();
      } else {
        await _refresh(quiet: true);
        if (mounted && !_locked) {
          setState(() {
            if (j.state == 'completed') {
              _showResult(j);
            } else {
              _error = j.error;
            }
            _pendingKey = null;
            _pendingSignature = null;
          });
        }
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final a = _asset(_lookId);
    if (a == null || _busy || _locked) return;
    setState(() => _busy = true);
    try {
      final b = await widget.client.imageBytes(a.id);
      if (!mounted || _locked) return;
      if (widget.saveImage != null) {
        await widget.saveImage!(b, 'KORLIX-look.png');
      } else {
        await saveKorlixGeneratedImage(
          bytes: b,
          filename: 'KORLIX-look-${a.id}.png',
          mimeType: 'image/png',
        );
      }
      if (mounted && !_locked) {
        setState(
          () => _notice =
              'Your PNG is ready. Check your device downloads or share options.',
        );
      }
    } catch (e) {
      if (mounted && !_locked) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(18)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
  Widget _title(String title, IconData icon, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _cyan, size: 22),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _image(
    ClosetAsset? a, {
    bool thumbnail = false,
    BoxFit fit = BoxFit.contain,
  }) {
    final url = thumbnail ? a?.thumbnailUrl : a?.imageUrl;
    if (url == null) {
      return Center(
        child: Icon(
          a?.kind == 'garment' ? Icons.checkroom : Icons.person_outline,
          size: 64,
          color: _muted.withValues(alpha: .5),
        ),
      );
    }
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: false,
      errorBuilder: (_, _, _) => const Center(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Refresh to reload this photo',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted),
          ),
        ),
      ),
    );
  }

  Widget _empty(String title, String detail, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 46, color: _cyan),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );
  Widget _garmentCard(ClosetAsset a) {
    final selected = _selected.contains(a.id);
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: _working || !a.ready
            ? null
            : () => setState(() {
                if (selected) {
                  _selected.remove(a.id);
                } else if (_selected.length < 4) {
                  _selected.add(a.id);
                } else {
                  _error = 'Choose up to four items for one outfit.';
                }
                _lookId = null;
                _before = false;
              }),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _cyan : _line,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: const Color(0xFFF5F7F8),
                          child: _image(a, thumbnail: true),
                        ),
                      ),
                    ),
                    if (selected)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(Icons.check_circle, color: _cyan),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: IconButton(
                        tooltip: 'Remove ${a.name}',
                        onPressed: _working ? null : () => _remove(a),
                        icon: const Icon(Icons.close, size: 16),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: .9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  a.ready ? a.name : '${a.name} · ${a.state}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wardrobe() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'My wardrobe',
          Icons.checkroom,
          subtitle: '${_garments.length}/100 items · select up to 4',
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Search your closet',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: {'all': 'All', ..._categories}.entries
              .map(
                (e) => ChoiceChip(
                  label: Text(e.value),
                  selected: _filter == e.key,
                  onSelected: (_) => setState(() => _filter = e.key),
                  visualDensity: VisualDensity.compact,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_garments.isEmpty)
          _empty(
            'Your style starts here',
            'Add a clear photo of one clothing item. Give it a name and choose its category.',
            Icons.add_photo_alternate_outlined,
          )
        else
          Builder(
            builder: (c) {
              final rows = _garments
                  .where(
                    (a) =>
                        (_filter == 'all' || a.category == _filter) &&
                        a.name.toLowerCase().contains(
                          _search.text.toLowerCase(),
                        ),
                  )
                  .toList();
              return rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No items match your search.'),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            childAspectRatio: .73,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _garmentCard(rows[i]),
                    );
            },
          ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('closet-add-clothes'),
            onPressed: _working ? null : () => _add('garment'),
            icon: const Icon(Icons.add),
            label: const Text('Add clothes'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Photos are saved privately to your account.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );
  Widget _preview() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          _lookId != null ? 'Your saved preview' : 'Your outfit preview',
          Icons.auto_awesome_outlined,
        ),
        ..._assets
            .where((a) => a.kind == 'photo' && !a.ready)
            .map(
              (a) => ListTile(
                title: Text('${a.name} · ${a.state}'),
                subtitle: const Text(
                  'If this stays incomplete, remove it after three minutes and upload again.',
                ),
                trailing: IconButton(
                  tooltip: 'Remove ${a.name}',
                  onPressed: _working ? null : () => _remove(a),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        if (_photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _photos
                .map(
                  (p) => InputChip(
                    label: Text(p.name),
                    selected: p.id == _photoId,
                    onPressed: _working
                        ? null
                        : () => setState(() {
                            _photoId = p.id;
                            _lookId = null;
                          }),
                    onDeleted: _working ? null : () => _remove(p),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: const Color(0xFFF3F5F4),
            child: SizedBox(
              width: double.infinity,
              height: MediaQuery.sizeOf(context).width >= 1100 ? 420 : 440,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _photoId == null && _lookId == null
                        ? SingleChildScrollView(
                            child: _empty(
                              'Meet your virtual fitting room',
                              'Upload a clear, well-lit photo of yourself. A full-length photo works best for complete outfits.',
                              Icons.person_add_alt,
                            ),
                          )
                        : _image(
                            _asset(
                              _before ? _lookSourceId : (_lookId ?? _photoId),
                            ),
                          ),
                  ),
                  if (_photoId != null || _lookId != null)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Chip(
                        label: Text(
                          _lookId != null && !_before
                              ? 'AI preview'
                              : 'Your photo',
                        ),
                        avatar: Icon(
                          _lookId != null && !_before
                              ? Icons.auto_awesome
                              : Icons.person,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('closet-upload-photo'),
              onPressed: _working ? null : () => _add('photo'),
              icon: const Icon(Icons.upload_outlined),
              label: Text(
                _photos.isEmpty ? 'Upload your photo' : 'Add another photo',
              ),
            ),
            IconButton(
              tooltip: 'Take a photo',
              onPressed: _working ? null : () => _add('photo', camera: true),
              icon: const Icon(Icons.camera_alt_outlined),
            ),
            if (_lookId != null && _asset(_lookSourceId) != null)
              FilterChip(
                label: const Text('Before'),
                selected: _before,
                onSelected: (v) => setState(() => _before = v),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Row(
            key: const Key('closet-try-on-status'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _canTryOn ? Icons.check_circle : Icons.info_outline,
                size: 20,
                color: _canTryOn ? _cyan : _muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tryOnStatus,
                  style: TextStyle(
                    color: _canTryOn ? _cyan : _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_outfit.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _outfit
                .map(
                  (a) => InputChip(
                    label: Text(a.name),
                    avatar: const Icon(Icons.checkroom, size: 16),
                    deleteButtonTooltipMessage: 'Unselect ${a.name} for try-on',
                    onDeleted: _working
                        ? null
                        : () => setState(() {
                            _selected.remove(a.id);
                            _lookId = null;
                            _before = false;
                          }),
                  ),
                )
                .toList(),
          ),
        ] else if (MediaQuery.sizeOf(context).width < 1100)
          TextButton.icon(
            onPressed: _working ? null : () => setState(() => _tab = 0),
            icon: const Icon(Icons.checkroom),
            label: const Text('Choose clothes'),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('closet-try-on'),
            onPressed: _canTryOn ? () => _start('tryon') : null,
            icon: const Icon(Icons.checkroom),
            label: Text(
              'Try it on${_selected.isNotEmpty ? ' · ${_selected.length} items' : ''}',
            ),
          ),
        ),
        if (_lookId != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _download,
              icon: const Icon(Icons.download),
              label: const Text('Download PNG'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        const Text(
          '1 credit per successful preview. Ultra Premium or Enterprise. Visual preview only; fit and likeness may vary.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );
  Widget _stylist() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'KORLIX · Your stylist',
          Icons.auto_awesome,
          subtitle: 'A fresh look from what you already own',
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFEDF8FC),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(_nova, style: const TextStyle(height: 1.5)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: ['Business lunch', 'Weekend casual', 'Wedding guest']
              .map(
                (v) => ActionChip(
                  label: Text(v),
                  onPressed: _working
                      ? null
                      : () => setState(
                          () => _occasion.text =
                              'Style me for a ${v.toLowerCase()}.',
                        ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('closet-style-prompt'),
          controller: _occasion,
          enabled: !_working,
          maxLength: 1500,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'What are you dressing for?',
            hintText: 'Occasion, colors, weather, or a look you love…',
            alignLabelWithHint: true,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('closet-ask-nova'),
            onPressed: _working ? null : () => _start('style'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Ask KORLIX'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '1 credit per successful suggestion. KORLIX selects up to four items you can try on together.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        if (_selected.isNotEmpty) ...[
          const Divider(height: 30),
          Text(
            'Selected outfit · ${_selected.length}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ..._selected
              .map((id) => _asset(id))
              .whereType<ClosetAsset>()
              .map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 44,
                          height: 48,
                          child: _image(a, thumbnail: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(a.name)),
                      IconButton(
                        tooltip: 'Unselect ${a.name}',
                        onPressed: _working
                            ? null
                            : () => setState(() {
                                _selected.remove(a.id);
                                _lookId = null;
                              }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    ),
  );
  Widget _saved() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          'Saved Looks',
          Icons.favorite_border,
          subtitle: '${_looks.length}/50 looks · saved automatically',
        ),
        if (_looks.isEmpty)
          _empty(
            'Your next favorite outfit belongs here',
            'Generate a try-on and it will be saved here automatically, ready to reopen or download.',
            Icons.favorite_border,
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              childAspectRatio: .58,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _looks.length,
            itemBuilder: (c, i) {
              final a = _looks[i];
              return Column(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: !a.ready
                          ? null
                          : () => setState(() {
                              _lookId = a.id;
                              _lookSourceId = null;
                              _before = false;
                              _tab = 1;
                            }),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _image(a),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.ready ? a.name : '${a.name} · ${a.state}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${a.name}',
                        onPressed: _working ? null : () => _remove(a),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: !a.ready
                        ? null
                        : () => setState(() {
                            _lookId = a.id;
                            _lookSourceId = null;
                            _before = false;
                            _tab = 1;
                          }),
                    child: Text(a.ready ? 'View look' : 'Incomplete upload'),
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );
  Widget _steps() => Wrap(
    spacing: 18,
    runSpacing: 8,
    children:
        [
              ('1', 'Upload photo', _photos.isNotEmpty),
              ('2', 'Choose outfit', _selected.isNotEmpty),
              ('3', 'Try it on', _lookId != null),
            ]
            .map(
              (s) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: s.$3 ? _navy : const Color(0xFFEAF3F8),
                    foregroundColor: s.$3 ? Colors.white : _navy,
                    child: Text(s.$1, style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    s.$2,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            )
            .toList(),
  );
  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _cyan,
          brightness: Brightness.light,
        ).copyWith(
          primary: _cyan,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: _navy,
        );
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF6F9FB),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF9FBFD),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _line),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: _navy,
          displayColor: _navy,
        ),
      ),
      child: Builder(
        builder: (context) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1100;
            return Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                title: Row(
                  children: [
                    Image.asset(
                      'assets/branding/korlix_mini_mark.png',
                      width: 32,
                      height: 32,
                      errorBuilder: (_, _, _) => const Icon(Icons.checkroom),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Virtual Closet',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Refresh closet',
                    onPressed: _locked ? null : () => _refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              bottomNavigationBar: desktop || _locked
                  ? null
                  : NavigationBar(
                      selectedIndex: _tab,
                      onDestinationSelected: (i) => setState(() => _tab = i),
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.checkroom),
                          label: 'Closet',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.person_outline),
                          label: 'Try on',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.auto_awesome),
                          label: 'KORLIX',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.favorite_border),
                          label: 'Saved',
                        ),
                      ],
                    ),
              body: SafeArea(
                child: _locked
                    ? Center(
                        child: _empty(
                          'Your session changed',
                          'Close this screen, sign in, and reopen Virtual Closet to continue.',
                          Icons.lock_outline,
                        ),
                      )
                    : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (desktop)
                            Container(
                              width: 170,
                              color: _navy,
                              child: Column(
                                children: [
                                  const SizedBox(height: 30),
                                  Image.asset(
                                    'assets/branding/korlix_mini_mark.png',
                                    width: 64,
                                    height: 64,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'KORLIX',
                                    style: TextStyle(
                                      color: Colors.cyanAccent,
                                      fontSize: 20,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  ...[
                                    (Icons.checkroom, 'My Closet', 0),
                                    (Icons.person_outline, 'Try On', 1),
                                    (Icons.auto_awesome, 'KORLIX Stylist', 2),
                                    (Icons.favorite_border, 'Saved Looks', 3),
                                  ].map(
                                    (v) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      child: Material(
                                        color: _navy,
                                        child: ListTile(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          selected: _tab == v.$3,
                                          selectedTileColor: const Color(
                                            0xFF075473,
                                          ),
                                          leading: Icon(
                                            v.$1,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          title: Text(
                                            v.$2,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                          onTap: () =>
                                              setState(() => _tab = v.$3),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  const Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Your wardrobe.\nReimagined.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(desktop ? 24 : 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your wardrobe. Reimagined.',
                                    style: TextStyle(
                                      fontSize: desktop ? 28 : 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Style what you own. Discover what suits you.',
                                    style: TextStyle(color: _muted),
                                  ),
                                  const SizedBox(height: 20),
                                  _steps(),
                                  const SizedBox(height: 20),
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: _card(
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _error!,
                                              style: const TextStyle(
                                                color: Color(0xFF9A2929),
                                              ),
                                            ),
                                            Wrap(
                                              spacing: 10,
                                              children: [
                                                TextButton(
                                                  onPressed: () => _refresh(),
                                                  child: const Text(
                                                    'Refresh closet',
                                                  ),
                                                ),
                                                if (_retryUpload != null)
                                                  TextButton(
                                                    onPressed: _working
                                                        ? null
                                                        : () => _retryUpload!(),
                                                    child: const Text(
                                                      'Retry upload',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_notice != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: Text(
                                        _notice!,
                                        style: const TextStyle(color: _cyan),
                                      ),
                                    ),
                                  if (_working)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: _card(
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const LinearProgressIndicator(),
                                            const SizedBox(height: 12),
                                            Text(
                                              _job?.running == true
                                                  ? (_job!.kind == 'tryon'
                                                        ? 'KORLIX is creating your outfit preview…'
                                                        : 'KORLIX is styling your wardrobe…')
                                                  : 'Saving your changes…',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (_job?.running == true) ...[
                                              const SizedBox(height: 6),
                                              const Text(
                                                'This can take a few minutes. You can leave and reopen Virtual Closet to check your result.',
                                                style: TextStyle(color: _muted),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (_tab == 3)
                                    _saved()
                                  else if (desktop)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(flex: 30, child: _wardrobe()),
                                        const SizedBox(width: 18),
                                        Expanded(flex: 40, child: _preview()),
                                        const SizedBox(width: 18),
                                        Expanded(flex: 30, child: _stylist()),
                                      ],
                                    )
                                  else if (_tab == 0)
                                    _wardrobe()
                                  else if (_tab == 1)
                                    _preview()
                                  else
                                    _stylist(),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'Only upload photos you have permission to use. Your closet is private. KORLIX styling shares wardrobe photos and item details with the AI provider; try-on shares your chosen photo and clothing.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GarmentDetails extends StatefulWidget {
  const _GarmentDetails({required this.initialName});
  final String initialName;
  @override
  State<_GarmentDetails> createState() => _GarmentDetailsState();
}

class _GarmentDetailsState extends State<_GarmentDetails> {
  late final TextEditingController name;
  String category = 'tops';
  @override
  void initState() {
    super.initState();
    name = TextEditingController(
      text: widget.initialName.length > 80
          ? widget.initialName.substring(0, 80)
          : widget.initialName,
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add to your wardrobe'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            maxLength: 80,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Item name',
              hintText: 'Ivory blazer',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: _categories.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: (v) => setState(() => category = v!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (name.text.trim(), category)),
        child: const Text('Save item'),
      ),
    ],
  );
}
