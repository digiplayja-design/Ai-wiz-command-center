import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../camera_ask/camera_capture.dart';
import '../theme/korlix_action_button.dart';
import '../theme/korlix_action_grid.dart';
import '../theme/korlix_theme.dart';

const korlixUploadExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
  'txt',
  'md',
  'csv',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
];
const korlixUploadMaxBytes = 15 * 1024 * 1024;

String? validateKorlixUploads(List<PlatformFile> files) {
  if (files.length > 8) return 'Choose up to 8 files at a time.';
  for (final file in files) {
    if (!korlixUploadExtensions.contains(file.extension?.toLowerCase())) {
      return '${file.name}: this file type is not supported.';
    }
    if (file.size > korlixUploadMaxBytes ||
        (file.bytes?.length ?? 0) > korlixUploadMaxBytes) {
      return '${file.name}: choose a file smaller than 15 MB.';
    }
    if (file.bytes == null || file.bytes!.isEmpty) {
      return '${file.name}: the file could not be read. Choose it again.';
    }
  }
  return null;
}

String korlixFileSize(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
bool korlixUploadIsImage(PlatformFile file) =>
    ['jpg', 'jpeg', 'png', 'webp'].contains(file.extension?.toLowerCase());

Future<List<PlatformFile>> pickKorlixDocuments() async =>
    (await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: korlixUploadExtensions,
    ))?.files ??
    [];
Future<List<PlatformFile>> pickKorlixPhotos() async {
  final photos = await ImagePicker().pickMultiImage(
    requestFullMetadata: false,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 92,
  );
  if (photos.length > 8) {
    throw const FormatException('Choose up to 8 photos at a time.');
  }
  final files = <PlatformFile>[];
  for (final photo in photos) {
    if (await photo.length() > korlixUploadMaxBytes) {
      throw FormatException(
        '${photo.name}: choose a photo smaller than 15 MB.',
      );
    }
    final bytes = await photo.readAsBytes();
    files.add(PlatformFile(name: photo.name, size: bytes.length, bytes: bytes));
  }
  return files;
}

class KorlixUploadDraft {
  const KorlixUploadDraft(this.files, this.prompt);
  final List<PlatformFile> files;
  final String prompt;
}

class KorlixUploadStudio extends StatefulWidget {
  const KorlixUploadStudio({
    super.key,
    this.initialFiles = const [],
    this.initialPrompt = '',
    this.pickFiles = pickKorlixDocuments,
    this.pickPhotos = pickKorlixPhotos,
    this.capture,
    this.sessionChanges,
    this.isSessionCurrent,
  });
  final List<PlatformFile> initialFiles;
  final String initialPrompt;
  final Future<List<PlatformFile>> Function() pickFiles, pickPhotos;
  final Future<PlatformFile?> Function(BuildContext)? capture;
  final Listenable? sessionChanges;
  final bool Function()? isSessionCurrent;
  @override
  State<KorlixUploadStudio> createState() => _KorlixUploadStudioState();
}

class _KorlixUploadStudioState extends State<KorlixUploadStudio> {
  late final _files = List<PlatformFile>.from(widget.initialFiles);
  late final _prompt = TextEditingController(text: widget.initialPrompt);
  bool _busy = false, _expired = false;
  String? _error, _notice;
  bool get _valid => !_expired && (widget.isSessionCurrent?.call() ?? true);
  @override
  void initState() {
    super.initState();
    widget.sessionChanges?.addListener(_checkSession);
  }

  void _checkSession() {
    if (!mounted || _valid) return;
    _expired = true;
    _files.clear();
    _prompt.clear();
    final route = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == route);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.sessionChanges?.removeListener(_checkSession);
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pick(Future<List<PlatformFile>> Function() picker) async {
    if (_busy || !_valid) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final incoming = await picker();
      if (!mounted || !_valid) return;
      final added = <PlatformFile>[];
      var duplicates = 0;
      for (final file in incoming) {
        if ([
          ..._files,
          ...added,
        ].any((f) => f.name == file.name && listEquals(f.bytes, file.bytes))) {
          duplicates++;
        } else {
          added.add(file);
        }
      }
      final next = [..._files, ...added];
      final error = validateKorlixUploads(next);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      setState(() {
        _files
          ..clear()
          ..addAll(next);
        if (duplicates > 0) {
          _notice =
              '$duplicates duplicate ${duplicates == 1 ? 'file was' : 'files were'} skipped.';
        }
      });
    } catch (error) {
      if (mounted && _valid) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not open the picker. Try Files or Photos again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<PlatformFile>> _camera() async {
    if (widget.capture != null) {
      final file = await widget.capture!(context);
      return file == null ? [] : [file];
    }
    final photo = await captureCameraAskPhoto(context);
    return photo == null
        ? []
        : [
            PlatformFile(
              name: photo.name,
              size: photo.bytes.length,
              bytes: photo.bytes,
            ),
          ];
  }

  void _preview(PlatformFile file) {
    if (!korlixUploadIsImage(file) || !_valid) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(file.name),
            leading: IconButton(
              tooltip: 'Close preview',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 5,
              child: Image.memory(
                file.bytes!,
                errorBuilder: (_, _, _) =>
                    const Text('Preview unavailable for this image.'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Upload studio')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: KorlixActionButton(
            label: _busy
                ? 'Reading files…'
                : _files.isEmpty
                ? 'Update attachments'
                : 'Attach ${_files.length} ${_files.length == 1 ? 'file' : 'files'}',
            icon: Icons.add_to_photos_outlined,
            expand: true,
            onPressed:
                _busy ||
                    !_valid ||
                    (_files.isEmpty && widget.initialFiles.isEmpty)
                ? null
                : () {
                    final error = validateKorlixUploads(_files);
                    if (error != null) {
                      setState(() => _error = error);
                      return;
                    }
                    Navigator.pop(
                      context,
                      KorlixUploadDraft(
                        List.unmodifiable(_files),
                        _prompt.text,
                      ),
                    );
                  },
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 740),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [skin.panelSoft, skin.panelDeep],
                  ),
                  border: Border.all(color: skin.primary.withValues(alpha: .3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.layers_outlined, size: 38, color: skin.primary),
                    const SizedBox(height: 14),
                    Text(
                      'Bring your files into focus.',
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add documents or photos. Review them here, then ask K-Nova in your conversation.',
                      style: TextStyle(color: skin.mutedText, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Up to 8 files · 15 MB per file',
                      style: TextStyle(
                        color: skin.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              KorlixActionGrid(
                compact: true,
                children: [
                  KorlixActionButton(
                    label: 'Files',
                    icon: Icons.folder_open_rounded,
                    onPressed: _busy ? null : () => _pick(widget.pickFiles),
                    expand: true,
                  ),
                  KorlixActionButton(
                    label: 'Photos',
                    icon: Icons.photo_library_outlined,
                    onPressed: _busy ? null : () => _pick(widget.pickPhotos),
                    expand: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              KorlixActionButton(
                label: 'Take a photo',
                icon: Icons.camera_alt_outlined,
                onPressed: _busy ? null : () => _pick(_camera),
                expand: true,
              ),
              const SizedBox(height: 12),
              Text(
                'PDF, Word, Excel, PowerPoint, text, CSV, JPG, PNG and WebP.',
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: TextStyle(color: skin.danger)),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _notice!,
                      style: TextStyle(color: skin.mutedText),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your selection · ${_files.length}/8',
                      style: TextStyle(
                        color: skin.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_files.isNotEmpty)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _files.clear()),
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              if (_files.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Text(
                    'Your selected files will appear here.',
                    style: TextStyle(color: skin.mutedText),
                  ),
                ),
              for (var i = 0; i < _files.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: KorlixUploadFileCard(
                    file: _files[i],
                    onPreview: korlixUploadIsImage(_files[i])
                        ? () => _preview(_files[i])
                        : null,
                    onRemove: _busy
                        ? null
                        : () => setState(() => _files.removeAt(i)),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'What would you like to do?',
                style: TextStyle(
                  color: skin.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final entry in const {
                    'Summarize':
                        'Summarize these files and highlight the key points.',
                    'Compare':
                        'Compare these files and explain the important differences.',
                    'Extract details':
                        'Extract the key names, dates, amounts, and action items from these files.',
                    'Ask a question': '',
                  }.entries)
                    ActionChip(
                      label: Text(entry.key),
                      onPressed:
                          _busy || (entry.key == 'Compare' && _files.length < 2)
                          ? null
                          : () => _prompt.text = entry.value,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                minLines: 3,
                maxLines: 6,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Your question or instructions',
                  hintText: 'For example: What needs my attention?',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Files stay in this draft until you tap Send in your conversation.',
                style: TextStyle(
                  color: skin.mutedText,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KorlixUploadFileCard extends StatelessWidget {
  const KorlixUploadFileCard({
    super.key,
    required this.file,
    this.onRemove,
    this.onPreview,
  });
  final PlatformFile file;
  final VoidCallback? onRemove, onPreview;
  @override
  Widget build(BuildContext context) {
    final skin = korlixSkinOf(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: skin.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.border.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: korlixUploadIsImage(file) && file.bytes != null
                ? Tooltip(
                    message: onPreview == null
                        ? file.name
                        : 'Preview ${file.name}',
                    child: InkWell(
                      onTap: onPreview,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.memory(
                          file.bytes!,
                          fit: BoxFit.cover,
                          cacheWidth: 144,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_not_supported_outlined,
                            color: skin.mutedText,
                          ),
                        ),
                      ),
                    ),
                  )
                : Icon(
                    Icons.description_outlined,
                    color: skin.primary,
                    size: 28,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: skin.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.extension?.toUpperCase() ?? 'FILE'} · ${korlixFileSize(file.size)}',
                  style: TextStyle(color: skin.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove ${file.name}',
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}
