import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' as ip;

import '../models/portrait_studio_callback.dart';
import '../models/template_model.dart';
import 'template_gallery.dart';

class PortraitStudioHome extends StatefulWidget {
  const PortraitStudioHome({
    super.key,
    this.onGeneratePrompt,
    this.previewHeadersBuilder,
  });

  final ImprovePicturePromptCallback? onGeneratePrompt;
  final KorlixPreviewHeadersBuilder? previewHeadersBuilder;

  @override
  State<PortraitStudioHome> createState() => _PortraitStudioHomeState();
}

class _PortraitStudioHomeState extends State<PortraitStudioHome> {
  final ip.ImagePicker _picker = ip.ImagePicker();

  ImproveGender _gender = ImproveGender.female;
  fp.PlatformFile? _pickedFile;
  Uint8List? _previewBytes;
  String? _error;
  bool _picking = false;
  bool _bestResults = true;
  bool _identityLock = true;

  bool get _hasPhoto => _pickedFile != null;

  Future<void> _pickImage(ip.ImageSource source) async {
    if (_picking) return;

    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 2400,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final fallbackName =
          'korlix_portrait_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final imageName = image.name.trim().isEmpty ? fallbackName : image.name;

      setState(() {
        _pickedFile = fp.PlatformFile(
          name: imageName,
          size: bytes.length,
          bytes: bytes,
          path: image.path,
        );
        _previewBytes = bytes;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Selected $imageName')));
    } catch (error) {
      setState(() {
        _error =
            'Could not open your photos. Check iOS Photos permission, then try again.';
      });

      debugPrint('Portrait Studio image picker failed: $error');
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  void _continueToGallery() {
    if (!_hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a portrait from Gallery or Camera first.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateGalleryScreen(
          gender: _gender,
          hasUploadedPhoto: _hasPhoto,
          uploadedFile: _pickedFile,
          bestResults: _bestResults,
          identityLock: _identityLock,
          onGeneratePrompt: widget.onGeneratePrompt,
          previewHeadersBuilder: widget.previewHeadersBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text(
          'AI Portrait Studio',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
          children: [
            const _HeroCard(),
            const SizedBox(height: 18),
            _GenderSelector(
              gender: _gender,
              onChanged: (value) => setState(() => _gender = value),
            ),
            const SizedBox(height: 18),
            _UploadCard(
              picking: _picking,
              photoSelected: _hasPhoto,
              fileName: _pickedFile?.name,
              previewBytes: _previewBytes,
              onPickGallery: () => _pickImage(ip.ImageSource.gallery),
              onPickCamera: () => _pickImage(ip.ImageSource.camera),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _PromptOptionsCard(
              bestResults: _bestResults,
              identityLock: _identityLock,
              onBestResultsChanged: (value) =>
                  setState(() => _bestResults = value),
              onIdentityLockChanged: (value) =>
                  setState(() => _identityLock = value),
            ),
            const SizedBox(height: 18),
            _IdentityLockCard(
              gender: _gender,
              identityLock: _identityLock,
              bestResults: _bestResults,
            ),
            const SizedBox(height: 22),
            _ContinueButton(
              label: _hasPhoto ? 'Continue to Templates' : 'Choose Photo First',
              onPressed: _continueToGallery,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: Color(0xFFC07CFF),
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Improve My Picture',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Upload one portrait, choose a premium template, then generate that selected look with KORLIX AI.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.35,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({required this.gender, required this.onChanged});

  final ImproveGender gender;
  final ValueChanged<ImproveGender> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle(
            title: 'Choose Gender',
            subtitle: 'Only the selected gender gallery will be shown.',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF0D101A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF7B3CFF).withOpacity(0.35),
              ),
            ),
            child: Row(
              children: [
                _GenderPill(
                  active: gender == ImproveGender.female,
                  icon: Icons.female_rounded,
                  label: 'Female',
                  onTap: () => onChanged(ImproveGender.female),
                ),
                _GenderPill(
                  active: gender == ImproveGender.male,
                  icon: Icons.male_rounded,
                  label: 'Male',
                  onTap: () => onChanged(ImproveGender.male),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderPill extends StatelessWidget {
  const _GenderPill({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8B3DFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.picking,
    required this.photoSelected,
    required this.onPickGallery,
    required this.onPickCamera,
    this.fileName,
    this.previewBytes,
  });

  final bool picking;
  final bool photoSelected;
  final String? fileName;
  final Uint8List? previewBytes;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;

  @override
  Widget build(BuildContext context) {
    final bytes = previewBytes;

    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle(
            title: 'Upload Portrait',
            subtitle: 'Pick one clear face photo from Gallery or Camera.',
          ),
          const SizedBox(height: 14),
          if (bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                bytes,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: picking ? null : onPickGallery,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0D101A),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: photoSelected
                      ? const Color(0xFFB6FF2E)
                      : const Color(0xFF7B3CFF).withOpacity(0.45),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    photoSelected
                        ? Icons.check_circle_rounded
                        : Icons.photo_library_rounded,
                    color: photoSelected
                        ? const Color(0xFFB6FF2E)
                        : const Color(0xFFB266FF),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      photoSelected
                          ? 'Selected: ${fileName ?? 'portrait'}'
                          : 'Tap to choose from Gallery',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (picking)
                    const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _UploadAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: picking ? null : onPickGallery,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UploadAction(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  onTap: picking ? null : onPickCamera,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadAction extends StatelessWidget {
  const _UploadAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withOpacity(0.18)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}

class _PromptOptionsCard extends StatelessWidget {
  const _PromptOptionsCard({
    required this.bestResults,
    required this.identityLock,
    required this.onBestResultsChanged,
    required this.onIdentityLockChanged,
  });

  final bool bestResults;
  final bool identityLock;
  final ValueChanged<bool> onBestResultsChanged;
  final ValueChanged<bool> onIdentityLockChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _OptionSwitch(
            title: 'Best Results',
            subtitle:
                'Premium lighting, skin polish, clarity, sharpness, color, and background finish.',
            value: bestResults,
            onChanged: onBestResultsChanged,
          ),
          const Divider(color: Color(0x22FFFFFF), height: 24),
          _OptionSwitch(
            title: 'Identity Lock',
            subtitle:
                'Preserve the same face, age range, skin tone, hairline, and recognizable features.',
            value: identityLock,
            onChanged: onIdentityLockChanged,
          ),
        ],
      ),
    );
  }
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFFB6FF2E),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withOpacity(0.62), height: 1.35),
      ),
    );
  }
}

class _IdentityLockCard extends StatelessWidget {
  const _IdentityLockCard({
    required this.gender,
    required this.identityLock,
    required this.bestResults,
  });

  final ImproveGender gender;
  final bool identityLock;
  final bool bestResults;

  @override
  Widget build(BuildContext context) {
    final label = gender == ImproveGender.female ? 'woman' : 'man';

    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: _BlockTitle(
        title: 'Prompt Summary',
        subtitle:
            '${bestResults ? 'Best Results ON' : 'Best Results OFF'} • ${identityLock ? 'Identity Lock ON' : 'Identity Lock OFF'} • Realistic templates preserve the same $label while applying the selected style.',
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8B3DFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _BlockTitle extends StatelessWidget {
  const _BlockTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.62), height: 1.35),
        ),
      ],
    );
  }
}

BoxDecoration _studioBox() {
  return BoxDecoration(
    color: const Color(0xFF0B0E17),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: const Color(0xFF7B3CFF).withOpacity(0.26)),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF7B3CFF).withOpacity(0.12),
        blurRadius: 24,
        offset: const Offset(0, 14),
      ),
    ],
  );
}
