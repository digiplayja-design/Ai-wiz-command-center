import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/korlix_theme.dart';
import 'social_client.dart';
import 'social_design.dart';

const _audiences = {
  'connections': 'Connections',
  'private': 'Only me',
  'members': 'Social members',
};

class SocialAlbumsScreen extends StatefulWidget {
  const SocialAlbumsScreen({
    super.key,
    required this.client,
    required this.profile,
    this.owned = false,
    this.picker,
  });
  final SocialClient client;
  final SocialMap profile;
  final bool owned;
  final Future<List<XFile>> Function()? picker;
  @override
  State<SocialAlbumsScreen> createState() => _SocialAlbumsScreenState();
}

class _SocialAlbumsScreenState extends State<SocialAlbumsScreen> {
  List<SocialMap> _albums = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_session);
    unawaited(_load());
  }

  void _session() {
    if (!widget.client.available && mounted) {
      setState(() {
        _albums = [];
        _error = 'Sign in and reopen Social.';
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_session);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.get('albums', {
        'peer': widget.profile['id'],
      });
      if (mounted && widget.client.available) {
        setState(() {
          _albums = socialItems(r['items']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _albums = [];
          _error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final data = await _editAlbum(context);
    if (data == null || !mounted) return;
    try {
      final r = await widget.client.post('album_create', {
        'album': socialId(),
        ...data,
      });
      if (mounted && widget.client.available) {
        await _open(socialMap(r['album']));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(SocialMap album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocialAlbumScreen(
          client: widget.client,
          album: album,
          owned: widget.owned,
          picker: widget.picker,
        ),
      ),
    );
    if (mounted && widget.client.available) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.owned
              ? 'My photo albums'
              : '${widget.profile['name']} · Albums',
        ),
      ),
      floatingActionButton: widget.owned && widget.client.available
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Create album'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            SocialPanel(
              child: Row(
                children: [
                  SocialAvatar(member: widget.profile),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Life, in pictures.',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: s.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.owned
                              ? 'Collect your favorite moments. Share each album with the people you choose.'
                              : 'Photo collections shared with you.',
                          style: TextStyle(color: s.mutedText, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, style: TextStyle(color: s.danger)),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _albums.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 44),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 60,
                      color: s.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      widget.owned
                          ? 'Your first album starts here'
                          : 'No shared albums yet',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.owned
                          ? 'Create an album, then select several photos to upload.'
                          : 'New collections will appear when shared with you.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            LayoutBuilder(
              builder: (context, c) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _albums.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: c.maxWidth > 800
                      ? 3
                      : c.maxWidth > 480
                      ? 2
                      : 1,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  mainAxisExtent: 280,
                ),
                itemBuilder: (context, i) {
                  final a = _albums[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _open(a),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _photo(socialMap(a['cover'])['photo_url']),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${a['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${a['photo_count']} photos · ${_audiences[a['visibility']] ?? 'Connections'}',
                                  style: TextStyle(color: s.mutedText),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Upload {
  _Upload(this.file) : id = socialId();
  final XFile file;
  final String id;
  String? error;
  bool done = false;
}

class SocialAlbumScreen extends StatefulWidget {
  const SocialAlbumScreen({
    super.key,
    required this.client,
    required this.album,
    required this.owned,
    this.picker,
  });
  final SocialClient client;
  final SocialMap album;
  final bool owned;
  final Future<List<XFile>> Function()? picker;
  @override
  State<SocialAlbumScreen> createState() => _SocialAlbumScreenState();
}

class _SocialAlbumScreenState extends State<SocialAlbumScreen> {
  late SocialMap _album = widget.album;
  List<SocialMap> _photos = [];
  List<_Upload> _uploads = [];
  bool _loading = true, _busy = false;
  String? _error;
  Timer? _refresh;
  String get _id => '${widget.album['id']}';
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_session);
    unawaited(_load());
    _refresh = Timer.periodic(const Duration(minutes: 3), (_) {
      if (!_busy) unawaited(_load());
    });
  }

  void _session() {
    if (!widget.client.available && mounted) {
      setState(() {
        _photos = [];
        _uploads = [];
        _error = 'Sign in and reopen Social.';
      });
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    widget.client.removeListener(_session);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.get('album', {'album': _id});
      if (mounted && widget.client.available) {
        setState(() {
          _album = socialMap(r['album']);
          _photos = socialItems(r['items']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _photos = [];
          _error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files =
          await (widget.picker?.call() ??
              ImagePicker().pickMultiImage(
                maxWidth: 2048,
                maxHeight: 2048,
                imageQuality: 90,
                limit: 20,
              ));
      if (!mounted || !widget.client.available) return;
      if (files.isEmpty) return;
      if (files.length > 20 || files.length + _photos.length > 100) {
        throw const SocialException(
          'Select up to 20 photos at a time. Each album holds 100 photos.',
        );
      }
      setState(() => _uploads = files.map(_Upload.new).toList());
      await _uploadPending();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadPending() async {
    setState(() => _busy = true);
    for (final task in _uploads.where((u) => !u.done).toList()) {
      if (!mounted || !widget.client.available) break;
      setState(() => task.error = null);
      try {
        if (await task.file.length() > 8 * 1024 * 1024) {
          throw const SocialException('This photo is larger than 8 MB.');
        }
        final bytes = await task.file.readAsBytes();
        if (!mounted || !widget.client.available) break;
        await widget.client.uploadAlbumPhoto(
          album: _id,
          id: task.id,
          bytes: bytes,
        );
        task.done = true;
      } catch (e) {
        task.error = '$e';
      }
      if (mounted) setState(() {});
    }
    if (mounted && widget.client.available) await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _edit() async {
    final data = await _editAlbum(context, album: _album);
    if (data == null || !mounted) return;
    await _mutate('album_save', data);
  }

  Future<void> _mutate(String action, SocialMap data) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.client.post(action, {'album': _id, ...data});
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAlbum() async {
    if (!await _confirm(
      context,
      'Delete this album?',
      'All photos in this album will be removed.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.client.post('album_delete', {'album': _id});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photoAction(String action, SocialMap photo) async {
    if (action == 'delete' &&
        !await _confirm(
          context,
          'Delete this photo?',
          'This photo will be removed from the album.',
        )) {
      return;
    }
    if (mounted) {
      await _mutate(action == 'delete' ? 'album_photo_delete' : 'album_cover', {
        'photo': photo['id'],
      });
    }
  }

  Future<void> _view(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewer(client: widget.client, album: _id, initial: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = korlixSkinOf(context),
        finished = _uploads.where((u) => u.done).length,
        failed = _uploads.where((u) => u.error != null).length;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_album['title']}'),
          actions: widget.owned
              ? [
                  PopupMenuButton<String>(
                    enabled: !_busy && widget.client.available,
                    onSelected: (v) => v == 'edit' ? _edit() : _deleteAlbum(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Album name & privacy'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete album'),
                      ),
                    ],
                  ),
                ]
              : null,
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_photos.length} photos · ${_audiences[_album['visibility']] ?? 'Connections'}',
                      style: TextStyle(color: s.mutedText),
                    ),
                  ),
                  if (widget.owned)
                    FilledButton.icon(
                      onPressed: _busy || !widget.client.available
                          ? null
                          : _pick,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photos'),
                    ),
                ],
              ),
              if (widget.owned)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Select up to 20 photos at once · 100 per album · 8 MB per photo',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (_uploads.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SocialPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _busy
                              ? 'Uploading photos · $finished of ${_uploads.length} saved'
                              : '$finished of ${_uploads.length} photos saved',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: _uploads.isEmpty
                              ? 0
                              : finished / _uploads.length,
                        ),
                        for (final task in _uploads.where(
                          (u) => u.error != null,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${task.file.name}: ${task.error}',
                              style: TextStyle(color: s.danger),
                            ),
                          ),
                        if (!_busy && failed > 0)
                          TextButton(
                            onPressed: _uploadPending,
                            child: const Text('Retry failed photos'),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!, style: TextStyle(color: s.danger)),
                ),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (!_loading && _photos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 70),
                  child: Column(
                    children: [
                      Icon(Icons.collections_outlined, size: 70),
                      SizedBox(height: 12),
                      Text('Add the first moments to this album.'),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _photos.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: c.maxWidth > 800
                        ? 4
                        : c.maxWidth > 480
                        ? 3
                        : 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, i) {
                    final p = _photos[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          InkWell(
                            onTap: () => _view(i),
                            child: _photo(p['photo_url']),
                          ),
                          if (p['id'] == _album['cover_id'])
                            const Positioned(
                              left: 8,
                              bottom: 8,
                              child: Chip(
                                label: Text('Cover'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          if (widget.owned)
                            Positioned(
                              right: 4,
                              top: 4,
                              child: Material(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(24),
                                child: PopupMenuButton<String>(
                                  color: s.panel,
                                  iconColor: Colors.white,
                                  enabled: !_busy,
                                  onSelected: (v) => _photoAction(v, p),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'cover',
                                      child: Text('Make album cover'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete photo'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _photo(dynamic url, {BoxFit fit = BoxFit.cover}) =>
    url is String && url.isNotEmpty
    ? Image.network(
        url,
        fit: fit,
        errorBuilder: (_, e, s) =>
            const Center(child: Icon(Icons.broken_image_outlined, size: 36)),
      )
    : const ColoredBox(
        color: Color(0xFF173146),
        child: Center(
          child: Icon(
            Icons.photo_library_outlined,
            size: 48,
            color: Color(0xFF64DCE9),
          ),
        ),
      );

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

Future<SocialMap?> _editAlbum(BuildContext context, {SocialMap? album}) async {
  final name = TextEditingController(text: album?['title']);
  String visibility = album?['visibility'] ?? 'connections';
  final result = await showDialog<SocialMap>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(album == null ? 'Create a photo album' : 'Album details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                maxLength: 80,
                onChanged: (_) => set(() {}),
                decoration: const InputDecoration(
                  labelText: 'Album name',
                  hintText: 'Family, celebrations, travel…',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: visibility,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Who can view this album?',
                ),
                items: _audiences.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => set(() => visibility = v!),
              ),
              const SizedBox(height: 12),
              const Text(
                'Connections means accepted follows. Members can save or share photos they can view.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(c, {
                    'title': name.text.trim(),
                    'visibility': visibility,
                  }),
            child: Text(album == null ? 'Create album' : 'Save'),
          ),
        ],
      ),
    ),
  );
  // The dialog reverse animation may still be using its TextField controller.
  unawaited(Future<void>.delayed(const Duration(seconds: 1), name.dispose));
  return result;
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({
    required this.client,
    required this.album,
    required this.initial,
  });
  final SocialClient client;
  final String album;
  final int initial;
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  List<SocialMap> _items = [];
  String? _error;
  late int _index = widget.initial;
  PageController? _pages;
  @override
  void initState() {
    super.initState();
    widget.client.addListener(_session);
    unawaited(_load());
  }

  void _session() {
    if (!widget.client.available && mounted) {
      setState(() {
        _items = [];
        _error = 'Sign in and reopen Social.';
      });
    }
  }

  Future<void> _load() async {
    try {
      final r = await widget.client.get('album', {'album': widget.album});
      if (mounted && widget.client.available) {
        setState(() {
          _items = socialItems(r['items']);
          _index = _items.isEmpty ? 0 : _index.clamp(0, _items.length - 1);
          _pages = PageController(initialPage: _index);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_session);
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(
        _items.isEmpty ? 'Photos' : '${_index + 1} / ${_items.length}',
      ),
    ),
    body: _error != null
        ? Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white)),
          )
        : _pages == null
        ? const Center(child: CircularProgressIndicator())
        : PageView.builder(
            controller: _pages,
            itemCount: _items.length,
            onPageChanged: (v) => setState(() => _index = v),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: _photo(_items[i]['photo_url'], fit: BoxFit.contain),
              ),
            ),
          ),
    bottomNavigationBar: _items.isEmpty
        ? null
        : SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  color: Colors.white,
                  onPressed: _index == 0
                      ? null
                      : () => _pages!.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_left),
                ),
                const Text(
                  'Swipe to browse · Pinch to zoom',
                  style: TextStyle(color: Colors.white70),
                ),
                IconButton(
                  color: Colors.white,
                  onPressed: _index == _items.length - 1
                      ? null
                      : () => _pages!.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
  );
}
