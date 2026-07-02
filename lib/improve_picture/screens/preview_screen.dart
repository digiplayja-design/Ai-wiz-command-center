import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../controllers/portrait_studio_controller.dart';
import '../models/portrait_studio_callback.dart';
import '../models/template_model.dart';
import 'processing_screen.dart';

const String _kKorlixPortraitPreviewEndpoint =
    'https://chee-chai-chee-backend.onrender.com/api/image/improve';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.variation,
    required this.hasUploadedPhoto,
    required this.bestResults,
    required this.identityLock,
    this.uploadedFile,
    this.onGeneratePrompt,
    this.previewHeadersBuilder,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;
  final bool hasUploadedPhoto;
  final bool bestResults;
  final bool identityLock;
  final fp.PlatformFile? uploadedFile;
  final ImprovePicturePromptCallback? onGeneratePrompt;
  final KorlixPreviewHeadersBuilder? previewHeadersBuilder;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PortraitStudioController _promptController = PortraitStudioController();

  double _strength = 0.85;
  String _ratio = '9:16';

  bool _previewLoading = false;
  String? _previewError;
  Uint8List? _generatedPreviewBytes;
  bool _hasAttemptedPreview = false;

  Uint8List? get _uploadedBytes => widget.uploadedFile?.bytes;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_generateAfterPreview());
      }
    });
  }

  String _buildPrompt() {
    return _promptController.buildGenerationPrompt(
      gender: widget.gender,
      template: widget.template,
      variation: widget.variation,
      strength: _strength,
      ratio: _ratio,
      bestResults: widget.bestResults,
      identityLock: widget.identityLock,
    );
  }

  Future<void> _generateAfterPreview() async {
    final bytes = _uploadedBytes;

    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _hasAttemptedPreview = true;
        _previewLoading = false;
        _previewError = 'Upload a portrait first to generate an after preview.';
      });
      return;
    }

    if (_previewLoading) {
      return;
    }

    setState(() {
      _hasAttemptedPreview = true;
      _previewLoading = true;
      _previewError = null;
    });

    try {
      final prompt = _buildPrompt();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_kKorlixPortraitPreviewEndpoint),
      );

      final previewHeaders = Map<String, String>.from(
        await widget.previewHeadersBuilder?.call() ?? const <String, String>{},
      );

      previewHeaders.removeWhere(
        (key, _) => key.toLowerCase() == 'content-type',
      );

      if (!previewHeaders.keys.any(
        (key) => key.toLowerCase() == 'authorization',
      )) {
        throw Exception(
          'Sign in required before generating a live after preview.',
        );
      }

      request.headers.addAll(previewHeaders);
      request.headers['Accept'] = 'application/json';
      request.headers['X-Korlix-Portrait-Preview'] = 'true';
      request.headers['X-Korlix-Preview-Mode'] = 'portrait_studio';

      request.fields.addAll({
        'prompt': prompt,
        'command': prompt,
        'mode': 'portrait_studio_preview',
        'preview': 'true',
        'source': 'ios_testflight',
        'template': widget.template.name,
        'variation': widget.variation,
        'gender': widget.gender.name,
        'ratio': _ratio,
        'strength': _strength.toStringAsFixed(2),
        'bestResults': widget.bestResults.toString(),
        'identityLock': widget.identityLock.toString(),
      });

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: widget.uploadedFile?.name ?? 'portrait.jpg',
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Preview server returned ${response.statusCode}: ${response.body}',
        );
      }

      final contentType = response.headers['content-type'] ?? '';
      final previewBytes = contentType.toLowerCase().startsWith('image/')
          ? response.bodyBytes
          : await _extractPreviewBytes(response.body);

      if (previewBytes == null || previewBytes.isEmpty) {
        throw Exception('Preview server did not return an image.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _generatedPreviewBytes = previewBytes;
        _previewError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _previewError =
            'Live after preview did not return an image yet. Tap Generate to create the final image. Details: ${_shortPreviewError(error)}';
      });

      debugPrint('Portrait Studio after preview failed: $error');
    } finally {
      if (mounted) {
        setState(() => _previewLoading = false);
      }
    }
  }

  String _shortPreviewError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();

    if (raw.isEmpty) {
      return 'Unknown preview error.';
    }

    return raw.length > 180 ? '${raw.substring(0, 180)}...' : raw;
  }

  Future<Uint8List?> _extractPreviewBytes(String body) async {
    Object? decoded;

    try {
      decoded = jsonDecode(body);
    } catch (_) {
      final trimmed = body.trim();

      if (_looksLikeImageString(trimmed)) {
        return _bytesFromImageString(trimmed);
      }

      return null;
    }

    final imageValue = _findImageString(decoded);

    if (imageValue == null) {
      return null;
    }

    return _bytesFromImageString(imageValue);
  }

  String? _findImageString(Object? value) {
    const preferredKeys = [
      'imageDataUrl',
      'image_data_url',
      'dataUrl',
      'data_url',
      'imageUrl',
      'image_url',
      'url',
      'outputUrl',
      'output_url',
      'resultUrl',
      'result_url',
      'image',
      'output',
      'result',
      'base64',
      'b64',
    ];

    if (value is String) {
      return _looksLikeImageString(value) ? value : null;
    }

    if (value is Map) {
      for (final key in preferredKeys) {
        if (value.containsKey(key)) {
          final found = _findImageString(value[key]);
          if (found != null) {
            return found;
          }
        }
      }

      for (final entry in value.entries) {
        final found = _findImageString(entry.value);
        if (found != null) {
          return found;
        }
      }
    }

    if (value is Iterable) {
      for (final item in value) {
        final found = _findImageString(item);
        if (found != null) {
          return found;
        }
      }
    }

    return null;
  }

  bool _looksLikeImageString(String value) {
    final trimmed = value.trim();

    if (trimmed.startsWith('data:image/')) {
      return true;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }

    if (trimmed.length > 120 &&
        RegExp(r'^[A-Za-z0-9+/=\r\n]+$').hasMatch(trimmed)) {
      return true;
    }

    return false;
  }

  Future<Uint8List?> _bytesFromImageString(String value) async {
    final trimmed = value.trim();

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final response = await http.get(Uri.parse(trimmed));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }

      return null;
    }

    if (trimmed.startsWith('data:image/')) {
      final comma = trimmed.indexOf(',');
      if (comma == -1) {
        return null;
      }

      return base64Decode(trimmed.substring(comma + 1));
    }

    try {
      return base64Decode(trimmed);
    } catch (_) {
      return null;
    }
  }

  void _generate() {
    final callback = widget.onGeneratePrompt;
    final prompt = _buildPrompt();

    if (callback != null) {
      callback(prompt, widget.uploadedFile, true);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          gender: widget.gender,
          template: widget.template,
          variation: widget.variation,
          strength: _strength,
          ratio: _ratio,
          hasUploadedPhoto: widget.hasUploadedPhoto,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final genderLabel = widget.gender == ImproveGender.female
        ? 'Female'
        : 'Male';
    final bytes = _uploadedBytes;

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Template Preview'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            Text(
              '${widget.template.name} Preview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$genderLabel • ${widget.variation}',
              style: const TextStyle(
                color: Color(0xFFC07CFF),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.bestResults ? 'Best Results ON' : 'Best Results OFF'} • ${widget.identityLock ? 'Identity Lock ON' : 'Identity Lock OFF'}',
              style: const TextStyle(
                color: Color(0xFFB6FF2E),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              height: 430,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E17),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF7B3CFF).withOpacity(0.30),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BeforePreview(
                      imageBytes: bytes,
                      hasUploadedPhoto: widget.hasUploadedPhoto,
                    ),
                  ),
                  Container(width: 1.5, color: const Color(0xFFB266FF)),
                  Expanded(
                    child: _AfterTemplatePreview(
                      originalBytes: bytes,
                      generatedBytes: _generatedPreviewBytes,
                      previewLoading: _previewLoading,
                      hasAttemptedPreview: _hasAttemptedPreview,
                      template: widget.template,
                      variation: widget.variation,
                      bestResults: widget.bestResults,
                      identityLock: widget.identityLock,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _generatedPreviewBytes != null
                  ? 'Live after preview generated. Tap Generate to use this selected template with KORLIX AI.'
                  : 'After preview is loading. If the server preview is unavailable, the styled fallback still shows the selected template direction.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                height: 1.35,
              ),
            ),
            if (_previewError != null) ...[
              const SizedBox(height: 10),
              Text(
                _previewError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _previewLoading ? null : _generateAfterPreview,
              icon: _previewLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _previewLoading
                    ? 'Generating After Preview...'
                    : 'Refresh After Preview',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.18)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Effect Strength',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            Slider(
              value: _strength,
              activeColor: const Color(0xFFB266FF),
              onChanged: (value) {
                setState(() => _strength = value);
              },
              onChangeEnd: (_) {
                unawaited(_generateAfterPreview());
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: ['1:1', '4:5', '9:16', '16:9'].map((ratio) {
                final active = ratio == _ratio;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () {
                        setState(() => _ratio = ratio);
                        unawaited(_generateAfterPreview());
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF241A38)
                              : const Color(0xFF0F121C),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: active
                                ? const Color(0xFFB266FF)
                                : Colors.white.withOpacity(0.10),
                          ),
                        ),
                        child: Text(
                          ratio,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _generate,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  'Generate ${widget.template.name} Template',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B3DFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeforePreview extends StatelessWidget {
  const _BeforePreview({
    required this.imageBytes,
    required this.hasUploadedPhoto,
  });

  final Uint8List? imageBytes;
  final bool hasUploadedPhoto;

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;

    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bytes == null)
            Center(
              child: Icon(
                Icons.person_rounded,
                color: Colors.white.withOpacity(0.18),
                size: 120,
              ),
            )
          else
            Image.memory(bytes, fit: BoxFit.cover),
          Positioned(
            left: 12,
            top: 12,
            child: _Tag(label: hasUploadedPhoto ? 'Before' : 'Demo Before'),
          ),
        ],
      ),
    );
  }
}

class _AfterTemplatePreview extends StatelessWidget {
  const _AfterTemplatePreview({
    required this.originalBytes,
    required this.generatedBytes,
    required this.previewLoading,
    required this.hasAttemptedPreview,
    required this.template,
    required this.variation,
    required this.bestResults,
    required this.identityLock,
  });

  final Uint8List? originalBytes;
  final Uint8List? generatedBytes;
  final bool previewLoading;
  final bool hasAttemptedPreview;
  final ImproveTemplate template;
  final String variation;
  final bool bestResults;
  final bool identityLock;

  @override
  Widget build(BuildContext context) {
    final generated = generatedBytes;

    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (generated != null)
            Image.memory(generated, fit: BoxFit.cover)
          else
            _StyledAfterFallback(
              imageBytes: originalBytes,
              template: template,
              variation: variation,
              bestResults: bestResults,
              identityLock: identityLock,
            ),
          Positioned(
            right: 12,
            top: 12,
            child: _Tag(
              label: generated != null
                  ? 'After Preview'
                  : previewLoading
                  ? 'Generating'
                  : 'After Style',
            ),
          ),
          if (previewLoading)
            Container(
              color: Colors.black.withOpacity(0.24),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFC07CFF)),
              ),
            ),
          if (generated == null && !previewLoading && hasAttemptedPreview)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Styled fallback shown until live preview returns.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StyledAfterFallback extends StatelessWidget {
  const _StyledAfterFallback({
    required this.imageBytes,
    required this.template,
    required this.variation,
    required this.bestResults,
    required this.identityLock,
  });

  final Uint8List? imageBytes;
  final ImproveTemplate template;
  final String variation;
  final bool bestResults;
  final bool identityLock;

  Color get _overlayColor {
    switch (template.id) {
      case 'mask':
        return const Color(0xFFFFD166);
      case 'cartoon':
      case 'caricature':
        return const Color(0xFFC07CFF);
      case 'gothic':
        return const Color(0xFF5B2E91);
      case 'fiery':
        return const Color(0xFFFF5C2E);
      case 'wet':
        return const Color(0xFF69D9E8);
      case 'smoky':
        return const Color(0xFFB0B7C3);
      default:
        return const Color(0xFFB266FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = imageBytes;
    final overlay = _overlayColor;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (bytes == null)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [overlay.withOpacity(0.52), const Color(0xFF05070D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          )
        else
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              overlay.withOpacity(0.42),
              BlendMode.overlay,
            ),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.10),
                overlay.withOpacity(0.34),
                Colors.black.withOpacity(0.62),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(template.icon, color: Colors.white, size: 58),
                const SizedBox(height: 12),
                Text(
                  template.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 23,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  variation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB6FF2E),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _templatePreviewText(template.id, template.name, variation),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${bestResults ? 'Best Results' : 'Natural'} • ${identityLock ? 'Identity Lock' : 'Creative Identity'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _templatePreviewText(
    String templateId,
    String templateName,
    String variation,
  ) {
    switch (templateId) {
      case 'mask':
        return 'Mask overlay preview: the live result should add a visible $variation mask while preserving the same face.';
      case 'cartoon':
        return 'Cartoon preview: the live result should visibly stylize the portrait, not just brighten it.';
      case 'caricature':
        return 'Caricature preview: the live result should exaggerate expression and style while keeping identity.';
      case 'gothic':
        return 'Gothic preview: the live result should add fashion, mood, makeup, and dramatic lighting.';
      default:
        return '$templateName preview: the live result should clearly apply $variation.';
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}
