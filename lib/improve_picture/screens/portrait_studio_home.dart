import 'package:flutter/material.dart';

import '../models/template_model.dart';
import 'template_gallery.dart';

class PortraitStudioHome extends StatefulWidget {
  const PortraitStudioHome({super.key, this.onGeneratePrompt});

  final void Function(String prompt)? onGeneratePrompt;

  @override
  State<PortraitStudioHome> createState() => _PortraitStudioHomeState();
}

class _PortraitStudioHomeState extends State<PortraitStudioHome> {
  ImproveGender _gender = ImproveGender.female;
  bool _photoSelected = false;

  void _continueToGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateGalleryScreen(
          gender: _gender,
          hasUploadedPhoto: _photoSelected,
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
              photoSelected: _photoSelected,
              onPick: () => setState(() => _photoSelected = true),
            ),
            const SizedBox(height: 18),
            const _TipsCard(),
            const SizedBox(height: 18),
            _IdentityLockCard(gender: _gender),
            const SizedBox(height: 22),
            _ContinueButton(
              label: _photoSelected
                  ? 'Continue to Templates'
                  : 'Explore Templates',
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
            'Transform one portrait into realistic HD results with 12 premium template categories and 3 ideas each.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.35,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                child: _HeroStat(
                  icon: Icons.grid_view_rounded,
                  label: '12 Templates',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  icon: Icons.filter_3_rounded,
                  label: '36 Looks',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(
                child: _HeroStat(icon: Icons.hd_rounded, label: 'HD Preview'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _HeroStat(icon: Icons.compare_rounded, label: 'Compare'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFC07CFF), size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
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
            borderRadius: BorderRadius.circular(999),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF6D3BFF), Color(0xFFD83BFF)],
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? Colors.white : Colors.white54),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white54,
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
  const _UploadCard({required this.photoSelected, required this.onPick});

  final bool photoSelected;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle(
            title: 'Upload Portrait',
            subtitle: 'Use a clear front-facing photo for the best result.',
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onPick,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 160,
              decoration: BoxDecoration(
                color: photoSelected
                    ? const Color(0xFF151827)
                    : const Color(0xFF111426),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: photoSelected
                      ? const Color(0xFF35D07F)
                      : const Color(0xFF8B5CFF),
                  width: 1.4,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      photoSelected
                          ? Icons.check_circle_rounded
                          : Icons.upload_rounded,
                      color: photoSelected
                          ? const Color(0xFF35D07F)
                          : const Color(0xFFA970FF),
                      size: 46,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      photoSelected ? 'Portrait Selected' : 'Upload Your Photo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      photoSelected
                          ? 'Ready for template preview'
                          : 'JPG, PNG • Max 20MB',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _PickerButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: onPick,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: onPick,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF7B3CFF)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    final tips = [
      'Face centered and visible',
      'Good lighting works best',
      'Avoid sunglasses or heavy blur',
      'Use high-resolution portraits',
      'Portrait format is recommended',
    ];

    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BlockTitle(
            title: 'Best Results Tips',
            subtitle: 'Small photo choices make the output more realistic.',
          ),
          const SizedBox(height: 12),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF35D07F),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityLockCard extends StatelessWidget {
  const _IdentityLockCard({required this.gender});

  final ImproveGender gender;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _studioBox(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF251A38),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFB266FF).withOpacity(0.55),
              ),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFFC07CFF),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Identity Lock',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Realistic templates preserve the same ${gender == ImproveGender.female ? 'woman' : 'man'} while changing only the selected style.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.62),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8B3DFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          elevation: 0,
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
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withOpacity(0.58), fontSize: 12),
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
        offset: const Offset(0, 12),
      ),
    ],
  );
}
