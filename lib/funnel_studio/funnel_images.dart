import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../workforce/workforce_style.dart';
import 'funnel_client.dart';

class FunnelPickedImage {
  const FunnelPickedImage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

Future<FunnelPickedImage?> pickFunnelImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  if (file.size > 5 * 1024 * 1024 || file.bytes == null) {
    throw const FunnelException('Choose a JPG, PNG, or WebP image up to 5 MB.');
  }
  return FunnelPickedImage(file.name, file.bytes!);
}

/// Authenticated bytes never become a public URL or a persisted client cache.
class FunnelPrivateImage extends StatefulWidget {
  const FunnelPrivateImage({
    super.key,
    required this.client,
    required this.id,
    required this.description,
    this.height = 220,
    this.fit = BoxFit.contain,
  });
  final FunnelClient client;
  final String id, description;
  final double height;
  final BoxFit fit;
  @override
  State<FunnelPrivateImage> createState() => _FunnelPrivateImageState();
}

class _FunnelPrivateImageState extends State<FunnelPrivateImage> {
  late Future<Uint8List> _bytes;
  bool _denied = false;
  void _deny() {
    if (mounted) setState(() => _denied = true);
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    _bytes = widget.client.imageBytes(widget.id);
  }

  @override
  void didUpdateWidget(covariant FunnelPrivateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.client != widget.client) {
      oldWidget.client.removeAccessDeniedListener(_deny);
      widget.client.addAccessDeniedListener(_deny);
      _bytes = widget.client.imageBytes(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: _denied
        ? const Center(child: Icon(Icons.lock_outline))
        : FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (c, s) {
              if (s.hasError) {
                return Center(
                  child: IconButton(
                    tooltip: 'Reload image',
                    onPressed: () => setState(
                      () => _bytes = widget.client.imageBytes(widget.id),
                    ),
                    icon: const Icon(Icons.refresh),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return Image.memory(
                s.data!,
                fit: widget.fit,
                semanticLabel: widget.description,
                gaplessPlayback: false,
                errorBuilder: (_, error, stack) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              );
            },
          ),
  );
}

class FunnelImageLibrary extends StatefulWidget {
  const FunnelImageLibrary({
    super.key,
    required this.client,
    required this.slot,
    required this.protectedIds,
    this.picker = pickFunnelImage,
  });
  final FunnelClient client;
  final String slot;
  final Set<String> protectedIds;
  final Future<FunnelPickedImage?> Function() picker;
  @override
  State<FunnelImageLibrary> createState() => _FunnelImageLibraryState();
}

class _FunnelImageLibraryState extends State<FunnelImageLibrary> {
  List<Map<String, dynamic>> _images = [];
  bool _busy = true, _denied = false;
  String? _error;
  int _usedBytes = 0;
  void _deny() {
    if (mounted) {
      setState(() {
        _denied = true;
        _images = [];
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    widget.client.removeAccessDeniedListener(_deny);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.client.addAccessDeniedListener(_deny);
    _load();
  }

  void _failure(Object e) {
    if (!mounted) return;
    setState(() {
      _error = e.toString();
      if (e is FunnelException && [401, 403].contains(e.status)) {
        _denied = true;
        _images = [];
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.client.request('GET', '/images');
      if (!mounted || _denied) return;
      setState(() {
        _images = (data['images'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _usedBytes = (data['used_bytes'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _choose(Map<String, dynamic> image) {
    Navigator.pop(context, {
      'id': image['id'],
      'alt': image['label'].toString().replaceFirst(RegExp(r'\.[^.]+$'), ''),
    });
  }

  Future<void> _upload() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await widget.picker();
      if (picked == null || !mounted || _denied) return;
      final result = await widget.client.uploadImage(picked.name, picked.bytes);
      if (mounted && !_denied) {
        _choose(Map<String, dynamic>.from(result['image'] as Map));
      }
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> image) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete unused image?'),
        content: Text(
          'Permanently remove “${image['label']}” from your image library? Saved drafts and published pages must not use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete image'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.request(
        'DELETE',
        '/images/${image['id']}',
        body: {'confirmed': true},
      );
      await _load();
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text('Choose ${widget.slot}'),
      content: SizedBox(
        width: 600,
        height: MediaQuery.sizeOf(context).height * .60,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'JPG, PNG, or WebP · up to 5 MB and 16 megapixels. Images are optimized and camera metadata is removed.',
              style: TextStyle(fontSize: 12, color: WfStyle.muted),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose images you have permission to publish. Uploads stay private until used on a published page.',
              style: TextStyle(fontSize: 12, color: WfStyle.muted),
            ),
            const SizedBox(height: 12),
            if (!_denied)
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Upload image'),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: WfStyle.gold),
                ),
              ),
            if (!_denied)
              Text(
                '${_images.length} of 50 images · ${(_usedBytes / (1024 * 1024)).toStringAsFixed(1)} of 20 MB',
                style: const TextStyle(fontSize: 12, color: WfStyle.muted),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _denied
                  ? const Center(
                      child: Text(
                        'Close this window and sign in with Enterprise access.',
                      ),
                    )
                  : _images.isEmpty && !_busy
                  ? const Center(
                      child: Text('Upload your first logo or main image.'),
                    )
                  : ListView.separated(
                      itemCount: _images.length,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (c, i) {
                        final a = _images[i],
                            used =
                                (a['page_count'] as num? ?? 0) > 0 ||
                                widget.protectedIds.contains(a['id']);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 64,
                              child: FunnelPrivateImage(
                                key: ValueKey(a['id']),
                                client: widget.client,
                                id: a['id'].toString(),
                                description: a['label'].toString(),
                                height: 64,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a['label'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${a['width']} × ${a['height']}${used ? ' · In use' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: WfStyle.muted,
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _choose(a),
                                        child: const Text('Use image'),
                                      ),
                                      if (!used)
                                        TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _delete(a),
                                          child: const Text('Delete'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (_error != null && !_denied)
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Refresh library'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
