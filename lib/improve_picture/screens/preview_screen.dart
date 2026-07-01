import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';

import '../controllers/portrait_studio_controller.dart';
import '../models/portrait_studio_callback.dart';
import '../models/template_model.dart';
import 'processing_screen.dart';

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
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;
  final bool hasUploadedPhoto;
  final bool bestResults;
  final bool identityLock;
  final fp.PlatformFile? uploadedFile;
  final ImprovePicturePromptCallback? onGeneratePrompt;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final PortraitStudioController _promptController = PortraitStudioController();

  double _strength = 0.85;
  String _ratio = '9:16';

  void _generate() {
    final prompt = _promptController.buildGenerationPrompt(
      gender: widget.gender,
      template: widget.template,
      variation: widget.variation,
      strength: _strength,
      ratio: _ratio,
      bestResults: widget.bestResults,
      identityLock: widget.identityLock,
    );

    final callback = widget.onGeneratePrompt;

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
    final bytes = widget.uploadedFile?.bytes;

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
              'Preview shows the selected template direction. Tap generate to create the real finished image with KORLIX AI.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.66),
                height: 1.35,
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
              onChanged: (value) => setState(() => _strength = value),
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
                      onTap: () => setState(() => _ratio = ratio),
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

  final dynamic imageBytes;
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
          const Positioned(left: 12, top: 12, child: _Tag(label: 'Before')),
        ],
      ),
    );
  }
}

class _AfterTemplatePreview extends StatelessWidget {
  const _AfterTemplatePreview({
    required this.template,
    required this.variation,
    required this.bestResults,
    required this.identityLock,
  });

  final ImproveTemplate template;
  final String variation;
  final bool bestResults;
  final bool identityLock;

  @override
  Widget build(BuildContext context) {
    final isMask = template.name.toLowerCase() == 'mask';

    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isMask
                ? const [Color(0xFF261A08), Color(0xFF05070D)]
                : const [Color(0xFF271747), Color(0xFF05070D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Stack(
          children: [
            const Positioned(right: 0, top: 0, child: _Tag(label: 'After')),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    template.icon,
                    color: isMask
                        ? const Color(0xFFFFD166)
                        : const Color(0xFFC07CFF),
                    size: 92,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    template.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
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
                  const SizedBox(height: 16),
                  Text(
                    _templatePreviewText(template.name, variation),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${bestResults ? 'Best Results' : 'Natural'} • ${identityLock ? 'Identity Lock' : 'Creative Identity'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _templatePreviewText(String templateName, String variation) {
    final lower = templateName.toLowerCase();

    if (lower == 'mask') {
      return 'The generated result will add a visible $variation mask style while preserving the same face.';
    }

    if (lower == 'gothic') {
      return 'The generated result will add gothic mood, fashion, lighting, and styling.';
    }

    if (lower == 'cartoon' || lower == 'caricature') {
      return 'The generated result will apply the selected stylized look while keeping the person recognizable.';
    }

    return 'The generated result will apply the selected $variation look clearly, not just brighten the original.';
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
