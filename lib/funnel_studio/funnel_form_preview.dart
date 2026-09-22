import 'package:flutter/material.dart';

class FunnelFormPreview extends StatefulWidget {
  const FunnelFormPreview({
    super.key,
    required this.mode,
    required this.brand,
    required this.cta,
    required this.accent,
  });
  final String mode, brand, cta;
  final Color accent;
  @override
  State<FunnelFormPreview> createState() => _FunnelFormPreviewState();
}

class _FunnelFormPreviewState extends State<FunnelFormPreview> {
  int _step = 0;
  static const _ink = Color(0xFF142B38), _muted = Color(0xFF526776);
  @override
  void didUpdateWidget(covariant FunnelFormPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _step = 0;
  }

  Widget _field(String label, [String? sample]) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFD8E0E3)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
        if (sample != null) ...[
          const SizedBox(height: 5),
          Text(sample, style: const TextStyle(color: _ink, height: 1.4)),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final guided = widget.mode == 'guided';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (guided) ...[
          const Text(
            'Explore the three form steps',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  key: ValueKey('form-preview-step-$i'),
                  label: Text(['1 · Contact', '2 · Request', '3 · Review'][i]),
                  labelStyle: const TextStyle(color: _ink, fontSize: 12),
                  backgroundColor: Colors.white,
                  selectedColor: const Color(0xFFB5EEE7),
                  showCheckmark: false,
                  selected: _step == i,
                  onSelected: (_) => setState(() => _step = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text(
          guided
              ? [
                  'Your contact details',
                  'Your request',
                  'Review your inquiry',
                ][_step]
              : 'Let’s connect',
          style: const TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        if (!guided || _step == 0) ...[
          _field('Your name *'),
          _field('Email address *'),
          _field('Phone (optional)'),
        ],
        if (!guided || _step == 1) ...[
          _field('How can we help? (optional)'),
          Text(
            '□ I agree that ${widget.brand} may contact me about this request.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'This does not subscribe you to marketing messages.',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
        if (guided && _step == 2) ...[
          const Text(
            'Sample details for preview',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _field('Name', 'Taylor Morgan'),
          _field('Email', 'taylor@example.com'),
          _field(
            'Your request',
            'I would like to learn more about your services.',
          ),
          Text(
            'Visitors review their details and consent before pressing “${widget.cta}”. They can go back to edit.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: widget.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            !guided || _step == 2
                ? widget.cta
                : _step == 0
                ? 'Continue to request →'
                : 'Review inquiry →',
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w800),
          ),
        ),
        if (guided) ...[
          const SizedBox(height: 12),
          const Text(
            'Preview only. Only the final submission creates a lead; earlier steps do not save a partial inquiry.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }
}
