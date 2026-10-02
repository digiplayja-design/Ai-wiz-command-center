import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'fieldproof_client.dart';
import 'fieldproof_report.dart';

class FieldProofQueuedPhoto {
  FieldProofQueuedPhoto({required this.name, required this.load})
    : key = fieldProofRequestKey();
  final String key;
  final Future<FieldProofPhoto> Function() load;
  String name, tag = 'after', note = '';
  bool attempted = false, saved = false;
  FieldProofPhoto? cached;
}

Future<List<FieldProofQueuedPhoto>> pickFieldProofBatch(int remaining) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    allowMultiple: true,
    withData: false,
    withReadStream: true,
  );
  if (result == null) return [];
  final limit = remaining < 12 ? remaining : 12;
  if (result.files.length > limit)
    throw FieldProofException('Choose up to $limit photos for this upload.');
  if (result.files.any((x) => x.size > 10 * 1024 * 1024))
    throw const FieldProofException('Each photo must be under 10 MB.');
  return result.files
      .map(
        (file) => FieldProofQueuedPhoto(
          name: file.name.length > 100
              ? file.name.substring(0, 100)
              : file.name,
          load: () async {
            if (file.bytes != null)
              return FieldProofPhoto(file.name, file.bytes!);
            final stream = file.readStream;
            if (stream == null)
              throw const FieldProofException('Select this photo again.');
            final builder = BytesBuilder(copy: false);
            await for (final chunk in stream) {
              if (builder.length + chunk.length > 10 * 1024 * 1024)
                throw const FieldProofException(
                  'Each photo must be under 10 MB.',
                );
              builder.add(chunk);
            }
            return FieldProofPhoto(file.name, builder.takeBytes());
          },
        ),
      )
      .toList();
}

class FieldProofBatchDialog extends StatefulWidget {
  const FieldProofBatchDialog({
    super.key,
    required this.remaining,
    required this.pick,
    required this.upload,
  });
  final int remaining;
  final Future<List<FieldProofQueuedPhoto>> Function(int) pick;
  final Future<void> Function(FieldProofQueuedPhoto, FieldProofPhoto) upload;
  @override
  State<FieldProofBatchDialog> createState() => _FieldProofBatchDialogState();
}

class _FieldProofBatchDialogState extends State<FieldProofBatchDialog> {
  List<FieldProofQueuedPhoto> _photos = [];
  bool _busy = false;
  String? _error;
  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      final rows = await widget.pick(widget.remaining);
      if (!mounted) return;
      if (rows.length > widget.remaining || rows.length > 12)
        throw const FieldProofException(
          'Choose no more than 12 photos and keep within the job limit.',
        );
      setState(() {
        _photos = rows;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    if (_busy || _photos.isEmpty) return;
    if (_photos.any((x) => x.name.trim().isEmpty)) {
      setState(() => _error = 'Give each photo a label.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final row in _photos.where((x) => !x.saved)) {
        if (!mounted) return;
        setState(() => row.attempted = true);
        final photo = row.cached ??= await row.load();
        if (!mounted) return;
        await widget.upload(row, photo);
        if (!mounted) return;
        setState(() {
          row.saved = true;
          row.cached = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Add several photos'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose up to 12 originals per batch. Each keeps its own label, category and note. Saved photos are skipped if you retry.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('fp-batch-pick'),
                onPressed: _busy || _photos.any((x) => x.attempted)
                    ? null
                    : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos'),
              ),
              if (_photos.isNotEmpty)
                Text(
                  '${_photos.where((x) => x.saved).length} / ${_photos.length} saved',
                ),
              if (_busy) const LinearProgressIndicator(),
              for (final row in _photos)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (row.saved)
                        Text('✓ ${row.name}')
                      else ...[
                        TextFormField(
                          initialValue: row.name,
                          enabled: !_busy && !row.attempted,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Photo label',
                          ),
                          onChanged: (v) => row.name = v,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: row.tag,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Evidence category',
                          ),
                          items: fpTagNames.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _busy || row.attempted
                              ? null
                              : (v) => setState(() => row.tag = v ?? 'after'),
                        ),
                        TextFormField(
                          initialValue: row.note,
                          enabled: !_busy && !row.attempted,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Photo note',
                          ),
                          onChanged: (v) => row.note = v,
                        ),
                      ],
                    ],
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('fp-batch-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
        FilledButton(
          key: const Key('fp-batch-upload'),
          onPressed: _busy || _photos.isEmpty || _photos.every((x) => x.saved)
              ? null
              : _upload,
          child: Text(
            _photos.any((x) => x.attempted)
                ? 'Retry remaining'
                : 'Upload photos',
          ),
        ),
      ],
    ),
  );
}

class FieldProofCompareDialog extends StatefulWidget {
  const FieldProofCompareDialog({super.key, required this.photos});
  final List<Map<String, dynamic>> photos;
  @override
  State<FieldProofCompareDialog> createState() =>
      _FieldProofCompareDialogState();
}

class _FieldProofCompareDialogState extends State<FieldProofCompareDialog> {
  late String _before, _after;
  double _split = .5;
  @override
  void initState() {
    super.initState();
    _before = fpText(
      (widget.photos.where((x) => x['tag'] == 'before').firstOrNull ??
          widget.photos.first)['id'],
    );
    _after = fpText(
      (widget.photos
              .where((x) => x['id'] != _before && x['tag'] == 'after')
              .firstOrNull ??
          widget.photos.firstWhere((x) => x['id'] != _before))['id'],
    );
  }

  Widget _select(
    String label,
    String selected,
    String other,
    ValueChanged<String?> change,
  ) => DropdownButtonFormField<String>(
    initialValue: selected,
    key: ValueKey('$label-$selected'),
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: widget.photos
        .where((x) => x['id'] != other)
        .map(
          (x) => DropdownMenuItem(
            value: fpText(x['id']),
            child: Text(fpText(x['name']), overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: change,
  );
  Widget _photo(String id) {
    final row = widget.photos.firstWhere((x) => x['id'] == id);
    return Image.network(
      fpText(row['previewUrl']),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Center(
        child: Text('Preview unavailable. Close and refresh this job.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Compare before & after'),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _select(
              'Before / left',
              _before,
              _after,
              (v) => setState(() => _before = v ?? _before),
            ),
            const SizedBox(height: 12),
            _select(
              'After / right',
              _after,
              _before,
              (v) => setState(() => _after = v ?? _after),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFFEAF0F3),
                      child: _photo(_after),
                    ),
                    ClipRect(
                      clipper: _ComparisonClip(_split),
                      child: ColoredBox(
                        color: const Color(0xFFEAF0F3),
                        child: _photo(_before),
                      ),
                    ),
                    Positioned(
                      left: box.maxWidth * _split,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            Slider(
              value: _split,
              onChanged: (v) => setState(() => _split = v),
              semanticFormatterCallback: (v) =>
                  'Before ${(v * 100).round()} percent',
            ),
            const Text(
              'Move the divider to compare previews. Original files remain unchanged.',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _ComparisonClip extends CustomClipper<Rect> {
  const _ComparisonClip(this.split);
  final double split;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * split, size.height);
  @override
  bool shouldReclip(_ComparisonClip old) => old.split != split;
}
