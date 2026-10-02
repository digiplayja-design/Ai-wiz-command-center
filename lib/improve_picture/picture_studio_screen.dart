import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../korlix_image_saver.dart';
import '../theme/korlix_theme.dart';
import 'picture_studio_client.dart';

typedef PictureEditCallback =
    Future<PictureEditResult> Function(PlatformFile, PictureEditOptions);

class PictureStudioScreen extends StatefulWidget {
  const PictureStudioScreen({
    super.key,
    required this.onImprove,
    required this.ensureConsent,
    required this.onOpenTemplates,
    this.initialFile,
    this.initialPrompt = '',
    this.language = 'en',
    this.pickPhoto,
    this.savePicture,
  });
  final PictureEditCallback onImprove;
  final Future<bool> Function() ensureConsent;
  final VoidCallback onOpenTemplates;
  final PlatformFile? initialFile;
  final String initialPrompt, language;
  final Future<PlatformFile?> Function()? pickPhoto;
  final Future<void> Function(Uint8List)? savePicture;

  @override
  State<PictureStudioScreen> createState() => _PictureStudioScreenState();
}

class _PictureStudioScreenState extends State<PictureStudioScreen> {
  KorlixSkinPalette get _skin => korlixSkinOf(context);
  Color get accent => _skin.primary;
  static const presets = <String, (String, IconData, String)>{
    'enhance': (
      'Natural polish',
      Icons.auto_awesome,
      'Better light, color and detail. Keep it natural.',
    ),
    'restore': (
      'Restore a photo',
      Icons.restore,
      'Repair fading and damage while keeping the original character.',
    ),
    'headshot': (
      'Studio headshot',
      Icons.person_outline,
      'Professional lighting and a clean, polished setting.',
    ),
    'product': (
      'Product photo',
      Icons.shopping_bag_outlined,
      'Crisp materials, clean edges and accurate branding.',
    ),
    'cutout': (
      'Remove background',
      Icons.layers_clear_outlined,
      'A transparent PNG with carefully preserved edges.',
    ),
    'custom': (
      'My own edit',
      Icons.edit_outlined,
      'Describe exactly what should change and what should stay.',
    ),
  };
  late final TextEditingController _prompt;
  final ScrollController _scroll = ScrollController();
  PlatformFile? _original, _source;
  final List<_PictureVersion> _versions = [];
  _PictureVersion? _selectedVersion;
  PictureEditResult? get _result => _selectedVersion?.result;
  String _preset = 'enhance', _strength = 'balanced', _size = 'auto';
  String _look = 'original', _lighting = 'original';
  String _sourceLabel = 'Original photo', _previewMode = 'after';
  int _nextVersion = 1;
  String? _error;
  bool _preserve = true, _busy = false, _picking = false, _saving = false;
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.initialPrompt);
    if (widget.initialFile != null &&
        pictureFileError(widget.initialFile!) == null) {
      _source = _original = widget.initialFile;
    }
    if (widget.initialPrompt.trim().isNotEmpty) _preset = 'custom';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick({bool camera = false}) async {
    if (_busy || _picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      PlatformFile? file;
      if (camera) {
        final picked = await ip.ImagePicker().pickImage(
          source: ip.ImageSource.camera,
        );
        if (picked != null) {
          final bytes = await picked.readAsBytes();
          file = PlatformFile(
            name: picked.name,
            size: bytes.length,
            bytes: bytes,
          );
        }
      } else if (widget.pickPhoto != null) {
        file = await widget.pickPhoto!();
      } else {
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
          withData: true,
        );
        file = selection?.files.single;
      }
      if (!mounted || file == null) return;
      final problem = pictureFileError(file);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      setState(() {
        _original = _source = file;
        _selectedVersion = null;
        _versions.clear();
        _nextVersion = 1;
        _sourceLabel = 'Original photo';
        _previewMode = 'after';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open that photo. Try Choose photo or check camera permissions.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _improve() async {
    if (_busy || _source == null) return;
    if (_preset == 'custom' && _prompt.text.trim().isEmpty) {
      setState(
        () => _error = 'Describe the change you want, or choose a treatment.',
      );
      return;
    }
    final source = _source!;
    final sourceLabel = _sourceLabel;
    final options = PictureEditOptions(
      preset: _preset,
      strength: _strength,
      look: _look,
      lighting: _lighting,
      size: _size,
      preserveIdentity: _preserve,
      prompt: _prompt.text.trim(),
      language: widget.language,
    );
    setState(() {
      _busy = true;
      _error = null;
      _elapsed = 0;
    });
    try {
      if (!await widget.ensureConsent() || !mounted) return;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed++);
      });
      final result = await widget.onImprove(source, options);
      if (!mounted) return;
      setState(() {
        final version = _PictureVersion(
          number: _nextVersion++,
          source: source,
          sourceLabel: sourceLabel,
          result: result,
          options: options,
        );
        _versions.add(version);
        _trimHistory();
        _selectedVersion = version;
        _previewMode = 'after';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst(
            RegExp(r'^Exception: '),
            '',
          ),
        );
      }
    } finally {
      _timer?.cancel();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_result == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (widget.savePicture != null) {
        await widget.savePicture!(_result!.bytes);
      } else {
        await saveKorlixGeneratedImage(
          bytes: _result!.bytes,
          filename:
              'korlix_improved_${DateTime.now().millisecondsSinceEpoch}.png',
          mimeType: 'image/png',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your PNG is ready to save or share.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this picture. Keep this screen open and try Save PNG again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _trimHistory() {
    int retainedBytes() {
      final buffers = <Uint8List>{
        ?_original?.bytes,
        for (final version in _versions) ...[
          ?version.source.bytes,
          version.result.bytes,
        ],
      };
      return buffers.fold(0, (total, bytes) => total + bytes.length);
    }

    while (_versions.length > 1 &&
        (_versions.length > 6 || retainedBytes() > 64 * 1024 * 1024)) {
      _versions.removeAt(0);
    }
  }

  void _refine() {
    final version = _selectedVersion;
    if (version == null || _busy) return;
    setState(() {
      _source = PlatformFile(
        name: 'korlix_refinement.png',
        size: version.result.bytes.length,
        bytes: version.result.bytes,
      );
      _sourceLabel = 'Version ${version.number}';
      _selectedVersion = null;
      _preset = 'custom';
      _look = _lighting = 'original';
      _prompt.clear();
      _previewMode = 'after';
      _error = null;
    });
  }

  void _selectVersion(_PictureVersion version) {
    if (_busy) return;
    setState(() {
      _selectedVersion = version;
      _source = version.source;
      _sourceLabel = version.sourceLabel;
      _preset = version.options.preset;
      _strength = version.options.strength;
      _look = version.options.look;
      _lighting = version.options.lighting;
      _size = version.options.size;
      _preserve = version.options.preserveIdentity;
      _prompt.text = version.options.prompt;
      _previewMode = 'after';
      _error = null;
    });
  }

  void _startFromOriginal() {
    if (_busy || _original == null) return;
    setState(() {
      _source = _original;
      _sourceLabel = 'Original photo';
      _selectedVersion = null;
      _preset = 'enhance';
      _look = _lighting = 'original';
      _previewMode = 'after';
      _error = null;
    });
  }

  void _suggest(String hint) {
    if (_busy) return;
    final text = _prompt.text.trim();
    if (text.contains(hint)) return;
    final combined = text.isEmpty ? hint : '$text\n$hint';
    if (combined.length > 12000) return;
    _prompt.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  Widget _card(Widget child) => Material(
    color: _skin.panel,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: _skin.border.withValues(alpha: .35)),
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );

  Widget _step(String number, String title, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: TextStyle(color: _skin.text, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Widget _photoView(Uint8List bytes, {String? label, Key? imageKey}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: _skin.mutedText, fontSize: 12),
          ),
        ),
      Expanded(
        child: InteractiveViewer(
          key: ValueKey('${identityHashCode(bytes)}-$label'),
          minScale: 1,
          maxScale: 5,
          child: Image.memory(
            bytes,
            key: imageKey,
            fit: BoxFit.contain,
            cacheWidth: 1600,
            errorBuilder: (_, _, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'This photo could not be previewed. Choose another.',
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _emptyPhotoPicker() => ColoredBox(
    color: _skin.panelSoft,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 46,
            color: _skin.secondary,
          ),
          const SizedBox(height: 12),
          const Text(
            'Start with a photo you love',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'JPG, PNG or WEBP · Up to 15 MB',
            textAlign: TextAlign.center,
            style: TextStyle(color: _skin.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _picking ? null : _pick,
            icon: const Icon(Icons.upload_outlined),
            label: Text(_picking ? 'Opening…' : 'Choose photo'),
          ),
        ],
      ),
    ),
  );

  Widget _preview() {
    final version = _selectedVersion;
    final before = version?.source.bytes ?? _source?.bytes;
    final bytes = switch (_previewMode) {
      'original' => _original?.bytes,
      'before' => before,
      _ => _result?.bytes ?? _source?.bytes,
    };
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(
            '1',
            version == null ? 'Your photo' : 'Compare your edit',
            _skin.secondary,
          ),
          if (_versions.isNotEmpty) ...[
            const Text(
              'Your versions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    key: const Key('picture-original'),
                    avatar: const Icon(Icons.photo_outlined, size: 17),
                    label: const Text('Original'),
                    onPressed: _busy ? null : _startFromOriginal,
                  ),
                  ..._versions.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        key: ValueKey('picture-version-${item.number}'),
                        label: Text('Version ${item.number}'),
                        selected: identical(item, version),
                        onSelected: _busy ? null : (_) => _selectVersion(item),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (version != null) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in const {
                  'before': 'Before',
                  'after': 'After',
                  'side': 'Side by side',
                  'original': 'View original',
                }.entries)
                  ChoiceChip(
                    key: ValueKey('picture-compare-${entry.key}'),
                    label: Text(entry.value),
                    selected: _previewMode == entry.key,
                    onSelected: (_) => setState(() => _previewMode = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: bytes == null
                ? _emptyPhotoPicker()
                : LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      height: constraints.maxWidth < 400 ? 285 : 365,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: _TransparencyPainter(
                              _skin.panelDeep,
                              _skin.panelSoft,
                            ),
                          ),
                          if (version != null && _previewMode == 'side')
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _photoView(
                                      version.source.bytes!,
                                      label: version.sourceLabel,
                                      imageKey: const Key(
                                        'picture-before-image',
                                      ),
                                    ),
                                  ),
                                  VerticalDivider(
                                    width: 14,
                                    color: _skin.border.withValues(alpha: .6),
                                  ),
                                  Expanded(
                                    child: _photoView(
                                      version.result.bytes,
                                      label: 'Version ${version.number}',
                                      imageKey: const Key(
                                        'picture-after-image',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            _photoView(
                              bytes,
                              imageKey: const Key('picture-preview-image'),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            version != null && _previewMode == 'before'
                ? 'Before = ${version.sourceLabel.toLowerCase()}, the source for this edit.'
                : bytes == null
                ? 'Your original stays available while you experiment.'
                : 'Pinch or scroll to zoom. Drag to inspect details.',
            style: TextStyle(color: _skin.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_source != null)
                OutlinedButton.icon(
                  onPressed: _busy || _picking ? null : _pick,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Change photo'),
                ),
              OutlinedButton.icon(
                onPressed: _busy || _picking ? null : () => _pick(camera: true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              if (_source != null && !identical(_source, _original))
                TextButton(
                  onPressed: _busy ? null : _startFromOriginal,
                  child: const Text('Start from original'),
                ),
            ],
          ),
          if (version != null) ...[
            const Divider(height: 26),
            if (version.result.summary.isNotEmpty) ...[
              Text(
                version.result.summary,
                style: TextStyle(color: _skin.mutedText, height: 1.45),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(_saving ? 'Saving…' : 'Save PNG'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _refine,
                  icon: const Icon(Icons.tune),
                  label: const Text('Refine this image'),
                ),
              ],
            ),
          ],
          if (_versions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Up to 6 recent edits stay here until you leave or change photos. Older edits make room for new ones. Save your favorites.',
              style: TextStyle(
                color: _skin.mutedText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _presetColor(String id) => switch (id) {
    'restore' => const Color(0xfff5ac64),
    'headshot' => const Color(0xffb49aff),
    'product' => const Color(0xff58cbb8),
    'cutout' => const Color(0xff72b7fa),
    'custom' => const Color(0xfff390ba),
    _ => const Color(0xffb8cf63),
  };

  Widget _presetChoices() => LayoutBuilder(
    builder: (context, constraints) {
      final columns =
          constraints.maxWidth >= 290 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.5
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: presets.entries.map((entry) {
          final selected = _preset == entry.key;
          final tint = _presetColor(entry.key);
          return SizedBox(
            width: width,
            child: Semantics(
              selected: selected,
              button: true,
              child: Material(
                color: Color.alphaBlend(
                  tint.withValues(alpha: selected ? .19 : .08),
                  _skin.panel,
                ),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: ValueKey('picture-preset-${entry.key}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: _busy
                      ? null
                      : () => setState(() => _preset = entry.key),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 90),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? accent
                            : _skin.border.withValues(alpha: .35),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(entry.value.$2, color: _skin.text, size: 22),
                            const Spacer(),
                            if (selected)
                              Icon(Icons.check_circle, color: accent, size: 18)
                            else
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: tint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          entry.value.$1,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    },
  );

  Widget _lookAndLight() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label('Color look'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in const <String, (String, Color)>{
            'original': ('Original colors', Color(0xffaab5c4)),
            'vivid': ('Vivid', Color(0xffd877df)),
            'warm': ('Warm', Color(0xffefb15a)),
            'cool': ('Cool', Color(0xff78bde9)),
            'cinematic': ('Cinematic', Color(0xffa396dc)),
            'mono': ('Black & white', Color(0xff9da6b6)),
          }.entries)
            ChoiceChip(
              key: ValueKey('picture-look-${entry.key}'),
              avatar: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: entry.value.$2,
                  shape: BoxShape.circle,
                  border: Border.all(color: _skin.border),
                ),
              ),
              label: Text(entry.value.$1),
              selected: _look == entry.key,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _look = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('picture-lighting-$_lighting'),
        initialValue: _lighting,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Lighting',
          prefixIcon: Icon(Icons.wb_sunny_outlined),
        ),
        items: const [
          DropdownMenuItem(
            value: 'original',
            child: Text('Keep original lighting'),
          ),
          DropdownMenuItem(value: 'brighten', child: Text('Bright & clear')),
          DropdownMenuItem(value: 'soft', child: Text('Soft & flattering')),
          DropdownMenuItem(value: 'golden', child: Text('Golden hour')),
          DropdownMenuItem(value: 'studio', child: Text('Studio lighting')),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() => _lighting = value ?? 'original'),
      ),
    ],
  );

  Widget _controls() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _step('2', 'Choose your treatment', _skin.tertiary),
        _presetChoices(),
        const SizedBox(height: 12),
        Text(
          presets[_preset]!.$3,
          style: TextStyle(color: _skin.mutedText, height: 1.4),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const Key('picture-color-lighting'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          leading: Icon(Icons.palette_outlined, color: _skin.secondary),
          title: const Text(
            'Color & lighting',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'Set the mood with a look and light',
            style: TextStyle(fontSize: 12),
          ),
          children: [_lookAndLight()],
        ),
        const SizedBox(height: 18),
        _step('3', 'Make it yours', _skin.primary),
        if (_source != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16, color: _skin.mutedText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Editing: $_sourceLabel',
                    style: TextStyle(color: _skin.mutedText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          controller: _prompt,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          maxLength: 12000,
          decoration: InputDecoration(
            labelText: _preset == 'custom'
                ? 'Describe your edit'
                : 'Your instructions (optional)',
            hintText: 'Tell us what should change and what should stay.',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        Text(
          'Add a suggestion, then edit it your way:',
          style: TextStyle(color: _skin.mutedText, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in const {
              'Natural skin':
                  'Keep natural skin texture; avoid an airbrushed look.',
              'Clean background':
                  'Remove background distractions while keeping the subject unchanged.',
              'Keep details':
                  'Keep faces, text, logos and small details faithful to the original.',
            }.entries)
              ActionChip(
                label: Text(entry.key),
                onPressed: _busy ? null : () => _suggest(entry.value),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _preserve,
          onChanged: _busy
              ? null
              : (value) => setState(() => _preserve = value),
          title: const Text(
            'Preserve identity & details',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Ask the editor to retain faces, skin tone, hairlines, shapes and labels.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        ExpansionTile(
          key: const Key('picture-finish-options'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 16),
          title: const Text(
            'Finish & output shape',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Adjust the amount of change and framing',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _label('How much should change?'),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['subtle', 'balanced', 'creative']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(
                            value[0].toUpperCase() + value.substring(1),
                          ),
                          selected: _strength == value,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _strength = value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  key: ValueKey('picture-size-$_size'),
                  initialValue: _size,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Output shape'),
                  items: const [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text('Match my photo'),
                    ),
                    DropdownMenuItem(
                      value: '1024x1024',
                      child: Text('Square · 1024 × 1024'),
                    ),
                    DropdownMenuItem(
                      value: '1024x1536',
                      child: Text('Portrait · 1024 × 1536'),
                    ),
                    DropdownMenuItem(
                      value: '1536x1024',
                      child: Text('Landscape · 1536 × 1024'),
                    ),
                    DropdownMenuItem(
                      value: '1536x1536',
                      child: Text('Detailed square · 1536 × 1536'),
                    ),
                    DropdownMenuItem(
                      value: '1536x2304',
                      child: Text('Detailed portrait · 1536 × 2304'),
                    ),
                    DropdownMenuItem(
                      value: '2304x1536',
                      child: Text('Detailed landscape · 2304 × 1536'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _size = value ?? 'auto'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(_error!, style: TextStyle(color: _skin.danger)),
            ),
          ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Studying your photo and creating your edit…'),
                  const SizedBox(height: 6),
                  Text(
                    'A careful edit can take several minutes. Keep this screen open. ${_elapsed}s elapsed.',
                    style: TextStyle(color: _skin.mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        FilledButton.icon(
          key: const Key('improve-picture-submit'),
          onPressed: _busy || _picking || _source == null ? null : _improve,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            _busy ? 'Creating your edit…' : 'Improve my picture',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Compare the result before saving. Your original stays untouched.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _skin.mutedText, height: 1.4, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _busy ? null : widget.onOpenTemplates,
          icon: const Icon(Icons.collections_outlined),
          label: const Text('Explore portrait templates'),
        ),
      ],
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _skin.border.withValues(alpha: .3)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(_skin.secondary.withValues(alpha: .15), _skin.panel),
          Color.alphaBlend(_skin.tertiary.withValues(alpha: .14), _skin.panel),
          Color.alphaBlend(
            const Color(0xfff390ba).withValues(alpha: .12),
            _skin.panel,
          ),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, color: _skin.text, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'KORLIX PHOTO STUDIO',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final color in const [
              Color(0xffb49aff),
              Color(0xff58cbb8),
              Color(0xfff390ba),
            ])
              Container(
                margin: const EdgeInsets.only(left: 5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Your photo. Your kind of brilliant.',
          style: TextStyle(
            fontSize: 28,
            height: 1.16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Restore a memory, polish a portrait or make your product shine. Play with color, compare every edit, and keep your favorite.',
          style: TextStyle(color: _skin.text, height: 1.5),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = korlixBuildTheme(_skin.id);
    return Theme(
      data: theme,
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Improve My Picture'),
            backgroundColor: _skin.backgroundMid,
            automaticallyImplyLeading: !_busy,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1160),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _hero(),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth >= 840 &&
                                MediaQuery.textScalerOf(context).scale(1) < 1.5
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _preview()),
                                  const SizedBox(width: 20),
                                  Expanded(child: _controls()),
                                ],
                              )
                            : Column(
                                children: [
                                  _preview(),
                                  const SizedBox(height: 20),
                                  _controls(),
                                ],
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
}

class _PictureVersion {
  const _PictureVersion({
    required this.number,
    required this.source,
    required this.sourceLabel,
    required this.result,
    required this.options,
  });
  final int number;
  final PlatformFile source;
  final String sourceLabel;
  final PictureEditResult result;
  final PictureEditOptions options;
}

class _TransparencyPainter extends CustomPainter {
  const _TransparencyPainter(this.first, this.second);
  final Color first, second;
  @override
  void paint(Canvas canvas, Size size) {
    const side = 16.0;
    final paint = Paint();
    for (var y = 0; y < size.height / side; y++) {
      for (var x = 0; x < size.width / side; x++) {
        paint.color = (x + y).isEven ? first : second;
        canvas.drawRect(Rect.fromLTWH(x * side, y * side, side, side), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TransparencyPainter oldDelegate) =>
      first != oldDelegate.first || second != oldDelegate.second;
}
