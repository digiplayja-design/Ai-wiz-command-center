import 'package:flutter/material.dart';
import '../models/template_model.dart';

class ImprovePictureHome extends StatefulWidget {
  const ImprovePictureHome({super.key});

  @override
  State<ImprovePictureHome> createState() => _ImprovePictureHomeState();
}

class _ImprovePictureHomeState extends State<ImprovePictureHome> {
  ImproveGender _gender = ImproveGender.female;
  ImproveTemplate? _selectedTemplate;
  String? _selectedVariation;

  @override
  Widget build(BuildContext context) {
    final templates = kImprovePictureTemplates;
    final selectedTemplate = _selectedTemplate ?? templates.first;
    final selectedVariation =
        _selectedVariation ?? selectedTemplate.variations.first;

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Improve My Picture'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            _HeroHeader(gender: _gender),
            const SizedBox(height: 18),
            _GenderSelector(
              gender: _gender,
              onChanged: (value) {
                setState(() {
                  _gender = value;
                  _selectedTemplate = null;
                  _selectedVariation = null;
                });
              },
            ),
            const SizedBox(height: 18),
            _UploadPanel(),
            const SizedBox(height: 18),
            _SectionTitle(
              title:
                  '${_gender == ImproveGender.female ? 'Female' : 'Male'} Templates',
              subtitle: '12 template categories. Each includes 3 ideas.',
            ),
            const SizedBox(height: 12),
            _TemplateGrid(
              templates: templates,
              selected: selectedTemplate,
              onSelected: (template) {
                setState(() {
                  _selectedTemplate = template;
                  _selectedVariation = template.variations.first;
                });
              },
            ),
            const SizedBox(height: 18),
            _VariationPicker(
              template: selectedTemplate,
              selected: selectedVariation,
              onSelected: (value) => setState(() => _selectedVariation = value),
            ),
            const SizedBox(height: 18),
            _PreviewPanel(
              gender: _gender,
              template: selectedTemplate,
              variation: selectedVariation,
            ),
            const SizedBox(height: 18),
            _ActionButtons(),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.gender});

  final ImproveGender gender;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Portrait Studio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Realistic HD results. Same you, different styles.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _FeaturePill(
                icon: Icons.grid_view_rounded,
                label: '12 Templates',
              ),
              const SizedBox(width: 8),
              _FeaturePill(
                icon: Icons.auto_awesome_rounded,
                label: '3 Ideas Each',
              ),
            ],
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D101A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF7B3CFF).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          _GenderTab(
            active: gender == ImproveGender.female,
            icon: Icons.female_rounded,
            label: 'Female',
            onTap: () => onChanged(ImproveGender.female),
          ),
          _GenderTab(
            active: gender == ImproveGender.male,
            icon: Icons.male_rounded,
            label: 'Male',
            onTap: () => onChanged(ImproveGender.male),
          ),
        ],
      ),
    );
  }
}

class _GenderTab extends StatelessWidget {
  const _GenderTab({
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
          padding: const EdgeInsets.symmetric(vertical: 13),
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 145,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF8B5CFF), width: 1.3),
              color: const Color(0xFF111426),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.upload_rounded,
                    color: Color(0xFFA970FF),
                    size: 42,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Upload Your Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'JPG, PNG • Max 20MB',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SmallButton(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SmallButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({
    required this.templates,
    required this.selected,
    required this.onSelected,
  });

  final List<ImproveTemplate> templates;
  final ImproveTemplate selected;
  final ValueChanged<ImproveTemplate> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: templates.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final template = templates[index];
        final active = template.id == selected.id;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onSelected(template),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF10131E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? const Color(0xFFB266FF)
                    : Colors.white.withOpacity(0.10),
                width: active ? 1.8 : 1,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '3 ideas',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  template.icon,
                  color: active ? const Color(0xFFC07CFF) : Colors.white70,
                  size: 26,
                ),
                const SizedBox(height: 8),
                Text(
                  '${index + 1}. ${template.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VariationPicker extends StatelessWidget {
  const _VariationPicker({
    required this.template,
    required this.selected,
    required this.onSelected,
  });

  final ImproveTemplate template;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: '${template.name} Variations',
            subtitle: template.description,
          ),
          const SizedBox(height: 12),
          ...template.variations.map((variation) {
            final active = variation == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(variation),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF241A38)
                        : const Color(0xFF0F121C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active
                          ? const Color(0xFFB266FF)
                          : Colors.white.withOpacity(0.09),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: const Color(0xFFA970FF),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          variation,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.gender,
    required this.template,
    required this.variation,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _boxDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: 'Preview + Compare',
            subtitle: 'Portrait-only preview before saving.',
          ),
          const SizedBox(height: 14),
          Container(
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF171B29), Color(0xFF05070D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: const Color(0xFF8B5CFF).withOpacity(0.35),
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      template.icon,
                      color: const Color(0xFFC07CFF),
                      size: 58,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${gender == ImproveGender.female ? 'Female' : 'Male'} • ${template.name}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      variation,
                      style: const TextStyle(
                        color: Color(0xFFC07CFF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preserve identity. Transform the style.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.62)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Effect Strength',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Slider(
            value: 0.8,
            onChanged: (_) {},
            activeColor: const Color(0xFFB266FF),
          ),
          Row(
            children: const [
              _RatioChip(label: '1:1'),
              SizedBox(width: 8),
              _RatioChip(label: '4:5', active: true),
              SizedBox(width: 8),
              _RatioChip(label: '9:16'),
              SizedBox(width: 8),
              _RatioChip(label: '16:9'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B3DFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () {},
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text(
              'Generate Preview',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withOpacity(0.15)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            onPressed: () {},
            icon: const Icon(Icons.history_rounded),
            label: const Text('View History'),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

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
            fontSize: 18,
            fontWeight: FontWeight.w900,
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

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFC07CFF), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF7B3CFF)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _RatioChip extends StatelessWidget {
  const _RatioChip({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF241A38) : const Color(0xFF0F121C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? const Color(0xFFB266FF)
                : Colors.white.withOpacity(0.09),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _boxDecoration() {
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
