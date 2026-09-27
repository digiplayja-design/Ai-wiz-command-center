import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../korlix_image_saver.dart';
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
  static const accent = Color(0xFF63D9F6);
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
  PictureEditResult? _result;
  String _preset = 'enhance', _strength = 'balanced', _size = 'auto';
  String? _error;
  bool _preserve = true,
      _busy = false,
      _picking = false,
      _saving = false,
      _showBefore = false;
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
        _result = null;
        _showBefore = false;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not open that photo. Try Choose photo or check camera permissions.',
        );
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
    final options = PictureEditOptions(
      preset: _preset,
      strength: _strength,
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
        _result = result;
        _showBefore = false;
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
      if (mounted)
        setState(
          () => _error = error.toString().replaceFirst(
            RegExp(r'^Exception: '),
            '',
          ),
        );
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your PNG is ready to save or share.')),
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not save this picture. Keep this screen open and try Save PNG again.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _refine() {
    if (_result == null || _busy) return;
    setState(() {
      _source = PlatformFile(
        name: 'korlix_refinement.png',
        size: _result!.bytes.length,
        bytes: _result!.bytes,
      );
      _result = null;
      _preset = 'custom';
      _prompt.clear();
      _showBefore = false;
      _error = null;
    });
  }

  Widget _card(Widget child) => Material(
    color: const Color(0xFF101E30),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: Colors.white12),
    ),
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    ),
  );

  Widget _preview() {
    final bytes = _result != null && !_showBefore
        ? _result!.bytes
        : _source?.bytes;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _label(
                  _result == null ? 'Your photo' : 'Compare your edit',
                ),
              ),
              if (_result != null)
                const Icon(Icons.check_circle_outline, color: accent),
            ],
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Before'),
                    selected: _showBefore,
                    onSelected: (_) => setState(() => _showBefore = true),
                  ),
                  ChoiceChip(
                    label: const Text('After'),
                    selected: !_showBefore,
                    onSelected: (_) => setState(() => _showBefore = false),
                  ),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 340,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _TransparencyPainter()),
                  if (bytes != null)
                    InteractiveViewer(
                      key: ValueKey(bytes),
                      minScale: 1,
                      maxScale: 5,
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        cacheWidth: 1600,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            'This photo could not be previewed. Choose another.',
                          ),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 54,
                            color: accent,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Start with a photo you love',
                            style: TextStyle(fontSize: 17),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'JPG, PNG or WEBP · Up to 15 MB',
                            style: TextStyle(color: Colors.white60),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _busy || _picking ? null : _pick,
                            icon: const Icon(Icons.upload_outlined),
                            label: Text(_picking ? 'Opening…' : 'Choose photo'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            bytes == null
                ? 'Your original stays available while you experiment.'
                : 'Pinch or scroll to zoom. Drag to inspect details.',
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 12),
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
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _source = _original;
                            _result = null;
                            _showBefore = false;
                            _error = null;
                          });
                        },
                  child: const Text('Start from original'),
                ),
            ],
          ),
          if (_result != null) ...[
            const Divider(height: 30),
            if (_result!.summary.isNotEmpty) ...[
              const Text(
                'Edit direction',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _result!.summary,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '${_result!.quality == 'max' ? 'Maximum' : _result!.quality} quality · PNG · ${_result!.size}',
              style: const TextStyle(color: accent, fontSize: 12),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 10),
            const Text(
              'Save your favorite before leaving. Edits stay in this open workspace.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _controls() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('What would you like to improve?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.entries
              .map(
                (entry) => ChoiceChip(
                  avatar: Icon(entry.value.$2, size: 17),
                  label: Text(entry.value.$1),
                  selected: _preset == entry.key,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _preset = entry.key),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Text(
          presets[_preset]!.$3,
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 20),
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
            hintText:
                'For example: brighten the lighting, keep my face and hairline, and use a warm studio background.',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
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
        const SizedBox(height: 12),
        _label('Finish'),
        Wrap(
          spacing: 8,
          children: ['subtle', 'balanced', 'creative']
              .map(
                (value) => ChoiceChip(
                  label: Text(value[0].toUpperCase() + value.substring(1)),
                  selected: _strength == value,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _strength = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _size,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Output shape',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Match my photo')),
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
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFFAFAD)),
              ),
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
                    'Maximum quality can take several minutes. Keep this screen open. ${_elapsed}s elapsed.',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        FilledButton.icon(
          key: const Key('improve-picture-submit'),
          onPressed: _busy || _picking || _source == null ? null : _improve,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? 'Creating your edit…' : 'Improve my picture'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Astra · Extra-high reasoning\nSunburst · Maximum image quality',
          textAlign: TextAlign.center,
          style: TextStyle(color: accent, height: 1.5, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _busy ? null : widget.onOpenTemplates,
          icon: const Icon(Icons.collections_outlined),
          label: const Text('Explore portrait templates'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF08111E),
    );
    return Theme(
      data: theme,
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Improve My Picture'),
            backgroundColor: const Color(0xFF08111E),
            automaticallyImplyLeading: !_busy,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your photo. A remarkable finish.',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose a treatment, tell us what matters, and compare the result.',
                        style: TextStyle(color: Colors.white70, height: 1.5),
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth >= 840
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

class _TransparencyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const side = 16.0;
    final paint = Paint();
    for (var y = 0; y < size.height / side; y++) {
      for (var x = 0; x < size.width / side; x++) {
        paint.color = (x + y).isEven
            ? const Color(0xFF1B293A)
            : const Color(0xFF233247);
        canvas.drawRect(Rect.fromLTWH(x * side, y * side, side, side), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
