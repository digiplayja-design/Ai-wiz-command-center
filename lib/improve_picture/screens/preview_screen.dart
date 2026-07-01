import 'package:flutter/material.dart';

import '../models/template_model.dart';
import 'processing_screen.dart';

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    super.key,
    required this.gender,
    required this.template,
    required this.variation,
    required this.hasUploadedPhoto,
  });

  final ImproveGender gender;
  final ImproveTemplate template;
  final String variation;
  final bool hasUploadedPhoto;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  double _strength = 0.8;
  String _ratio = '9:16';

  void _generate() {
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

    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF05070D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Preview'),
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
            const SizedBox(height: 18),
            Container(
              height: 420,
              decoration: BoxDecoration(
                color: const Color(0xFF0B0E17),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF7B3CFF).withOpacity(0.30),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Center(
                      child: Icon(
                        widget.template.icon,
                        color: Colors.white.withOpacity(0.18),
                        size: 140,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 1.5,
                        color: const Color(0xFFB266FF),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    top: 18,
                    child: _Tag(
                      label: widget.hasUploadedPhoto ? 'Before' : 'Demo Before',
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: const _Tag(label: 'After'),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Text(
                      'Before / After split preview placeholder',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.62)),
                    ),
                  ),
                ],
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
                label: const Text(
                  'Generate Result',
                  style: TextStyle(fontWeight: FontWeight.w900),
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
